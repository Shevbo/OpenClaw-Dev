#!/usr/bin/env python3
"""
Политика «разработчик / полный доступ» для шлюза OpenClaw:

- Разрешает инструмент nodes в sandbox tool policy (alsoAllow).
- Убирает nodes / group:nodes из sandbox deny (deny побеждает allow).
- Если задан непустой tools.sandbox.tools.allow — добавляет nodes (иначе
  инструмент остаётся заблокированным).
- По умолчанию: agents.defaults.sandbox.mode = off и то же для каждого
  agents.list[] (иначе override с mode=all/non-main снова включает Docker-
  песочницу). В Docker-backend у контейнера по умолчанию нет сети
  (docker.network: none) — exec внутри sandbox не сможет открыть SSH;
  см. https://docs.openclaw.ai/gateway/sandboxing
- Опционально --docker-network bridge: исходящая сеть из sandbox-контейнера,
  если песочницу оставляете включённой (--no-gateway-sandbox-off).
- По умолчанию: tools.elevated.enabled = true (запасной выход exec при
  включённой песочнице; см. доку Elevated). Отключить: --no-elevated.
- По умолчанию: блок в workspace/AGENTS.md (подмешивается в контекст агента
  OpenClaw) с инструкцией сначала вызывать openclaw sandbox explain и
  пробовать nodes. Отключить: --no-inject-agents.

Запуск на хосте шлюза: python3 scripts/openclaw/patch-openclaw-dev-full-access.py
или с копией в ~/bin. После: openclaw config validate &&
  systemctl --user restart openclaw-gateway.service

Док: https://docs.openclaw.ai/gateway/sandbox-vs-tool-policy-vs-elevated
Изоляция без сети в Docker: https://docs.openclaw.ai/gateway/sandboxing
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

NODE_KEYS = frozenset({"nodes", "group:nodes"})

AGENTS_BEGIN = "<!-- OPENCLAW_AUTOGEN_DEV_ACCESS_BEGIN -->"
AGENTS_END = "<!-- OPENCLAW_AUTOGEN_DEV_ACCESS_END -->"
AGENTS_SNIPPET = f"""{AGENTS_BEGIN}

## Доступ шлюза (автодобавлено `patch-openclaw-dev-full-access.py`)

1. Если задача связана с **сетью, SSH или «изоляцией»**, **сначала выполни** `openclaw sandbox explain` для текущей сессии (по возможности с `--json`), чтобы увидеть, sandboxed ли сессия и какой backend/network.
2. Для действий на **paired remote node** (например Raspberry Pi): **сначала пробуй инструмент `nodes`** (выполнение на node), а не `exec` с SSH, пока explain не покажет выполнение на хосте шлюза.
3. По умолчанию Docker-sandbox **без исходящей сети** — SSH из `exec` внутри контейнера часто таймаутится; это ожидаемо (см. Sandboxing на docs.openclaw.ai). Для SSH с хоста нужен **host exec** (sandbox off) или `agents.defaults.sandbox.docker.network` (например bridge).
4. **`Permission denied (publickey,password)`** — это **не «починить Docker»**: `exec` **не может ввести пароль** SSH. Нужен **вход по ключу** на целевой хост. На шлюзе одноразово (человек или интерактивный shell): `scripts/ssh/shevbo-cloud-install-pi-key.sh user@pi-ip`, см. `scripts/wiki/SSH-shevbo-cloud-to-pi.md`. Проверка без пароля: `bash scripts/ssh/verify-shevbo-pi-ssh-batchmode.sh` (на VPS, из репозитория или `~/bin`).
5. Снос Docker-**sandbox** не добавит ключи в `~/.ssh` и не сделает парольным SSH рабочим из неинтерактивного `exec`.
6. После правок `openclaw.json` на шлюзе: `openclaw config validate`, `systemctl --user restart openclaw-gateway.service`; для node: `openclaw nodes status --connected`.

{AGENTS_END}
"""


def _workspace_dir(d: dict, cfg: Path) -> Path:
    agents = d.get("agents") if isinstance(d.get("agents"), dict) else {}
    defaults = agents.get("defaults") if isinstance(agents.get("defaults"), dict) else {}
    ws = defaults.get("workspace")
    if isinstance(ws, str) and ws.strip():
        p = Path(ws).expanduser()
        return p if p.is_absolute() else (cfg.resolve().parent / p).resolve()
    return (Path.home() / ".openclaw" / "workspace").resolve()


def _inject_workspace_agents_snippet(workspace: Path) -> None:
    workspace.mkdir(parents=True, exist_ok=True)
    agents_path = workspace / "AGENTS.md"
    text = agents_path.read_text(encoding="utf-8") if agents_path.is_file() else ""
    if AGENTS_BEGIN in text and AGENTS_END in text:
        pre, _, rest = text.partition(AGENTS_BEGIN)
        _, _, post = rest.partition(AGENTS_END)
        new_text = pre.rstrip() + "\n\n" + AGENTS_SNIPPET.strip() + "\n" + post.lstrip()
    else:
        sep = "\n\n" if text and not text.endswith("\n") else "\n"
        new_text = (text.rstrip() + sep + AGENTS_SNIPPET.strip() + "\n") if text.strip() else AGENTS_SNIPPET.strip() + "\n"
    if new_text != text:
        agents_path.write_text(new_text, encoding="utf-8")
        print("updated:", agents_path)
    else:
        print("no AGENTS.md snippet change:", agents_path)


def _ensure_elevated_enabled(d: dict) -> None:
    elev = d.setdefault("tools", {}).setdefault("elevated", {})
    elev["enabled"] = True


def _strip_nodes_from_deny(deny: object) -> tuple[list[str], bool]:
    if not isinstance(deny, list):
        return [], False
    out = [x for x in deny if isinstance(x, str) and x not in NODE_KEYS]
    return out, out != deny


def _ensure_nodes_in_allow(allow: object) -> tuple[list[str], bool]:
    if not isinstance(allow, list) or not allow:
        return list(allow) if isinstance(allow, list) else [], False
    al = list(allow)
    if "nodes" in al or "group:nodes" in al:
        return al, False
    al.append("nodes")
    return al, True


def _append_also_allow(cur: object) -> tuple[list[str], bool]:
    also = list(cur) if isinstance(cur, list) else []
    changed = False
    if "nodes" not in also:
        also.append("nodes")
        changed = True
    return also, changed


def _sandbox_dict(agent: dict) -> dict:
    sb = agent.get("sandbox")
    if not isinstance(sb, dict):
        sb = {}
        agent["sandbox"] = sb
    return sb


def _force_sandbox_mode_off(d: dict) -> None:
    agents = d.setdefault("agents", {})
    defaults = agents.setdefault("defaults", {})
    sb = defaults.setdefault("sandbox", {})
    sb["mode"] = "off"
    for agent in agents.get("list") or []:
        if not isinstance(agent, dict):
            continue
        _sandbox_dict(agent)["mode"] = "off"


def _apply_docker_sandbox_network(d: dict, network: str) -> None:
    agents = d.setdefault("agents", {})
    defaults = agents.setdefault("defaults", {})
    sb = defaults.setdefault("sandbox", {})
    docker = sb.setdefault("docker", {})
    docker["network"] = network
    for agent in agents.get("list") or []:
        if not isinstance(agent, dict):
            continue
        a_sb = _sandbox_dict(agent)
        dck = a_sb.setdefault("docker", {})
        if not isinstance(dck, dict):
            dck = {}
            a_sb["docker"] = dck
        dck["network"] = network


def apply(
    cfg: Path,
    *,
    gateway_sandbox_off: bool,
    docker_network: str | None,
    elevated: bool,
    inject_agents: bool,
) -> int:
    if not cfg.is_file():
        print("missing:", cfg, file=sys.stderr)
        return 1
    raw = cfg.read_text(encoding="utf-8")
    d = json.loads(raw)

    # --- global tools.deny (not sandbox-specific; deny wins) ---
    tools_root = d.setdefault("tools", {})
    deny_top, dt = _strip_nodes_from_deny(tools_root.get("deny"))
    if dt:
        tools_root["deny"] = deny_top

    # --- global tools.sandbox.tools ---
    ts = tools_root.setdefault("sandbox", {}).setdefault("tools", {})
    deny, dch = _strip_nodes_from_deny(ts.get("deny"))
    if dch:
        ts["deny"] = deny
    allow, ach = _ensure_nodes_in_allow(ts.get("allow"))
    if ach:
        ts["allow"] = allow
    also, och = _append_also_allow(ts.get("alsoAllow"))
    if och:
        ts["alsoAllow"] = also

    # --- per-agent ---
    for agent in d.get("agents", {}).get("list") or []:
        tools = agent.setdefault("tools", {})
        deny_agent, da = _strip_nodes_from_deny(tools.get("deny"))
        if da:
            tools["deny"] = deny_agent
        st = tools.setdefault("sandbox", {}).setdefault("tools", {})
        deny2, d2 = _strip_nodes_from_deny(st.get("deny"))
        if d2:
            st["deny"] = deny2
        allow2, a2 = _ensure_nodes_in_allow(st.get("allow"))
        if a2:
            st["allow"] = allow2
        also2, o2 = _append_also_allow(st.get("alsoAllow"))
        if o2:
            st["alsoAllow"] = also2

    if gateway_sandbox_off:
        _force_sandbox_mode_off(d)

    if docker_network:
        _apply_docker_sandbox_network(d, docker_network)

    if elevated:
        _ensure_elevated_enabled(d)

    new_text = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
    if new_text != raw:
        cfg.write_text(new_text, encoding="utf-8")
        print("updated:", cfg)
    else:
        print("no changes needed:", cfg)

    if inject_agents:
        _inject_workspace_agents_snippet(_workspace_dir(d, cfg))

    print(
        "Next on gateway: openclaw config validate && "
        "systemctl --user restart openclaw-gateway.service && "
        "openclaw sandbox explain",
    )
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--config",
        type=Path,
        default=Path.home() / ".openclaw" / "openclaw.json",
        help="Path to openclaw.json",
    )
    p.add_argument(
        "--no-gateway-sandbox-off",
        action="store_true",
        help="Do not force sandbox.mode off on defaults and agents.list (only fix nodes tool policy).",
    )
    p.add_argument(
        "--docker-network",
        metavar="NAME",
        default=None,
        help='Docker sandbox egress, e.g. "bridge". Default OpenClaw sandbox has no network; '
        "needed for ssh/curl from inside the container if sandbox stays on.",
    )
    p.add_argument(
        "--no-elevated",
        action="store_true",
        help="Do not set tools.elevated.enabled to true.",
    )
    p.add_argument(
        "--no-inject-agents",
        action="store_true",
        help="Do not update workspace AGENTS.md bootstrap snippet.",
    )
    args = p.parse_args()
    return apply(
        args.config,
        gateway_sandbox_off=not args.no_gateway_sandbox_off,
        docker_network=args.docker_network,
        elevated=not args.no_elevated,
        inject_agents=not args.no_inject_agents,
    )


if __name__ == "__main__":
    raise SystemExit(main())
