#!/usr/bin/env bash
#
# AmneziaWG Quickstart — install.sh
# https://github.com/serenkiy-commits/amneziawg-quickstart
#
# Поднимает сервер AmneziaWG на свежем Ubuntu/Debian VPS за ~2 минуты.
# AmneziaWG — это WireGuard + обфускация (Jc/S1/H1), которая обходит DPI там,
# где обычный WireGuard заблокирован (РФ, Иран, Китай).
#
# Запуск:
#   sudo bash install.sh
#

set -euo pipefail

# -------- утилиты вывода --------
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYA=$'\033[36m'; DIM=$'\033[2m'; RST=$'\033[0m'
say()  { echo "${CYA}==>${RST} $*"; }
ok()   { echo "${GRN}✓${RST} $*"; }
warn() { echo "${YEL}!${RST} $*"; }
err()  { echo "${RED}✗${RST} $*" >&2; }
die()  { err "$*"; exit 1; }
ask()  { local p="$1" def="${2:-}" ans; read -rp "  $p${def:+ [$def]}: " ans; echo "${ans:-$def}"; }

# -------- проверки окружения --------
[[ $EUID -eq 0 ]] || die "Запусти от root: sudo bash $0"
[[ -f /etc/os-release ]] && . /etc/os-release || die "Не могу определить ОС"
case "${ID:-}" in
  ubuntu|debian) : ;;
  *) die "Поддерживается только Ubuntu/Debian. У тебя: ${ID:-unknown}" ;;
esac

WAN_IF=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
[[ -n "$WAN_IF" ]] || die "Не нашёл интерфейс наружу. Проверь: ip route show default"

PUBLIC_IP=$(curl -fsS -4 --max-time 5 ifconfig.me 2>/dev/null \
         || curl -fsS -4 --max-time 5 ipinfo.io/ip 2>/dev/null \
         || true)
[[ -n "$PUBLIC_IP" ]] || warn "Не определил публичный IP автоматически — спрошу ниже"

CONF_DIR=/etc/amnezia/amneziawg
WG_NAME=awg0
SUBNET=10.9.0
BIN_DIR=/usr/local/sbin
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# -------- идемпотентность --------
if [[ -f "$CONF_DIR/$WG_NAME.conf" ]]; then
  warn "Уже установлено: $CONF_DIR/$WG_NAME.conf существует."
  echo "  Чтобы переустановить, сначала сделай: bash $SCRIPT_DIR/uninstall.sh"
  echo "  Чтобы добавить устройство: sudo amneziawg-add-peer <имя>"
  exit 0
fi

# -------- диалог --------
echo
echo "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo "  ${CYA}AmneziaWG Quickstart${RST}"
echo "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo
echo "  Внешний интерфейс: ${GRN}$WAN_IF${RST}"
[[ -n "$PUBLIC_IP" ]] && echo "  Публичный IP:       ${GRN}$PUBLIC_IP${RST}"
echo
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(ask "Публичный IP сервера")
PORT=$(ask "UDP-порт для VPN" "443")
PEER_NAME=$(ask "Имя первого устройства" "my-phone")
echo

# Валидация порта
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT > 0 && PORT < 65536 )) || die "Невалидный порт: $PORT"

# -------- установка пакетов --------
say "Устанавливаю AmneziaWG из PPA"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq software-properties-common ca-certificates curl qrencode iptables >/dev/null

if ! grep -rq "amnezia/ppa" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  add-apt-repository -y ppa:amnezia/ppa >/dev/null 2>&1
  apt-get update -qq
fi
apt-get install -y -qq amneziawg amneziawg-tools >/dev/null
ok "Пакеты установлены"

# Проверка модуля ядра
if ! modprobe amneziawg 2>/dev/null; then
  die "Ядро не поддерживает модуль amneziawg. Проверь uname -r и обнови ядро."
fi
ok "Модуль ядра amneziawg загружен"

# -------- IP forwarding --------
say "Включаю IP forwarding"
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-amneziawg.conf
sysctl --system >/dev/null
ok "net.ipv4.ip_forward = 1"

# -------- ключи + параметры обфускации --------
say "Генерирую ключи сервера и параметры обфускации"
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"
cd "$CONF_DIR"
umask 077

SERVER_PRIV=$(awg genkey)
echo "$SERVER_PRIV" > server_private.key
SERVER_PUB=$(echo "$SERVER_PRIV" | awg pubkey)
echo "$SERVER_PUB" > server_public.key

# Случайные H1..H4 — у каждого сервера уникальны, иначе сети между собой палятся.
# Jc/S1/S2 в безопасных диапазонах из спецификации Amnezia.
rand32() { printf "%u" $(( ( (RANDOM << 17) | (RANDOM << 2) | (RANDOM & 3) ) & 0x7FFFFFFF )); }
JC=$(( (RANDOM % 7) + 3 ))      # 3..9
JMIN=50
JMAX=1000
S1=$(( (RANDOM % 80) + 15 ))    # 15..94
S2=$(( (RANDOM % 80) + 15 ))    # 15..94
# H1..H4 должны быть попарно разными
H1=$(rand32); H2=$(rand32); H3=$(rand32); H4=$(rand32)
while [[ "$H2" == "$H1" ]]; do H2=$(rand32); done
while [[ "$H3" == "$H1" || "$H3" == "$H2" ]]; do H3=$(rand32); done
while [[ "$H4" == "$H1" || "$H4" == "$H2" || "$H4" == "$H3" ]]; do H4=$(rand32); done

cat > .params <<EOF
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
SERVER_IP=$PUBLIC_IP
SERVER_PORT=$PORT
WAN_IF=$WAN_IF
SUBNET=$SUBNET
EOF
chmod 600 .params
ok "Ключи сервера: $CONF_DIR/server_{private,public}.key"
ok "Параметры обфускации: $CONF_DIR/.params"

# -------- awg0.conf --------
say "Создаю конфиг сервера $WG_NAME.conf"
cat > "$WG_NAME.conf" <<EOF
[Interface]
Address = $SUBNET.1/24
ListenPort = $PORT
PrivateKey = $SERVER_PRIV

Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -s $SUBNET.0/24 -o $WAN_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -s $SUBNET.0/24 -o $WAN_IF -j MASQUERADE
EOF
chmod 600 "$WG_NAME.conf"
ok "$CONF_DIR/$WG_NAME.conf"

# -------- запуск --------
say "Поднимаю туннель и включаю автозапуск"
awg-quick up "$WG_NAME"
systemctl enable "awg-quick@$WG_NAME" >/dev/null 2>&1
ok "Туннель $WG_NAME поднят, автозапуск включён"

# -------- ставим утилиты управления --------
say "Устанавливаю утилиты управления в $BIN_DIR"
install -m 755 "$SCRIPT_DIR/add-peer.sh"    "$BIN_DIR/amneziawg-add-peer"
install -m 755 "$SCRIPT_DIR/remove-peer.sh" "$BIN_DIR/amneziawg-remove-peer"
ok "Команды доступны: amneziawg-add-peer, amneziawg-remove-peer"

# -------- первый пир --------
echo
say "Создаю первое устройство: $PEER_NAME"
"$BIN_DIR/amneziawg-add-peer" "$PEER_NAME"

# -------- итог --------
echo
echo "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo "  ${GRN}✓ Готово${RST}"
echo "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo
echo "  Сервер:           ${CYA}$PUBLIC_IP:$PORT${RST} (UDP)"
echo "  Интерфейс:        ${CYA}$WG_NAME${RST}"
echo "  Подсеть:          ${CYA}$SUBNET.0/24${RST}"
echo "  Конфиг сервера:   ${CYA}$CONF_DIR/$WG_NAME.conf${RST}"
echo "  Конфиги клиентов: ${CYA}/root/vpn-clients/<имя>.conf${RST}"
echo
echo "  Добавить устройство:  ${CYA}sudo amneziawg-add-peer <имя>${RST}"
echo "  Удалить устройство:   ${CYA}sudo amneziawg-remove-peer <имя>${RST}"
echo "  Статус туннеля:       ${CYA}sudo awg show${RST}"
echo
echo "  ${YEL}Важно:${RST} на телефоне/компьютере используй приложение ${CYA}AmneziaVPN${RST}."
echo "  Обычный WireGuard ${RED}не подойдёт${RST} — он не умеет обфускацию Jc/S1/H1."
echo "  Скачать: ${CYA}https://amnezia.org/downloads${RST}"
echo
