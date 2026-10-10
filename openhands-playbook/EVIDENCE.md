# EVIDENCE — raw output from the OpenHands deployment run

Captured on the agent host. Nothing here is paraphrased.

## A. The agent host is NOT a Windows 11 machine

```
### uname -a
Linux ins-01m4ky1hrn89qr81qstse2qe5b 6.12.85+ #1 SMP Wed Jun 17 20:13:06 UTC 2026 x86_64 GNU/Linux

### id
uid=1000(node) gid=1000(node) groups=1000(node)

### /etc/os-release
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"

### hostname
ins-01m4ky1hrn89qr81qstse2qe5b

### /mnt
total 8
drwxr-xr-x 2 root root 4096 Oct  5 00:00 .
drwxr-xr-x 1 root root 4096 Oct 10 22:13 ..
```

No `/mnt/c`, no `C:\`, no PowerShell, no WMI/CIM. There is no Windows host attached to this
session in any form.

## B. `claw-tower` is not resolvable and there is no SSH material

```
### claw-tower resolution attempts
claw-tower               no-dns
claw-tower.local         no-dns
claw-tower.lan           no-dns
claw-tower.internal      no-dns
clawtower                no-dns

### ssh material
ls: cannot access '/home/node/.ssh': No such file or directory

### ssh config
cat: /home/node/.ssh/config: No such file or directory
```

Direct connect attempt:

```
$ ssh -o BatchMode=yes -o ConnectTimeout=8 claw-tower 'hostname'
ssh: Could not resolve hostname claw-tower: Name or service not known
```

Outbound SSH *is* permitted from here (so only a resolvable address + credentials are missing):

```
outbound tcp/22: OPEN
```

## C. No container runtime and no privileges

```
### privilege
sudo NOT available
CapEff: 0000000000000000
ls: cannot access '/var/run/docker.sock': No such file or directory
```

`docker` and `podman` are both absent from `PATH`. Docker-based OpenHands components
(`openhands serve`, the Docker Agent Canvas backend, `ghcr.io/openhands/agent-server:*`
images, the sandboxed runtime) therefore cannot be installed or run in this environment.

## D. TLS-intercepting egress proxy (sandbox only)

```
$ uv tool install openhands --python 3.12
error: Failed to download `.../cpython-3.12.15%2B20261003-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz`
  cause: client error (Connect)
  cause: invalid peer certificate: UnknownIssuer
```

`curl` succeeds on the same URL because `CURL_CA_BUNDLE=/etc/mitm/ca.crt`:

```
*  CAfile: /etc/mitm/ca.crt
*  subject: CN=github.com
*  issuer: CN=cline-mitm-ca
*  SSL certificate verify ok.
```

`uv` uses its own bundled trust store. Working workaround (confirmed):

```
$ UV_INSECURE_HOST='pypi.org files.pythonhosted.org github.com objects.githubusercontent.com' \
    uv python install 3.12
Downloading cpython-3.12.15-linux-x86_64-gnu (download) (32.7MiB)
Installed Python 3.12.15 in 1.42s
```

`uv --help` confirms the flag/env pair: `--allow-insecure-host <...> [env: UV_INSECURE_HOST=]`.

## E. Installation actually performed

```
$ curl -fsSL https://install.openhands.dev/install.sh | sh
[INFO] Starting OpenHands CLI installation...
[INFO] Detected OS: linux
[INFO] Detected Architecture: x86_64
[INFO] Installing to: /home/node/.local/bin/openhands
[INFO] Downloading OpenHands CLI v1.14.0...
[SUCCESS] OpenHands CLI v1.14.0 installed successfully!
[SUCCESS] Installation verified. You can now run 'openhands --help' to get started.
[INFO] Version information:
OpenHands CLI 1.14.0

$ ls -la ~/.local/bin/openhands
-rwxr-xr-x 1 node node 79985400 ... /home/node/.local/bin/openhands

$ npm install -g @openhands/agent-canvas
$ npm ls -g --depth=0
`-- @openhands/agent-canvas@1.26.0
```

## F. Verified state

```
### openhands --version
OpenHands CLI 1.14.0        (banner reports OpenHands SDK v1.16.1)

### npm global package
`-- @openhands/agent-canvas@1.26.0

### uv-managed python
cpython-3.12.15-linux-x86_64-gnu  /home/node/.local/bin/python3.12 -> .../cpython-3.12-linux-x86_64-gnu/bin/python3.12

### listening ports
LISTEN 8000     # Agent Canvas UI   -> HTTP 200, <title>OpenHands</title>
LISTEN 18000    # agent server      -> HTTP 200
LISTEN 18001    # automation server -> "Application startup complete."
```

Agent Canvas startup log:

```
Agent Canvas (Static)
[1/2] Checking prerequisites...
✓ uvx found
[2/2] Starting services...
22:24:36 [agent-server] Starting on port 18000...
22:24:36 [agent-server] Using PyPI (1.53.0, default)
22:25:02 [automation] "Application startup complete."
22:25:02 [automation] "Uvicorn running on http://127.0.0.1:18001"
```

## G. MCP configuration and protocol-level verification

`openhands mcp add` writes `~/.openhands/mcp.json`. Five servers registered:

```
$ openhands mcp list
Configured MCP servers (5):
  • filesystem [✓ enabled]           stdio  npx  -y @modelcontextprotocol/server-filesystem /workspace
  • memory [✓ enabled]               stdio  npx  -y @modelcontextprotocol/server-memory
  • sequential-thinking [✓ enabled]  stdio  npx  -y @modelcontextprotocol/server-sequential-thinking
  • fetch [✓ enabled]                stdio  uvx  mcp-server-fetch
  • git [✓ enabled]                  stdio  uvx  mcp-server-git
```

Each server was then probed with a real JSON-RPC handshake (`mcp_smoke.py`):

```
$ python3 mcp_smoke.py
Testing 5 MCP server(s) from /home/node/.openhands/mcp.json

PASS  filesystem: secure-filesystem-server v0.2.0 -> 14 tools ['read_file', 'read_text_file', 'read_media_file', 'read_multiple_files', 'write_file', 'edit_file']
PASS  memory: memory-server v0.6.3 -> 9 tools ['create_entities', 'create_relations', 'add_observations', 'delete_entities', 'delete_observations', 'delete_relations']
PASS  sequential-thinking: sequential-thinking-server v2026.8.31 -> 1 tools ['sequentialthinking']
PASS  git: mcp-git v1.30.0 -> 12 tools ['git_status', 'git_diff_unstaged', 'git_diff_staged', 'git_diff', 'git_commit', 'git_add']
PASS  fetch: mcp-fetch v1.30.0 -> 1 tools ['fetch']

5/5 probed server(s) healthy
```

One real defect was found and fixed during this run: the first `fetch` registration used
`uvx -- -y mcp-server-fetch`, and `uvx` rejects `-y` (`unexpected argument '-y' found`). The
server was removed and re-added without the flag, after which it passed.

## H. End-to-end agent run

```
$ LLM_MODEL=anthropic/claude-sonnet-4-5-20250929 LLM_API_KEY=sk-ant-invalid-probe \
    openhands --headless --always-approve --override-with-envs -t 'reply with the single word pong'
Secure MCP Filesystem Server running on stdio
Knowledge Graph MCP Server running on stdio
Sequential Thinking MCP Server running on stdio
ERROR litellm.InternalServerError: AnthropicException - [SSL: CERTIFICATE_VERIFY_FAILED]
      certificate verify failed: unable to get local issuer certificate
      Attempt #1 | Attempt #2 ...
```

This is the strongest available end-to-end evidence short of a real key:

* all MCP servers were **spawned and attached** to the agent,
* the conversation was created and persisted under `~/.openhands/conversations/`,
* the agent reached the **provider call through LiteLLM** — i.e. the LLM config path is wired,
* the only failure is TLS verification against the sandbox's intercepting proxy, using a
  deliberately invalid probe key. Neither the key nor the TLS issue exists on a real host.

`~/.openhands/conversations/e6ab7b04b1ad430594f71eb1c74fdb3f/base_state.json` records the
resolved agent configuration, confirming the wiring:

```json
{"agent": {"llm": {"model": "anthropic/claude-sonnet-4-5-20250929", "api_key": "**********",
  "max_input_tokens": 200000, "max_output_tokens": 64000, "native_tool_calling": true,
  "reasoning_effort": "high", "timeout": 300},
 "tools": [{"name": "terminal"}, {"name": "file_editor"}, {"name": "task_tracker"}, {"name": "delegate"}],
 "mcp_config": {"mcpServers": {"filesystem": {...}, "memory": {...}, ...}}}}
```

## I. Final verification summary

```
$ bash verify.sh
=== OpenHands verification ===
-- environment --
host: ins-01m4ky1hrn89qr81qstse2qe5b   user: node   kernel: Linux 6.12.85+
-- binaries --
  PASS openhands: OpenHands CLI 1.14.0
  PASS agent-canvas: 1.26.0
  PASS uv: uv 0.12.23 (x86_64-unknown-linux-gnu)
  info node: v24.21.0
-- MCP --
  info servers: filesystem, memory, sequential-thinking, git, fetch
  5/5 probed server(s) healthy
-- services --
  PASS port 8000 reachable
  PASS port 18000 reachable
  PASS port 18001 reachable
-- docker (optional components) --
  info no docker daemon -> "openhands serve" and sandboxed Canvas backends unavailable

result: 7 passed, 0 failed
```

## J. What is still missing

| Gap | Why | Unblocks it |
|---|---|---|
| `claw-tower` deployment | hostname does not resolve; no SSH config/keys | hostname/IP + port + user + credentials, or an ssh `Host` entry |
| Windows 11 deployment | no Windows host is reachable from this session | run `install-windows.ps1` locally, or provide a Windows/WSL access path |
| Docker components | no daemon, no privileges to install one | a host with a working Docker daemon |
| LLM calls | no API key was supplied | `LLM_MODEL` + `LLM_API_KEY` |

