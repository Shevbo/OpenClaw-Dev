#!/usr/bin/env bash
# Запуск на сервере: проверка POST /save с токеном из ~/.openclaw/.workspace-api-token
set -euo pipefail
TOKEN_FILE="${HOME}/.openclaw/.workspace-api-token"
PORT="${WORKSPACE_API_PORT:-38471}"
TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
curl -sS -w "\nHTTP %{http_code}\n" -X POST "http://127.0.0.1:${PORT}/save" \
  -H "Content-Type: application/json; charset=utf-8" \
  -H "X-Api-Token: ${TOKEN}" \
  -d '{"relativePath":".openclaw/_workspace-api-probe.txt","content":"ok"}'

# Через тот же домен, что и в браузере (проверка Caddy → API):
if [[ "${1:-}" == "--public" ]]; then
  echo "--- via https://claw.shectory.ru/links/api/save"
  curl -sS -w "\nHTTP %{http_code}\n" -X POST "https://claw.shectory.ru/links/api/save" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "X-Api-Token: ${TOKEN}" \
    -d '{"relativePath":".openclaw/_workspace-api-probe-public.txt","content":"ok"}'
fi
