#!/bin/bash
# Добавить фрагмент из Telegram в ingest.d для следующего цикла observer (registry-runner).
# Использование:
#   ./append-telegram-ingest.sh 'текст из чата'
#   pbpaste | ./append-telegram-ingest.sh     # macOS
#   powershell Get-Clipboard | wsl bash ./append-telegram-ingest.sh
set -euo pipefail
BASE="${OBSERVER_TROUBLESHOOTING_DIR:-$HOME/.config/openclaw/observer/troubleshooting}"
DIR="$BASE/ingest.d"
mkdir -p "$DIR"
OUT="$DIR/telegram-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "=== $(date -Iseconds) ==="
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$*"
  else
    cat
  fi
} >>"$OUT"
echo "Written: $OUT (observer подхватит за ≤5 мин)"
