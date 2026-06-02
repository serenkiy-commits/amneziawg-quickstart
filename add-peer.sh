#!/usr/bin/env bash
#
# amneziawg-add-peer — добавить устройство в AmneziaWG.
#
#   sudo amneziawg-add-peer <имя>           # автоматически найдёт свободный IP
#   sudo amneziawg-add-peer <имя> <октет>   # вручную выбрать последний октет (2..254)
#
# Делает за один проход:
#   1) генерит приватный/публичный ключ клиента + preshared key
#   2) дописывает [Peer] в /etc/amnezia/amneziawg/awg0.conf
#   3) применяет на лету (awg set, без рестарта туннеля — активные сессии не рвутся)
#   4) сохраняет клиентский .conf в /root/vpn-clients/<имя>.conf
#   5) рисует QR-код для сканирования из приложения AmneziaVPN

set -euo pipefail

NAME="${1:-}"
OCTET="${2:-}"

CONF_DIR=/etc/amnezia/amneziawg
WG_NAME=awg0
OUT_DIR=/root/vpn-clients

[[ $EUID -eq 0 ]] || { echo "Запусти от root: sudo $0 $*"; exit 1; }
[[ -n "$NAME" ]] || { echo "Использование: $0 <имя> [последний-октет]"; exit 1; }
[[ "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Имя может содержать только a-z A-Z 0-9 . _ -"; exit 1; }
[[ -f "$CONF_DIR/$WG_NAME.conf" ]] || { echo "Сервер не установлен. Запусти install.sh"; exit 1; }
[[ -f "$CONF_DIR/.params" ]] || { echo "Нет $CONF_DIR/.params"; exit 1; }

# shellcheck disable=SC1091
source "$CONF_DIR/.params"
SERVER_PUB=$(cat "$CONF_DIR/server_public.key")

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# -------- автоподбор IP --------
if [[ -z "$OCTET" ]]; then
  USED=$(awk '/AllowedIPs/ {print $3}' "$CONF_DIR/$WG_NAME.conf" \
    | awk -F'[./]' '{print $4}' | sort -un)
  for o in $(seq 2 254); do
    if ! grep -qx "$o" <<< "$USED"; then OCTET=$o; break; fi
  done
  [[ -n "$OCTET" ]] || { echo "В подсети $SUBNET.0/24 не осталось свободных адресов"; exit 1; }
fi

[[ "$OCTET" =~ ^[0-9]+$ ]] && (( OCTET >= 2 && OCTET <= 254 )) \
  || { echo "Октет должен быть 2..254"; exit 1; }

CLIENT_IP="$SUBNET.$OCTET"

# -------- проверки на дубликаты --------
if grep -q "^# $NAME$" "$CONF_DIR/$WG_NAME.conf"; then
  echo "Устройство '$NAME' уже есть в конфиге. Сначала: sudo amneziawg-remove-peer $NAME"
  exit 1
fi
if grep -q "AllowedIPs = ${CLIENT_IP}/32" "$CONF_DIR/$WG_NAME.conf"; then
  echo "IP $CLIENT_IP уже занят. Выбери другой октет."
  exit 1
fi
if [[ -f "$OUT_DIR/$NAME.conf" ]]; then
  read -rp "Конфиг $OUT_DIR/$NAME.conf уже есть. Пересоздать? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || exit 1
  rm -f "$OUT_DIR/$NAME.conf"
fi

# -------- ключи клиента --------
cd "$CONF_DIR"
umask 077
CLIENT_PRIV=$(awg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | awg pubkey)
PSK=$(awg genpsk)

# -------- запись в серверный конфиг --------
cat >> "$CONF_DIR/$WG_NAME.conf" <<EOF

[Peer]
# $NAME
PublicKey = $CLIENT_PUB
PresharedKey = $PSK
AllowedIPs = ${CLIENT_IP}/32
EOF

# -------- применяем на лету --------
awg set "$WG_NAME" peer "$CLIENT_PUB" \
  preshared-key <(echo "$PSK") \
  allowed-ips "${CLIENT_IP}/32"

# -------- клиентский конфиг --------
cat > "$OUT_DIR/$NAME.conf" <<EOF
[Interface]
Address = ${CLIENT_IP}/32
DNS = 1.1.1.1, 8.8.8.8
PrivateKey = $CLIENT_PRIV

Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PSK
AllowedIPs = 0.0.0.0/0
Endpoint = ${SERVER_IP}:${SERVER_PORT}
PersistentKeepalive = 25
EOF
chmod 600 "$OUT_DIR/$NAME.conf"

# -------- QR в терминал + PNG --------
QR_PNG="$OUT_DIR/$NAME.png"
qrencode -t PNG -o "$QR_PNG" < "$OUT_DIR/$NAME.conf"
chmod 600 "$QR_PNG"

echo
echo "════════════════════════════════════════════════"
echo "  ✓ $NAME готов  (IP в VPN: $CLIENT_IP)"
echo "════════════════════════════════════════════════"
echo "  Файл конфига: $OUT_DIR/$NAME.conf"
echo "  QR (PNG):     $QR_PNG"
echo
echo "  Скан QR-кода из приложения AmneziaVPN на телефоне:"
echo
qrencode -t ansiutf8 < "$OUT_DIR/$NAME.conf"
echo
