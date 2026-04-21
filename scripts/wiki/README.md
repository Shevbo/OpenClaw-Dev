# scripts/wiki — зеркало вики шлюза

Операционные **`.md`** здесь дублируют канон на прод-шлюзе:

**`/home/shevbo/.openclaw/Wiki/`**

Оглавление всех материалов (включая контексты из корня репо) — **`Wiki-INDEX.md`** на шлюзе.

Синхронизация из корня репозитория:

```bash
bash scripts/openclaw/sync-wiki-to-gateway.sh
bash scripts/openclaw/sync-wiki-from-gateway.sh
```
