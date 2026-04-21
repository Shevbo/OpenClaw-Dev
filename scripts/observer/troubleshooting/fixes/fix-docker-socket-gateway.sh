#!/bin/bash
# Реестр: docker.sock недоступен процессу шлюза — перезапуск user-unit (часто после смены группы/docker).
set -euo pipefail
echo "[fix-docker-socket-gateway] restarting gateway user service"
systemctl --user restart "${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}" || systemctl --user start "${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}"
sleep 5
if docker info >/dev/null 2>&1; then
  echo "[fix-docker-socket-gateway] docker info: ok"
else
  echo "[fix-docker-socket-gateway] warn: docker info failed (проверь группу docker / unit sg docker)" >&2
fi
