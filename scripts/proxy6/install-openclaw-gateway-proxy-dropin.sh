#!/bin/bash
# Drop-in: подставить прокси в user openclaw-gateway из proxy.systemd.env
set -euo pipefail
U="${1:-$HOME}"
DROP="${U}/.config/systemd/user/openclaw-gateway.service.d"
mkdir -p "${DROP}"
cat >"${DROP}/proxy.conf" <<'EOF'
[Service]
EnvironmentFile=-%h/.config/proxy6/proxy.systemd.env
EOF
systemctl --user daemon-reload
echo "installed ${DROP}/proxy.conf — затем: systemctl --user restart openclaw-gateway"
