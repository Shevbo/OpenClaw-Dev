#!/usr/bin/env python3
"""
Убирает из agents.list[].tools.alsoAllow записи, которые шлюз OpenClaw
помечает как «unknown / unavailable» при runtime Google + direct (sandbox off):
gateway, cron, apply_patch и т.д. — см. журнал [tools] allowlist contains unknown entries.

Запись «nodes» намеренно не удаляем: иначе ломается доступ агента к paired
node (Pi); см. patch-openclaw-dev-full-access.py.

Запускать на хосте шлюза под пользователем с конфигом ~/.openclaw/openclaw.json
После: openclaw config validate && systemctl --user restart openclaw-gateway.service
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Совпадает с типичными предупреждениями gateway для google + embedded/direct.
REMOVE_FOR_GOOGLE_DIRECT = frozenset(
    {
        "gateway",
        "message",
        "web_search",
        "code_execution",
        "apply_patch",
        "x_search",
        "cron",
        "update_plan",
    }
)

cfg = Path.home() / ".openclaw" / "openclaw.json"
if not cfg.is_file():
    print("missing:", cfg, file=sys.stderr)
    sys.exit(1)

d = json.loads(cfg.read_text(encoding="utf-8"))
changed = False
for agent in d.get("agents", {}).get("list") or []:
    tools = agent.get("tools")
    if not isinstance(tools, dict):
        continue
    al = tools.get("alsoAllow")
    if not isinstance(al, list):
        continue
    new_al = [x for x in al if isinstance(x, str) and x not in REMOVE_FOR_GOOGLE_DIRECT]
    if new_al != al:
        removed = sorted(set(al) - set(new_al))
        print(f"agent {agent.get('id')!r}: removed from alsoAllow: {removed}")
        tools["alsoAllow"] = new_al
        changed = True

if not changed:
    print("no changes (nothing to remove or alsoAllow missing)")
else:
    cfg.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("updated:", cfg)

sys.exit(0)
