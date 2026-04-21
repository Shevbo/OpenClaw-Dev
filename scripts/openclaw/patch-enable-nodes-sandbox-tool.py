#!/usr/bin/env python3
"""
Совместимость: только политика sandbox для nodes (без agents.defaults.sandbox).

Полная настройка: patch-openclaw-dev-full-access.py (по умолчанию ещё и
sandbox.mode off на defaults агента).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    here = Path(__file__).resolve().parent
    script = here / "patch-openclaw-dev-full-access.py"
    cmd = [
        sys.executable,
        str(script),
        "--no-gateway-sandbox-off",
        "--no-inject-agents",
    ]
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
