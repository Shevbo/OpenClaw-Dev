#!/usr/bin/env bash
# Запуск на shevbo-cloud после смены gateway.auth.token: записать URL Control UI (с токеном)
# в файл с правами 600. В stdout токен не печатается.
set -euo pipefail
OUT="${OPENCLAW_CONTROL_UI_URL_FILE:-$HOME/.openclaw/tmp/control-ui-connect.url}"
PUBLIC_BASE="${OPENCLAW_CONTROL_UI_PUBLIC_BASE:-https://claw.shectory.ru}"
mkdir -p "$(dirname "$OUT")"
umask 077
TMP="${OUT}.tmp.$$"
# --no-open пишет несколько строк; берём только строку «Dashboard URL: …».
openclaw dashboard --no-open >"$TMP" 2>/dev/null
grep -E '^Dashboard URL: ' "$TMP" | head -1 \
  | sed -e "s#http://127.0.0.1:18789#${PUBLIC_BASE}#g" -e "s#http://localhost:18789#${PUBLIC_BASE}#g" >"$OUT"
rm -f "$TMP"
chmod 600 "$OUT"
echo "[control-ui] URL (с секретом в #fragment) записан в: $OUT"
echo "[control-ui] Откройте на доверенной машине: scp или ssh+cat; не вставляйте в чаты."
