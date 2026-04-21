# OpenClaw-Dev — инструкции для агента (workspace)

## Где живут документы и контексты (канон)

**Все** операционные материалы, handoff-контексты, вики и длинные описания для прод-OpenClaw ведём **на шлюзе** в каталоге:

**`/home/shevbo/.openclaw/Wiki/`**

(SSH: **`shevbo-cloud`**, пользователь **`shevbo`**. Полный список файлов — **`Wiki-INDEX.md`** в том же каталоге.)

### Состав вики (кратко)

| На шлюзе `Wiki/` | Смысл |
|-------------------|--------|
| `Wiki-INDEX.md` | Оглавление всех материалов |
| `CONTINUATION-CONTEXT.md` | Архитектура, сделано, хвосты, проверки |
| `AGENT-CONTEXT-OpenClaw-Caddy-Developer.md` | Handoff: OpenClaw + Caddy + VPS |
| `cursor-handoff-openclaw-shevbo-cloud.md` | Короткий handoff по шлюзу |
| `AGENTS.md` | Этот же файл (копия для агента на сервере) |
| `Caddy.md`, `OpenClaw-*.md`, `SSH-*.md` | Инфраструктура, голос, Pi, SSH |
| `Wiki-Observer.md` | Observer, healthcheck, Telegram |
| `Wiki-OBSERVER-TROUBLESHOOTING-GUIDE.md` | Реестр сбоев и авто-fix |

### Репозиторий Git

Каталог **`scripts/wiki/`** и корневые **`CONTINUATION-CONTEXT.md`**, **`AGENT-CONTEXT-*.md`**, **`cursor-handoff-*.md`** — **зеркало для истории в Git**. При расхождении **приоритет у файлов на шлюзе** (`~/.openclaw/Wiki/`).

### Синхронизация (из корня репо)

```bash
bash scripts/openclaw/sync-wiki-to-gateway.sh    # репо → шлюз (после правок локально)
bash scripts/openclaw/sync-wiki-from-gateway.sh  # шлюз → репо (после правок на VPS)
```

Не создавайте новые «источники правды» только в чате или в случайных `.md` вне вики — добавляйте файл в **`/home/shevbo/.openclaw/Wiki/`**, строку в **`Wiki-INDEX.md`**, затем синхронизируйте в репо и коммит.
