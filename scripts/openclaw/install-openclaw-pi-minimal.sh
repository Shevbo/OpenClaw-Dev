#!/usr/bin/env bash
# OpenClaw на Linux (в т.ч. Raspberry Pi): без правок системного Node, без Docker/Caddy.
# Node из репозитория openclaw: >=22.14.0 — ставим через nvm в $HOME/.nvm.
#
# Использование на Pi:
#   bash install-openclaw-pi-minimal.sh
#
# После установки CLI — onboarding (интерактивно или с ключом в env):
#   openclaw onboard --install-daemon
# или неинтерактивно (пример Anthropic):
#   export ANTHROPIC_API_KEY="..."
#   openclaw onboard --non-interactive --mode local --auth-choice apiKey \
#     --anthropic-api-key "$ANTHROPIC_API_KEY" --secret-input-mode plaintext \
#     --gateway-port 18789 --gateway-bind loopback --install-daemon --daemon-runtime node --skip-skills
#
# Автозапуск user-unit после перезагрузки (один раз sudo):
#   sudo loginctl enable-linger "$USER"
#
# Токен шлюза + systemd user unit (после первого onboard или пустого конфига):
#   bash scripts/openclaw/pi-onboard-finish.sh

set -euo pipefail

NVM_VER="${NVM_VER:-v0.40.3}"
NODE_MAJOR="${NODE_MAJOR:-22}"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "[openclaw-pi] Installing nvm to $NVM_DIR ..."
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VER}/install.sh" | bash
fi

# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"

echo "[openclaw-pi] Installing Node ${NODE_MAJOR} (LTS) via nvm ..."
nvm install "${NODE_MAJOR}"
nvm alias default "${NODE_MAJOR}"
nvm use default

node --version
npm --version

echo "[openclaw-pi] Installing openclaw CLI globally (nvm Node) ..."
npm install -g "openclaw@latest"

openclaw --version
# nvm install уже дописал загрузку в ~/.bashrc — не дублируем.

echo ""
echo "[openclaw-pi] CLI готово. Дальше:"
echo "  1) Интерактив:  openclaw onboard --install-daemon"
echo "  2) Или задайте ANTHROPIC_API_KEY (и см. комментарий в начале этого скрипта)."
echo "  3) После daemon:  sudo loginctl enable-linger \"$USER\"   # автозапуск user-сервисов после reboot"
echo ""
