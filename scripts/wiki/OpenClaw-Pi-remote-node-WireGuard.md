# OpenClaw: Pi как удалённый node, главный шлюз в облаке (shevbo-cloud)

Цель: **один Gateway** на VPS (`shevbo-cloud`), выполнение и node-инструменты на Raspberry Pi (`shevbo-pi`). Трафик агента и каналов остаётся в облаке; Pi подключается к WebSocket шлюза как [node host](https://docs.openclaw.ai/cli/node).

## Почему «нужен обратный канал»

WireGuard **симметричен**: достаточно, чтобы на **Pi** в `[Peer]` к облаку были:

- `PublicKey` сервера (VPS),
- при необходимости **`Endpoint`** VPS (публичный IP:порт WG), чтобы Pi мог **инициировать** сессию из-за NAT,
- **`AllowedIPs`**, включающие **внутренний адрес WG сервера** (и при необходимости подсеть за WG).

Если настроен только «шлюз в сторону Pi» без маршрута **Pi → адрес WG на VPS**, node не сможет открыть `ws://<wg-ip-vps>:18789`. Проверка с Pi:

```bash
ping -c 2 <WG_IP_облака>
# при bind шлюза на все интерфейсы:
curl -sS -o /dev/null -w "%{http_code}\n" "http://<WG_IP_облака>:18789/__openclaw__/" || true
```

Аналогия с **shevbo-shectory**: там обычно оба конца знают peer и маршруты; здесь то же — **маршрут до WG-IP облака с Pi** обязателен для прямого WebSocket без SSH.

## Автозапуск и стабильность туннеля (shevbo-cloud ↔ shevbo-pi)

Чтобы после перезагрузки **оба** хоста сами поднимали `wg0` и туннель не «засыпал» за NAT:

1. **`wg0.conf`** уже согласован (ключи, `AllowedIPs`, на Pi — **`Endpoint`** публичного облака с портом WG).
2. На **Raspberry Pi за NAT** один раз добавьте keepalive к peer с `Endpoint` (иначе handshake на VPS может долго не обновляться):
   ```bash
   sudo bash scripts/wireguard/shevbo-wg-peer-ensure-keepalive.sh
   ```
3. На **каждом** хосте (облако и Pi) включите автозапуск `wg-quick` и при желании watchdog по ping:
   ```bash
   # опционально: периодический ping противоположной стороны + restart wg при обрыве
   sudo cp scripts/wireguard/shevbo-wg-health.default.example /etc/default/shevbo-wg-health
   sudo nano /etc/default/shevbo-wg-health   # на Pi: WG_HEALTH_TARGET=WG-IP облака; на облаке: WG-IP Pi
   sudo bash scripts/wireguard/shevbo-wg-enable-autostart.sh
   ```
   Скрипт делает: **`systemctl enable --now wg-quick@wg0`**, копирует **`shevbo-wg-healthcheck.sh`** в `/usr/local/sbin`, при наличии **`/etc/default/shevbo-wg-health`** — timer **`shevbo-wg-health.timer`** (раз в несколько минут).
4. Диагностика на Pi: **`scripts/pi/shevbo-pi-wg-cloud-check.sh`** (опция **`--restart`**).

Файлы в репозитории: `scripts/wireguard/shevbo-wg-enable-autostart.sh`, `shevbo-wg-peer-ensure-keepalive.sh`, `shevbo-wg-healthcheck.sh`, `shevbo-wg-health.service`, `shevbo-wg-health.timer`, `shevbo-wg-health.default.example`.

## Вариант A (предпочтительно): WebSocket по WireGuard

1. **Облако** (`~/.openclaw/openclaw.json`): шлюз слушает адрес, доступный с Pi. Часто достаточно `gateway.bind: lan` и открыть **18789/tcp только для интерфейса WG** (или для подсети WG в `ufw`), не обязательно весь интернет.
2. **Токен** на Pi должен **байт-в-байт** совпадать с `gateway.auth.token` в **`~/.openclaw/openclaw.json` на шлюзе**. Не используйте для копирования `openclaw config get gateway.auth.token` на сервере, если в выводе редактирование/редакция — берите значение через **`jq -r '.gateway.auth.token' ~/.openclaw/openclaw.json`** или скрипт `scripts/openclaw/cloud-sync-pi-gateway-token.sh` (запуск на облаке, пишет на Pi и перезапускает node).
3. **Pi**: скрипт из репозитория (см. ниже) или вручную:

   ```bash
   export OPENCLAW_GATEWAY_TOKEN='...'   # тот же, что в JSON шлюза
   export CLOUD_GATEWAY_HOST='<WG_IP_VPS>'  # например 10.66.0.3
   export CLOUD_GATEWAY_PORT=18789
   export ALLOW_STOP_LOCAL_GATEWAY=1
   bash scripts/openclaw/pi-node-remote-to-cloud.sh
   ```

   Скрипт настраивает user-unit и drop-in: токен из `~/.config/openclaw/pi-node-remote.env` и **`OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1`** для `ws://` на частный адрес (WG), см. [Remote Access](https://docs.openclaw.ai/gateway/remote).

4. **Облако — два одобрения** (с 2026.3.31+ недостаточно только device UI; см. [Gateway-owned pairing](https://docs.openclaw.ai/gateway/pairing)):

   ```bash
   # 1) Device pairing (роль node) — заявка лежит в ~/.openclaw/devices/pending.json при сомнениях:
   openclaw devices approve <requestId>

   # 2) Node pairing (node.pair) — заявка в ~/.openclaw/nodes/pending.json:
   openclaw nodes approve <requestId>
   ```

5. На Pi **не** должен одновременно мешать второй полноценный шлюз на том же порту: скрипт отключает `openclaw-gateway.service` при `ALLOW_STOP_LOCAL_GATEWAY=1`.

## Вариант B: WebSocket по HTTPS (`wss://claw.shectory.ru`)

Если Pi не должен ходить на WG-порт, а только в интернет по 443:

```bash
export OPENCLAW_GATEWAY_TOKEN='...'
export CLOUD_GATEWAY_HOST='claw.shectory.ru'
export CLOUD_GATEWAY_PORT=443
export CLOUD_USE_TLS=1
bash scripts/openclaw/pi-node-remote-to-cloud.sh
```

При проблемах с сертификатом см. `--tls-fingerprint` в [доке node](https://docs.openclaw.ai/cli/node).

## Вариант C: SSH-туннель с Pi на облако (если WG только в одну сторону)

На Pi в `~/.ssh/config` — хост к VPS (ключи как у вас принято), затем **LocalForward**: локальный порт на Pi → `127.0.0.1:18789` на облаке:

```ssh
Host shevbo-cloud-wg
  HostName <WG_IP_или_публичный_VPS>
  User shevbo
  IdentityFile ~/.ssh/id_ed25519
  LocalForward 18789 127.0.0.1:18789
```

```bash
ssh -N -f shevbo-cloud-wg
export OPENCLAW_GATEWAY_TOKEN='...'
export CLOUD_GATEWAY_HOST=127.0.0.1
export CLOUD_GATEWAY_PORT=18789
bash scripts/openclaw/pi-node-remote-to-cloud.sh
```

Туннель должен быть **всегда поднят** (systemd `ssh` с `Restart=always` или autossh) — иначе node отвалится.

## Проверка

- На облаке: `openclaw nodes status --connected` — строка **Shevbo-pi** со статусом **paired · connected**.
- На Pi: `systemctl --user is-active openclaw-node.service` и при необходимости `ss -tnp | grep <WG_IP_облака>`.
- Логи шлюза: `journalctl --user -u openclaw-gateway.service -n 80 --no-pager` (искать `peer=10.66.0.2` и отсутствие `pairing required` после одобрений).

## Частые сбои

| Симптом | Что сделать |
|--------|-------------|
| В логах шлюза `code=1008 reason=pairing required` | Выполнить **оба** approve: `devices` затем `nodes` (см. выше). |
| На Pi нет исходящего TCP к WG-IP шлюза, токен «есть», но не коннектится | Сверить SHA256 токена на Pi и в JSON шлюза; не доверять `config get`, если он редактирует вывод. |
| `ws://` на частный IP | На процесс-клиенте задать **`OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1`** (уже в drop-in из `pi-node-remote-to-cloud.sh`). |
| В unit на Pi `OPENCLAW_GATEWAY_TOKEN=__OPENCLAW_REDACTED__` | Использовать **ExecStart** через `bash -lc 'set -a; . …/pi-node-remote.env; …'` из скрипта, а не только `EnvironmentFile`. |

## Связанные файлы репозитория

| Файл | Назначение |
|------|------------|
| `scripts/openclaw/pi-node-remote-to-cloud.sh` | Установка/обновление node, env с токеном, drop-in systemd |
| `scripts/openclaw/cloud-push-pi-node-remote.sh` | С облака по SSH на Pi: передать токен (**jq** из JSON) и запустить скрипт выше |
| `scripts/openclaw/cloud-sync-pi-gateway-token.sh` | Только синхронизация токена с JSON шлюза в `pi-node-remote.env` на Pi + restart node |
| `scripts/openclaw/cloud-repair-pi-node-pairing.sh` | Полная пере-пара Pi-node + ротация `gateway.auth.token` (запуск на облаке; см. [OpenClaw-Pi-repair-rotate-and-secrets.md](./OpenClaw-Pi-repair-rotate-and-secrets.md)) |
| `scripts/openclaw/cloud-set-gateway-trusted-proxies-loopback.sh` | `gateway.trustedProxies` для Caddy на `127.0.0.1` / `::1` (убирает WARN про untrusted proxy headers) |
| `scripts/openclaw/cloud-refresh-control-ui-connect.sh` | Файл `~/.openclaw/tmp/control-ui-connect.url` с URL Control UI после смены токена |
| `scripts/openclaw/cloud-rotate-gateway-token-full.sh` | Ротация токена шлюза + sync на Pi + обновление URL-файла для UI |
| `scripts/wiki/SSH-shevbo-cloud-to-pi.md` | SSH cloud → Pi (админка), не путать с трафиком node |
| `scripts/openclaw/install-openclaw-pi-minimal.sh` | CLI на Pi |
| `scripts/pi/shevbo-pi-wg-cloud-check.sh` | Диагностика WG с Pi к облаку (`--restart` опционально) |
| `scripts/wireguard/shevbo-wg-enable-autostart.sh` | `enable+start` **wg-quick@wg0**, опционально timer health-check |
| `scripts/wireguard/shevbo-wg-peer-ensure-keepalive.sh` | **PersistentKeepalive** в `[Peer]` с **Endpoint** (обычно Pi) |
| `scripts/wireguard/shevbo-wg-healthcheck.sh` + `.service` + `.timer` + `shevbo-wg-health.default.example` | Ping противоположного WG-IP и **restart** интерфейса при обрыве |

Официально: [Remote Access](https://docs.openclaw.ai/gateway/remote), [`openclaw node`](https://docs.openclaw.ai/cli/node), [`openclaw devices`](https://docs.openclaw.ai/cli/devices).
