#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
if [[ -r "${HOME}/.config/proxy6/proxy.systemd.env" ]]; then
	set -a
	# shellcheck source=/dev/null
	source "${HOME}/.config/proxy6/proxy.systemd.env"
	set +a
fi
set -a
# shellcheck source=/dev/null
source "${1:-$HOME/.config/openclaw/observer/telegram.env}"
set +a
PX=()
[[ -n "${HTTPS_PROXY:-}" ]] && PX=(-x "${HTTPS_PROXY}")
curl -sS -m 45 "${PX[@]}" -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${2:-OpenClaw observer: test OK}" | jq -e '.ok == true' >/dev/null
