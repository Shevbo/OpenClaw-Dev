# Индекс вики OpenClaw (шлюз shevbo-cloud)

**Каталог на шлюзе:** `/home/shevbo/.openclaw/Wiki/`  
**Пользователь:** `shevbo` · **SSH:** `shevbo-cloud`

Здесь собраны **все** операционные материалы и контексты: процедуры, handoff для агентов, Caddy, Pi, голос/Google, observer, troubleshooting.

| Файл | Назначение |
|------|------------|
| **AGENTS.md** | Инструкции агента Cursor: канон на шлюзе, синхронизация с репо |
| **CONTINUATION-CONTEXT.md** | Единый контекст продолжения работы (архитектура, сделано, хвосты, проверки) |
| **AGENT-CONTEXT-OpenClaw-Caddy-Developer.md** | Handoff для ИИ: OpenClaw + Caddy + VPS |
| **cursor-handoff-openclaw-shevbo-cloud.md** | Короткий handoff по шлюзу shevbo-cloud |
| **Caddy.md** | Reverse proxy, TLS, откат, Proxy6 |
| **OpenClaw-shevbo-google-only-voice.md** | Голос/STT/TTS только Google, модели, прокси, нагрузка |
| **SSH-shevbo-cloud-to-pi.md** | SSH между облаком и Pi |
| **OpenClaw-Pi-remote-node-WireGuard.md** | Pi как remote node, WireGuard |
| **OpenClaw-Pi-repair-rotate-and-secrets.md** | Ремонт пары, ротация токенов, секреты |
| **Wiki-Observer.md** | Observer: healthcheck, прокси, Telegram, таймер |
| **Wiki-OBSERVER-TROUBLESHOOTING-GUIDE.md** | Реестр сбоев, авто-fix, ingest |
| **README.md** | Пояснение зеркала `scripts/wiki/` ↔ эта вики |

**Синхронизация с репозиторием** (с dev-машины из корня репо):

```bash
bash scripts/openclaw/sync-wiki-to-gateway.sh      # репо → шлюз
bash scripts/openclaw/sync-wiki-from-gateway.sh    # шлюз → репо (после правок на VPS)
```

*Обновляйте этот индекс при добавлении новых файлов в Wiki.*
