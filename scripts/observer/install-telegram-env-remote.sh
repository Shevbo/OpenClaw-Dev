#!/bin/bash
# Одноразово на сервере: читает токен из openclaw.json, пишет telegram.env
set -euo pipefail
CFG="${1:-$HOME/.openclaw/openclaw.json}"
OUT="${2:-$HOME/.config/openclaw/observer/telegram.env}"
CHAT_ID="${3:-36910539}"
mkdir -p "$(dirname "$OUT")"
BOT=$(jq -r '.channels.telegram.botToken // empty' "$CFG")
if [[ -z "$BOT" ]]; then
  echo "Нет channels.telegram.botToken в $CFG" >&2
  exit 1
fi
umask 077
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$BOT" "$CHAT_ID" >"$OUT"
chmod 600 "$OUT"
echo "OK $OUT ($(wc -c <"$OUT") bytes)"
