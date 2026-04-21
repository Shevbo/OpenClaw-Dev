#!/usr/bin/env python3
"""Serve the web-voice-mvp folder over HTTP for local checks (stdlib only).

  python serve_mvp.py
  # open http://127.0.0.1:8765/  — localhost counts as a secure context for mic in Chromium.

For HTTPS on a public host use your reverse proxy (e.g. Caddy) and point root to this directory.

Voice STT/TTS API (Google): run `pip install -r requirements-voice-mvp.txt` then `python voice_backend.py`
(listens on 127.0.0.1:8091). Open index.html with `?api=http://127.0.0.1:8091` when static files are served here.
See ../Caddyfile.voice-mvp.snippet for production routing.
"""

from __future__ import annotations

import argparse
import http.server
import os
import socketserver
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parent
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8765)
    args = p.parse_args()
    os.chdir(root)

    handler = http.server.SimpleHTTPRequestHandler

    class Quiet(handler):  # type: ignore[misc, valid-type]
        def log_message(self, fmt: str, *a: object) -> None:
            pass

    with socketserver.TCPServer((args.host, args.port), Quiet) as httpd:
        print(f"Serving {root} at http://{args.host}:{args.port}/")
        print("Open index.html in the browser (default listing may show index.html).")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
