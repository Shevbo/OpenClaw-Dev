#!/bin/bash
set -euo pipefail
set -a
# shellcheck source=/dev/null
source "${1:-$HOME/.config/openclaw/gateway-api-keys.env}"
set +a
if [[ -z "${GOOGLE_API_KEY:-}" ]]; then
  echo "GOOGLE_API_KEY empty" >&2
  exit 1
fi
code=$(curl -sS -o /tmp/gmodels.json -w "%{http_code}" "https://generativelanguage.googleapis.com/v1beta/models?key=${GOOGLE_API_KEY}")
echo "HTTP ${code}"
head -c 180 /tmp/gmodels.json
echo
