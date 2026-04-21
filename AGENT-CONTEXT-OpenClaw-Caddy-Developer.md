# Контекст агента: «Разработчик OpenClaw + Caddy»

**Канон на шлюзе:** `/home/shevbo/.openclaw/Wiki/AGENT-CONTEXT-OpenClaw-Caddy-Developer.md` — см. **`Wiki-INDEX.md`**, синхронизация: **`scripts/openclaw/sync-wiki-*.sh`**.

Документ для передачи другому ИИ-агенту вместе с **конкретным заданием** (например, доработка страницы за Caddy, интеграция с OpenClaw, скрипты на VPS). **Примеры задач внизу — иллюстрация формата; их не выполнять, только использовать как образец постановки.**

---

## 1. Роль и зона ответственности

- **OpenClaw**: шлюз (Gateway), Control UI в браузере, агенты, конфиг `openclaw.json`, workspace, systemd user-сервис.
- **Caddy**: reverse HTTPS на домене, дополнительные маршруты (статика, отдельные «мини-приложения» рядом с порталом).
- **Сервер**: Linux VPS (Ubuntu), пользователь развёртывания — не root-повседневный; правки Caddy и системных путей — через `sudo` где нужно.

Агенту выдают **SSH-доступ** (или уже настроенный alias вроде `shevbo-cloud`) и ожидают **изменения на сервере** + **краткий откат**, если что-то ломает прод.

**Вики на шлюзе (канон):** операционные документы и описания для прод-OpenClaw ведём в **`/home/shevbo/.openclaw/Wiki/`** на VPS (`shevbo`). В репозитории **`scripts/wiki/`** — зеркало для Git; после правок синхронизировать на шлюз. Подробнее: **`AGENTS.md`** в корне репозитория.

---

## 2. Хост и доступ

| Параметр | Типичное значение (уточнять у владельца) |
|----------|------------------------------------------|
| SSH alias | `shevbo-cloud` (см. `~/.ssh/config` на рабочей машине) |
| Пользователь на VPS | `shevbo` (uid 1000) |
| Домен портала | `claw.shectory.ru` (HTTPS) |
| Публичный IP VPS | задаётся A-записью DNS на домен/поддомен |

**Важно:** секреты (токен шлюза, пароли прокси, ключи API) в чат **не вставлять**; брать с хоста через существующие файлы окружения и конфиг.

**User systemd:** для сервисов пользователя включён **`loginctl` linger** (после ребута user-сервисы поднимаются).

---

## 3. Архитектура (логическая)

```text
[Браузер] --HTTPS:443--> [Caddy]
                              |
          +-------------------+-------------------+
          |                                       |
    route /links/*                         reverse_proxy
    (статика)                         localhost:18789
          |                                       |
    /var/www/...                         [OpenClaw Gateway]
    (генерируемые HTML)                  WS + HTTP Control UI
```

- **Caddy** терминирует TLS и маршрутизирует:
  - основной трафик на **`127.0.0.1:18789`** (OpenClaw Gateway);
  - при необходимости — отдельные пути (например, **`/links/`**) на **статический каталог** или другой backend.
- **OpenClaw** слушает **`gateway.bind: lan`** → на хосте `*:18789` (за прокси пользователь ходит на 443).

---

## 4. Стек

| Слой | Технологии |
|------|------------|
| ОС | Ubuntu 24.04 LTS (пример) |
| Web / TLS | **Caddy 2** (`/etc/caddy/Caddyfile`) |
| Приложение | **Node.js**, глобальный пакет **`openclaw`** (CLI + gateway) |
| Процесс шлюза | **systemd --user**: `openclaw-gateway.service` |
| Конфиг OpenClaw | `~/.openclaw/openclaw.json` |
| Рабочая область агента | `~/.openclaw/workspace/` |
| Логи gateway | обычно под `/tmp/openclaw/…` или путь из `openclaw gateway status` |

**Control UI** (встроенный портал OpenClaw): статика из пакета `dist/control-ui`, **Vite + Lit**; кастомизация «внутри» портала = **сборка из исходников OpenClaw** или отдельная страница за Caddy (часто проще для изолированных фич).

---

## 5. Ключевые пути на VPS

| Назначение | Путь |
|------------|------|
| Конфиг OpenClaw | `/home/shevbo/.openclaw/openclaw.json` |
| Workspace | `/home/shevbo/.openclaw/workspace/` |
| User unit шлюза | `/home/shevbo/.config/systemd/user/openclaw-gateway.service` |
| Обход гео/исходящий трафик (по желанию) | WireGuard: `/etc/wireguard/wg0.conf`, скрипт `scripts/wireguard-host-setup.sh`; после настройки peer — `wg-quick@wg0` |
| Caddy | `/etc/caddy/Caddyfile` |
| Бэкап Caddy до правок | искать `/etc/caddy/Caddyfile.bak*` (имя с timestamp) |
| Статическая «карта» workspace (пример) | `/var/www/openclaw-links/` + скрипт в `/home/shevbo/bin/gen-workspace-links.sh` |
| Инструкция отката страницы `/links` | `/home/shevbo/ROLLBACK-openclaw-workspace-links.txt` (если создавалась) |

---

## 6. Команды проверки (после изменений)

```bash
openclaw config validate
openclaw gateway status
systemctl --user status openclaw-gateway.service
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Перезапуск шлюза: `systemctl --user restart openclaw-gateway.service`.

---

## 7. Caddy: типичные приёмы

**Операционная документация (конфиг, прокси, откат, observer):** канон на шлюзе — **`/home/shevbo/.openclaw/Wiki/`** (например `Caddy.md`); в репозитории то же содержимое в **`scripts/wiki/`** — зеркало для Git.

Кратко: один серверный блок на `claw.shectory.ru` — сначала узкие маршруты, затем **`reverse_proxy localhost:18789`**; после правок **`caddy validate`** и **`systemctl reload caddy`**; откат из `Caddyfile.bak.*`.

Ссылки: [Caddyfile](https://caddyserver.com/docs/caddyfile), OpenClaw — [Control UI](https://docs.openclaw.ai/web/control-ui), [Gateway configuration](https://docs.openclaw.ai/gateway/configuration).

---

## 8. OpenClaw: что помнить агенту

- Аутентификация Control UI: токен/пароль, pairing устройств (`openclaw devices list` / `approve`).
- Ошибки «origin not allowed» → `gateway.controlUi.allowedOrigins` (полные `https://…` origins).
- Исходящий трафик с VPS (в т.ч. LLM): при необходимости — **WireGuard** на весь хост (`AllowedIPs = 0.0.0.0/0, ::/0`), не HTTP-прокси в unit OpenClaw.
- Встроенный UI **не всегда** имеет hook для произвольной кнопки без патча upstream; для быстрых UI-экспериментов часто выбирают **отдельную страницу за Caddy** (тот же домен, другой path) или **статический JS**, который ходит на **WebSocket/API шлюза** (если есть документированные RPC и CORS/Origin разрешены).

---

## 9. Безопасность

- Не коммитить и не логировать токены, ключи API, пароли прокси.
- Публичные URL со списком файлов workspace — осознанный риск; при необходимости — **basicauth** в Caddy или ограничение доступа.
- Правки `gateway.*` и открытый `bind: lan` требуют сильной аутентификации.

---

## 10. Репозиторий на машине разработчика (Cursor)

В workspace могут лежать копии скриптов, например:

- `scripts/gen-workspace-links.sh`
- `scripts/ROLLBACK-openclaw-workspace-links.txt`

Актуальная «истина» для прод — **файлы на сервере**; при расхождении синхронизировать осознанно.

---

## 11. Формат входного задания для агента (шаблон)

Владелец дополняет блок **«Задача»** своим ТЗ. Пример **только формулировки**, **не для выполнения из этого документа**:

> **Задача:** реализовать в связке Caddy + статика: создать нижний фрейм «Статус основной сессии», вывести JSON и дату последнего опроса субагента Auditor, добавить кнопку Refresh. Детали UX и источник данных уточнить по коду/конфигу на сервере.

Агент должен: уточнить, **откуда брать JSON** (файл, RPC OpenClaw, cron, отдельный сервис), как **не ломать** основной `reverse_proxy`, сохранить **откат**, проверить **HTTPS** и права на файлы.

---

## 12. Версионирование

Перед крупными правками: зафиксировать `openclaw --version`, версию пакета в `/usr/lib/node_modules/openclaw/package.json` (если релевантно) и сделать копию `Caddyfile`.

---

*Документ описывает типовую схему; конкретные IP, секреты и точные имена файлов бэкапов — уточнять у владельца окружения.*
