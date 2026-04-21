#!/usr/bin/env python3
"""
Заполняет channels.telegram.proxy из HTTPS_PROXY в файле Proxy6 (как у шлюза),
чтобы загрузка голосов/медиа с api.telegram.org шла через тот же прокси.

Без этого часть путей может уйти в обход или без нужного undici-dispatcher →
«Failed to download media» на VPS с обязательным исходящим прокси.

По умолчанию: /etc/proxy6/environment.env и ~/.openclaw/openclaw.json
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


def read_https_proxy(env_path: Path) -> str | None:
    if not env_path.is_file():
        return None
    for line in env_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^HTTPS_PROXY=(.*)$", line)
        if not m:
            continue
        v = m.group(1).strip().strip('"').strip("'")
        return v or None
    return None


def main() -> int:
    env_path = Path(os.environ.get("PROXY6_ENV_FILE", "/etc/proxy6/environment.env"))
    cfg_path = Path.home() / ".openclaw" / "openclaw.json"
    proxy = read_https_proxy(env_path)
    if not proxy:
        print(f"skip: no HTTPS_PROXY in {env_path}", file=sys.stderr)
        return 1
    if not cfg_path.is_file():
        print(f"missing: {cfg_path}", file=sys.stderr)
        return 1
    data = json.loads(cfg_path.read_text(encoding="utf-8"))
    ch = data.setdefault("channels", {})
    tg = ch.setdefault("telegram", {})
    cur = tg.get("proxy")
    if cur == proxy:
        print("unchanged: channels.telegram.proxy already matches HTTPS_PROXY file")
        return 0
    tg["proxy"] = proxy
    cfg_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"updated {cfg_path}: channels.telegram.proxy set from {env_path} (value not printed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
