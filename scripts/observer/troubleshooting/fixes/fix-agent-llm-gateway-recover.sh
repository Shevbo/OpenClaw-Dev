#!/bin/bash
# Реестр: агент не смог сгенерировать ответ / cron billing-monitor (часто сбой LLM, таймаут, сессия).
# Мягкое восстановление: валидация конфига + перезапуск шлюза (не трогает ключи и квоты).
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:${HOME}/.local/bin:${HOME}/.npm-global/bin:${PATH}"
UNIT="${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}"
LOG="${HOME}/.local/log/openclaw-observer-llm-recover.log"
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Iseconds) fix-agent-llm-gateway-recover ==="
  if command -v openclaw >/dev/null 2>&1; then
    openclaw config validate 2>&1 || true
    openclaw gateway status 2>&1 || true
  else
    echo "openclaw CLI not in PATH for this script user"
  fi
  echo "--- journal tail gateway ---"
  journalctl --user -u "$UNIT" -n 40 --no-pager 2>&1 || true
} >>"$LOG" 2>&1

echo "[fix-agent-llm-gateway-recover] restarting $UNIT (see $LOG)"
systemctl --user restart "$UNIT" || systemctl --user start "$UNIT"
sleep 6
echo "[fix-agent-llm-gateway-recover] done"
