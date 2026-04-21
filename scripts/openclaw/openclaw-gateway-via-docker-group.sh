#!/bin/bash
set -euo pipefail
# user systemd не подхватывает группу docker из /etc/group — доступ к docker.sock через sg(1)
exec sg docker -c "exec /usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port ${OPENCLAW_GATEWAY_PORT:-18789}"
