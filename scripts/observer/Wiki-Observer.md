# OpenClaw Observer (внешний worker)

Наблюдатель **не входит** в пакет OpenClaw — это отдельный `bash`-скрипт и **systemd user timer**, который раз в **5 минут** проверяет хост и шлюз, пытается **восстановить** типовые сбои и шлёт алерты в **Telegram**, если проблема не устранена или нужно внимание человека.

## Расположение на сервере

| Что | Путь |
|-----|------|
| Скрипт | `/home/shevbo/bin/openclaw-observer.sh` |
| Лог | `~/.local/log/openclaw-observer.log` (ротация при > ~1 МБ) |
| Состояние (счётчики) | `~/.cache/openclaw-observer/` |
| Telegram | `~/.config/openclaw/observer/telegram.env` (права **600**) |
| Опции | `~/.config/openclaw/observer/observer.env` (опционально) |
| systemd | `~/.config/systemd/user/openclaw-observer.service` + `.timer` |

## Что проверяется

1. **Прокси (Proxy6)** — переменные берутся из **`~/.config/proxy6/proxy.systemd.env`** (если есть), иначе из **`/etc/proxy6/environment.env`**. Выполняется `curl` на `https://ipinfo.io/ip` **через** `HTTPS_PROXY`. Первый путь нужен, чтобы **user systemd** не зависел от группы `proxyaccess` для чтения системного `640`. При сбое: `proxy6-fetch-proxy-env.py` и `sudo /usr/local/sbin/sync-proxy6-system-env.sh` (если есть **NOPASSWD**).
2. **Шлюз OpenClaw** — `systemctl --user is-active openclaw-gateway.service` и HTTP GET на `http://127.0.0.1:18789/__openclaw__/`. После **restart** шлюзу часто нужно **20–40 с** до ответа HTTP; observer **ждёт до** `OBSERVER_GATEWAY_HTTP_WAIT_MAX_SEC` (по умолчанию **120**), опрос каждые `OBSERVER_GATEWAY_HTTP_POLL_SEC` (**3** с), и только потом шлёт «не поднялся» / делает heal. При сбое: `start` / `restart` юнита.
3. **Логи** — за последние **20 минут** из `journalctl --user -u openclaw-gateway.service` ищутся строки по шаблонам (неверный ключ, гео, `EADDRINUSE`, и т.д.). При **новом** наборе совпадений (хэш меняется) — сообщение в Telegram. Для `EADDRINUSE` дополнительно: перезапуск шлюза и **caddy** (через `sudo`, если разрешено). Ошибки вида **«No available auth profile for google»** в этот общий срез **не входят** (иначе спам): для них отдельное короткое уведомление не чаще чем раз в **6 часов** (`OBSERVER_GOOGLE_AUTH_ALERT_COOLDOWN_SEC`, по умолчанию 21600). Реестр может перезапускать шлюз по этим строкам в журнале — см. `google-auth-profile-unavailable` в `troubleshooting/GUIDE.md`.
4. **Реестр сбоев** — каталог `~/.config/openclaw/observer/troubleshooting/`: `registry.json` + `fixes/*.sh` + `registry-runner.py` (Python 3). По паттернам из журнала шлюза (и опционально `ingest.txt` для текста из Telegram) запускаются **заранее описанные** скрипты исправления с **cooldown**. Подробности и таблица: `scripts/observer/troubleshooting/GUIDE.md` в репозитории.

## Авто-лечение

- Перезапуск **только** user-сервиса шлюза и при необходимости **caddy** (системный).
- **Перезагрузка хоста** по умолчанию **выключена**. Включается только если в `observer.env` задано `OBSERVER_ALLOW_REBOOT=1` и выполнено одно из условий:
  - заполнение диска **/** ≥ **95%** (после уведомления пауза **60 с**);
  - шлюз недоступен **подряд** `OBSERVER_FAILS_BEFORE_REBOOT` запусков таймера (по умолчанию **12** ≈ **1 час** при шаге 5 мин) — пауза **90 с** перед `reboot`.

Без явного `OBSERVER_ALLOW_REBOOT=1` хост **никогда** не перезагружается скриптом.

## Telegram

На **shevbo-cloud** уже выполнено: токен взят из `openclaw.json` (`channels.telegram.botToken`), **chat_id** личного чата — **36910539** (как в сессиях `telegram:direct`). Файл: `~/.config/openclaw/observer/telegram.env`, права **600**.

Переустановить вручную:

```bash
~/bin/install-telegram-env-remote.sh
```

Проверка отправки (через **Proxy6**, как у шлюза):

```bash
~/bin/test-telegram-send.sh ~/.config/openclaw/observer/telegram.env "тест"
```

Если переносишь на другой хост: создай бота в @BotFather, задай `TELEGRAM_CHAT_ID` (из `getUpdates`), шаблон — `telegram.env.example`.

Уведомления о **постоянно сломанном прокси** throttled: первый раз сразу, затем примерно раз в **час** (каждые **12** неудачных проверок).

## sudo

На сервере установлено:

- `/etc/sudoers.d/proxy6-sync` — `sync-proxy6-system-env.sh` (уже было).
- `/etc/sudoers.d/openclaw-observer` — `systemctl restart caddy`, `reboot` (для лечения и `OBSERVER_ALLOW_REBOOT=1`).

Файлы-образцы в репозитории: `observer.sudoers.example`, `openclaw-observer.sudoers`.

## Команды

```bash
# Ручной прогон
/home/shevbo/bin/openclaw-observer.sh

# Статус таймера
systemctl --user status openclaw-observer.timer
systemctl --user list-timers | grep observer

# Логи наблюдателя
tail -f ~/.local/log/openclaw-observer.log
```

## Установка / обновление

Файлы кладутся из репозитория `scripts/observer/` на сервер: скрипт в `~/bin`, unit-файлы в `~/.config/systemd/user/`, затем:

```bash
systemctl --user daemon-reload
systemctl --user enable --now openclaw-observer.timer
```

Требуется **linger** для пользователя (`loginctl show-user shevbo -p Linger` → `yes`), чтобы таймер жил без интерактивного входа.

## Связанные документы

- `~/.openclaw/Wiki/Caddy.md` — reverse proxy, TLS, откат `Caddyfile`, Proxy6 и **caddy**. Оглавление вики: `~/.openclaw/Wiki/Wiki-INDEX.md`.

## Ограничения

- Не заменяет мониторинг инфраструктуры (Prometheus и т.д.); это **лёгкий** watchdog.
- Ошибки **модели** (квоты Gemini, 429) скрипт **не «лечит»**, только может **сообщить**, если строка попала в журнал за 20 минут.
- Секреты OpenClaw (`my_secrets.json`) скрипт **не читает**.
