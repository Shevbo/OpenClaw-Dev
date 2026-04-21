#!/bin/bash
# Добавляет в ~/.profile подключение proxy.env (idempotent).
set -euo pipefail
MARKER="# openclaw-proxy6-proxy-env"
PROFILE="${HOME}/.profile"
if grep -q "${MARKER}" "${PROFILE}" 2>/dev/null; then
  echo "already in ${PROFILE}"
  exit 0
fi
{
  echo ""
  echo "${MARKER}"
  echo "if [ -f \"\$HOME/.config/proxy6/proxy.env\" ]; then"
  echo "  set -a"
  echo "  . \"\$HOME/.config/proxy6/proxy.env\""
  echo "  set +a"
  echo "fi"
} >>"${PROFILE}"
echo "appended to ${PROFILE}"
