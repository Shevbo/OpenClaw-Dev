# OpenClaw: пере-пара Pi-node, ротация секретов и гигиена логов

Когда это нужно:

- после утечки **gateway** или **node** токенов в логи/чат/скриншоты;
- после экспериментов с `paired.json` / `pending.json`, когда проще «с нуля», чем чинить состояние вручную;
- при застрявших `pairing required` / `code=1008` в журнале шлюза.

## Принципы безопасности

1. **Считайте скомпрометированными** любые значения, которые когда-либо попали в непредназначенный канал (в т.ч. вывод `openclaw nodes approve` без перенаправления — CLI может напечатать чувствительные поля). После инцидента делайте **ротацию `gateway.auth.token`** и **полную пере-пару** node.
2. **Не копируйте** `gateway.auth.token` через `openclaw config get`, если не уверены, что вывод совпадает с JSON байт-в-байт. Для синхронизации на Pi используйте **`jq -r '.gateway.auth.token' ~/.openclaw/openclaw.json`** или скрипт `cloud-sync-pi-gateway-token.sh`.
3. В скриптах и runbook одобряйте node так: `openclaw nodes approve "<requestId>" >/dev/null` — без сохранения stdout в файлы/чат.
4. **Два шага одобрения**: сначала `openclaw devices approve <requestId>` (роль node), затем `openclaw nodes approve <requestId>` (node.pair). Заявки лежат в `~/.openclaw/devices/pending.json` и `~/.openclaw/nodes/pending.json` (ключи объекта — это `requestId`).

## Автоматический сценарий на облаке

На **shevbo-cloud** в `~/bin` лежит `cloud-repair-pi-node-pairing.sh`. Он:

- останавливает `openclaw-node` на Pi по SSH (`PI_SSH`, по умолчанию `shevbo-pi`);
- снимает pairing **device** роли node (по умолчанию ищет `deviceId` в `openclaw devices list --json`, можно задать `NODE_DEVICE_ID`);
- обнуляет `~/.openclaw/nodes/paired.json` и `pending.json`;
- при необходимости **ротирует** `gateway.auth.token` (отключить: `SKIP_GATEWAY_TOKEN_ROTATE=1`);
- валидирует конфиг, перезапускает `openclaw-gateway.service`;
- записывает новый токен в `~/.config/openclaw/pi-node-remote.env` на Pi, удаляет `~/.openclaw/node.json`, поднимает node;
- **ждёт до ~90 с**, пока Pi создаст заявки в `pending.json`, и выполняет оба approve (вывод `nodes approve` подавлен).

Зависимости на облаке: `jq`, `openssl`, `ssh` к Pi.

Пример:

```bash
chmod +x ~/bin/cloud-repair-pi-node-pairing.sh
bash ~/bin/cloud-repair-pi-node-pairing.sh
```

После **ротации `gateway.auth.token`** Pi-node подтягивается скриптами синхронизации; **Control UI в браузере** нужно обновить отдельно (см. ниже).

## После ротации шлюза: Web UI (`token_mismatch`)

Симптом в логах шлюза: `reason=token_mismatch` или `gateway token mismatch` для `openclaw-control-ui` с `Origin: https://claw.shectory.ru` — в UI всё ещё указан **старый** токен.

**Решение (предпочтительно, без ручного копирования hex из JSON):** на **shevbo-cloud** выполнить `~/bin/cloud-refresh-control-ui-connect.sh`. Скрипт пишет **одну строку** в файл `~/.openclaw/tmp/control-ui-connect.url` (права `600`): готовый `Dashboard URL: https://claw.shectory.ru/#token=…` для открытия за Caddy (база задаётся `OPENCLAW_CONTROL_UI_PUBLIC_BASE`, по умолчанию `https://claw.shectory.ru`). Откройте файл на доверенной машине (`scp` или `ssh … cat …` в локальный браузер), **не** вставляйте URL в мессенджеры.

**Комбо:** `~/bin/cloud-rotate-gateway-token-full.sh` — новый `gateway.auth.token`, перезапуск шлюза, вызов `cloud-sync-pi-gateway-token.sh` (если есть в `~/bin`) и обновление `control-ui-connect.url`.

**Вручную:** в Control UI → настройки подключения вставить актуальный токен из `jq -r '.gateway.auth.token' ~/.openclaw/openclaw.json` на сервере (или из UI админки, если у вас принят другой канал выдачи секретов).

Официально: [`openclaw dashboard`](https://docs.openclaw.ai/cli/dashboard).

## `trustedProxies` и предупреждение про proxy headers

Если шлюз за **Caddy** на том же хосте (`reverse_proxy 127.0.0.1:18789`), без доверенных прокси в логах появляется предупреждение вида **«Proxy headers detected from untrusted address… Configure gateway.trustedProxies»**.

**Решение:** на облаке выполнить `~/bin/cloud-set-gateway-trusted-proxies-loopback.sh` — выставляет `gateway.trustedProxies: ["127.0.0.1","::1"]`, валидирует конфиг и перезапускает `openclaw-gateway.service`. После этого предупреждение при нормальном трафике через локальный Caddy не должно повторяться (проверка: `journalctl --user -u openclaw-gateway.service | grep -c 'Proxy headers detected'` за интервал после перезапуска).

См. также [Security / reverse proxy](https://docs.openclaw.ai/gateway/security).

## Ошибки Google `503` / «temporarily overloaded»

Это **временная перегрузка или квоты на стороне Google** для выбранной preview/lite-модели. Полностью убрать из логов нельзя без смены провайдера или модели.

**Практика снижения шума:** не ставить «нестабильные» preview в начало цепочки fallback для фоновых задач; при необходимости перенести `google/gemini-3.1-flash-lite-preview` ниже в `agents.defaults.model.fallbacks` в `openclaw.json`; сгладить частоту тяжёлых cron; дождаться стабилизации сервиса Google.

## Ручной порядок (если без скрипта)

1. Остановить node на Pi: `systemctl --user stop openclaw-node.service`.
2. На облаке: `openclaw devices remove <deviceId_роли_node>` (или через UI), при необходимости очистить `~/.openclaw/nodes/paired.json` → `{}` и `pending.json` → `{}` при остановленном шлюзе либо осознавая гонки с процессом.
3. Сгенерировать новый токен, записать в `openclaw.json`, `openclaw config validate`, перезапуск шлюза.
4. Синхронизировать токен на Pi (`cloud-sync-pi-gateway-token.sh` или эквивалент), `rm -f ~/.openclaw/node.json`, `systemctl --user start openclaw-node.service`.
5. Дождаться записей в `devices/pending.json`, затем `nodes/pending.json`; выполнить оба approve по **requestId** из ключей JSON (не публикуйте файлы целиком).

## Проверка

- Облако: `openclaw nodes status --connected` — **Shevbo-pi**, **paired · connected**; в последних строках `journalctl --user -u openclaw-gateway.service` нет повторяющихся `code=1008 reason=pairing required` от WG-IP Pi.
- Pi: `systemctl --user is-active openclaw-node.service`; при отсутствии строк в `journalctl --user` убедитесь, что включён **linger** для пользователя и сервис логирует (см. основной документ по Pi-node).

## См. также

- [OpenClaw-Pi-remote-node-WireGuard.md](./OpenClaw-Pi-remote-node-WireGuard.md) — основная схема WG + скрипты `pi-node-remote-to-cloud.sh`, `cloud-sync-pi-gateway-token.sh`, `cloud-push-pi-node-remote.sh`.
