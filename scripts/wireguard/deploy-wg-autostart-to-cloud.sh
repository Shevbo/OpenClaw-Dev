#!/usr/bin/env bash
# Деплой WG health + autostart на shevbo-cloud. Нужен рабочий: ssh shevbo-cloud
# Git Bash / WSL / Linux, из корня репозитория:
#   bash scripts/wireguard/deploy-wg-autostart-to-cloud.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="${REMOTE:-shevbo-cloud}"
PI_WG_IP="${PI_WG_IP:-10.66.0.2}"

scp "$HERE/shevbo-wg-enable-autostart.sh" "$HERE/shevbo-wg-healthcheck.sh" \
  "$HERE/shevbo-wg-peer-ensure-keepalive.sh" "$HERE/shevbo-wg-health.service" \
  "$HERE/shevbo-wg-health.timer" "${REMOTE}:~/wireguard-deploy/"

ssh -o BatchMode=yes "$REMOTE" \
  "mkdir -p ~/wireguard-deploy && sed -i 's/\r\$//' ~/wireguard-deploy/*.sh 2>/dev/null || true && \
   chmod +x ~/wireguard-deploy/*.sh && \
   printf '%s\n' 'WG_IF=wg0' 'WG_HEALTH_TARGET=${PI_WG_IP}' | sudo tee /etc/default/shevbo-wg-health >/dev/null && \
   sudo chmod 644 /etc/default/shevbo-wg-health && \
   cd ~/wireguard-deploy && sudo bash shevbo-wg-enable-autostart.sh && \
   systemctl is-active wg-quick@wg0 && (systemctl is-active shevbo-wg-health.timer || true)"

echo "Done."
