#!/usr/bin/env bash
# Запуск на shevbo-cloud: прочитать токен шлюза из сырого JSON (jq), подключиться по SSH к shevbo-pi и выполнить pi-node-remote-to-cloud.sh.
# Нужны: jq, ssh к shevbo-pi. На Pi: ~/bin/pi-node-remote-to-cloud.sh (chmod +x).
set -euo pipefail
command -v jq >/dev/null
CLOUD_WG_IP="${CLOUD_WG_IP:-10.66.0.3}"
CLOUD_GATEWAY_PORT="${CLOUD_GATEWAY_PORT:-18789}"
PI_SSH="${PI_SSH:-shevbo-pi}"
CFG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
TOK="$(jq -r '.gateway.auth.token // empty' "$CFG")"
[[ -n "$TOK" && "$TOK" != "null" ]]
QE="$(printf '%q' "$TOK")"
ssh "$PI_SSH" "export OPENCLAW_GATEWAY_TOKEN=$QE; export ALLOW_STOP_LOCAL_GATEWAY=1; export CLOUD_GATEWAY_HOST=$CLOUD_WG_IP; export CLOUD_GATEWAY_PORT=$CLOUD_GATEWAY_PORT; bash /home/shevbo/bin/pi-node-remote-to-cloud.sh"
