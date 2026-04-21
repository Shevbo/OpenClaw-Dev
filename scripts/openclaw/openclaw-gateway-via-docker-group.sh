#!/bin/bash
set -euo pipefail
# user systemd не подхватывает группу docker из /etc/group — доступ к docker.sock через sg(1)
# Дублируем подстановку прокси: исходящий трафик шлюза (LLM и т.д.) должен идти через HTTP(S)_PROXY из unit.
for _f in "/etc/proxy6/environment.env" "${HOME}/.config/proxy6/proxy.systemd.env"; do
	[[ -r "$_f" ]] || continue
	set -a
	# shellcheck source=/dev/null
	. "$_f"
	set +a
done
exec sg docker -c "exec /usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port ${OPENCLAW_GATEWAY_PORT:-18789}"
