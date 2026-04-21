#!/bin/bash
# Реестр: в контейнере песочницы нет node/python/openclaw — пересоздать sandbox-контейнеры и перезапустить шлюз.
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:${HOME}/.local/bin:${HOME}/.npm-global/bin:${HOME}/.volta/bin:${PATH}"
UNIT="${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}"

echo "[fix-sandbox-recreate] openclaw in PATH: $(command -v openclaw || echo MISSING)"

if command -v openclaw >/dev/null 2>&1; then
  echo "[fix-sandbox-recreate] openclaw sandbox explain (кратко):"
  openclaw sandbox explain 2>&1 | head -40 || true
  if openclaw sandbox recreate --help >/dev/null 2>&1; then
    echo "[fix-sandbox-recreate] openclaw sandbox recreate --all --force"
    openclaw sandbox recreate --all --force 2>&1 || true
  else
    echo "[fix-sandbox-recreate] подкоманда recreate недоступна, пробуем prune"
    openclaw sandbox prune --help >/dev/null 2>&1 && openclaw sandbox prune 2>&1 || true
  fi
else
  echo "[fix-sandbox-recreate] openclaw CLI не найден — только перезапуск шлюза" >&2
fi

if command -v docker >/dev/null 2>&1; then
  echo "[fix-sandbox-recreate] docker images (openclaw):"
  docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -iE 'openclaw|sandbox' | head -15 || true
fi

echo "[fix-sandbox-recreate] restart $UNIT"
systemctl --user restart "$UNIT" || systemctl --user start "$UNIT"
sleep 8
echo "[fix-sandbox-recreate] done"
