#!/bin/bash
# Кладёт GOOGLE_API_KEY в env-файл для шлюза: TTS читает ключ из env / models.providers.google.apiKey,
# но не из authProfile — см. extensions/google/speech-provider.js (resolveGoogleTtsApiKey).
set -euo pipefail
AUTH="${OPENCLAW_AUTH_PROFILES:-$HOME/.openclaw/agents/main/agent/auth-profiles.json}"
OUT="${OPENCLAW_GATEWAY_API_KEYS_ENV:-$HOME/.config/openclaw/gateway-api-keys.env}"
KEY="$(jq -r '.profiles["google:default"].key // empty' "$AUTH")"
if [[ -z "$KEY" ]]; then
  echo "Нет .profiles[\"google:default\"].key в $AUTH" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"
umask 077
printf 'GOOGLE_API_KEY=%s\n' "$KEY" >"$OUT"
chmod 600 "$OUT"
echo "OK $OUT"
