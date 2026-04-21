#!/usr/bin/env python3
"""
Telegram + голос: согласованная схема (координация, не замена шлюза OpenClaw).

Достижимость (важно)
--------------------
1) «Звонить реальным людям через Telegram» в буквальном смысле (PSTN из приложения
   Telegram или нативный Telegram-звонок от имени бота) — **недостижимо** через
   стандартный Bot API: бот не может инициировать телефонный звонок абоненту и не
   имеет доступа к VoIP Telegram как мессенджер для пользователей.

2) Достижимая модель:
   - **Telegram** — идентификация пользователя, согласие, уведомления, кнопка
     «Открыть голосовую сессию» (HTTPS) или «Ожидайте звонок на +…».
   - **PSTN** — исходящий/входящий звонок на **номер телефона** через Twilio
     (или Telnyx/Plivo/Voice plugin OpenClaw), параллельно с сообщением в Telegram.
   - **Интерактивный голос без voice messages** — **браузер** (страница
     voice-session-shell.html) + микрофон + WebSocket/WebRTC к **медиа-конечной
     точке шлюза** (настраивается в продукте OpenClaw Voice), не цикл
     sendVoice в Telegram.

Этот скрипт реализует только **тонкий координационный слой** (HTTP к Telegram и
опционально Twilio). Медиа-пайплайн STT/TTS и логика агента остаются в OpenClaw.

Примеры
-------
  export TELEGRAM_BOT_TOKEN=...
  python3 telegram_voice_bridge.py invite-web-voice --chat-id 123 \
    --session-url 'https://claw.example/voice-session-shell.html?voice_ws=wss%3A%2F%2F...'

  python3 telegram_voice_bridge.py pstn-notify-and-call --chat-id 123 --to +79001234567 \
    --twiml-say-ru 'Вам звонит ассистент OpenClaw, оставайтесь на линии.'
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


def _env(name: str, default: str | None = None) -> str | None:
    v = os.environ.get(name)
    if v is None or v.strip() == "":
        return default
    return v


def telegram_send_message(
    token: str,
    chat_id: int | str,
    text: str,
    reply_markup: dict[str, Any] | None = None,
) -> dict[str, Any]:
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
    }
    if reply_markup is not None:
        payload["reply_markup"] = json.dumps(reply_markup, ensure_ascii=False)
    data = urllib.parse.urlencode(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=45) as resp:
        body = resp.read().decode("utf-8")
    out = json.loads(body)
    if not out.get("ok"):
        raise RuntimeError(f"Telegram API error: {out}")
    return out


def twilio_create_call(
    account_sid: str,
    auth_token: str,
    to_e164: str,
    from_e164: str,
    twiml: str,
) -> dict[str, Any]:
    """POST /2010-04-01/Accounts/{Sid}/Calls.json — минимальный исходящий звонок."""
    url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Calls.json"
    form = {
        "To": to_e164,
        "From": from_e164,
        "Twiml": twiml,
    }
    data = urllib.parse.urlencode(form).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    basic = base64.b64encode(f"{account_sid}:{auth_token}".encode()).decode()
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=45) as resp:
        body = resp.read().decode("utf-8")
    return json.loads(body)


def cmd_invite_web_voice(args: argparse.Namespace) -> int:
    token = args.token or _env("TELEGRAM_BOT_TOKEN")
    if not token:
        print("TELEGRAM_BOT_TOKEN or --token required", file=sys.stderr)
        return 2
    chat_id = args.chat_id or _env("TELEGRAM_CHAT_ID")
    if not chat_id:
        print("--chat-id or TELEGRAM_CHAT_ID required", file=sys.stderr)
        return 2
    session_url = args.session_url
    if not session_url:
        base = _env("VOICE_SESSION_PUBLIC_BASE")
        if not base:
            print("--session-url or VOICE_SESSION_PUBLIC_BASE required", file=sys.stderr)
            return 2
        session_url = base.rstrip("/") + "/voice-session-shell.html"

    markup = {
        "inline_keyboard": [
            [{"text": args.button_label, "url": session_url}],
        ]
    }
    text = (
        args.message
        or "Голосовой диалог с агентом (браузер, не голосовые в Telegram).\n"
        "Нажмите кнопку — откроется страница с микрофоном и WebSocket к шлюзу."
    )
    telegram_send_message(token, chat_id, text, reply_markup=markup)
    print("ok: invite sent")
    return 0


def cmd_pstn_notify_and_call(args: argparse.Namespace) -> int:
    token = args.token or _env("TELEGRAM_BOT_TOKEN")
    chat_id = args.chat_id or _env("TELEGRAM_CHAT_ID")
    sid = args.account_sid or _env("TWILIO_ACCOUNT_SID")
    auth = args.auth_token or _env("TWILIO_AUTH_TOKEN")
    from_num = args.from_number or _env("TWILIO_FROM_NUMBER")
    if not token or not chat_id:
        print("Telegram: TELEGRAM_BOT_TOKEN and --chat-id (or TELEGRAM_CHAT_ID)", file=sys.stderr)
        return 2
    if not sid or not auth or not from_num:
        print("Twilio: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER", file=sys.stderr)
        return 2

    say = html.escape(args.twiml_say_ru, quote=True)
    twiml = f'<?xml version="1.0" encoding="UTF-8"?><Response><Say language="ru-RU">{say}</Say></Response>'

    pre = (
        args.notify_text
        or f"Сейчас поступит телефонный звонок на номер {args.to} (не через Telegram). "
        "Если не хотите звонков, ответьте /stop_calls в боте (обработчик нужно добавить в вашего бота)."
    )
    telegram_send_message(token, chat_id, pre)

    try:
        call = twilio_create_call(sid, auth, args.to, from_num, twiml)
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        print(f"Twilio HTTP {e.code}: {err}", file=sys.stderr)
        telegram_send_message(
            token,
            chat_id,
            "Не удалось начать звонок (ошибка Twilio). Проверьте гео-разрешения и номер отправителя.",
        )
        return 1
    call_sid = call.get("sid", "?")
    telegram_send_message(
        token,
        chat_id,
        f"Звонок поставлен в очередь, Call SID: {call_sid}.",
    )
    print(json.dumps(call, indent=2))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        description="Telegram + PSTN + web voice coordination layer for OpenClaw (ASCII)",
    )
    p.add_argument("--token", help="Telegram bot token (or TELEGRAM_BOT_TOKEN)")

    sub = p.add_subparsers(dest="cmd", required=True)

    p_inv = sub.add_parser("invite-web-voice", help="Send Telegram button opening HTTPS voice shell page")
    p_inv.add_argument("--chat-id", help="Telegram chat_id (or TELEGRAM_CHAT_ID)")
    p_inv.add_argument(
        "--session-url",
        help="Full HTTPS URL to voice-session-shell.html (or VOICE_SESSION_PUBLIC_BASE + default path)",
    )
    p_inv.add_argument("--button-label", default="Голос с агентом (браузер)")
    p_inv.add_argument("--message", default=None, help="Override invite text")

    p_call = sub.add_parser(
        "pstn-notify-and-call",
        help="Notify in Telegram, then place outbound PSTN via Twilio (not via Telegram)",
    )
    p_call.add_argument("--chat-id")
    p_call.add_argument("--to", required=True, help="Destination E.164, e.g. +79001234567")
    p_call.add_argument("--account-sid", default=None)
    p_call.add_argument("--auth-token", default=None)
    p_call.add_argument("--from-number", default=None)
    p_call.add_argument(
        "--twiml-say-ru",
        default="Здравствуйте, это голосовой канал OpenClaw.",
        help="Short phrase for Twilio <Say> (XML-escaped internally for basic chars)",
    )
    p_call.add_argument("--notify-text", default=None)

    args = p.parse_args()
    if args.cmd == "invite-web-voice":
        return cmd_invite_web_voice(args)
    if args.cmd == "pstn-notify-and-call":
        return cmd_pstn_notify_and_call(args)
    raise AssertionError(args.cmd)


if __name__ == "__main__":
    sys.exit(main())
