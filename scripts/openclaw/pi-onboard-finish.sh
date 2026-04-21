#!/usr/bin/env bash
# Завершение установки на Pi: plaintext-токен шлюза + systemd user unit.
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
nvm use 22
TOK="$(openssl rand -hex 24)"
openclaw config set gateway.auth.token "$TOK"
openclaw config validate
openclaw gateway install
systemctl --user daemon-reload
systemctl --user enable --now openclaw-gateway.service
sleep 2
systemctl --user status openclaw-gateway.service --no-pager
openclaw gateway status
