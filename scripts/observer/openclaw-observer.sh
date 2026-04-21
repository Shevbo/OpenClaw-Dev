#!/bin/bash
# Внешний наблюдатель OpenClaw (не часть openclaw): health, прокси, логи, авто-лечение, алерты в Telegram.
set -euo pipefail
# user/systemd часто без UTF-8: иначе curl --data-urlencode ломает кириллицу; bash при LANG=C режет ${var:…} по байтам
export LC_ALL=C.UTF-8

STATE_DIR="${OBSERVER_STATE_DIR:-$HOME/.cache/openclaw-observer}"
LOG_FILE="${OBSERVER_LOG:-$HOME/.local/log/openclaw-observer.log}"
TELEGRAM_ENV="${OBSERVER_TELEGRAM_ENV:-$HOME/.config/openclaw/observer/telegram.env}"
GATEWAY_UNIT="${OBSERVER_GATEWAY_UNIT:-openclaw-gateway.service}"
GATEWAY_URL="${OBSERVER_GATEWAY_URL:-http://127.0.0.1:18789/__openclaw__/}"
# Сначала копия у пользователя (читается из systemd user без группы proxyaccess); иначе системный файл.
PROXY_ENV_SYSTEM="${OBSERVER_PROXY_ENV_SYSTEM:-}"
if [[ -z "$PROXY_ENV_SYSTEM" ]]; then
	if [[ -r "$HOME/.config/proxy6/proxy.systemd.env" ]]; then
		PROXY_ENV_SYSTEM="$HOME/.config/proxy6/proxy.systemd.env"
	else
		PROXY_ENV_SYSTEM="/etc/proxy6/environment.env"
	fi
fi
FETCH_PROXY="${OBSERVER_FETCH_PROXY:-$HOME/.local/bin/proxy6-fetch-proxy-env.py}"
SYNC_SYSTEM_PROXY="${OBSERVER_SYNC_SYSTEM_PROXY:-/usr/local/sbin/sync-proxy6-system-env.sh}"
MAX_LOG_BYTES="${OBSERVER_MAX_LOG_BYTES:-1048576}"
FAILS_BEFORE_REBOOT="${OBSERVER_FAILS_BEFORE_REBOOT:-12}"
# 12 * 5 мин ≈ 1 час полного даунтайма шлюза
# Реестр авто-исправлений: ~/.config/openclaw/observer/troubleshooting/ (или рядом со скриптом)
OBSERVER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR"
touch "$LOG_FILE"
if [[ -f "$LOG_FILE" ]] && [[ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]]; then
	mv -f "$LOG_FILE" "${LOG_FILE}.1"
fi

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG_FILE"; }

load_telegram() {
	TELEGRAM_BOT_TOKEN=""
	TELEGRAM_CHAT_ID=""
	[[ -f "$TELEGRAM_ENV" ]] || return 1
	# shellcheck disable=SC1090
	source "$TELEGRAM_ENV"
	[[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]
}

notify_telegram() {
	local text="$1"
	load_telegram || { log "telegram: skip (no $TELEGRAM_ENV)"; return 0; }
	local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
	local px=()
	if [[ -r "$HOME/.config/proxy6/proxy.systemd.env" ]]; then
		set -a
		# shellcheck source=/dev/null
		. "$HOME/.config/proxy6/proxy.systemd.env"
		set +a
	fi
	[[ -n "${HTTPS_PROXY:-}" ]] && px=(-x "${HTTPS_PROXY}")
	# ограничение Telegram ~4096; режем безопасно
	if [[ ${#text} -gt 3500 ]]; then
		text="${text:0:3500}…"
	fi
	if curl -sS -m 45 "${px[@]}" -X POST "$url" \
		-d "chat_id=${TELEGRAM_CHAT_ID}" \
		--data-urlencode "text=${text}" \
		-d "disable_web_page_preview=true" >/dev/null; then
		log "telegram: sent alert"
	else
		log "telegram: send failed"
	fi
}

count_state() {
	local key="$1"
	local f="$STATE_DIR/$key"
	local n=0
	[[ -f "$f" ]] && n="$(cat "$f")"
	echo "${n:-0}"
}

bump_state() {
	local key="$1"
	echo $(($(count_state "$key") + 1)) >"$STATE_DIR/$key"
}

reset_state() {
	rm -f "$STATE_DIR/$1"
}

check_proxy_egress() {
	# HTTPS через прокси из system env (тот же файл, что у caddy/шлюза при EnvironmentFile).
	set -a
	# shellcheck source=/dev/null
	. "$PROXY_ENV_SYSTEM"
	set +a
	local px="${HTTPS_PROXY:-${HTTP_PROXY:-}}"
	if [[ -z "$px" ]]; then
		log "proxy: в $PROXY_ENV_SYSTEM нет HTTPS_PROXY/HTTP_PROXY"
		return 1
	fi
	local out
	out="$(curl -sS -m 25 -x "$px" "https://ipinfo.io/ip" 2>/dev/null || true)"
	[[ -n "$out" ]]
}

heal_proxy() {
	log "heal: proxy fetch / sync"
	if [[ -x "$FETCH_PROXY" ]]; then
		python3 "$FETCH_PROXY" >>"$LOG_FILE" 2>&1 || true
	fi
	if [[ -x "$SYNC_SYSTEM_PROXY" ]] && sudo -n "$SYNC_SYSTEM_PROXY" >>"$LOG_FILE" 2>&1; then
		log "heal: sync-proxy6-system ok"
	elif [[ -x "$SYNC_SYSTEM_PROXY" ]]; then
		log "heal: sync-proxy6-system skipped (no sudo -n)"
	fi
}

check_gateway_systemd() {
	systemctl --user is-active --quiet "$GATEWAY_UNIT"
}

heal_gateway() {
	log "heal: restart $GATEWAY_UNIT"
	systemctl --user restart "$GATEWAY_UNIT" || systemctl --user start "$GATEWAY_UNIT"
	sleep 4
}

check_gateway_http() {
	# Явно без прокси: иначе при HTTPS_PROXY в окружении user/cron curl к 127.0.0.1 уходит на прокси и даёт ложный даунтайм.
	env -u ALL_PROXY -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
		NO_PROXY='127.0.0.1,localhost' no_proxy='127.0.0.1,localhost' \
		curl -sf --max-time 10 --noproxy '*' "$GATEWAY_URL" -o /dev/null
}

run_troubleshooting_registry() {
	local d="${OBSERVER_TROUBLESHOOTING_DIR:-}"
	if [[ -z "$d" ]]; then
		if [[ -d "$HOME/.config/openclaw/observer/troubleshooting" ]]; then
			d="$HOME/.config/openclaw/observer/troubleshooting"
		elif [[ -d "$OBSERVER_SCRIPT_DIR/troubleshooting" ]]; then
			d="$OBSERVER_SCRIPT_DIR/troubleshooting"
		fi
	fi
	[[ -n "$d" && -f "$d/registry.json" && -f "$d/registry-runner.py" ]] || return 0
	chmod +x "$d/registry-runner.py" 2>/dev/null || true
	shopt -s nullglob
	for _fx in "$d/fixes/"*.sh; do chmod +x "$_fx"; done
	shopt -u nullglob
	log "registry: scan ($d)"
	export OBSERVER_TROUBLESHOOTING_DIR="$d"
	export OBSERVER_STATE_DIR="$STATE_DIR"
	export OBSERVER_GATEWAY_UNIT="$GATEWAY_UNIT"
	if command -v python3 >/dev/null 2>&1; then
		python3 "$d/registry-runner.py" 2>&1 | tee -a "$LOG_FILE" || true
	else
		log "registry: skip (no python3)"
	fi
}

scan_logs() {
	# Критичные паттерны за последние 20 минут (user unit)
	journalctl --user -u "$GATEWAY_UNIT" --since "20 min ago" --no-pager 2>/dev/null | grep -iE \
		'API_KEY_INVALID|API key expired|User location is not supported|No available auth profile for google|FATAL|EADDRINUSE|Cannot find module' \
		|| true
}

heal_caddy() {
	if systemctl is-active --quiet caddy 2>/dev/null; then
		if sudo -n systemctl restart caddy >>"$LOG_FILE" 2>&1; then
			log "heal: caddy restarted"
		else
			log "heal: caddy restart skipped (no sudo -n)"
		fi
	fi
}

disk_critical() {
	local p
	p="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
	[[ -n "$p" && "$p" -ge 95 ]]
}

maybe_reboot_host() {
	if [[ "${OBSERVER_ALLOW_REBOOT:-0}" != "1" ]]; then
		return 0
	fi
	if disk_critical; then
		notify_telegram "observer: критично заполнен диск (/) — перезагрузка хоста через 60 с (OBSERVER_ALLOW_REBOOT=1)."
		sleep 60
		sudo -n reboot || log "reboot failed"
	fi
}

# --- main ---
RUN_ID="$(date +%s)"
log "run begin id=$RUN_ID"

PROXY_OK=1
GATEWAY_OK=1
LOG_ISSUES=""

if [[ ! -r "$PROXY_ENV_SYSTEM" ]]; then
	log "proxy: пропуск (нет $PROXY_ENV_SYSTEM)"
	PROXY_OK=1
elif check_proxy_egress; then
	log "proxy: ok"
	reset_state proxy_fail
	PROXY_OK=1
else
	log "proxy: FAIL"
	PROXY_OK=0
	bump_state proxy_fail
	heal_proxy
	if check_proxy_egress; then
		log "proxy: recovered after heal"
		reset_state proxy_fail
		notify_telegram "observer[$HOSTNAME]: прокси восстановлен после fetch/sync."
		PROXY_OK=1
	else
		PF="$(count_state proxy_fail)"
		if [[ "$PF" -eq 1 ]] || [[ $((PF % 12)) -eq 0 ]]; then
			notify_telegram "observer[$HOSTNAME]: прокси недоступен после лечения (счётчик=$PF / ~$((PF * 5)) мин). Проверь Proxy6 и /etc/proxy6/environment.env."
		fi
	fi
fi

if check_gateway_systemd && check_gateway_http; then
	log "gateway: ok"
	reset_state gw_fail
	GATEWAY_OK=1
elif check_gateway_systemd && ! check_gateway_http; then
	log "gateway: systemd active but HTTP fail"
	bump_state gw_fail
	heal_gateway
	if check_gateway_http; then
		notify_telegram "observer[$HOSTNAME]: шлюз OpenClaw перезапущен (HTTP не отвечал)."
		reset_state gw_fail
		GATEWAY_OK=1
	else
		notify_telegram "observer[$HOSTNAME]: шлюз не поднялся после restart. Смотри journalctl --user -u $GATEWAY_UNIT."
		GATEWAY_OK=0
	fi
else
	log "gateway: systemd inactive"
	bump_state gw_fail
	systemctl --user start "$GATEWAY_UNIT" || true
	sleep 5
	if check_gateway_systemd && check_gateway_http; then
		notify_telegram "observer[$HOSTNAME]: шлюз был остановлен — запущен."
		reset_state gw_fail
		GATEWAY_OK=1
	else
		heal_gateway
		if check_gateway_http; then
			notify_telegram "observer[$HOSTNAME]: шлюз восстановлен после start/restart."
			reset_state gw_fail
			GATEWAY_OK=1
		else
			notify_telegram "observer[$HOSTNAME]: шлюз не отвечает. Нужна ручная диагностика."
			GATEWAY_OK=0
		fi
	fi
fi

LOG_ISSUES="$(scan_logs)"
if [[ -n "$LOG_ISSUES" ]]; then
	# не спамим одинаковым: хэш последнего среза
	H="$(echo "$LOG_ISSUES" | sha256sum | awk '{print $1}')"
	OLD=""
	[[ -f "$STATE_DIR/last_log_hash" ]] && OLD="$(cat "$STATE_DIR/last_log_hash")"
	if [[ "$H" != "$OLD" ]]; then
		echo "$H" >"$STATE_DIR/last_log_hash"
		notify_telegram "observer[$HOSTNAME]: в логах шлюза найдены предупреждения (20 мин):
${LOG_ISSUES:0:3000}"
	fi
	# Лечим только типовые: порт занят / caddy
	if echo "$LOG_ISSUES" | grep -qi 'EADDRINUSE'; then
		heal_gateway
		heal_caddy
	fi
fi

run_troubleshooting_registry

# Долгий даунтайм шлюза
if [[ "$GATEWAY_OK" != "1" ]]; then
	bump_state gw_down_cycles
	if [[ "$(count_state gw_down_cycles)" -ge "$FAILS_BEFORE_REBOOT" ]] && [[ "${OBSERVER_ALLOW_REBOOT:-0}" == "1" ]]; then
		notify_telegram "observer[$HOSTNAME]: шлюз недоступен ${FAILS_BEFORE_REBOOT} проверок подряд — перезагрузка через 90 с."
		sleep 90
		sudo -n reboot || true
	fi
else
	reset_state gw_down_cycles
fi

maybe_reboot_host

log "run end id=$RUN_ID ok gateway=$GATEWAY_OK proxy=$PROXY_OK"
