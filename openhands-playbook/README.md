# OpenHands full-package deployment playbook

Requested: *download, install and configure the full available OpenHands software package
(including MCP and the terminal CLI) on **both** this local Windows 11 host **and** the
Debian server reachable as `claw-tower`.*

> **Read this first.** Neither requested target could be reached from the agent
> environment. The full OpenHands stack was instead installed and verified on the
> Debian 12 Linux machine the agent actually had access to, and the two target
> playbooks below were produced from that validated procedure. See
> [Blockers](#1-blockers-why-the-original-request-could-not-be-executed-as-written).

---

## 1. Blockers (why the original request could not be executed as written)

| # | Target | Claim | What the agent actually observed |
|---|--------|-------|----------------------------------|
| 1 | "this local Win 11 host" | Windows 11 | The session runs in a Kubernetes pod on **Debian GNU/Linux 12 (bookworm)**, `x86_64`, user `node` (uid 1000). `uname -a` → `Linux ins-01m4ky1hrn89qr81qstse2qe5b 6.12.85+`. No PowerShell, no `C:\`, no `/mnt/c`, no WMI. It is not a Windows machine and has no path to one. |
| 2 | `claw-tower` | reachable Debian server | **DNS does not resolve.** Tested `claw-tower`, `claw-tower.local`, `claw-tower.lan`, `claw-tower.internal`, `clawtower` → all `no-dns`. No `~/.ssh/` directory exists (no config, no keys, no `known_hosts`). Nothing to connect to. |

Additional constraints found in the agent environment (they bound what "full package" can mean here):

* **No container runtime.** No `docker`, no `podman`, no `/var/run/docker.sock`.
* **No privilege.** `id` → `uid=1000(node) gid=1000(node)`; `sudo` unavailable;
  `CapEff: 0000000000000000` (zero effective capabilities), so installing Docker is impossible.
* **TLS-intercepting egress proxy** (`/etc/mitm/ca.crt`). `curl`/`git`/`npm` trust it via
  `CURL_CA_BUNDLE`/`NODE_EXTRA_CA_CERTS`, but `uv` ships its own trust store and fails with
  `invalid peer certificate: UnknownIssuer`. Workaround used here:
  `UV_INSECURE_HOST="pypi.org files.pythonhosted.org github.com objects.githubusercontent.com"`.
  **Sandbox-only workaround — do not carry it to the real hosts.**

What was *not* available and therefore not configured: an **LLM API key**. Every OpenHands
surface needs model access, so the stack is installed and wired but not "logged in".


---

## 2. What was actually installed and verified

Executed on the Debian 12 machine the agent controls. Raw output in [`EVIDENCE.md`](EVIDENCE.md).

| Component | Version | Method | Verified |
|---|---|---|---|
| OpenHands CLI (`openhands`) | **1.14.0** | `curl -fsSL https://install.openhands.dev/install.sh \| sh` → `~/.local/bin/openhands` (80 MB self-contained binary) | `openhands --version`, `--help`, subcommand tree enumerated |
| Bundled Software Agent SDK | **1.16.1** | ships inside the CLI binary | banner printed on every invocation |
| Agent Canvas | **1.26.0** | `npm install -g @openhands/agent-canvas` | UI served on `:8000` (HTTP 200, `<title>OpenHands</title>`) |
| Agent Canvas agent-server | **1.53.0** | spawned by `agent-canvas` via `uvx` | listening on `:18000`, HTTP 200 |
| Agent Canvas automation server | — | spawned by `agent-canvas` | listening on `:18001`, `Application startup complete.` |
| MCP servers | 5 registered | `openhands mcp add` → `~/.openhands/mcp.json` | **5/5 passed a live JSON-RPC handshake** (`initialize` + `tools/list`) |
| uv-managed CPython | **3.12.15** | `uv python install 3.12` | runtime for the agent server |
| Docker components | — | **not installable** | no daemon, no privileges |

MCP servers registered and individually handshake-tested:

| Server | Transport | Tools exposed |
|---|---|---|
| `filesystem` | stdio (`npx`) | 14 — `read_file`, `write_file`, `edit_file`, … |
| `memory` | stdio (`npx`) | 9 — `create_entities`, `create_relations`, … |
| `sequential-thinking` | stdio (`npx`) | 1 — `sequentialthinking` |
| `git` | stdio (`uvx`) | 12 — `git_status`, `git_diff`, `git_commit`, … |
| `fetch` | stdio (`uvx`) | 1 — `fetch` |

End-to-end agent wiring was proven with a headless run:
`openhands --headless --always-approve --override-with-envs -t '…'` started all MCP servers,
built the agent with the terminal / file-editor / task-tracker / delegate tool set, loaded
`mcp.json`, persisted a conversation under `~/.openhands/conversations/`, and reached the
provider call through LiteLLM. The only error was `SSL: CERTIFICATE_VERIFY_FAILED` raised by
the sandbox's TLS-intercepting proxy at the outbound provider call — the failure is in the
sandbox network layer, not in OpenHands or the configuration.

---

## 3. Files in this directory

| File | Purpose | Validated? |
|---|---|---|
| `install-debian.sh` | Full-package installer for Debian/Ubuntu — the playbook for **`claw-tower`**. | ✅ every step executed successfully on Debian 12 |
| `install-windows.ps1` | Windows 11 installer (winget + Node 24 + uv + Agent Canvas native + WSL2 Ubuntu for the CLI). | ❌ **never executed** — no Windows host reachable. Review before use. |
| `mcp-servers.json` | MCP template (the 5 verified servers + GitHub + a remote HTTP example). | ✅ 5/5 declared servers handshake-tested |
| `mcp_smoke.py` | Protocol-level MCP health check; non-zero exit if any server fails. | ✅ produced the 5/5 result |
| `verify.sh` | One-shot post-install verification (versions, services, MCP). | ✅ |
| `EVIDENCE.md` | Raw command output captured during this run. | ✅ |

---

## 4. Finishing the deployment

### 4a. On the Debian server (`claw-tower`) — still blocked on access

```bash
# from a machine that can reach claw-tower
scp -r openhands-playbook <user>@claw-tower:~/
ssh <user>@claw-tower 'bash ~/openhands-playbook/install-debian.sh'
ssh <user>@claw-tower 'export PATH=$HOME/.local/bin:$PATH; python3 ~/openhands-playbook/mcp_smoke.py'
```

To let the agent do it directly, provide the **hostname or IP**, **SSH port**, **username** and
**key/password** (or add a `Host claw-tower` block to `~/.ssh/config` on the agent host).
The agent environment has outbound TCP/22 open, so a resolvable address is the only missing piece.

### 4b. On the Windows 11 host

```powershell
pwsh -ExecutionPolicy Bypass -File .\install-windows.ps1
```

Upstream supports Windows only through **WSL2 (Ubuntu)** for the CLI — its install page states
*"Windows users: all commands below should be run inside the WSL terminal (Ubuntu)"*.
Agent Canvas additionally runs natively on Windows via npm, and there is a desktop preview
`.exe`. The script encodes all of that; it is unvalidated here.

### 4c. Required on every host — model access

```bash
export LLM_MODEL="anthropic/claude-sonnet-4-5-20250929"   # or openai/gpt-5.5, openhands/...
export LLM_API_KEY="<your key>"
openhands --override-with-envs        # or run `openhands` once to persist settings
```

### 4d. Ports to open / expect

| Service | Port | Notes |
|---|---|---|
| Agent Canvas UI | 8000 | browser client |
| Agent Canvas agent server | 18000 | executes conversations |
| Agent Canvas automation server | 18001 | schedules/automations |
| `openhands web` | user-chosen | CLI exposed as a web app |

---

## 5. Component status matrix

| Component | Debian 12 (verified here) | `claw-tower` | Windows 11 |
|---|---|---|---|
| Terminal CLI (`openhands`) | ✅ 1.14.0 | ⏳ script ready | ⏳ via WSL2 |
| Agent Canvas UI + backend | ✅ :8000 / :18000 / :18001 | ⏳ script ready | ⏳ native npm |
| MCP servers | ✅ 5/5 handshake-verified | ⏳ script ready | ⏳ via WSL2 |
| Software Agent SDK | ✅ 1.16.1 (bundled) | ⏳ script ready | ⏳ via WSL2 |
| ACP agent (`openhands acp`) | ✅ command present | ⏳ | ⏳ |
| Docker runtime (`openhands serve`, sandboxed Canvas, `agent-server` image) | ❌ no daemon/privileges | ⏳ needs Docker | ⏳ needs Docker Desktop |
| LLM credentials | ❌ no key supplied | ❌ | ❌ |

Legend: ✅ installed **and** verified · ⏳ not executed (see §1) · ❌ impossible or not provided

---

## 6. Reproducing the verified install

```bash
export PATH="$HOME/.local/bin:$PATH"
export UV_INSECURE_HOST="pypi.org files.pythonhosted.org github.com objects.githubusercontent.com"  # sandbox only

curl -fsSL https://install.openhands.dev/install.sh | sh          # 1. CLI
npm install -g @openhands/agent-canvas                            # 2. Agent Canvas
openhands mcp add filesystem --transport stdio npx -- -y @modelcontextprotocol/server-filesystem "$HOME"   # 3. MCP
agent-canvas &                                                    # 4. start the stack
python3 mcp_smoke.py                                              # 5. verify
```

`install-debian.sh` performs exactly these steps, idempotently, plus the SDK venv.

