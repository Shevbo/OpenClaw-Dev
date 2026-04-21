#!/usr/bin/env python3
"""
HTTP API for web voice MVP: PCM (mono int16 LE) -> Google Speech-to-Text -> optional agent -> Google Text-to-Speech (MP3).

Env:
  GOOGLE_API_KEY or GEMINI_API_KEY — API key with Cloud Speech-to-Text and Cloud Text-to-Speech enabled.
  GOOGLE_TTS_VOICE — default ru-RU-Wavenet-D
  GOOGLE_STT_LANGUAGE — default ru-RU
  AGENT_URL — optional POST JSON {"message":"..."} -> {"reply":"..."} (or {"text":"..."}); else echo stub.
  VOICE_API_SECRET — if set, require header X-Voice-Api-Secret matching this value.

Bind defaults to 127.0.0.1:8091 for reverse_proxy behind Caddy.
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request
from typing import Any

from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Route


def _api_key() -> str | None:
    return (os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY") or "").strip() or None


def _decimate_48k_to_16k(pcm16: bytes) -> bytes:
    """Keep every 3rd int16 sample (48 kHz -> 16 kHz mono)."""
    n = len(pcm16) // 2
    out = bytearray((n // 3) * 2)
    j = 0
    for i in range(0, n, 3):
        out[j : j + 2] = pcm16[i * 2 : i * 2 + 2]
        j += 2
    return bytes(out)


def google_stt_recognize(
    key: str,
    pcm16_mono: bytes,
    sample_rate_hz: int,
    language_code: str,
) -> str:
    url = f"https://speech.googleapis.com/v1/speech:recognize?key={key}"
    body: dict[str, Any] = {
        "config": {
            "encoding": "LINEAR16",
            "sampleRateHertz": sample_rate_hz,
            "languageCode": language_code,
            "enableAutomaticPunctuation": True,
        },
        "audio": {"content": base64.b64encode(pcm16_mono).decode("ascii")},
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        out = json.loads(resp.read().decode("utf-8"))
    results = out.get("results") or []
    if not results:
        return ""
    alts = (results[0].get("alternatives") or [{}])[0]
    return (alts.get("transcript") or "").strip()


def google_tts_synthesize(key: str, text: str, voice_name: str) -> bytes:
    url = f"https://texttospeech.googleapis.com/v1/text:synthesize?key={key}"
    parts = voice_name.split("-")
    lang = f"{parts[0]}-{parts[1]}" if len(parts) >= 2 else "ru-RU"
    body: dict[str, Any] = {
        "input": {"text": text},
        "voice": {"languageCode": lang, "name": voice_name},
        "audioConfig": {"audioEncoding": "MP3", "speakingRate": 1.0},
    }

    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json; charset=utf-8")
    with urllib.request.urlopen(req, timeout=60) as resp:
        out = json.loads(resp.read().decode("utf-8"))
    b64 = out.get("audioContent")
    if not b64:
        return b""
    return base64.b64decode(b64)


def call_agent(agent_url: str, message: str) -> str:
    body = json.dumps({"message": message}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(agent_url, data=body, method="POST")
    req.add_header("Content-Type", "application/json; charset=utf-8")
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = resp.read().decode("utf-8")
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        return raw.strip()
    if isinstance(obj, dict):
        for k in ("reply", "text", "response", "content"):
            v = obj.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
    return raw.strip()


async def handle_turn(request: Request) -> Response:
    secret = (os.environ.get("VOICE_API_SECRET") or "").strip()
    if secret and request.headers.get("x-voice-api-secret") != secret:
        return JSONResponse({"error": "unauthorized"}, status_code=401)

    key = _api_key()
    if not key:
        return JSONResponse({"error": "GOOGLE_API_KEY or GEMINI_API_KEY not set"}, status_code=500)

    try:
        payload = await request.json()
    except Exception:
        return JSONResponse({"error": "invalid JSON"}, status_code=400)

    b64 = payload.get("pcm16_base64")
    if not b64 or not isinstance(b64, str):
        return JSONResponse({"error": "pcm16_base64 required"}, status_code=400)

    try:
        pcm = base64.b64decode(b64)
    except Exception:
        return JSONResponse({"error": "invalid base64"}, status_code=400)

    if len(pcm) < 3200:  # ~100 ms at 16 kHz
        return JSONResponse({"error": "audio too short"}, status_code=400)

    sr = int(payload.get("sampleRateHertz") or 16000)
    lang = (payload.get("languageCode") or os.environ.get("GOOGLE_STT_LANGUAGE") or "ru-RU").strip()
    voice = (os.environ.get("GOOGLE_TTS_VOICE") or "ru-RU-Wavenet-D").strip()

    if sr == 48000:
        pcm16 = _decimate_48k_to_16k(pcm)
        sr = 16000
    elif sr == 16000:
        pcm16 = pcm
    else:
        return JSONResponse({"error": "sampleRateHertz must be 16000 or 48000"}, status_code=400)

    if len(pcm16) % 2 != 0:
        return JSONResponse({"error": "pcm length must be even"}, status_code=400)

    try:
        transcript = google_stt_recognize(key, pcm16, sr, lang)
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        return JSONResponse({"error": "stt_failed", "detail": err}, status_code=502)

    agent_url = (os.environ.get("AGENT_URL") or "").strip()
    if agent_url and transcript:
        try:
            reply = call_agent(agent_url, transcript)
            if not (reply or "").strip():
                reply = f"Вы сказали: {transcript}"
        except Exception as e:
            return JSONResponse({"error": "agent_failed", "detail": str(e)}, status_code=502)
    else:
        if not transcript:
            reply = "Не расслышал. Удерживайте кнопку и говорите чуть дольше."
        else:
            reply = f"Вы сказали: {transcript}"

    try:
        mp3 = google_tts_synthesize(key, reply, voice)
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        return JSONResponse({"error": "tts_failed", "detail": err}, status_code=502)

    if not mp3:
        return JSONResponse({"error": "tts_empty"}, status_code=502)

    audio_b64 = base64.b64encode(mp3).decode("ascii")
    return JSONResponse(
        {
            "transcript": transcript,
            "reply": reply,
            "audioMp3Base64": audio_b64,
            "mime": "audio/mpeg",
        }
    )


async def health(_: Request) -> Response:
    return JSONResponse({"ok": True, "google_key": bool(_api_key())})


def build_app() -> Starlette:
    app = Starlette(
        routes=[
            Route("/api/voice/turn", handle_turn, methods=["POST"]),
            Route("/api/voice/health", health, methods=["GET"]),
        ],
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    return app


app = build_app()


def main() -> None:
    import uvicorn

    host = os.environ.get("VOICE_BIND_HOST", "127.0.0.1")
    port = int(os.environ.get("VOICE_BIND_PORT", "8091"))
    uvicorn.run(app, host=host, port=port, reload=False)


if __name__ == "__main__":
    main()
