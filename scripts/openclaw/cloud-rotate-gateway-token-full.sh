#!/usr/bin/env bash
# Запуск на shevbo-cloud: новый gateway.auth.token, перезапуск шлюза, синхронизация Pi, URL для Control UI в файл.
set -euo pipefail
NEW="$(openssl rand -hex 24)"
openclaw config set gateway.auth.token "$NEW"
openclaw config validate
systemctl --user restart openclaw-gateway.service
sleep 4
systemctl --user is-active openclaw-gateway.service
if [[ -x "${HOME}/bin/cloud-sync-pi-gateway-token.sh" ]]; then
  bash "${HOME}/bin/cloud-sync-pi-gateway-token.sh"
fi
if [[ -x "${HOME}/bin/cloud-refresh-control-ui-connect.sh" ]]; then
  bash "${HOME}/bin/cloud-refresh-control-ui-connect.sh"
fi
echo "[rotate] done (token not printed). Pi node restarted if cloud-sync present."
