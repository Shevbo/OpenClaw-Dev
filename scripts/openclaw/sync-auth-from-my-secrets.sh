#!/bin/bash
# Подставляет ключи из ~/.openclaw/my_secrets.json в auth-profiles.json (google:default, openai:default),
# затем можно вызвать sync-google-tts-key-from-auth.sh для GOOGLE_API_KEY в systemd.
set -euo pipefail
SECRETS="${1:-$HOME/.openclaw/my_secrets.json}"
AUTH="${2:-$HOME/.openclaw/agents/main/agent/auth-profiles.json}"
if ! [[ -f "$SECRETS" ]]; then
  echo "Нет файла: $SECRETS" >&2
  exit 1
fi
if ! [[ -f "$AUTH" ]]; then
  echo "Нет файла: $AUTH" >&2
  exit 1
fi
cp -a "$AUTH" "${AUTH}.bak.$(date +%Y%m%d%H%M%S)"
G=$(jq -r '.google.api_key // empty' "$SECRETS" | tr -d '\r\n')
O=$(jq -r '.openai.api_key // empty' "$SECRETS" | tr -d '\r\n')
if [[ -z "$G" ]]; then
  echo "В $SECRETS нет .google.api_key" >&2
  exit 1
fi
if [[ "$G" == AAIza* ]]; then
  echo "Ошибка: google.api_key начинается с «AAIza…» — лишняя «A». У валидного ключа Google префикс «AIzaSy…» (одна A)." >&2
  exit 1
fi
if [[ "$G" != AIza* ]]; then
  echo "Предупреждение: google.api_key обычно начинается с «AIza…». Проверьте копирование из Google AI Studio." >&2
fi
if [[ -z "$O" ]]; then
  echo "В $SECRETS нет .openai.api_key" >&2
  exit 1
fi
TMP=$(mktemp)
jq --arg g "$G" --arg o "$O" \
  '.profiles["google:default"].key = $g | .profiles["openai:default"].key = $o' "$AUTH" >"$TMP"
mv "$TMP" "$AUTH"
chmod 600 "$AUTH"
echo "OK $AUTH обновлён из my_secrets (google + openai)."
