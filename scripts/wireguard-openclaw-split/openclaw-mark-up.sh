#!/usr/bin/env bash
# PostUp для wg0: маршрутизация по fwmark только для трафика openclaw-gateway → таблица WG.
set -euo pipefail
MARK_HEX="0xca6c"
TABLE="${WG_TABLE:-51820}"
CGROUP="${OPENCLAW_CGROUP:-user.slice/user-1000.slice/user@1000.service/app.slice/openclaw-gateway.service}"

ip rule add fwmark "$MARK_HEX" table "$TABLE" pref 100 2>/dev/null || true
ip -6 rule add fwmark "$MARK_HEX" table "$TABLE" pref 100 2>/dev/null || true

iptables -t mangle -N OCWG 2>/dev/null || true
iptables -t mangle -F OCWG
iptables -t mangle -D OUTPUT -j OCWG 2>/dev/null || true
iptables -t mangle -A OUTPUT -j OCWG
iptables -t mangle -A OCWG -m cgroup --path "$CGROUP" -j MARK --set-mark "$MARK_HEX"

if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -t mangle -N OCWG6 2>/dev/null || true
  ip6tables -t mangle -F OCWG6
  ip6tables -t mangle -D OUTPUT -j OCWG6 2>/dev/null || true
  ip6tables -t mangle -A OUTPUT -j OCWG6
  ip6tables -t mangle -A OCWG6 -m cgroup --path "$CGROUP" -j MARK --set-mark "$MARK_HEX"
fi

exit 0
