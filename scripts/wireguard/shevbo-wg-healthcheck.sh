#!/usr/bin/env bash
# Проверка связности по WG и при необходимости restart wg-quick (вызывается из systemd timer).
# Конфиг: /etc/default/shevbo-wg-health (см. shevbo-wg-health.default.example).
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Требуется root (systemd вызывает от root)"; exit 1; }

DEFAULT=/etc/default/shevbo-wg-health
[[ -f "$DEFAULT" ]] || exit 0

# shellcheck source=/dev/null
set -a
. "$DEFAULT"
set +a

WG_IF="${WG_IF:-wg0}"
T="${WG_HEALTH_TARGET:-}"
[[ -n "$T" ]] || exit 0

if ! ip link show "$WG_IF" &>/dev/null; then
  logger -t shevbo-wg-health "interface $WG_IF missing, starting wg-quick@${WG_IF}"
  systemctl start "wg-quick@${WG_IF}" 2>/dev/null || true
  exit 0
fi

if ping -c 2 -W 4 "$T" &>/dev/null; then
  exit 0
fi

logger -t shevbo-wg-health "ping $T via $WG_IF failed, restarting wg-quick@${WG_IF}"
systemctl restart "wg-quick@${WG_IF}"
