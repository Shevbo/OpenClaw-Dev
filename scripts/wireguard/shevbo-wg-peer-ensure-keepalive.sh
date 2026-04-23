#!/usr/bin/env bash
# Для клиента за NAT (обычно shevbo-pi): добавить PersistentKeepalive = 25 в [Peer], если есть Endpoint и нет keepalive.
# Не трогает конфиги без Endpoint (типичная сторона сервера в облаке).
# Запуск: sudo bash scripts/wireguard/shevbo-wg-peer-ensure-keepalive.sh
# Переменные: WG_IF (по умолчанию wg0), KEEPALIVE_SEC (по умолчанию 25)
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Нужен sudo"; exit 1; }

WG_IF="${WG_IF:-wg0}"
CONF="/etc/wireguard/${WG_IF}.conf"
KEEPALIVE_SEC="${KEEPALIVE_SEC:-25}"

[[ -f "$CONF" ]] || { echo "Нет $CONF"; exit 1; }

if grep -qE '^[[:space:]]*PersistentKeepalive[[:space:]]*=' "$CONF"; then
  echo "OK: PersistentKeepalive уже есть в $CONF"
  exit 0
fi

if ! grep -qE '^[[:space:]]*Endpoint[[:space:]]*=' "$CONF"; then
  echo "Нет секции с Endpoint (вероятно сторона сервера) — keepalive не добавляем."
  exit 0
fi

BK="${CONF}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$CONF" "$BK"
echo "Резервная копия: $BK"

tmp="$(mktemp)"
awk -v k="$KEEPALIVE_SEC" '
  /^\[Peer\]/ { inpeer = 1; ins = 0 }
  inpeer && /^[[:space:]]*Endpoint[[:space:]]*=/ && !ins {
    print
    print "PersistentKeepalive = " k
    ins = 1
    next
  }
  /^\[/ && inpeer && $0 !~ /^\[Peer\]/ { inpeer = 0 }
  { print }
' "$CONF" >"$tmp"
mv "$tmp" "$CONF"
chmod 600 "$CONF"
echo "Добавлено PersistentKeepalive = $KEEPALIVE_SEC после первой строки Endpoint в [Peer]."
echo "Перезапуск: systemctl restart wg-quick@${WG_IF}"
