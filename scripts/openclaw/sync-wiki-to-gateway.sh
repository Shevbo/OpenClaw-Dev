#!/usr/bin/env bash
# Выгрузка всей документации и контекстов в каноническую вики на шлюзе:
#   /home/shevbo/.openclaw/Wiki/
#
# Запуск из корня репозитория: bash scripts/openclaw/sync-wiki-to-gateway.sh
# Переменная: WIKI_HOST=shevbo-cloud (по умолчанию)

set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOST="${WIKI_HOST:-shevbo-cloud}"
R="shevbo@${HOST}:/home/shevbo/.openclaw/Wiki/"

echo "==> Sync repo documentation -> ${R}"

scp "$ROOT/AGENTS.md" \
	"$ROOT/CONTINUATION-CONTEXT.md" \
	"$ROOT/AGENT-CONTEXT-OpenClaw-Caddy-Developer.md" \
	"$ROOT/cursor-handoff-openclaw-shevbo-cloud.md" \
	"$ROOT/scripts/wiki/"*.md \
	"$ROOT/scripts/observer/Wiki-Observer.md" \
	"$R"

scp "$ROOT/scripts/observer/troubleshooting/GUIDE.md" \
	"${HOST}:/home/shevbo/.openclaw/Wiki/Wiki-OBSERVER-TROUBLESHOOTING-GUIDE.md"

echo "Done. Index: /home/shevbo/.openclaw/Wiki/Wiki-INDEX.md"
