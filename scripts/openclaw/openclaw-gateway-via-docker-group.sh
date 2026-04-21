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
# Высший приоритет: не доверять NO_PROXY из файла Proxy6 для облачных API.
# Иначе шаблон вроде *.googleapis.com / api.telegram.org может дать прямой выход
# и сломать egress ИЛИ обойти SSRF-режим fetch (см. resolveProviderHttpRequestConfig в OpenClaw).
# Локальный health/проба шлюза — только loopback.
export NO_PROXY="127.0.0.1,localhost,::1"
export no_proxy="$NO_PROXY"
exec sg docker -c "exec /usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port ${OPENCLAW_GATEWAY_PORT:-18789}"
