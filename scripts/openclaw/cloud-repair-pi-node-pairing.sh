#!/usr/bin/env bash
# Запуск на shevbo-cloud: безопасная пере-пара Pi-node + ротация gateway.auth.token + синхронизация на Pi.
# Не выводит токены. Требует: jq, openssl, ssh к shevbo-pi.
#
# Переменные:
#   PI_SSH=shevbo-pi
#   NODE_DEVICE_ID — deviceId роли node для Pi (по умолчанию из предыдущей пары; можно переопределить)
#   SKIP_GATEWAY_TOKEN_ROTATE=1 — не менять gateway.auth.token (только снять пару и заново одобрить)
#
set -euo pipefail
command -v jq openssl ssh >/dev/null
PI="${PI_SSH:-shevbo-pi}"
STATE="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CFG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
NODE_DEVICE_ID="${NODE_DEVICE_ID:-}"

if [[ -z "$NODE_DEVICE_ID" ]]; then
  NODE_DEVICE_ID="$(jq -r '.paired[] | select(.clientId == "node-host" and .clientMode == "node") | .deviceId' \
    <(openclaw devices list --json 2>/dev/null) | head -1)"
fi
[[ -n "$NODE_DEVICE_ID" && "$NODE_DEVICE_ID" != "null" ]]

echo "[repair] Останавливаю node на Pi..."
ssh "$PI" "systemctl --user stop openclaw-node.service 2>/dev/null || true"

echo "[repair] Снимаю device pairing node-host: $NODE_DEVICE_ID"
openclaw devices remove "$NODE_DEVICE_ID" 2>/dev/null || true

echo "[repair] Очищаю node.pair store (paired/pending)..."
mkdir -p "$STATE/nodes"
printf '%s\n' '{}' >"$STATE/nodes/paired.json"
printf '%s\n' '{}' >"$STATE/nodes/pending.json"

if [[ "${SKIP_GATEWAY_TOKEN_ROTATE:-0}" != "1" ]]; then
  echo "[repair] Ротация gateway.auth.token..."
  NEWTOK="$(openssl rand -hex 24)"
  openclaw config set gateway.auth.token "$NEWTOK"
  openclaw config validate
else
  openclaw config validate
fi

echo "[repair] Перезапуск шлюза..."
systemctl --user restart openclaw-gateway.service
sleep 5
systemctl --user is-active openclaw-gateway.service

echo "[repair] Синхронизация токена на Pi и сброс node.json..."
TOK="$(jq -r '.gateway.auth.token // empty' "$CFG")"
[[ -n "$TOK" && "$TOK" != "null" ]]
umask 077
printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$TOK" | ssh "$PI" 'umask 077; cat > /home/shevbo/.config/openclaw/pi-node-remote.env'
ssh "$PI" "rm -f /home/shevbo/.openclaw/node.json"
ssh "$PI" "systemctl --user start openclaw-node.service"
sleep 6

wait_first_key() {
  local file="$1" label="$2" max_wait="${3:-90}"
  local waited=0
  while (( waited < max_wait )); do
    if [[ -f "$file" ]]; then
      local k
      k="$(jq -r 'keys[0] // empty' "$file" 2>/dev/null || true)"
      if [[ -n "$k" && "$k" != "null" ]]; then
        echo "$k"
        return 0
      fi
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "[repair] WARN: нет ключа в $label за ${max_wait}s" >&2
  return 1
}

echo "[repair] Ожидание device pairing (Pi должна достучаться до шлюза по WG)..."
DREQ="$(wait_first_key "$STATE/devices/pending.json" devices/pending.json 90 || true)"
if [[ -n "${DREQ:-}" ]]; then
  echo "[repair] devices approve <requestId>"
  openclaw devices approve "$DREQ"
else
  echo "[repair] WARN: пропуск devices approve — проверьте WG и логи node на Pi" >&2
fi

sleep 3

echo "[repair] Ожидание node.pair заявки..."
NREQ="$(wait_first_key "$STATE/nodes/pending.json" nodes/pending.json 90 || true)"
if [[ -n "${NREQ:-}" ]]; then
  echo "[repair] nodes approve <requestId> (вывод подавлен)"
  openclaw nodes approve "$NREQ" >/dev/null
else
  echo "[repair] WARN: пропуск nodes approve — смотрите ~/.openclaw/nodes/pending.json" >&2
fi

ssh "$PI" "systemctl --user restart openclaw-node.service" || true
sleep 6

echo "[repair] Проверка (без секретов):"
openclaw nodes status --connected 2>/dev/null | head -20 || true
ssh "$PI" "systemctl --user is-active openclaw-node.service"
