#!/bin/bash
# Реестр: EADDRINUSE — перезапуск шлюза и при наличии caddy (как в основном observer).
set -euo pipefail
UNIT="${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}"
echo "[fix-eaddrinuse] restart $UNIT"
systemctl --user restart "$UNIT" || systemctl --user start "$UNIT"
sleep 4
if systemctl is-active --quiet caddy 2>/dev/null; then
  if sudo -n systemctl restart caddy 2>/dev/null; then
    echo "[fix-eaddrinuse] caddy restarted"
  else
    echo "[fix-eaddrinuse] caddy restart skipped (no sudo -n)"
  fi
fi
