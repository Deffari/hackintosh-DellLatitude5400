# OpenHands full-package installer for Windows 11
#
# STATUS: NOT EXECUTED / NOT VALIDATED. The agent session that produced this
# playbook ran on a Debian 12 container with no access to any Windows host.
# Review before running. Run from an ELEVATED PowerShell 7+ prompt:
#
#     pwsh -ExecutionPolicy Bypass -File .\install-windows.ps1
#
# What it installs:
#   - Node.js 24 + Git (winget)                      -> Agent Canvas runs natively on Windows
#   - uv (Windows)                                   -> python runtime for the agent server
#   - @openhands/agent-canvas (npm global)           -> browser UI on http://localhost:8000
#   - WSL2 + Ubuntu, then OpenHands CLI inside WSL   -> `openhands` TUI (upstream supports
#                                                       Windows only through WSL)
#   - MCP servers (filesystem, memory, sequential-thinking, git, fetch)
#   - Docker Desktop (optional, prompted)            -> enables `openhands serve` and
#                                                       sandboxed Agent Canvas backends
#
# Rationale: the upstream CLI install script is bash-only and its docs state
# "Windows users: All commands below should be run inside the WSL terminal (Ubuntu)".

#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$SkipCanvas,
    [switch]$SkipCli,
    [switch]$SkipMcp,
    [switch]$InstallDockerDesktop
)

$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "[oh] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  ok $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  !! $m" -ForegroundColor Yellow }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}

if (-not (Test-Admin)) { throw 'Run this script from an elevated PowerShell prompt.' }

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store first.'
}

# --------------------------------------------------------------- prerequisites
Write-Step 'installing Node.js 24, Git and uv'
winget install --id OpenJS.NodeJS -e --accept-source-agreements --accept-package-agreements
winget install --id Git.Git       -e --accept-source-agreements --accept-package-agreements
Refresh-Path

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    powershell -NoProfile -ExecutionPolicy Bypass -Command `
        "irm https://astral.sh/uv/install.ps1 | iex"
    Refresh-Path
}
Write-Ok "node $(node -v) / npm $(npm -v) / uv $(uv --version)"

# ------------------------------------------------------------------- Agent Canvas
if (-not $SkipCanvas) {
    Write-Step 'installing Agent Canvas (native Windows)'
    npm install -g '@openhands/agent-canvas'
    Write-Ok 'run "agent-canvas" to start the UI on http://localhost:8000'

    Write-Step 'optional: Agent Canvas desktop preview build'
    Write-Host '  Download Agent-Canvas-Setup-<version>.exe from'
    Write-Host '  https://github.com/OpenHands/OpenHands/releases if you want the bundled app.'
}

# ------------------------------------------------------------------- WSL + CLI
if (-not $SkipCli) {
    Write-Step 'installing WSL2 + Ubuntu (required for the OpenHands CLI on Windows)'
    wsl --install -d Ubuntu --no-launch
    Write-Warn 'if WSL was just enabled for the first time, REBOOT and re-run this script'
    Write-Warn 'then create your Ubuntu user with:  wsl -d Ubuntu'

    Write-Step 'installing the OpenHands CLI inside WSL Ubuntu'
    $cliCmd = 'curl -fsSL https://install.openhands.dev/install.sh | sh && ' +
              'export PATH="$HOME/.local/bin:$PATH" && openhands --version'
    wsl -d Ubuntu -- bash -lc $cliCmd
    Write-Ok 'run "openhands" from inside WSL (wsl -d Ubuntu)'
}

# ------------------------------------------------------------------- MCP
if (-not $SkipMcp) {
    Write-Step 'configuring MCP servers inside WSL Ubuntu'
    $mcp = @(
        'openhands mcp remove filesystem >/dev/null 2>&1 || true',
        'openhands mcp add filesystem --transport stdio npx -- -y @modelcontextprotocol/server-filesystem $HOME',
        'openhands mcp add memory --transport stdio npx -- -y @modelcontextprotocol/server-memory',
        'openhands mcp add sequential-thinking --transport stdio npx -- -y @modelcontextprotocol/server-sequential-thinking',
        'openhands mcp add git   --transport stdio uvx -- mcp-server-git',
        'openhands mcp add fetch --transport stdio uvx -- mcp-server-fetch',
        'openhands mcp list'
    ) -join '; '
    wsl -d Ubuntu -- bash -lc "export PATH=\$HOME/.local/bin:\$PATH; $mcp"
}

# ------------------------------------------------------------------- Docker
if ($InstallDockerDesktop) {
    Write-Step 'installing Docker Desktop'
    winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements
    Write-Ok 'start Docker Desktop, then: docker run hello-world'
} else {
    Write-Warn 'Docker Desktop not requested (-InstallDockerDesktop). Without it you lose'
    Write-Warn '  "openhands serve" (legacy GUI) and the Docker/sandboxed Canvas backends.'
}

Write-Host @'

============================================================
OpenHands installation finished on Windows 11.

  agent-canvas           browser UI  http://localhost:8000
  wsl -d Ubuntu          then run:  openhands

REQUIRED NEXT STEP - provide model access (inside WSL):
  export LLM_MODEL="anthropic/claude-sonnet-4-5-20250929"
  export LLM_API_KEY="sk-ant-..."
  openhands --override-with-envs
============================================================
'@ -ForegroundColor Cyan
