#!/usr/bin/env bash
# Запуск на shevbo-cloud: проверка входа на Pi без пароля (интерактив недоступен из exec).
# Успех только при готовых ключах. Имя хоста из ~/.ssh/config: PI_SSH или shevbo-pi.
set -euo pipefail
HOST="${PI_SSH:-shevbo-pi}"
TO="${SSH_CONNECT_TIMEOUT:-12}"
if ssh -o BatchMode=yes -o ConnectTimeout="$TO" "$HOST" 'echo batch-ok'; then
  echo "[verify-ssh] OK: $HOST (BatchMode)"
  exit 0
fi
echo "[verify-ssh] FAIL: $HOST — см. scripts/wiki/SSH-shevbo-cloud-to-pi.md и shevbo-cloud-install-pi-key.sh" >&2
exit 1
