#!/usr/bin/env bash
# Забрать вики с шлюза в репозиторий (после правок на VPS).
# Запуск из корня репозитория: bash scripts/openclaw/sync-wiki-from-gateway.sh

set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOST="${WIKI_HOST:-shevbo-cloud}"
R="shevbo@${HOST}:/home/shevbo/.openclaw/Wiki"

echo "==> Pull ${R}/*.md -> repo"

scp "${R}/AGENTS.md" \
	"${R}/CONTINUATION-CONTEXT.md" \
	"${R}/AGENT-CONTEXT-OpenClaw-Caddy-Developer.md" \
	"${R}/cursor-handoff-openclaw-shevbo-cloud.md" \
	"$ROOT/"

for f in Wiki-INDEX.md Caddy.md OpenClaw-shevbo-google-only-voice.md SSH-shevbo-cloud-to-pi.md \
	OpenClaw-Pi-remote-node-WireGuard.md OpenClaw-Pi-repair-rotate-and-secrets.md; do
	scp "${R}/${f}" "$ROOT/scripts/wiki/" 2>/dev/null || echo "skip missing: $f"
done

scp "${R}/Wiki-Observer.md" "$ROOT/scripts/observer/Wiki-Observer.md" 2>/dev/null || true
scp "${R}/Wiki-OBSERVER-TROUBLESHOOTING-GUIDE.md" "$ROOT/scripts/observer/troubleshooting/GUIDE.md" 2>/dev/null || true

echo "Done. Проверьте git diff и закоммитьте при необходимости."
