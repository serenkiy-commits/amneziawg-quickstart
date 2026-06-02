#!/usr/bin/env bash
#
# amneziawg-remove-peer — удалить устройство из AmneziaWG.
#
#   sudo amneziawg-remove-peer <имя>
#
# Что делает:
#   1) находит PublicKey по комментарию "# <имя>" в awg0.conf
#   2) удаляет блок [Peer] из awg0.conf
#   3) применяет на лету (awg set ... remove — остальные пиры не страдают)
#   4) удаляет /root/vpn-clients/<имя>.conf и QR

set -euo pipefail

NAME="${1:-}"
CONF_DIR=/etc/amnezia/amneziawg
WG_NAME=awg0
OUT_DIR=/root/vpn-clients

[[ $EUID -eq 0 ]] || { echo "Запусти от root: sudo $0 $*"; exit 1; }
[[ -n "$NAME" ]] || { echo "Использование: $0 <имя>"; exit 1; }

CONF="$CONF_DIR/$WG_NAME.conf"
[[ -f "$CONF" ]] || { echo "Нет $CONF"; exit 1; }

if ! grep -q "^# $NAME$" "$CONF"; then
  echo "Устройство '$NAME' не найдено в $CONF"
  exit 1
fi

# Найти PublicKey: после строки "# NAME" идёт строка "PublicKey = ..."
PUB=$(awk -v n="$NAME" '
  $0 == "# " n {found=1; next}
  found && /^PublicKey = / {print $3; exit}
' "$CONF")

[[ -n "$PUB" ]] || { echo "Не смог вытащить PublicKey для '$NAME'"; exit 1; }

# Удалить блок [Peer] вместе с пустой строкой перед ним.
# Блок = от строки "[Peer]" до следующей пустой строки (либо EOF).
python3 - "$CONF" "$NAME" <<'PY'
import sys, re, pathlib
path = pathlib.Path(sys.argv[1])
name = sys.argv[2]
text = path.read_text()
# Регексп: опциональная пустая строка + [Peer] + комментарий имени + всё до пустой строки или конца файла
pattern = re.compile(
    r'\n*\[Peer\]\s*\n# ' + re.escape(name) + r'\s*\n(?:(?!\n\s*\n|\n\[).*\n?)+',
    re.MULTILINE
)
new_text, n = pattern.subn('\n', text, count=1)
if n == 0:
    sys.exit(f"Не нашёл блок [Peer] для '{name}'")
path.write_text(new_text)
PY

# Снять пир на лету
awg set "$WG_NAME" peer "$PUB" remove

# Удалить клиентские файлы
rm -f "$OUT_DIR/$NAME.conf" "$OUT_DIR/$NAME.png"

# Удалить локальные ключи если есть (на случай старых установок где они хранились)
rm -f "$CONF_DIR/${NAME}_private.key" \
      "$CONF_DIR/${NAME}_public.key" \
      "$CONF_DIR/${NAME}_psk.key"

echo "✓ $NAME удалён (PublicKey: ${PUB:0:16}...)"
