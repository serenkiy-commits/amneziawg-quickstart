#!/usr/bin/env bash
#
# uninstall.sh — полностью убрать AmneziaWG-сервер с этого VPS.
# ВНИМАНИЕ: удалит /etc/amnezia/amneziawg/ и /root/vpn-clients/ — все клиентские конфиги.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Запусти от root: sudo bash $0"; exit 1; }

read -rp "Реально удалить AmneziaWG со всеми конфигами? Это необратимо. [yes/NO] " ans
[[ "${ans,,}" == "yes" ]] || { echo "Отменено."; exit 0; }

systemctl disable --now awg-quick@awg0 2>/dev/null || true
awg-quick down awg0 2>/dev/null || true

apt-get remove --purge -y amneziawg amneziawg-tools 2>/dev/null || true
add-apt-repository -y --remove ppa:amnezia/ppa 2>/dev/null || true

rm -rf /etc/amnezia /etc/sysctl.d/99-amneziawg.conf
rm -rf /root/vpn-clients
rm -f /usr/local/sbin/amneziawg-add-peer /usr/local/sbin/amneziawg-remove-peer

sysctl --system >/dev/null

echo "✓ AmneziaWG удалён."
