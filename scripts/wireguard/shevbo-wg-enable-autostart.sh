#!/usr/bin/env bash
# Автоподнятие WireGuard shevbo-cloud <-> shevbo-pi: enable + start wg-quick, опционально timer health-check.
#
# Запуск на КАЖДОМ хосте с sudo:
#   sudo bash scripts/wireguard/shevbo-wg-enable-autostart.sh
#
# Перед этим:
#   1) Должен существовать /etc/wireguard/wg0.conf (ключи и peer уже согласованы).
#   2) На Pi за NAT рекомендуется один раз:
#        sudo bash scripts/wireguard/shevbo-wg-peer-ensure-keepalive.sh
#   3) Для периодического ping противоположной стороны и restart при обрыве:
#        sudo cp scripts/wireguard/shevbo-wg-health.default.example /etc/default/shevbo-wg-health
#        отредактировать WG_HEALTH_TARGET (на Pi — IP облака в WG, на облаке — IP Pi в WG)
#        снова: sudo bash scripts/wireguard/shevbo-wg-enable-autostart.sh
#
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Нужен sudo"; exit 1; }

WG_IF="${WG_IF:-wg0}"
CONF="/etc/wireguard/${WG_IF}.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$CONF" ]] || { echo "Ошибка: нет $CONF — сначала создайте конфиг WireGuard."; exit 1; }

install -d -m 755 /usr/local/sbin
install -m 755 "$SCRIPT_DIR/shevbo-wg-healthcheck.sh" /usr/local/sbin/shevbo-wg-healthcheck.sh

systemctl daemon-reload
systemctl enable "wg-quick@${WG_IF}"
if systemctl is-active --quiet "wg-quick@${WG_IF}"; then
  echo "wg-quick@${WG_IF} уже active"
else
  systemctl start "wg-quick@${WG_IF}"
fi

if [[ -f /etc/default/shevbo-wg-health ]]; then
  install -m 644 "$SCRIPT_DIR/shevbo-wg-health.service" /etc/systemd/system/shevbo-wg-health.service
  install -m 644 "$SCRIPT_DIR/shevbo-wg-health.timer" /etc/systemd/system/shevbo-wg-health.timer
  systemctl daemon-reload
  systemctl enable shevbo-wg-health.timer
  systemctl start shevbo-wg-health.timer
  echo "Включён timer: shevbo-wg-health.timer (см. /etc/default/shevbo-wg-health)"
  systemctl status shevbo-wg-health.timer --no-pager -l || true
else
  echo "Нет /etc/default/shevbo-wg-health — health-timer не ставим (только wg-quick autostart)."
  systemctl disable shevbo-wg-health.timer 2>/dev/null || true
  systemctl stop shevbo-wg-health.timer 2>/dev/null || true
fi

echo "=== Готово: wg-quick@${WG_IF} enabled + started ==="
systemctl is-active "wg-quick@${WG_IF}" && wg show "$WG_IF" 2>/dev/null | head -20 || true
