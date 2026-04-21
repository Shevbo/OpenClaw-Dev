#!/bin/bash
# Подключает proxy.env в ~/.bashrc (интерактивные SSH-сессии).
set -euo pipefail
MARKER="# openclaw-proxy6-proxy-env"
RC="${HOME}/.bashrc"
if grep -q "${MARKER}" "${RC}" 2>/dev/null; then
  echo "already in ${RC}"
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
} >>"${RC}"
echo "appended to ${RC}"
