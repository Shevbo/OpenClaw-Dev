# Реестр сбоев OpenClaw + observer (авто-исправления)

**Канон на шлюзе (копия для операторов):** `/home/shevbo/.openclaw/Wiki/Wiki-OBSERVER-TROUBLESHOOTING-GUIDE.md` — при правках синхронизировать с репозиторием (`scripts/openclaw/sync-wiki-from-gateway.sh` / `sync-wiki-to-gateway.sh`). См. **`Wiki-INDEX.md`** в `~/.openclaw/Wiki/`.

Цель: накопленные типовые ошибки, **команды восстановления** и **автозапуск** через `openclaw-observer.sh` по совпадению паттернов в журнале шлюза.

## Размещение на сервере

```bash
mkdir -p ~/.config/openclaw/observer/troubleshooting/fixes
# из репозитория:
cp -a scripts/observer/troubleshooting/* ~/.config/openclaw/observer/troubleshooting/
chmod +x ~/.config/openclaw/observer/troubleshooting/registry-runner.py
chmod +x ~/.config/openclaw/observer/troubleshooting/fixes/*.sh
```

Переопределение каталога: переменная окружения `OBSERVER_TROUBLESHOOTING_DIR`.

## Как это работает

1. `registry.json` — список записей: `id`, regex-паттерны по **journalctl** (`openclaw-gateway.service`), имя скрипта из `fixes/`, `cooldown_sec`.
2. `registry-runner.py` читает журнал за ~25 минут, ищет совпадения, при **истечении cooldown** запускает **только** `fixes/*.sh` (имя файла строго без `/`).
3. Время последнего успешного fix: `~/.cache/openclaw-observer/tr_registry_<id>_last`.

### Текст только из Telegram (не попал в journal)

Временно вставьте фрагмент в:

`~/.config/openclaw/observer/troubleshooting/ingest.txt`

Runner добавит его к тексту для поиска (до ~200 KiB с конца). После срабатывания fix файл можно очистить.

Если совпадение сработало **по тексту ingest** (а не только по `journalctl`), перед запуском fix в тот же Telegram уходит короткое сообщение вида: «Касательно этого кейса (`<id>`): я (observer) попробую решить сам — вернусь с обратной связью.» Используются `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` из `~/.config/openclaw/observer/telegram.env` (или `OBSERVER_TELEGRAM_ENV`). Учитывается `HTTPS_PROXY`, если задан в окружении процесса observer.

**Каталог `ingest.d/`:** все файлы `ingest.d/*.txt` (до ~80 KiB с конца каждого) тоже подмешиваются к поиску — удобно складывать вставки из Telegram отдельными файлами без перезаписи одного `ingest.txt`. Быстрая запись с VPS:

`bash ~/.config/openclaw/observer/troubleshooting/append-telegram-ingest.sh 'вставьте текст ошибки из чата'`

## Записи реестра (кратко)

| id | Симптом | Ручные команды (диагностика) | Авто-fix |
|----|---------|------------------------------|----------|
| `docker-sock-sandbox-inspect` | `permission denied` к `docker.sock`, ошибки inspect образа sandbox | `ls -la /var/run/docker.sock`; `groups`; `journalctl --user -u openclaw-gateway -n 50` | `fix-docker-socket-gateway.sh` |
| `sandbox-missing-runtime` | В песочнице нет `node` / `python3` / CLI | `openclaw sandbox explain`; `docker images`; `which openclaw` | `fix-sandbox-recreate.sh` |
| `eaddrinuse-port` | `EADDRINUSE`, порт занят | `ss -tlnp \| grep 18789`; `systemctl --user status openclaw-gateway` | `fix-eaddrinuse-gateway-caddy.sh` |
| `google-auth-profile-unavailable` | `No available auth profile for google`, FailoverError Google | Часто в журнале перед этим — **503 / high demand**: один `google:default` уходит в **cooldown**, пока не истечёт окно или не сделать **restart шлюза**. Ключи/квота — если **401/403/API_KEY_INVALID**. Лог restart: `~/.local/log/openclaw-observer-google-auth-recover.log` | `fix-google-auth-gateway-restart.sh` (restart шлюза, cooldown 1 ч) |
| `agent-llm-no-response` | «couldn't generate», cron `billing-monitor-daily` failed | `journalctl --user -u openclaw-gateway -n 80`; ключи/квота вручную | `fix-agent-llm-gateway-recover.sh` (validate + restart) |
| *(ручной)* incomplete turn | «couldn't generate… **tool actions may have already been executed**», пики нагрузки | `journalctl` на 503/429/TTS; вики **`scripts/wiki/OpenClaw-shevbo-google-only-voice.md`** § интенсив | С хоста: **`scripts/openclaw/patch-openclaw-throughput-mitigation.py`**, validate, restart шлюза (нет авто-fix в `fixes/`) |
| `monitoring-sandbox-paths` | Health/incident, monitoring вне sandbox, пути `/home/.../workspace/monitoring` | Промпты: `monitoring/` или `/workspace/monitoring/` | `fix-monitoring-workspace-in-sandbox.sh` (замена абсолютного пути на `monitoring/` в `*.md,yaml,yml,json,txt,sh` под workspace + в `openclaw.json`; symlink в `sandboxes/agent-*`). Отключить правки текста: `OBSERVER_SKIP_MONITORING_PATH_REPLACE=1` |

### Ручной сценарий «песочница без node/python» (как в вашем Telegram)

```bash
openclaw sandbox explain
openclaw sandbox recreate --all --force   # если команда есть в вашей версии CLI
systemctl --user restart openclaw-gateway.service
docker images | grep -iE 'openclaw|sandbox'
```

Если образ устарел — обновление по документации OpenClaw / `openclaw update`.

## Добавление новой ошибки

1. В `registry.json` — новый объект в `entries` (уникальный `id`, паттерны, `fix`, `cooldown_sec`).
2. Новый скрипт только как `fixes/имя.sh` (латиница, цифры, `_`, `-`, `.`).
3. Паттерны — **регулярные выражения** Python (`re`), флаги `IGNORECASE | DOTALL`.

Перезапуск observer-таймера не нужен: скрипт читает `registry.json` каждый запуск.
