#!/bin/bash
# Реестр: health check ссылается на /home/.../.openclaw/workspace/monitoring — вне корня sandbox.
# 1) Симлинк monitoring внутрь каждого sandboxes/agent-* (если разрешены symlink наружу).
# 2) Замена жёстко прошитого абсолютного пути на относительный "monitoring" в текстах под workspace
#    (и опционально в ~/.openclaw/openclaw.json), чтобы агент/cron не запрашивали путь хоста.
set -euo pipefail
WS="${HOME}/.openclaw/workspace"
MON="${WS}/monitoring"
SB="${HOME}/.openclaw/sandboxes"
BAD="${HOME}/.openclaw/workspace/monitoring"
# Относительный путь от корня workspace в промптах/cron
GOOD="monitoring"

mkdir -p "$MON"
if [[ ! -f "$MON/README.observer-autolink.txt" ]]; then
  cat >"$MON/README.observer-autolink.txt" <<'EOF'
В sandbox используйте только пути внутри workspace:
  monitoring/...     или     /workspace/monitoring/...
Не используйте абсолютный путь /home/<user>/.openclaw/workspace/monitoring в заданиях и health check.
EOF
fi

_patch_files_under_workspace() {
  [[ -d "$WS" ]] || return 0
  local patched=0
  while IFS= read -r -d '' f; do
    grep -qF "$BAD" "$f" 2>/dev/null || continue
    sed -i.bak "s|${BAD}/|${GOOD}/|g; s|${BAD}|${GOOD}|g" "$f"
    echo "[fix-monitoring-workspace-in-sandbox] patched: $f (backup .bak)"
    patched=$((patched + 1))
  done < <(find "$WS" -type f \( \
    -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.txt' -o -name '*.sh' \
  \) ! -path '*/.git/*' ! -name '*.bak' -print0 2>/dev/null || true)
  echo "[fix-monitoring-workspace-in-sandbox] workspace text patches: $patched"
}

_patch_openclaw_json() {
  local j="${HOME}/.openclaw/openclaw.json"
  [[ -f "$j" ]] || return 0
  grep -qF "$BAD" "$j" 2>/dev/null || return 0
  sed -i.bak "s|${BAD}/|${GOOD}/|g; s|${BAD}|${GOOD}|g" "$j"
  echo "[fix-monitoring-workspace-in-sandbox] patched: $j (backup .bak) — выполните: openclaw config validate"
}

if [[ "${OBSERVER_SKIP_MONITORING_PATH_REPLACE:-0}" != "1" ]]; then
  _patch_files_under_workspace
  _patch_openclaw_json
fi

if [[ ! -d "$SB" ]]; then
  echo "[fix-monitoring-workspace-in-sandbox] no $SB — symlinks skipped"
  exit 0
fi

shopt -s nullglob
linked=0
for d in "$SB"/agent-*; do
  [[ -d "$d" ]] || continue
  if [[ -d "$d/monitoring" && ! -L "$d/monitoring" ]]; then
    echo "[fix-monitoring-workspace-in-sandbox] skip $d: monitoring is a real directory"
    continue
  fi
  ln -sfn "$MON" "$d/monitoring"
  echo "[fix-monitoring-workspace-in-sandbox] linked $d/monitoring -> $MON"
  linked=$((linked + 1))
done
shopt -u nullglob

echo "[fix-monitoring-workspace-in-sandbox] done (symlinks=$linked). Если ошибка останется — перезапустите шлюз после validate."
