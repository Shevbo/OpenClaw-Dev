#!/bin/bash
# Одноразово: копирует pubkey на Pi (нужен пароль по SSH или уже работающий доступ).
# Использование: ./shevbo-cloud-install-pi-key.sh user@pi-host-or-ip
set -euo pipefail
PUB="${HOME}/.ssh/id_ed25519_shevbo_pi.pub"
if ! [[ -f "$PUB" ]]; then
  echo "Нет $PUB — сначала ssh-keygen на shevbo-cloud." >&2
  exit 1
fi
TARGET="${1:?укажи user@host}"
ssh-copy-id -i "$PUB" -o StrictHostKeyChecking=accept-new "$TARGET"
echo "OK: проверка: ssh shevbo-pi  (после правки HostName в ~/.ssh/config)"
