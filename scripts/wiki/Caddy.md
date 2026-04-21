# Caddy и OpenClaw (shevbo-cloud)

Краткая **операционная** документация: TLS, reverse proxy на шлюз OpenClaw, дополнительные маршруты, откат, связка с прокси и наблюдателем.

Официальные материалы: [Caddyfile](https://caddyserver.com/docs/caddyfile), [reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).

---

## Роль в стеке

- Терминация **HTTPS** (порт **443**, при необходимости **80** для ACME).
- **Маршрутизация** на **`127.0.0.1:18789`** — процесс OpenClaw Gateway (`gateway.bind: lan`).
- Опционально — узкие маршруты **раньше** общего `reverse_proxy`: статика, отдельные API, каталоги с `file_server`.

Схема:

```text
[Клиент] --HTTPS:443--> [Caddy] --HTTP--> [OpenClaw :18789]
                              |
                         route /links/* ...
```

---

## Пути на сервере

| Назначение | Путь |
|------------|------|
| Основной конфиг | `/etc/caddy/Caddyfile` |
| Drop-in окружения (прокси исходящих запросов Caddy) | `/etc/systemd/system/caddy.service.d/proxy.conf` |
| Системный env прокси (копия после sync) | `/etc/proxy6/environment.env` |
| Пример фрагмента для домена (репозиторий) | `scripts/Caddyfile.claw.shectory.ru.snippet` |
| Откат workspace `/links` | `~/ROLLBACK-openclaw-workspace-links.txt` (если есть) |

Домен прод-портала: **`claw.shectory.ru`** (уточнять DNS A/AAAA при переносе).

---

## Типовая структура серверного блока

1. Сначала **узкие** маршруты: `route`, `handle`, `handle_path` (например `/links/…`).
2. Затем общий **`reverse_proxy localhost:18789`** (или `127.0.0.1:18789`) на всё остальное.

Фрагмент из репозитория (`scripts/Caddyfile.claw.shectory.ru.snippet`): маршруты `/links/ws`, `/links/api`, статика `/links`, затем общий прокси на шлюз.

В **OpenClaw** для UI с домена должны быть перечислены полные origins, например `https://claw.shectory.ru` в `gateway.controlUi.allowedOrigins`.

Чтобы шлюз **доверял заголовкам** от Caddy на том же хосте и не спамил в лог предупреждением *«Proxy headers detected from untrusted address…»*, задайте `gateway.trustedProxies` (например `["127.0.0.1","::1"]`). В репозитории: `scripts/openclaw/cloud-set-gateway-trusted-proxies-loopback.sh` (копия в `~/bin` на VPS). Подробнее: [OpenClaw-Pi-repair-rotate-and-secrets.md](./OpenClaw-Pi-repair-rotate-and-secrets.md).

---

## Исходящий трафик Caddy и Proxy6

Скрипт `scripts/proxy6/sync-proxy6-system-env.sh` (на сервере часто `/usr/local/sbin/…`) может:

- копировать актуальный `proxy.systemd.env` в **`/etc/proxy6/environment.env`**;
- создавать **`caddy.service.d/proxy.conf`** с `EnvironmentFile=-/etc/proxy6/environment.env`;
- перезапускать **caddy** после обновления.

Так Caddy (например запросы к Let’s Encrypt или исходящие проверки) может использовать тот же **HTTP(S)_PROXY**, что и остальные сервисы. Если прокси не нужен для ACME — проверь поведение после смены прокси (firewall, DNS, логи `journalctl -u caddy`).

---

## Команды после правок

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
# при ошибках конфига reload не применится — смотри вывод validate
sudo systemctl status caddy --no-pager
```

Проверка снаружи:

```bash
curl -sSI "https://claw.shectory.ru/" | head -5
```

---

## Откат

1. Найти бэкап: `ls /etc/caddy/Caddyfile.bak*`
2. Восстановить: `sudo cp /etc/caddy/Caddyfile.bak.<timestamp> /etc/caddy/Caddyfile`
3. `sudo caddy validate --config /etc/caddy/Caddyfile` и `sudo systemctl reload caddy`

Пример текста отката только для маршрутов `/links`: см. `scripts/ROLLBACK-openclaw-workspace-links.txt`.

---

## Безопасность

- Не выкладывать в открытый доступ листинги workspace; при необходимости — **basicauth** в Caddy или ограничение по IP.
- При `gateway.bind: lan` порт **18789** слушает сеть интерфейса; прод обычно закрывают прямой доступ с интернета и оставляют только **443** через Caddy (см. firewall / security group).

---

## Наблюдатель (observer)

Внешний скрипт `openclaw-observer` при паттерне **`EADDRINUSE`** в логах шлюза может перезапускать **caddy** и шлюз (см. `~/.openclaw/Wiki/Wiki-Observer.md`). Для `systemctl restart caddy` пользователю **shevbo** выдан **NOPASSWD** в `/etc/sudoers.d/openclaw-observer`.

---

## Связанные документы

- `~/.openclaw/Wiki/Wiki-Observer.md` — healthcheck, прокси, Telegram.
- В репозитории: `AGENT-CONTEXT-OpenClaw-Caddy-Developer.md` — контекст для агентов (задачи, безопасность, шаблоны).

---

*Конкретные IP, токены и имена бэкапов уточнять на хосте; этот файл — соглашение по эксплуатации.*
