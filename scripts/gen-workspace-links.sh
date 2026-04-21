#!/bin/bash
# Список файлов от корня $HOME → files.json для дерева на /links/
set -euo pipefail

ROOT="${WORKSPACE_LINKS_ROOT:-$HOME}"
OUT="${1:-/var/www/openclaw-links/files.json}"
MAXDEPTH="${WORKSPACE_LINKS_MAXDEPTH:-8}"

mkdir -p "$(dirname "$OUT")"
TMP="${OUT}.tmp.$$"
export ROOT

# Исключаем типичные чувствительные/тяжёлые каталоги
find "$ROOT" -maxdepth "$MAXDEPTH" \
  \( -path "$ROOT/.ssh" -o -path "$ROOT/.gnupg" -o -path "$ROOT/.cache" \) -prune -o \
  \( -name .git -o -name node_modules -o -name __pycache__ \) -prune -o \
  -type f -print 2>/dev/null | LC_ALL=C sort | python3 -c '
import os, json, sys
root = os.path.abspath(os.environ["ROOT"])
rel = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    ap = os.path.abspath(line)
    if not ap.startswith(root + os.sep):
        continue
    rel.append(os.path.relpath(ap, root).replace(os.sep, "/"))
print(json.dumps(rel, ensure_ascii=False))
' > "$TMP"

mv "$TMP" "$OUT"
