#!/usr/bin/env bash
# PostDown: убрать правила пометки и policy rule (маршруты из таблицы снимет wg-quick).
set -euo pipefail
MARK_HEX="0xca6c"
TABLE="${WG_TABLE:-51820}"

iptables -t mangle -D OUTPUT -j OCWG 2>/dev/null || true
iptables -t mangle -F OCWG 2>/dev/null || true
iptables -t mangle -X OCWG 2>/dev/null || true

if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -t mangle -D OUTPUT -j OCWG6 2>/dev/null || true
  ip6tables -t mangle -F OCWG6 2>/dev/null || true
  ip6tables -t mangle -X OCWG6 2>/dev/null || true
fi

while ip rule del fwmark "$MARK_HEX" table "$TABLE" 2>/dev/null; do true; done
while ip -6 rule del fwmark "$MARK_HEX" table "$TABLE" 2>/dev/null; do true; done

exit 0
