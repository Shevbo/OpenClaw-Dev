#!/usr/bin/env bash
# Диагностика туннеля WireGuard с shevbo-pi к облаку (shevbo-cloud).
# Запуск на консоли Pi: bash scripts/pi/shevbo-pi-wg-cloud-check.sh
#   (скопируйте репозиторий на Pi или один файл в ~/bin)
#
# Переменные окружения (опционально):
#   WG_IF=wg0          — имя интерфейса WireGuard
#   CLOUD_WG_IP=10.66.0.3 — IP облака внутри WG (как на shevbo-cloud: wg0)
#
# Флаги:
#   --restart   — sudo systemctl restart wg-quick@<WG_IF> (после диагностики)
#   --fix       — то же, что --restart
#
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
CLOUD_WG_IP="${CLOUD_WG_IP:-10.66.0.3}"
DO_RESTART=0
for a in "$@"; do
  case "$a" in
    --restart|--fix) DO_RESTART=1 ;;
    -h|--help)
      sed -n '1,25p' "$0"
      exit 0
      ;;
  esac
done

echo "=== shevbo-pi WG / cloud check ==="
echo "Time: $(date -Is)"
echo "WG_IF=$WG_IF CLOUD_WG_IP=$CLOUD_WG_IP"
echo

echo "=== 1) Интернет (мимо WG)"
if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
  echo "OK: ping 1.1.1.1"
else
  echo "FAIL: нет ping до 1.1.1.1 — проверьте LAN/WAN Pi"
fi
echo

echo "=== 2) Интерфейс $WG_IF"
if ip link show "$WG_IF" >/dev/null 2>&1; then
  ip -br addr show "$WG_IF" || true
else
  echo "Нет интерфейса $WG_IF — WG не поднят или другое имя (export WG_IF=...)"
fi
echo

echo "=== 3) systemctl wg-quick@$WG_IF"
if systemctl list-unit-files "wg-quick@${WG_IF}.service" 2>/dev/null | grep -q wg-quick; then
  systemctl is-active "wg-quick@${WG_IF}.service" 2>/dev/null || true
  systemctl status "wg-quick@${WG_IF}.service" --no-pager -l 2>/dev/null | head -25 || true
else
  echo "Unit wg-quick@${WG_IF}.service не найден. Попробуйте: systemctl list-units 'wg-quick@*'"
fi
echo

echo "=== 4) sudo wg show $WG_IF"
if command -v wg >/dev/null 2>&1; then
  sudo wg show "$WG_IF" 2>/dev/null || sudo wg show 2>/dev/null || echo "wg show не удался (нет sudo или нет интерфейса)"
else
  echo "Команда wg не найдена"
fi
echo

echo "=== 5) Маршрут к облаку в туннеле ($CLOUD_WG_IP)"
ip route get "$CLOUD_WG_IP" 2>/dev/null || true
echo

echo "=== 6) Ping облака по WG ($CLOUD_WG_IP)"
if ping -c 4 -W 3 "$CLOUD_WG_IP" >/dev/null 2>&1; then
  echo "OK: туннель до облака живой"
  ping -c 4 -W 3 "$CLOUD_WG_IP" || true
else
  echo "FAIL: нет ответа от $CLOUD_WG_IP — handshake на облаке будет старым; см. п. 7–8"
fi
echo

echo "=== 7) SSH до облака по WG (опционально, без интерактива)"
if command -v ssh >/dev/null 2>&1; then
  if ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
      "${CLOUD_WG_IP}" "echo cloud_ok; hostname" 2>/dev/null; then
    :
  else
    echo "(SSH не прошёл или не настроен ключ на $CLOUD_WG_IP — для проверки туннеля достаточно ping)"
  fi
else
  echo "ssh не установлен"
fi
echo

echo "=== 8) Последние строки журнала wg-quick (если есть)"
sudo journalctl -u "wg-quick@${WG_IF}" -n 30 --no-pager 2>/dev/null || true
echo

if [[ "$DO_RESTART" -eq 1 ]]; then
  echo "=== --restart: sudo systemctl restart wg-quick@${WG_IF}"
  sudo systemctl restart "wg-quick@${WG_IF}"
  sleep 2
  sudo wg show "$WG_IF" 2>/dev/null || sudo wg show 2>/dev/null || true
  echo "Повторный ping $CLOUD_WG_IP:"
  ping -c 4 -W 3 "$CLOUD_WG_IP" || true
fi

echo "=== Готово ==="
echo "Если ping $CLOUD_WG_IP FAIL: проверьте питание Pi, UDP проброс 51820 на роутере,"
echo "совпадение ключей/AllowedIPs с shevbo-cloud, что endpoint в конфиге Pi указывает на актуальный IP облака."
