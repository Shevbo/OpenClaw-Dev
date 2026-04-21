#!/bin/bash
# Однократно: снять wg0, правила маршрутизации OpenClaw, отключить wg-quick, убрать конфиги в backup.
# Запуск на сервере: sudo bash remove-wireguard-from-host.sh
set -euo pipefail

PHYS="${PHYS:-enp3s0}"
WG_CONF="${WG_CONF:-/etc/wireguard/wg0.conf}"

wg-quick down wg0 2>/dev/null || true
if [[ -x /etc/wireguard/openclaw-routing-down.sh ]]; then
  /etc/wireguard/openclaw-routing-down.sh 2>/dev/null || true
fi

ip route del default dev wg0 2>/dev/null || true

GW="$(ip -4 route show dev "${PHYS}" 2>/dev/null | awk '/^default/{print $3; exit}')"
PRIMARY="$(ip -4 -o addr show dev "${PHYS}" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"

if [[ -n "${GW}" && -n "${PRIMARY}" ]]; then
  ip route replace default via "${GW}" dev "${PHYS}" metric 100 2>/dev/null || true
fi

ip rule del from "${PRIMARY}" lookup 100 pref 90 2>/dev/null || true
ip rule del fwmark 0x5353 lookup 100 pref 90 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
ip rule del fwmark 0xca6c table 51820 pref 32765 2>/dev/null || true

for ep in 64.253.89.2 192.121.113.64; do
  ip route del "${ep}/32" via "${GW}" dev "${PHYS}" 2>/dev/null || true
done

if command -v dig >/dev/null 2>&1; then
  while read -r cip; do
    [[ -n "${cip}" ]] || continue
    ip route del "${cip}/32" via "${GW}" dev "${PHYS}" 2>/dev/null || true
  done < <(dig +short claw.shectory.ru A 2>/dev/null | grep -E '^[0-9.]+$' || true)
fi

iptables -t mangle -D OUTPUT -j OCWG-SSH 2>/dev/null || true
iptables -t mangle -F OCWG-SSH 2>/dev/null || true
iptables -t mangle -X OCWG-SSH 2>/dev/null || true
iptables -t mangle -D OUTPUT -j OCWG-OUT 2>/dev/null || true
iptables -t mangle -F OCWG-OUT 2>/dev/null || true
iptables -t mangle -X OCWG-OUT 2>/dev/null || true

systemctl disable wg-quick@wg0 2>/dev/null || true
systemctl stop wg-quick@wg0 2>/dev/null || true

BK="/root/wireguard-removed-backup"
mkdir -p "${BK}"
[[ -f /etc/wireguard/wg0.conf ]] && mv /etc/wireguard/wg0.conf "${BK}/wg0.conf.bak"
[[ -f /etc/wireguard/openclaw-routing-up.sh ]] && mv /etc/wireguard/openclaw-routing-up.sh "${BK}/"
[[ -f /etc/wireguard/openclaw-routing-down.sh ]] && mv /etc/wireguard/openclaw-routing-down.sh "${BK}/"
rm -f /run/openclaw-routing.state

echo "=== default routes ==="
ip route show default || true
echo "=== ip rules ==="
ip rule list || true
echo "=== done ==="
