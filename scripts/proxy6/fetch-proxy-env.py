#!/usr/bin/env python3
"""Proxy6 getproxy → ~/.config/proxy6/proxy.env и proxy.systemd.env. Ключ: PROXY6_API_KEY, api_key или proxy6.json."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen

API_BASE = "https://px6.link/api"
# Не читаем ~/.openclaw/my_secrets.json — только отдельные пути ниже или PROXY6_API_KEY.
KEY_FILE = Path.home() / ".config" / "proxy6" / "api_key"
LEGACY_JSON = (
    Path.home() / ".config" / "proxy6" / "proxy6.json",
    Path.home() / "proxy6.json",
)
OUT_FILE = Path.home() / ".config" / "proxy6" / "proxy.env"
# systemd EnvironmentFile и environment.d: KEY=value без export
SYSTEMD_ENV = Path.home() / ".config" / "proxy6" / "proxy.systemd.env"
ENVIRONMENT_D = Path.home() / ".config/environment.d/99-openclaw-proxy.conf"


def _load_api_key_from_json(path: Path) -> str:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        return ""
    inner = raw.get("proxy6")
    if isinstance(inner, dict) and inner.get("api_key"):
        return str(inner["api_key"]).strip()
    if raw.get("api_key"):
        return str(raw["api_key"]).strip()
    return ""


def resolve_api_key() -> str:
    k = os.environ.get("PROXY6_API_KEY", "").strip()
    if k:
        return k
    if KEY_FILE.is_file():
        return KEY_FILE.read_text(encoding="utf-8").strip()
    extra = os.environ.get("PROXY6_JSON", "").strip()
    if extra:
        p = Path(extra).expanduser()
        if p.is_file():
            return _load_api_key_from_json(p)
    for p in LEGACY_JSON:
        if p.is_file():
            try:
                return _load_api_key_from_json(p)
            except (OSError, json.JSONDecodeError, ValueError):
                continue
    return ""


def main() -> int:
    key = resolve_api_key()
    if not key:
        print(
            "Нет ключа Proxy6: PROXY6_API_KEY, ~/.config/proxy6/api_key или JSON (proxy6.json)",
            file=sys.stderr,
        )
        return 1

    url = f"{API_BASE}/{key}/getproxy?state=active"
    with urlopen(url, timeout=60) as r:
        data = json.load(r)

    if data.get("status") != "yes":
        print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1

    lst = data.get("list") or {}
    if not lst:
        print("Список прокси пуст.", file=sys.stderr)
        return 1

    proxies = list(lst.values())
    us = [p for p in proxies if str(p.get("country", "")).lower() == "us"]
    pick = us[0] if us else proxies[0]

    host = pick["host"]
    port = pick["port"]
    user = pick["user"]
    pw = pick["pass"]

    uq = quote(str(user), safe="")
    pq = quote(str(pw), safe="")
    base = f"http://{uq}:{pq}@{host}:{port}"

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    # SSH не использует HTTP_PROXY. claw / shectory — без прокси (прямой доступ).
    no_proxy = (
        "127.0.0.1,localhost,::1,"
        "claw.shectory.ru,shectory.ru,.shectory.ru,"
        "192.144.14.187"
    )
    lines = [
        f"export HTTPS_PROXY={base!r}",
        f"export HTTP_PROXY={base!r}",
        f"export ALL_PROXY={base!r}",
        f"export NO_PROXY={no_proxy!r}",
        "",
    ]
    OUT_FILE.write_text("\n".join(lines), encoding="utf-8")
    # systemd EnvironmentFile: без префикса export, одна строка = одна переменная
    sys_lines = [
        f"HTTPS_PROXY={base}",
        f"HTTP_PROXY={base}",
        f"ALL_PROXY={base}",
        f"NO_PROXY={no_proxy}",
        "",
    ]
    systemd_body = "\n".join(sys_lines)
    SYSTEMD_ENV.write_text(systemd_body, encoding="utf-8")
    ENVIRONMENT_D.parent.mkdir(parents=True, exist_ok=True)
    ENVIRONMENT_D.write_text(systemd_body, encoding="utf-8")
    try:
        OUT_FILE.chmod(0o600)
        SYSTEMD_ENV.chmod(0o600)
        ENVIRONMENT_D.chmod(0o600)
    except OSError:
        pass

    print(f"OK {OUT_FILE} {SYSTEMD_ENV} {host}:{port} {pick.get('country')}")

    sync = Path("/usr/local/sbin/sync-proxy6-system-env.sh")
    if sync.is_file() and os.geteuid() != 0:
        r = subprocess.run(
            ["sudo", "-n", str(sync)],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0 and r.stderr:
            print(r.stderr, file=sys.stderr, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
