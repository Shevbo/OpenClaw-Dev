# Shevbo-cloud: голос и медиа — только Google (строгое требование)

**Политика (обязательная):** на **shevbo-cloud** не используется OpenAI для распознавания входящих голосовых и не задаётся резервная транскрипция через OpenAI. **STT** и **TTS** идут через провайдера **`google`** (Gemini API, тот же ключ/профиль, что и для чата).

**Термины:** голосовые от пользователя = **STT** (`tools.media.audio`). Озвучка ответа бота = **TTS** (`messages.tts`). Ответы в чате = **LLM** (`agents.defaults.model`, `agents.list[].model`).

---

## Модели (актуальные идентификаторы API)

| Роль | Поле конфига | Значение (пример для production) |
|------|----------------|----------------------------------|
| **Текст (основной LLM)** | `agents.defaults.model.primary`, агент `main` | `google/gemini-3.1-flash-lite-preview` |
| **Текст (запасной LLM)** | `agents.defaults.model.fallbacks[0]` | `google/gemini-2.5-flash-lite` (**GA**, не preview) |
| **STT (цепочка)** | `tools.media.audio.models[]` | 1) `gemini-3.1-flash-lite-preview` → 2) `gemini-2.5-flash-lite` |
| **TTS** | `messages.tts.providers.google.model` | например `gemini-3.1-flash-tts-preview` или `gemini-2.5-flash-preview-tts` |

**Allowlist:** ключи в **`agents.defaults.models`** должны включать все **`google/…`** модели, которые реально используются (primary, fallbacks, TTS-профили при необходимости), иначе сессии или инструменты могут не сопоставить модель.

**Устарело (не использовать):** `gemini-2.5-flash-lite-preview-09-2025` — снята с API (в changelog Gemini указано shut down / замена; вызов `generateContent` даёт **404 NOT_FOUND**). Запасной **Flash Lite 2.5** — только **`gemini-2.5-flash-lite`**.

---

## TTS и стабильность ответа

Пакет OpenClaw парсит ответ Google TTS на **PCM в `inlineData`** (`extensions/google/speech-provider.js`). **Preview 3.1 TTS** иногда отдаёт формат, с которым парсер не совпадает → ошибка вроде *«Google TTS response missing audio data»*; тогда временно ставят **`gemini-2.5-flash-preview-tts`**.

**Без Microsoft / Bing:** плагин **`microsoft`** регистрирует fallback TTS на `speech.platform.bing.com`. Для политики «только Google / только прокси» задайте **`plugins.entries.microsoft`**: **`"enabled": false`**.

---

## Прокси, Telegram и шлюз

- Исходящий трафик шлюза (LLM и т.д.) — через **`HTTP(S)_PROXY`** из unit / Proxy6.
- **`channels.telegram.proxy`** должен быть согласован с тем же прокси, иначе на VPS с обязательным прокси возможны **«Failed to download media»** при голосовых. Скрипт: **`scripts/openclaw/sync-telegram-proxy-from-proxy6-env.py`**.
- Обёртка **`scripts/openclaw/openclaw-gateway-via-docker-group.sh`**: после `source` файлов Proxy6 принудительно **`NO_PROXY=no_proxy=127.0.0.1,localhost,::1`**, чтобы широкий `NO_PROXY` из шаблона Proxy6 не отправлял облачные API в direct и не ломал egress / политику fetch.

---

## Cron и квота

Фоновые **`openclaw cron`** с **`agentTurn`** по умолчанию наследуют primary LLM. Если primary — узкоквотные или дорогие модели, джобы конкурируют с чатом. Для healthcheck/billing задаётся **`openclaw cron edit <id> --model google/gemini-2.5-flash-lite`**, чтобы не съедать лимиты основного чата.

---

## Секреты

Ключ Google: `GEMINI_API_KEY` / `GOOGLE_API_KEY` или файл, на который ссылается **`secrets.providers.google`** / профиль **`google:default`**.

**Не путать:** профиль **`openai-codex:*`** (OAuth Codex/ACP) — отдельно от голоса.

---

## Применение на сервере

1. Скрипт **`scripts/openclaw/patch-tools-media-audio-google-only.py`** (на хосте: `python3 …` из каталога со скриптом или с копией в `~/bin`).
2. **`openclaw config validate`**
3. **`systemctl --user restart openclaw-gateway.service`**

Обёртку шлюза с `sg docker` деплоить в **`~/bin/`** (или путь из unit) и перезапускать unit.

**Ссылки:** [Google (Gemini) в OpenClaw](https://docs.openclaw.ai/providers/google), [Audio / Voice Notes](https://docs.openclaw.ai/nodes/audio), [changelog моделей Gemini](https://ai.google.dev/gemini-api/docs/changelog).
