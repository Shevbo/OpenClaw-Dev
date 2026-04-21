# OpenClaw — контекст для продолжения работы (shectory-work)

Цель этого файла: **не дублировать уже сделанное** — зафиксировать архитектуру, политики, пути, скрипты и открытые хвосты. Репозиторий: **OpenClaw-Dev** (`main`), рабочая копия на **`shectory-work`**: `~/workspaces/openclaw`. Секреты и значения токенов **не** хранить здесь.

**Каноническая копия этого файла на шлюзе:** `/home/shevbo/.openclaw/Wiki/CONTINUATION-CONTEXT.md` — при расхождении править там, затем **`bash scripts/openclaw/sync-wiki-from-gateway.sh`** (или выкладка из репо: **`sync-wiki-to-gateway.sh`**). Оглавление всех материалов: **`Wiki-INDEX.md`** в том же каталоге.

---

## 1. Архитектура (один раз)

| Узел | Роль |
|------|------|
| **shevbo-cloud** | VPS (Ubuntu, пользователь **shevbo**), **единственный Gateway** OpenClaw, порт **18789**, Caddy **HTTPS** → `127.0.0.1:18789`, Proxy6 для исходящего трафика. |
| **shevbo-pi** | **Remote node** к шлюзу в облаке (WireGuard / `wss`), **не** второй полноценный публичный шлюз на том же порту при сценарии «node → cloud». |
| **shectory-work** | Dev-машина: клон репо, SSH-операции на cloud/Pi, правки и деплой скриптов. |
| **Observer** | Отдельный **bash + systemd user timer** (~5 мин), **не** npm-пакет OpenClaw; Telegram-алерты; реестр troubleshooting. |
| **Caddy** | Домен **`https://claw.shectory.ru`**, `trustedProxies` / `allowedOrigins` согласованы с шлюзом. |

---

## 2. Уже сделано (не переделывать вслепую)

### Облако (shevbo-cloud)

- Шлюз: **`~/.openclaw/openclaw.json`**, user-systemd **`openclaw-gateway.service`**; **`gateway.bind: lan`**; Control UI origins включали **127.0.0.1**, **localhost**, **192.144.14.187**, **`https://claw.shectory.ru`**.
- **Caddy**: reverse proxy на шлюз; **`gateway.trustedProxies`** для **`127.0.0.1` / `::1`** — убрать WARN про untrusted proxy headers (скрипт **`cloud-set-gateway-trusted-proxies-loopback.sh`**).
- **Прокси**: шлюз через drop-in **`openclaw-gateway.service.d/proxy.conf`** → **`/etc/proxy6/environment.env`**; **`openclaw-gateway-via-docker-group.sh`** — явный `source` прокси перед `sg docker`.
- **Observer**: **`EnvironmentFile`** на тот же прокси + **`~/.config/proxy6/proxy.systemd.env`**; в **`openclaw-observer.sh`** — **`load_observer_proxy_env`** для детей (**registry-runner**, python). Синхронизация системного env: **`scripts/proxy6/sync-proxy6-system-env.sh`** (на сервере часто под `/usr/local/sbin/`). Перед restart шлюза при «HTTP fail» — ожидание **`wait_gateway_http`** (по умолчанию до **120** с, шаг **3** с; переопределение **`OBSERVER_GATEWAY_HTTP_WAIT_MAX_SEC`** / **`OBSERVER_GATEWAY_HTTP_POLL_SEC`**), чтобы не ловить ложный даунтайм на cold start.
- **Observer troubleshooting**: каталог **`~/.config/openclaw/observer/troubleshooting/`** — **`registry.json`**, **`registry-runner.py`**, **`fixes/*.sh`**, ingest (**`append-telegram-ingest.sh`**, **`ingest.d/`**); при совпадении по ingest — короткое сообщение в Telegram до fix.
- **Google auth / спам в TG**: отдельный throttled-алерт (**`OBSERVER_GOOGLE_AUTH_ALERT_COOLDOWN_SEC`**, по умолчанию **21600**); реестр **`google-auth-profile-unavailable`** → restart шлюза (**cooldown 1 ч**); общий grep по логам observer под это убран.
- **Sandbox на облаке**: **`agents.defaults.sandbox.mode: off`**, **`sandbox.browser.enabled: false`**, **`openclaw sandbox recreate --all --force`** (старый docker-sandbox убран). При **включённом** sandbox ранее: абсолютный **`/home/shevbo/.openclaw/workspace/monitoring`** в заданиях ломал политику → нужны **`monitoring/...`** или **`/workspace/monitoring/...`**; fix-скрипты меняли пути + symlink **`sandboxes/agent-*/monitoring` → workspace/monitoring** (есть **`.bak`**).
- **Политика голоса / медиа (строго Google на cloud)**: только **`google`** для **STT** (`tools.media.audio`) и **TTS** (`messages.tts`); OpenAI **убран** из audio и плагина **`openai`**; **`openai-codex`** (OAuth Codex) — отдельно. Патч: **`scripts/openclaw/patch-tools-media-audio-google-only.py`**. Док: **`scripts/wiki/OpenClaw-shevbo-google-only-voice.md`**. «Telegram не понимает голосовые» — явный **`tools.media.audio`** + при обязательном прокси **`channels.telegram.proxy`** (см. **`sync-telegram-proxy-from-proxy6-env.py`**).
- **Политика моделей Gemini (shevbo-cloud, зафиксировано в вики)**: **LLM** primary — `google/gemini-3.1-flash-lite-preview`; запасной LLM — **`google/gemini-2.5-flash-lite`** (GA). Не использовать **`gemini-2.5-flash-lite-preview-09-2025`** — снята с API (**404** на `generateContent`, см. [changelog](https://ai.google.dev/gemini-api/docs/changelog)). **STT**: цепочка `gemini-3.1-flash-lite-preview` → `gemini-2.5-flash-lite` (как в патче). **TTS**: выбор в `messages.tts.providers.google.model` (3.1 TTS vs стабильный 2.5 — см. вики). **`agents.defaults.models`** — allowlist всех используемых `google/…`.
- **Cron vs квота**: фоновые **`openclaw cron`** (`agentTurn`) при необходимости **`openclaw cron edit <id> --model google/gemini-2.5-flash-lite`**, чтобы не конкурировать с основным чатом по тем же моделям/лимитам.
- **Пики нагрузки / incomplete turn**: сообщение *«Agent couldn't generate… tool actions may have already been executed»* — обрыв хода после мутационных инструментов (в т.ч. TTS), не отдельный mutex в конфиге. Смягчение: **`patch-openclaw-throughput-mitigation.py`** (`cron.maxConcurrentRuns=1`, `tools.media.concurrency=1`, `messages.queue.debounceMsByChannel.telegram` ≥ **400**), подробности в **`scripts/wiki/OpenClaw-shevbo-google-only-voice.md`**.
- **Шлюз и NO_PROXY**: **`scripts/openclaw/openclaw-gateway-via-docker-group.sh`** после `source` Proxy6 выставляет **`NO_PROXY=no_proxy=127.0.0.1,localhost,::1`**, чтобы шаблонный NO_PROXY из прокси-файла не уводил Google/Telegram API в direct.
- **Секреты Google**: типично **`~/.openclaw/my_secrets.json`** + **`secrets.providers.google`** (не дублировать в чатах).
- **SecretRef / токен шлюза в daemon**: рабочий путь — **`gateway.auth.token`** в JSON + **`openclaw gateway install`**, restart (не полагаться на обходной SecretRef без env в unit).
- **`openclaw config set` с JSON из PowerShell** — ломалось; правки через **Python на сервере**.

### Pi (shevbo-pi)

- **Node ≥ 22.14** для пакета **openclaw**; системный Node **20 не трогали** — **`nvm` + Node 22.x** в **`~/.nvm`**; глобальный **`npm i -g openclaw`** (**`install-openclaw-pi-minimal.sh`**).
- **`loginctl enable-linger shevbo`** — автозапуск user-сервисов после reboot.
- На Pi **bind loopback** для локального сценария; доступ шлюза с ПК: **`ssh -L 18789:127.0.0.1:18789`**.
- Пара node: **два** approve — **`devices`** затем **`nodes`**; токен с облака на Pi — **`jq -r '.gateway.auth.token'`** из **`openclaw.json`** или **`cloud-sync-pi-gateway-token.sh`** (не **`config get`**, если вывод может отличаться). **`OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1`** для **`ws://`** на WG. Unit: **`ExecStart` через `bash -lc` + `set -a; . pi-node-remote.env`** если токен в unit редактится.
- Ремонт пары / ротация: **`cloud-repair-pi-node-pairing.sh`**, **`cloud-rotate-gateway-token-full.sh`**, **`cloud-refresh-control-ui-connect.sh`** → **`~/.openclaw/tmp/control-ui-connect.url`** (права **600**).
- Скрипты: **`pi-node-remote-to-cloud.sh`**, **`cloud-push-pi-node-remote.sh`**, **`pi-onboard-finish.sh`**.

### Репозиторий и вики

- **Канон операционной документации на шлюзе:** **`/home/shevbo/.openclaw/Wiki/`** (пользователь **`shevbo`**). Туда перенесены **все** материалы: **`Wiki-INDEX.md`**, контексты (**`CONTINUATION-CONTEXT.md`**, **`AGENT-CONTEXT-…`**, **`cursor-handoff-…`**, **`AGENTS.md`**), **`scripts/wiki/*`**, **`Wiki-Observer.md`**, **`Wiki-OBSERVER-TROUBLESHOOTING-GUIDE.md`**. В репозитории — **зеркало для Git**; синхронизация: **`scripts/openclaw/sync-wiki-to-gateway.sh`** / **`sync-wiki-from-gateway.sh`**. Системный контекст агента: **`AGENTS.md`**, **`.cursor/rules/openclaw-gateway-wiki.mdc`**.
- Скрипты в **`scripts/`**, handoff: **`cursor-handoff-openclaw-shevbo-cloud.md`**, **`AGENT-CONTEXT-OpenClaw-Caddy-Developer.md`**.
- **Голосовой веб-MVP** в репо: **`scripts/web-voice-mvp/`** (**`voice_backend.py`** ~**8091**, **`serve_mvp.py`** ~**8765**, **`requirements-voice-mvp.txt`**, **`legacy-ws-mic.html`**), **`scripts/Caddyfile.voice-mvp.snippet`**. Вспомогательно: **`scripts/telegram-voice-bridge/`** (не обязательный путь MVP).
- **SSH Windows**: **`scripts/ssh/ssh-passwordless-setup.ps1`** (прокси Gallery, Proxy6, **`curl --proxy-user`**); локальная копия вне репо могла быть **`c:\dev\ssh-passwordless-setup.ps1`** / **`c:\dev\p.txt`** — ориентир репо.

### Версии (сверять на хостах)

- CLI / unit на серверах упоминались **2026.4.11** … **2026.4.15**; обновление — по официальной доке **`openclaw update`**.

---

## 3. Открытые задачи (сделать осознанно)

| Тема | Действие |
|------|----------|
| **DNS** | Проверить **A/AAAA** для **`claw.shectory.ru`** → IP VPS. |
| **Caddy** | Довести **443 → 127.0.0.1:18789**; при необходимости **закрыть 18789** с интернета; вставить сниппеты (**`Caddyfile.claw.shectory.ru.snippet`**, при MVP — **`Caddyfile.voice-mvp.snippet`**, каталог **`/var/www/openclaw-voice-mvp`**). |
| **shectory-work SSH** | **`Host shevbo-cloud`**, **`shevbo-pi`**, ключи, **`ssh -o BatchMode=yes`** для проверки без пароля; см. **`scripts/ssh/verify-shevbo-pi-ssh-batchmode.sh`**. |
| **Cron / user-скрипты** (напр. **`pull_gcp_alerts.py`**) | Могут ходить в API **мимо прокси** → **`set -a; . …proxy…; set +a`** или **user timer + unit** с **`EnvironmentFile=-/etc/proxy6/environment.env`**. |
| **`verify-shevbo-proxy-egress.sh`** | **`curl` к `127.0.0.1:18789/__openclaw__/`** без токена может не быть **2xx** — не путать с обходом прокси наружу. |
| **Pi** | Предупреждения **`openclaw doctor`** про Node из **nvm** в user-unit; при **DHCP** — обновить **HostName** в SSH-config. |
| **Codex** | Нужен ли **полный отказ** от **`openai-codex`**, если не пользуетесь ACP. |
| **Voice MVP** | Systemd для **`voice_backend.py`** на VPS; **`AGENT_URL`** — какой HTTP-эндпоинт реально дергать; интеграция с нативным Voice плагином OpenClaw — вне текущего репо. |
| **Control UI URL** | Кто забирает **`control-ui-connect.url`** / политика не светить токен в чатах. |
| **Google 503 / overload** | Политика **fallbacks**, отдельная **`--model`** у cron (см. вики); при **404 model not found** — сверить id с [changelog](https://ai.google.dev/gemini-api/docs/changelog), не использовать снятые preview. |
| **Cursor sandbox / SKILL** | Пути вне **`/workspace`** — тема клиента Cursor, не VPS. |

---

## 4. Якоря путей и файлов в репо

| Область | Пути |
|----------|------|
| Инструкции агента (Cursor) | **`AGENTS.md`**, **`.cursor/rules/openclaw-gateway-wiki.mdc`**; синхронизация вики: **`scripts/openclaw/sync-wiki-to-gateway.sh`**, **`scripts/openclaw/sync-wiki-from-gateway.sh`** |
| OpenClaw cloud/Pi | **`scripts/openclaw/*.sh`**, **`sync-wiki-to-gateway.sh`**, **`sync-wiki-from-gateway.sh`**, **`patch-tools-media-audio-google-only.py`**, **`patch-openclaw-throughput-mitigation.py`**, **`openclaw-gateway-via-docker-group.sh`**, **`sync-telegram-proxy-from-proxy6-env.py`**, **`patch-enable-nodes-sandbox-tool.py`**, **`patch-openclaw-dev-full-access.py`**, **`patch-agent-alsoallow-google-direct-runtime.py`**, **`openclaw-gateway.service.d-*.conf`** |
| Вики на шлюзе (канон) | **`/home/shevbo/.openclaw/Wiki/`**; зеркало в репо: **`scripts/wiki/*.md`** |
| Observer | **`scripts/observer/openclaw-observer.sh`**, **`.service`**, **`.timer`**, **`Wiki-Observer.md`**, **`troubleshooting/*`** |
| Прокси | **`scripts/proxy6/*`** (`sync-proxy6-system-env.sh`, `verify-shevbo-proxy-egress.sh`, `install-openclaw-gateway-proxy-dropin.sh`) |
| Caddy | **`scripts/wiki/Caddy.md`**, **`scripts/Caddyfile.claw.shectory.ru.snippet`**, **`Caddyfile.voice-mvp.snippet`** |
| Pi / WG | **`scripts/wiki/OpenClaw-Pi-remote-node-WireGuard.md`**, **`OpenClaw-Pi-repair-rotate-and-secrets.md`**, **`SSH-shevbo-cloud-to-pi.md`** |
| Голос политика | **`scripts/wiki/OpenClaw-shevbo-google-only-voice.md`** |
| SSH Windows / проверка | **`scripts/ssh/ssh-passwordless-setup.ps1`**, **`scripts/ssh/verify-shevbo-pi-ssh-batchmode.sh`** |

---

## 5. Деплой (паттерн с shectory-work)

```bash
# Пример: troubleshooting на облако
scp -r scripts/observer/troubleshooting shevbo-cloud:tmp-trouble
ssh shevbo-cloud 'rsync -a tmp-trouble/ ~/.config/openclaw/observer/troubleshooting/ && chmod +x ~/.config/openclaw/observer/troubleshooting/registry-runner.py ~/.config/openclaw/observer/troubleshooting/fixes/*.sh && rm -rf tmp-trouble'

scp scripts/observer/openclaw-observer.sh shevbo-cloud:~/bin/
ssh shevbo-cloud 'chmod +x ~/bin/openclaw-observer.sh && sed -i "s/\r$//" ~/bin/openclaw-observer.sh && systemctl --user daemon-reload && systemctl --user restart openclaw-observer.timer'

# Скрипты OpenClaw в ~/bin
scp scripts/openclaw/*.sh shevbo-cloud:~/bin/
ssh shevbo-cloud 'chmod +x ~/bin/*.sh; sed -i "s/\r$//" ~/bin/*.sh'

# Вся вики и контексты на шлюз (канон)
bash scripts/openclaw/sync-wiki-to-gateway.sh

# Шлюз после правок конфига / drop-in
ssh shevbo-cloud 'systemctl --user daemon-reload && systemctl --user restart openclaw-gateway.service'
```

---

## 6. Быстрые проверки (без секретов)

```bash
ssh shevbo-cloud 'openclaw gateway status && openclaw config validate && openclaw sandbox explain'
ssh shevbo-cloud 'systemctl --user is-active openclaw-gateway.service && journalctl --user -u openclaw-gateway.service -n 40 --no-pager'
ssh shevbo-cloud 'openclaw nodes status --connected | head -20'
ssh shevbo-pi 'systemctl --user is-active openclaw-node.service'
ssh shevbo-cloud 'journalctl --user -u openclaw-gateway.service --since "1 hour ago" | grep -c "Proxy headers detected" || true'
```

Ingest из Telegram (на облаке):  
`bash ~/.config/openclaw/observer/troubleshooting/append-telegram-ingest.sh 'фрагмент лога'`

Голос MVP локально (shectory-work):  
`pip install -r scripts/web-voice-mvp/requirements-voice-mvp.txt`  
`python scripts/web-voice-mvp/voice_backend.py` → `curl -sS http://127.0.0.1:8091/api/voice/health`  
`python scripts/web-voice-mvp/serve_mvp.py` → браузер **`index.html?api=http://127.0.0.1:8091`**

---

## 7. Симптом → что уже сработало

| Симптом | Действие |
|---------|----------|
| **pairing / code=1008** | **`devices approve`** + **`nodes approve`**; в repair — ожидание **pending** (~90s). |
| **token_mismatch / UI** | **`control-ui-connect.url`** / dashboard; не светить токен. |
| **Pi токен ≠ JSON** | **jq** из **`openclaw.json`**, **`cloud-sync-pi-gateway-token.sh`**. |
| **Token в unit как REDACTED** | **`bash -lc` + `set -a; . env`** (**`pi-node-remote-to-cloud.sh`**). |
| **Proxy headers untrusted** | **`trustedProxies`** loopback. |
| **Telegram «от cron»** | Чаще **observer**; отключение TG — убрать/не использовать **`telegram.env`**, не слепо таймер. |
| **Google auth + спам TG** | Throttle + реестр + restart шлюза; ключи/квота/billing вручную. |
| **Agent / LLM / billing-monitor** | Реестр **`agent-llm-no-response`** → validate + restart. |
| **404 NOT_FOUND на модели** | Сверить id с [changelog Gemini](https://ai.google.dev/gemini-api/docs/changelog); для Flash Lite 2.5 использовать **`gemini-2.5-flash-lite`**, не **`…-preview-09-2025`**. |
| **Cron rate_limit на TTS** | У джоб **`openclaw cron edit … --model google/gemini-2.5-flash-lite`** (или другой не-TTS LLM по политике). |
| **EADDRINUSE два шлюза** | Один **`openclaw-gateway.service`**, отключить конфликтующий unit. |
| **PowerShell Gallery за прокси** | **HTTPS_PROXY** / **`-ProxyUri`**, **`curl --proxy-user`**. |
| **Node 20 на Pi** | **nvm + Node 22+**, глобальный **openclaw**. |
| **Observer/дети без прокси** | **EnvironmentFile** + **`load_observer_proxy_env`**. |
| **PowerShell `&&` / curl** | **`;`**, **`curl.exe`**. |
| **argparse non-ASCII help на Windows** | В **`telegram_voice_bridge.py`** — ASCII в help. |

---

## 8. Первый сеанс на shectory-work после открытия папки

1. `git pull`  
2. `ssh -o BatchMode=yes shevbo-cloud true` (и **shevbo-pi** по необходимости)  
3. `ssh shevbo-cloud 'openclaw gateway status && openclaw config validate'`  
4. Вики на шлюзе: сверить **`~/.openclaw/Wiki/*.md`** с конфигом; при правках в репо — **`scp scripts/wiki/*.md shevbo-cloud:~/.openclaw/Wiki/`** (см. **`AGENTS.md`**). Сверить **`OpenClaw-shevbo-google-only-voice.md`** с **`tools.media.audio`** / **`messages.tts`** через **jq** (без секретов)  
5. `bash scripts/proxy6/verify-shevbo-proxy-egress.sh` на VPS (или **`~/bin`** после копирования) + отдельно учесть **cron без прокси**  
6. Закрыть хвосты из **§3**

---

*Файл сгенерирован для переноса контекста четырёх чатов в один источник правды. Обновляйте §2/§3 при смене инфраструктуры.*
