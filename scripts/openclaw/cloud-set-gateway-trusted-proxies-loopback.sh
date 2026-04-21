#!/usr/bin/env bash
# Запуск на shevbo-cloud: доверять reverse proxy (Caddy) на том же хосте — убирает WARN
# «Proxy headers detected from untrusted address» при token-auth за Caddy.
set -euo pipefail
openclaw config set gateway.trustedProxies '["127.0.0.1","::1"]' --strict-json
openclaw config validate
systemctl --user restart openclaw-gateway.service
sleep 4
systemctl --user is-active openclaw-gateway.service
echo "[trustedProxies] gateway.trustedProxies=$(jq -c '.gateway.trustedProxies' "${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}")"
