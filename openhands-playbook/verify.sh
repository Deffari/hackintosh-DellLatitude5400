#!/usr/bin/env bash
# Post-install verification for the OpenHands stack.
# Usage: bash verify.sh
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
export OPENHANDS_SUPPRESS_BANNER=1

pass=0; fail=0
chk() { # chk <label> <command...>
  local label="$1"; shift
  if out=$("$@" 2>&1); then
    printf '\033[1;32m  PASS\033[0m %s -> %s\n' "$label" "$(echo "$out" | head -1)"
    pass=$((pass+1))
  else
    printf '\033[1;31m  FAIL\033[0m %s\n' "$label"
    fail=$((fail+1))
  fi
}
port() { # port <n>
  curl -sS -o /dev/null --max-time 6 "http://127.0.0.1:$1/" >/dev/null 2>&1 \
    && { printf '\033[1;32m  PASS\033[0m port %s reachable\n' "$1"; pass=$((pass+1)); } \
    || { printf '\033[1;31m  FAIL\033[0m port %s not reachable\n' "$1"; fail=$((fail+1)); }
}

echo "=== OpenHands verification ==="
echo "-- environment --"
echo "host: $(hostname)   user: $(whoami)   kernel: $(uname -sr)"

echo "-- binaries --"
command -v openhands    >/dev/null && { printf '  PASS openhands: %s\n' "$(openhands --version 2>/dev/null | tail -1)"; pass=$((pass+1)); } || { printf '  FAIL openhands missing\n'; fail=$((fail+1)); }
command -v agent-canvas >/dev/null && { printf '  PASS agent-canvas: %s\n' "$(agent-canvas --version 2>/dev/null | head -1 || echo installed)"; pass=$((pass+1)); } || { printf '  !! agent-canvas missing (optional)\n'; }
command -v uv           >/dev/null && { printf '  PASS uv: %s\n' "$(uv --version)"; pass=$((pass+1)); } || { printf '  FAIL uv missing\n'; fail=$((fail+1)); }
command -v node         >/dev/null && printf '  info node: %s\n' "$(node -v)"

echo "-- MCP --"
if [ -f "$HOME/.openhands/mcp.json" ]; then
  printf '  info servers: %s\n' "$(python3 -c "import json;print(', '.join(json.load(open('$HOME/.openhands/mcp.json'))['mcpServers']))" 2>/dev/null)"
  python3 "$(dirname "$0")/mcp_smoke.py"
  [ $? -eq 0 ] && pass=$((pass+1)) || fail=$((fail+1))
else
  printf '\033[1;31m  FAIL no ~/.openhands/mcp.json\033[0m\n'; fail=$((fail+1))
fi

echo "-- services --"
port 8000    # Agent Canvas UI
port 18000   # agent server
port 18001   # automation server

echo "-- docker (optional components) --"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  printf '  PASS docker daemon reachable\n'; pass=$((pass+1))
else
  printf '  info no docker daemon -> "openhands serve" and sandboxed Canvas backends unavailable\n'
fi

echo
printf 'result: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
