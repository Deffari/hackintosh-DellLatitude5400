#!/usr/bin/env python3
"""MCP smoke test for OpenHands.

Performs a real JSON-RPC handshake (initialize -> notifications/initialized ->
tools/list) over stdio against every server declared in ~/.openhands/mcp.json.

Exit code 0 = all servers healthy, 1 = at least one failure.
Usage:  python3 mcp_smoke.py [--config PATH]
"""
import argparse
import json
import os
import subprocess
import sys
import time


def rpc(proc, payload, timeout=30):
    proc.stdin.write(json.dumps(payload) + "\n")
    proc.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = proc.stdout.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == payload.get("id"):
            return msg
    return None


def check(name, spec):
    env = dict(os.environ)
    env.update(spec.get("env") or {})
    cmd = [spec["command"], *(spec.get("args") or [])]
    try:
        proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=env, bufsize=1,
        )
    except FileNotFoundError as exc:
        return f"FAIL  {name}: command not found ({exc})"

    try:
        init = rpc(proc, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "openhands-smoke-test", "version": "1.0"},
            },
        })
        if not init or "result" not in init:
            err = (proc.stderr.read() or "")[:200] if proc.stderr else ""
            return f"FAIL  {name}: no initialize response {err!r}"

        server = init["result"].get("serverInfo", {})
        proc.stdin.write(json.dumps(
            {"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        proc.stdin.flush()

        tools = rpc(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        names = [t["name"] for t in tools.get("result", {}).get("tools", [])] if tools else []
        return (f"PASS  {name}: {server.get('name')} v{server.get('version')} "
                f"-> {len(names)} tools {names[:6]}")
    finally:
        proc.kill()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.expanduser("~/.openhands/mcp.json"))
    args = ap.parse_args()

    if not os.path.exists(args.config):
        print(f"no MCP config at {args.config}")
        return 1

    with open(args.config) as fh:
        servers = json.load(fh).get("mcpServers", {})

    print(f"Testing {len(servers)} MCP server(s) from {args.config}\n")
    checked = failures = 0
    for name, spec in servers.items():
        if spec.get("transport") != "stdio":
            print(f"SKIP  {name}: transport={spec.get('transport')} (remote, not probed)")
            continue
        if spec.get("enabled") is False:
            print(f"SKIP  {name}: disabled")
            continue
        checked += 1
        line = check(name, spec)
        print(line)
        if line.startswith("FAIL"):
            failures += 1

    print(f"\n{checked - failures}/{checked} probed server(s) healthy")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
