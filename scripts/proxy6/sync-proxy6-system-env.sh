#!/bin/bash
# Копирует proxy.systemd.env пользователя shevbo в /etc/proxy6/environment.env и обновляет конфиги.
# Запуск: sudo /usr/local/sbin/sync-proxy6-system-env.sh
set -euo pipefail
SRC=/home/shevbo/.config/proxy6/proxy.systemd.env
DST=/etc/proxy6/environment.env
GRP=proxyaccess

if ! [ -r "$SRC" ]; then
  echo "Нет $SRC — сначала: python3 /home/shevbo/.local/bin/proxy6-fetch-proxy-env.py" >&2
  exit 1
fi

getent group "$GRP" >/dev/null 2>&1 || groupadd -f "$GRP"
id -nG caddy 2>/dev/null | grep -qw "$GRP" || usermod -aG "$GRP" caddy 2>/dev/null || true
id -nG shevbo 2>/dev/null | grep -qw "$GRP" || usermod -aG "$GRP" shevbo 2>/dev/null || true

mkdir -p /etc/proxy6 /etc/environment.d
install -m 640 -o root -g "$GRP" "$SRC" "$DST"
install -m 640 -o root -g "$GRP" "$SRC" /etc/environment.d/99-proxy6-system.conf

cat >/etc/profile.d/99-proxy6-global.sh <<'EOF'
# Прокси для интерактивных shell (кроме явного unset)
if [ -f /etc/proxy6/environment.env ]; then
  set -a
  # shellcheck source=/dev/null
  . /etc/proxy6/environment.env
  set +a
fi
EOF
chmod 644 /etc/profile.d/99-proxy6-global.sh

if [ -d /etc/apt/apt.conf.d ]; then
  # Примерный формат; основной трафик apt — тот же прокси
  http_line="$(grep -E '^HTTPS_PROXY=' "$DST" | head -1 | cut -d= -f2-)"
  if [ -n "${http_line}" ]; then
    printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "${http_line}" "${http_line}" >/etc/apt/apt.conf.d/95proxy6.conf
    chmod 644 /etc/apt/apt.conf.d/95proxy6.conf
  fi
fi

mkdir -p /etc/systemd/system/caddy.service.d
cat >/etc/systemd/system/caddy.service.d/proxy.conf <<'EOF'
[Service]
EnvironmentFile=-/etc/proxy6/environment.env
EOF

if [ -d /home/shevbo/.config/systemd/user ]; then
  mkdir -p /home/shevbo/.config/systemd/user/openclaw-gateway.service.d
  cat >/home/shevbo/.config/systemd/user/openclaw-gateway.service.d/proxy.conf <<'EOF'
[Service]
EnvironmentFile=-/etc/proxy6/environment.env
EOF
  chown -R shevbo:shevbo /home/shevbo/.config/systemd/user/openclaw-gateway.service.d
fi

systemctl daemon-reload

if systemctl is-enabled caddy >/dev/null 2>&1; then
  systemctl restart caddy
fi

if id shevbo &>/dev/null; then
  u="$(id -u shevbo)"
  rund="/run/user/${u}"
  if [ -d "$rund" ]; then
    _usc() {
      sudo -u shevbo env \
        XDG_RUNTIME_DIR="$rund" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${rund}/bus" \
        systemctl --user "$@"
    }
    _usc daemon-reload 2>/dev/null || true
    if _usc is-enabled openclaw-gateway.service 2>/dev/null; then
      _usc restart openclaw-gateway.service 2>/dev/null || true
    fi
  fi
fi

echo "OK system proxy: $DST (group $GRP, mode 640)"
