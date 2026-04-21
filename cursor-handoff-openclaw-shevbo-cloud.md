# Handoff: OpenClaw Gateway на VPS (shevbo-cloud)

Контекст для продолжения в Cursor с **этой точки**. Пользователь: **shevbo** на VPS; домен: **shectory.ru** (план: поддомен **claw.shectory.ru**).

**Вики на шлюзе (канон):** **`/home/shevbo/.openclaw/Wiki/`** — туда писать операционные документы; **`scripts/wiki/`** в репо — зеркало для Git. См. **`AGENTS.md`**.

---

## Политика медиа (строгое требование)

**Голос входящий (распознавание / STT) и озвучка ответов (TTS) — только Google (Gemini API).** OpenAI для транскрипции голосовых и плагин `openai` в конфиге не используются. Подробно: **`~/.openclaw/Wiki/OpenClaw-shevbo-google-only-voice.md`** (копия в репо: `scripts/wiki/…`). Скрипт применения: `scripts/openclaw/patch-tools-media-audio-google-only.py`. Профиль **`openai-codex`** (OAuth Codex/ACP) — отдельно, при необходимости оставляют.

---

## Цели (что уже решали)

1. **SSH без пароля** — на Windows используется ключ `shevbo-cloud`, хост в браузере/чате: `shevbo@192.144.14.187`. На машине агента Cursor (Linux `shectory`) алиас **`shevbo-cloud` в `~/.ssh/config` нет** — SSH «отсюда» к VPS не настраивали.
2. **OpenClaw Gateway** — Control UI, токен, порт **18789**, конфиг **`~/.openclaw/openclaw.json`** (пользователь **shevbo**, uid 1000).
3. **Ошибка `origin not allowed`** — исправлено через **`gateway.controlUi.allowedOrigins`** (точный `http(s)://хост:порт` страницы, не `ws://`).
4. **Два процесса шлюза** — одновременно были **`openclaw.service` (system)** и **`openclaw-gateway.service` (user)** → `EADDRINUSE`. **Решение:** `sudo systemctl disable openclaw.service` + `stop`, оставлен только **user**: `openclaw-gateway.service` (`~/.config/systemd/user/openclaw-gateway.service`), **enabled; active**.
5. **Без SSH-туннеля по IP** — после **`gateway.bind: lan`** страница по **`http://192.144.14.187:18789`** даёт ошибку браузера: **`control ui requires device identity (use HTTPS or localhost secure context)`** — нужен **HTTPS** или **localhost** (Web Crypto / secure context).
6. **План без туннеля:** reverse proxy (**Caddy**) на **`https://claw.shectory.ru`** → `127.0.0.1:18789`, в **`allowedOrigins`** добавить **`https://claw.shectory.ru`**.

---

## Актуальное состояние конфига OpenClaw (структура)

- **`gateway.mode`:** `local`
- **`gateway.auth`:** `mode: token`, токен в конфиге (в чат не копировать).
- **`gateway.controlUi.allowedOrigins`** — уже включали как минимум:
  - `http://127.0.0.1:18789`
  - `http://localhost:18789`
  - `http://192.144.14.187:18789`
- **`gateway.bind`:** планировали выставить **`lan`** (для прослушивания не только loopback). Команда с ошибкой: `openclaw config set gateway.bind lan --strict-json` — неверно, т.к. с `--strict-json` значение должно быть JSON-строкой. **Правильно:** `openclaw config set gateway.bind lan` (без флага) или `openclaw config set gateway.bind '"lan"' --strict-json`.
- **Версия CLI:** OpenClaw **2026.4.11**; в логах было предложение обновиться до **2026.4.15** (`openclaw update`).

Полезные команды:

```bash
openclaw config file          # путь к активному openclaw.json
openclaw config validate
openclaw config get gateway.controlUi.allowedOrigins
openclaw config get gateway.bind
systemctl --user status openclaw-gateway.service
systemctl --user restart openclaw-gateway.service
sudo ss -tlnp | grep 18789
```

**Логи «unauthorized»** при подключении с `Origin: http://127.0.0.1:18789` — обычно **неверный/устаревший токен** в форме; для доверенного входа: на сервере **`openclaw dashboard`** (без GUI выдаёт URL с `#token=...` и подсказку про `ssh -L`).

---

## DNS

- **`dig +short claw.shectory.ru`** (и `@8.8.8.8`) был **пустой** — **A-запись в панели регистратора ещё не создана / не разошлась**.
- Следующий шаг для человека/агента с доступом к DNS: **A: `claw` → публичный IP VPS** (раньше фигурировал **192.144.14.187**).

---

## Caddy / HTTPS (скрипт не выполнялся агентом удалённо)

В чате был предложен bash-скрипт: проверка DNS → `apt install caddy` → `/etc/caddy/Caddyfile` с `claw.shectory.ru { reverse_proxy 127.0.0.1:18789 }` → `caddy validate` → `systemctl reload caddy` → при активном **ufw**: `allow 80,443/tcp`.

После работающего **https://claw.shectory.ru**:

1. В **`gateway.controlUi.allowedOrigins`** добавить **`https://claw.shectory.ru`**.
2. **`systemctl --user restart openclaw-gateway.service`**
3. В UI: WebSocket **`wss://claw.shectory.ru`**, токен из конфига / `openclaw dashboard`.

Опционально: закрыть прямой доступ к **18789** с интернета, оставить только **443** через Caddy.

---

## Ограничения среды прошлого агента

- Нет **`Host shevbo-cloud`** и ключа **`shevbo-cloud`** на рабочей машине репозитория → **`ssh shevbo-cloud` с агента не выполнялся**.
- Нет доступа к **панели DNS** регистратора.

---

## Что попросить у пользователя для следующего шага

1. Подтвердить: **`dig +short claw.shectory.ru @8.8.8.8`** возвращает IP.
2. Либо добавить в Cursor/SSH config на той машине, откуда агент будет ходить на VPS, блок **`Host shevbo-cloud`** (HostName, User, IdentityFile).
3. После HTTPS — фрагмент **`openclaw config get gateway.controlUi.allowedOrigins`** и скрин/текст ошибки из браузера, если что-то останется.

---

*Файл создан как контекст handoff; при необходимости обновите IP, поддомен и версию OpenClaw.*
