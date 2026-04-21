#!/usr/bin/env bash
# Запуск на shevbo-cloud: взять токен шлюза из openclaw.json (сырой JSON), записать на Pi, перезапустить node.
set -euo pipefail
PI="${PI_SSH:-shevbo-pi}"
CFG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
TOK="$(jq -r '.gateway.auth.token // empty' "$CFG")"
[[ -n "$TOK" && "$TOK" != "null" ]]
umask 077
printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$TOK" | ssh "$PI" 'umask 077; cat > /home/shevbo/.config/openclaw/pi-node-remote.env'
ssh "$PI" "systemctl --user restart openclaw-node.service"
sleep 5
ssh "$PI" "systemctl --user is-active openclaw-node.service"
