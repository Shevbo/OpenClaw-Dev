# Shevbo-cloud: голос и медиа — только Google (строгое требование)

**Политика (обязательная):** для OpenClaw на **shevbo-cloud** не используется OpenAI для распознавания входящих голосовых и не задаётся резервная транскрипция через OpenAI. Входящий аудио-текст (STT / media audio) идёт через провайдера **`google`** (Gemini API, тот же ключ, что и для Gemini).

**Термины:** «голосовые» от пользователя = **STT** (речь→текст), настраивается в **`tools.media.audio`**. Озвучка ответов ботом = **TTS** (текст→речь), настраивается в **`messages.tts`**. Оба направления — **только Google (Gemini)**, без OpenAI.

**Текст-в-речь (TTS)** для ответов в чатах задаётся через **`messages.tts`** с провайдером **`google`** (Gemini TTS), не через OpenAI.

**Секреты:** ключ Google — `GEMINI_API_KEY` / `GOOGLE_API_KEY` или файл секретов, на который ссылается `secrets.providers.google` / профиль `google:default`.

**Конфигурация (фрагмент):**

- `tools.media.audio.enabled`: `true`
- `tools.media.audio.models`: только записи с `"provider": "google"` (например модель `gemini-2.5-flash` и `"profile": "google:default"`).

**Не путать:** профиль **`openai-codex:*`** (OAuth для ACP/Codex) — отдельная интеграция; отключение «OpenAI для голоса» не требует удалять Codex, если он используется.

**Применение правок на сервере:** скрипт репозитория `scripts/openclaw/patch-tools-media-audio-google-only.py` (копировать на хост и выполнить `python3 …`), затем `openclaw config validate` и `systemctl --user restart openclaw-gateway.service`.

**Официальные ссылки:** [Google (Gemini)](https://docs.openclaw.ai/providers/google), [Audio / Voice Notes](https://docs.openclaw.ai/nodes/audio).
