#!/usr/bin/env bash
# OpenHands full-package installer for Debian / Ubuntu (validated on Debian 12 "bookworm").
#
# Installs:
#   1. OpenHands CLI            (standalone binary, self-contained)
#   2. OpenHands Agent Canvas   (npm global: UI + agent server + automation server)
#   3. Software Agent SDK       (python venv via uv)
#   4. MCP servers              (filesystem, memory, sequential-thinking, git, fetch)
#
# Docker-based components are OPTIONAL and only installed if a working Docker
# daemon is detected (openhands serve / sandboxed Agent Canvas backend).
#
# Usage:  bash install-debian.sh [--no-mcp] [--no-sdk] [--no-canvas]
set -euo pipefail

SKIP_MCP=0; SKIP_SDK=0; SKIP_CANVAS=0
for arg in "$@"; do
  case "$arg" in
    --no-mcp) SKIP_MCP=1 ;;
    --no-sdk) SKIP_SDK=1 ;;
    --no-canvas) SKIP_CANVAS=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m[oh]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  xx\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- prerequisites
log "checking prerequisites"
have curl || die "curl is required"
have python3 || die "python3 is required"

if ! have uv; then
  log "installing uv (provides the python runtime used by the agent server)"
  curl -fsSL https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
ok "uv $(uv --version 2>/dev/null | awk '{print $2}')"

if ! have node || [ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" -lt 24 ]; then
  warn "Node.js 24+ is required for Agent Canvas (found: $(node -v 2>/dev/null || echo none))"
  warn "install it first, e.g.:  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt-get install -y nodejs"
  [ "$SKIP_CANVAS" = "1" ] || die "aborting: Agent Canvas requested but Node.js 24+ is missing"
fi

# ------------------------------------------------------------------- 1. CLI
log "installing OpenHands CLI"
curl -fsSL https://install.openhands.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
have openhands || die "openhands binary not found on PATH after install"
ok "openhands $(openhands --version 2>/dev/null | tail -1)"

# ------------------------------------------------------------------- 2. Canvas
if [ "$SKIP_CANVAS" = "0" ]; then
  log "installing Agent Canvas"
  npm install -g @openhands/agent-canvas
  have agent-canvas || die "agent-canvas not found on PATH after install"
  ok "agent-canvas installed"
else
  log "skipping Agent Canvas (--no-canvas)"
fi

# ------------------------------------------------------------------- 3. SDK
if [ "$SKIP_SDK" = "0" ]; then
  log "installing the Software Agent SDK into ~/.openhands-sdk"
  uv venv "$HOME/.openhands-sdk" --python 3.12
  # shellcheck disable=SC1091
  uv pip install --python "$HOME/.openhands-sdk/bin/python" openhands-sdk openhands-tools
  ok "SDK venv ready at ~/.openhands-sdk"
else
  log "skipping SDK (--no-sdk)"
fi

# ------------------------------------------------------------------- 4. MCP
if [ "$SKIP_MCP" = "0" ]; then
  log "configuring MCP servers"
  mkdir -p "$HOME/.openhands"

  # add_or_replace <name> <transport> [--env K=V]... -- <command> [args...]
  add_or_replace() {
    local name="$1"; shift
    openhands mcp remove "$name" >/dev/null 2>&1 || true
    openhands mcp add "$name" "$@" >/dev/null 2>&1 \
      && ok "mcp: $name" || warn "mcp: $name failed to register"
  }

  add_or_replace filesystem --transport stdio npx -- -y @modelcontextprotocol/server-filesystem "$HOME"
  add_or_replace memory --transport stdio npx -- -y @modelcontextprotocol/server-memory
  add_or_replace sequential-thinking --transport stdio npx -- -y @modelcontextprotocol/server-sequential-thinking
  add_or_replace git --transport stdio uvx -- mcp-server-git
  add_or_replace fetch --transport stdio uvx -- mcp-server-fetch

  log "registered MCP servers:"
  openhands mcp list 2>/dev/null | sed 's/^/    /'
else
  log "skipping MCP configuration (--no-mcp)"
fi

# ------------------------------------------------------------------- 5. Docker
log "checking for a Docker runtime (optional components)"
if have docker && docker info >/dev/null 2>&1; then
  ok "docker daemon reachable -> 'openhands serve' and sandboxed Canvas backends are available"
  docker pull ghcr.io/openhands/agent-server:1.26.0-python >/dev/null 2>&1 \
    && ok "pulled ghcr.io/openhands/agent-server:1.26.0-python" \
    || warn "could not pull agent-server image (network/permissions)"
else
  warn "no usable Docker daemon: skipping Docker-only components"
  warn "  -> 'openhands serve' (legacy GUI) and the Docker Canvas backend stay unavailable"
  warn "  -> the CLI, Agent Canvas (npm backend) and MCP work without Docker"
fi

# ------------------------------------------------------------------- summary
cat <<'EOF'

============================================================
OpenHands installation complete.

  openhands              interactive terminal agent (TUI)
  openhands mcp list     show configured MCP servers
  agent-canvas           browser UI on http://localhost:8000
  openhands acp          ACP agent for Zed / Toad / IDEs

REQUIRED NEXT STEP - provide model access:
  export LLM_MODEL="anthropic/claude-sonnet-4-5-20250929"
  export LLM_API_KEY="sk-ant-..."
  openhands --override-with-envs
Or run `openhands` once interactively to store the settings in
~/.openhands/settings.json
============================================================
EOF
