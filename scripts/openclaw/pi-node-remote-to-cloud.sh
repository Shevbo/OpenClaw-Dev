#!/usr/bin/env bash
# Запуск на Raspberry Pi (shevbo-pi): подключить headless node к главному шлюзу на shevbo-cloud.
#
# Требования: установлен openclaw CLI (см. install-openclaw-pi-minimal.sh), сеть до шлюза
# (WireGuard до WG-IP VPS, или wss://домен, или SSH LocalForward на 127.0.0.1:18789).
#
# Обязательные переменные:
#   OPENCLAW_GATEWAY_TOKEN  — тот же секрет, что gateway.auth.token на облачном шлюзе
#   CLOUD_GATEWAY_HOST      — хост WebSocket шлюза (WG IP VPS, claw.shectory.ru, или 127.0.0.1 при туннеле)
#
# Опционально:
#   CLOUD_GATEWAY_PORT=18789
#   CLOUD_USE_TLS=1         — добавить --tls (например порт 443)
#   EXTRA_NODE_INSTALL_ARGS — доп. аргументы к openclaw node install (например --tls-fingerprint sha256/...)
#   ALLOW_STOP_LOCAL_GATEWAY=1 — остановить и отключить openclaw-gateway.service (user), чтобы не было двух шлюзов
#
# После скрипта на ОБЛАКЕ (два шага, см. Wiki):
#   1) device pairing (роль node): openclaw devices approve <requestId>  (или из ~/.openclaw/devices/pending.json)
#   2) node.pair: openclaw nodes approve <requestId>  (из ~/.openclaw/nodes/pending.json)
# Для ws:// на WG/RFC1918 на клиенте нужен OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1 (см. drop-in ниже).
#
set -euo pipefail

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  echo "Задайте OPENCLAW_GATEWAY_TOKEN (токен шлюза на VPS)." >&2
  exit 1
fi
if [[ -z "${CLOUD_GATEWAY_HOST:-}" ]]; then
  echo "Задайте CLOUD_GATEWAY_HOST (WG-IP облака, домен, или 127.0.0.1 при SSH LocalForward)." >&2
  exit 1
fi

PORT="${CLOUD_GATEWAY_PORT:-18789}"
TLS_ARGS=()
if [[ "${CLOUD_USE_TLS:-0}" == "1" ]]; then
  TLS_ARGS=(--tls)
fi

# nvm на Pi (если openclaw поставлен через nvm)
if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  . "$NVM_DIR/nvm.sh"
  nvm use default 2>/dev/null || true
fi

ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openclaw"
mkdir -p "$ENV_DIR"
ENV_FILE="$ENV_DIR/pi-node-remote.env"
umask 077
cat >"$ENV_FILE" <<EOF
# Автогенерация $(date -Iseconds) — pi-node-remote-to-cloud.sh
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
EOF
chmod 600 "$ENV_FILE"
echo "[pi-node] Записан $ENV_FILE (права 600)."

# Чтобы первый запуск install сразу подхватил секрет из окружения процесса
export OPENCLAW_GATEWAY_TOKEN

if [[ "${ALLOW_STOP_LOCAL_GATEWAY:-0}" == "1" ]]; then
  if systemctl --user is-active openclaw-gateway.service &>/dev/null; then
    systemctl --user stop openclaw-gateway.service
    echo "[pi-node] Остановлен openclaw-gateway.service"
  fi
  if systemctl --user is-enabled openclaw-gateway.service &>/dev/null; then
    systemctl --user disable openclaw-gateway.service
    echo "[pi-node] Отключён автозапуск openclaw-gateway.service"
  fi
fi

INSTALL_EXTRA=()
if [[ -n "${EXTRA_NODE_INSTALL_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  INSTALL_EXTRA=($EXTRA_NODE_INSTALL_ARGS)
fi
echo "[pi-node] openclaw node install --host $CLOUD_GATEWAY_HOST --port $PORT ${TLS_ARGS[*]:-} ${INSTALL_EXTRA[*]:-}"
openclaw node install --host "$CLOUD_GATEWAY_HOST" --port "$PORT" "${TLS_ARGS[@]}" "${INSTALL_EXTRA[@]}"

NODE_UNIT=""
while IFS= read -r u; do
  [[ -z "$u" ]] && continue
  NODE_UNIT="$u"
  break
done < <(systemctl --user list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^openclaw-node' || true)

if [[ -z "$NODE_UNIT" ]]; then
  NODE_UNIT="openclaw-node.service"
  echo "[pi-node] Предупреждение: unit не найден list-unit-files, пробуем drop-in для $NODE_UNIT"
fi

DROP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/${NODE_UNIT}.d"
mkdir -p "$DROP_DIR"
# В штатном unit openclaw-node стоит OPENCLAW_GATEWAY_TOKEN=__OPENCLAW_REDACTED__ — EnvironmentFile не перекрывает это.
# Поднимаем токен из файла + OPENCLAW_ALLOW_INSECURE_PRIVATE_WS для ws:// на WG/частные IP (документация Remote Access).
NODE_BIN="$(command -v node)"
OPENCLAW_ENTRY="$(readlink -f "$(dirname "$NODE_BIN")/../lib/node_modules/openclaw/dist/index.js")"
[[ -f "$OPENCLAW_ENTRY" ]]
cat >"$DROP_DIR/exec-override.conf" <<EOF
[Service]
ExecStart=
ExecStart=/bin/bash -lc 'set -a; . $ENV_FILE; set +a; export OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1; exec $NODE_BIN $OPENCLAW_ENTRY node run --host $CLOUD_GATEWAY_HOST --port $PORT'
EOF
echo "[pi-node] Drop-in: $DROP_DIR/exec-override.conf"

systemctl --user daemon-reload
systemctl --user restart "$NODE_UNIT" 2>/dev/null || systemctl --user start "$NODE_UNIT"
sleep 2
systemctl --user status "$NODE_UNIT" --no-pager || true
openclaw node status 2>/dev/null || true

echo ""
echo "[pi-node] Готово. На VPS (шлюз) выполните по очереди:"
echo "  openclaw devices approve <requestId>   # pending: ~/.openclaw/devices/pending.json"
echo "  openclaw nodes approve <requestId>     # pending: ~/.openclaw/nodes/pending.json"
