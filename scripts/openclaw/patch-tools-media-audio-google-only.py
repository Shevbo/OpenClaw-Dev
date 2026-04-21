#!/usr/bin/env python3
"""Google-only inbound audio (STT). Removes OpenAI from audio + openai plugin + openai:default profile."""
import json
import sys
from pathlib import Path

cfg = Path.home() / ".openclaw" / "openclaw.json"
d = json.loads(cfg.read_text(encoding="utf-8"))

tools = d.setdefault("tools", {})
media = tools.setdefault("media", {})
media["audio"] = {
    "enabled": True,
    "models": [
        {
            "provider": "google",
            "model": "gemini-2.5-flash",
            "profile": "google:default",
        }
    ],
}

plugins = d.get("plugins") or {}
entries = plugins.get("entries") or {}
if "openai" in entries:
    del entries["openai"]
    plugins["entries"] = entries
    d["plugins"] = plugins

auth = d.get("auth") or {}
profiles = auth.get("profiles") or {}
if "openai:default" in profiles:
    del profiles["openai:default"]
    auth["profiles"] = profiles
    d["auth"] = auth

cfg.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("updated:", cfg)
sys.exit(0)
