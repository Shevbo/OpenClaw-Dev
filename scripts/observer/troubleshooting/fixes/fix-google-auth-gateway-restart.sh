#!/bin/bash
# Реестр: FailoverError / No available auth profile for google — часто временный cooldown; мягкий restart шлюза.
set -euo pipefail
UNIT="${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}"
LOG="${HOME}/.local/log/openclaw-observer-google-auth-recover.log"
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Iseconds) fix-google-auth-gateway-restart ==="
  journalctl --user -u "$UNIT" -n 30 --no-pager 2>&1 || true
} >>"$LOG" 2>&1

echo "[fix-google-auth-gateway-restart] restarting $UNIT (см. $LOG)"
systemctl --user restart "$UNIT" || systemctl --user start "$UNIT"
sleep 6
echo "[fix-google-auth-gateway-restart] done — если снова нет profile: ключи, квота, billing Google Cloud, openclaw config"
