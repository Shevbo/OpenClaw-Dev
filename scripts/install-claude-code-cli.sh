#!/usr/bin/env bash
# Установка Claude Code CLI рядом с пользовательским окружением (без sudo).
# Официальный curl https://claude.ai/install.sh с VPS в RU часто отдаёт HTML «region» — используем npm.
set -euo pipefail
: "${HOME:?}"
PREFIX="${NPM_PREFIX:-$HOME/.local}"
export PATH="$PREFIX/bin:$PATH"
mkdir -p "$PREFIX/bin"
npm install -g --prefix "$PREFIX" @anthropic-ai/claude-code
echo "Установлено: $PREFIX/bin/claude"
"$PREFIX/bin/claude" --version
