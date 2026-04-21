#!/usr/bin/env python3
"""
Смягчение пиков нагрузки на шлюзе OpenClaw (shevbo-cloud и аналоги).

Проблема (типично при «интенсиве»): хвост хода агента обрывается с текстом вроде
«Agent couldn't generate a response. Note: some tool actions may have already
been executed» — это incomplete turn в pi-embedded-runner: уже отработали
мутационные инструменты (в т.ч. message / tts), а финальный ответ модели пустой,
ошибочный или оборван по таймауту/429/503. Это не отдельный «mutex TTS» в
конфиге: OpenClaw сериализует TTS по цепочке провайдеров (google → …), но
не ставит глобальную очередь на все параллельные сессии и не переключает
модель Gemini TTS внутри одного провайдера при rate limit автоматически.

Что делает патч (идемпотентно, только если значения слабее порога):
  - cron.maxConcurrentRuns = 1  — не запускать несколько cron agentTurn подряд.
  - tools.media.concurrency = 1 — меньше параллельного media understanding на ход.
  - messages.queue.debounceMsByChannel.telegram >= 400 — слегка сгладить всплески
    входящих в Telegram перед постановкой в очередь.

Дальше: openclaw config validate && systemctl --user restart openclaw-gateway.service
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

MIN_TELEGRAM_QUEUE_DEBOUNCE_MS = 400
CRON_MAX_CONCURRENT = 1
MEDIA_CONCURRENCY = 1


def main() -> int:
    cfg = Path.home() / ".openclaw" / "openclaw.json"
    d = json.loads(cfg.read_text(encoding="utf-8"))

    cron = d.setdefault("cron", {})
    cur_cron = cron.get("maxConcurrentRuns")
    if not isinstance(cur_cron, int) or cur_cron > CRON_MAX_CONCURRENT:
        cron["maxConcurrentRuns"] = CRON_MAX_CONCURRENT

    media = d.setdefault("tools", {}).setdefault("media", {})
    cur_m = media.get("concurrency")
    if not isinstance(cur_m, int) or cur_m > MEDIA_CONCURRENCY:
        media["concurrency"] = MEDIA_CONCURRENCY

    q = d.setdefault("messages", {}).setdefault("queue", {})
    dbc = q.setdefault("debounceMsByChannel", {})
    tg = dbc.get("telegram")
    if not isinstance(tg, int) or tg < MIN_TELEGRAM_QUEUE_DEBOUNCE_MS:
        dbc["telegram"] = MIN_TELEGRAM_QUEUE_DEBOUNCE_MS

    cfg.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("updated:", cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
