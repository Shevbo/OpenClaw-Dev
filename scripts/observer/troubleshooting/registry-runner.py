#!/usr/bin/env python3
"""
Читает registry.json, ищет совпадения паттернов в журнале user-unit шлюза,
при соблюдении cooldown запускает только скрипты из fixes/ рядом с registry.
Если совпадение есть и в тексте ingest (Telegram), перед fix отправляется короткое сообщение в Telegram.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def _patterns_match(patterns: list, text: str) -> bool:
    for raw in patterns:
        if not raw or not isinstance(raw, str):
            continue
        try:
            if re.search(raw, text, flags=re.IGNORECASE | re.DOTALL):
                return True
        except re.error as err:
            print(f"registry-runner: bad regex {raw!r}: {err}", file=sys.stderr)
    return False


def _load_telegram_credentials(path: Path) -> tuple[str, str] | None:
    if not path.is_file():
        return None
    token: str | None = None
    chat: str | None = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip().strip('"').strip("'")
        if k == "TELEGRAM_BOT_TOKEN":
            token = v
        elif k == "TELEGRAM_CHAT_ID":
            chat = v
    if token and chat:
        return (token, chat)
    return None


def _telegram_send_text(text: str) -> None:
    env_path = Path(
        os.environ.get("OBSERVER_TELEGRAM_ENV", Path.home() / ".config/openclaw/observer/telegram.env")
    ).expanduser()
    cred = _load_telegram_credentials(env_path)
    if not cred:
        print("registry-runner: telegram ack skip (no credentials file or vars)", file=sys.stderr)
        return
    token, chat_id = cred
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    body = urllib.parse.urlencode(
        {"chat_id": chat_id, "text": text, "disable_web_page_preview": "true"}
    ).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    if proxy:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({"https": proxy, "http": proxy}))
    else:
        opener = urllib.request.build_opener()
    try:
        with opener.open(req, timeout=45) as resp:
            resp.read()
        print("registry-runner: telegram ingest-ack sent")
    except (urllib.error.URLError, OSError) as e:
        print(f"registry-runner: telegram send failed: {e}", file=sys.stderr)


def _notify_ingest_case_ack(case_id: str) -> None:
    msg = (
        f"Касательно этого кейса ({case_id}): я (observer) попробую решить сам — вернусь с обратной связью."
    )
    _telegram_send_text(msg)


def main() -> int:
    base = Path(os.environ.get("OBSERVER_TROUBLESHOOTING_DIR", "")).expanduser()
    if not base or not base.is_dir():
        print("registry-runner: OBSERVER_TROUBLESHOOTING_DIR not set or missing", file=sys.stderr)
        return 0

    registry_path = base / "registry.json"
    fixes_dir = base / "fixes"
    state_dir = Path(os.environ.get("OBSERVER_STATE_DIR", Path.home() / ".cache/openclaw-observer")).expanduser()
    gateway_unit = os.environ.get("OBSERVER_GATEWAY_UNIT", "openclaw-gateway.service")
    since = os.environ.get("OBSERVER_REGISTRY_JOURNAL_SINCE", "25 min ago")

    if not registry_path.is_file():
        print(f"registry-runner: no {registry_path}", file=sys.stderr)
        return 0

    try:
        data = json.loads(registry_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"registry-runner: invalid JSON: {e}", file=sys.stderr)
        return 1

    entries = data.get("entries") or []
    if not entries:
        return 0

    try:
        log = subprocess.run(
            ["journalctl", "--user", "-u", gateway_unit, "--since", since, "--no-pager"],
            capture_output=True,
            text=True,
            timeout=120,
        )
        journal_only = (log.stdout or "") + (log.stderr or "")
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        print(f"registry-runner: journalctl failed: {e}", file=sys.stderr)
        journal_only = ""

    ingest_sections: list[str] = []
    ingest = base / "ingest.txt"
    if ingest.is_file():
        try:
            chunk = ingest.read_text(encoding="utf-8", errors="replace")
            ingest_sections.append("--- ingest.txt (Telegram/ручной текст) ---\n" + chunk[-200000:])
        except OSError as e:
            print(f"registry-runner: ingest read failed: {e}", file=sys.stderr)

    ingest_d = base / "ingest.d"
    if ingest_d.is_dir():
        for p in sorted(ingest_d.glob("*.txt")):
            try:
                chunk = p.read_text(encoding="utf-8", errors="replace")
                tail = chunk[-80000:] if len(chunk) > 80000 else chunk
                ingest_sections.append(f"--- ingest.d/{p.name} ---\n{tail}")
            except OSError as e:
                print(f"registry-runner: ingest.d read failed {p}: {e}", file=sys.stderr)

    ingest_blob = "\n".join(ingest_sections)
    journal_text = journal_only + ("\n" + ingest_blob if ingest_blob.strip() else "")

    state_dir.mkdir(parents=True, exist_ok=True)

    for ent in entries:
        eid = ent.get("id")
        if not eid or not isinstance(eid, str):
            continue
        patterns = ent.get("journal_patterns") or []
        fix_name = ent.get("fix")
        cooldown = int(ent.get("cooldown_sec") or 3600)
        if not fix_name or not isinstance(fix_name, str):
            continue

        if not _safe_fix_name(fix_name):
            print(f"registry-runner: skip unsafe fix name: {fix_name}", file=sys.stderr)
            continue

        script = (fixes_dir / fix_name).resolve()
        try:
            script.relative_to(fixes_dir.resolve())
        except ValueError:
            print(f"registry-runner: skip path escape: {script}", file=sys.stderr)
            continue

        if not script.is_file():
            print(f"registry-runner: missing script {script}", file=sys.stderr)
            continue

        if not _patterns_match(patterns, journal_text):
            continue

        stamp_path = state_dir / f"tr_registry_{eid}_last"
        now = time.time()
        if stamp_path.is_file():
            try:
                last = float(stamp_path.read_text().strip())
            except ValueError:
                last = 0.0
            if now - last < cooldown:
                print(f"registry-runner: cooldown {eid} ({int(now - last)}s < {cooldown}s)")
                continue

        matched_ingest = bool(ingest_blob.strip()) and _patterns_match(patterns, ingest_blob)
        if matched_ingest:
            _notify_ingest_case_ack(eid)

        print(f"registry-runner: MATCH {eid} -> {fix_name}")
        env = os.environ.copy()
        env.setdefault("OBSERVER_GATEWAY_UNIT", gateway_unit)
        try:
            r = subprocess.run(
                ["/bin/bash", str(script)],
                env=env,
                capture_output=True,
                text=True,
                timeout=600,
            )
            out = (r.stdout or "") + (r.stderr or "")
            print(out[-8000:] if len(out) > 8000 else out)
            if r.returncode == 0:
                stamp_path.write_text(str(now), encoding="utf-8")
                print(f"registry-runner: OK {eid} exit=0")
            else:
                print(f"registry-runner: FAIL {eid} exit={r.returncode}", file=sys.stderr)
        except subprocess.TimeoutExpired:
            print(f"registry-runner: TIMEOUT {eid}", file=sys.stderr)

    return 0


def _safe_fix_name(name: str) -> bool:
    if not name.endswith(".sh"):
        return False
    if "/" in name or "\\" in name or name.startswith("."):
        return False
    return bool(re.match(r"^[a-zA-Z0-9][a-zA-Z0-9_.-]+\.sh$", name))


if __name__ == "__main__":
    raise SystemExit(main())
