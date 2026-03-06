# z6m Claude Workspace

Docker-based development environment that runs Claude Code agents against the z6m codebase, with a lightweight task orchestrator for parallel agent workflows.

## Quick Start

```bash
# Interactive shell inside the container
./tools/claude/run.sh

# Start the task orchestrator
./tools/claude/run.sh orchestrator

# One-shot read-only task
./tools/claude/run.sh orchestrator "explain the MPT implementation"

# Build image only (no container)
./tools/claude/run.sh --build-only
```

## What Works

- **Claude `-p` (print) mode** — one-shot API calls from inside the container
- **Interactive `claude`** — full interactive sessions with OAuth auth
- **Session resume** — `claude --resume <id>` picks up where a previous task left off
- **Orchestrator REPL** — dispatch parallel read-only agents and serialized write agents
- **File ownership** — files created in mounted dirs are owned by your host user, not the container's internal UID
- **Credential sync** — OAuth tokens stay in sync between host and container (bind-mounted read-write)
- **Timezone** — container matches host clock via `/etc/localtime` mount

## Architecture

```
Host                                    Container (z6m-workspace)
─────────────────────                   ─────────────────────────────
~/.claude/                              /home/z6m/.claude/
  .credentials.json  ──bind-mount-rw──>   .credentials.json
  settings.json      ──copy──────────>   settings.json
  stats-cache.json   ──copy──────────>   stats-cache.json
  (other files)      ──copy──────────>   (other files)

~/.claude.json       ──bind-mount-rw──>  /home/z6m/.claude.json

./temp/orch_sessions ──bind-mount────>  /data/
./temp/claude_sessions ──bind-mount──>  /home/z6m/.claude/projects/

/etc/localtime       ──bind-mount-ro──>  /etc/localtime
```

### Entrypoint Flow (runs as root, then drops to z6m)

1. **UID/GID remap** — deletes conflicting users (e.g. `ubuntu` at UID 1000), then patches `/etc/passwd` via `sed` to give z6m the host user's UID/GID. Instant (avoids `usermod -u` 60s home-dir traversal).
2. **Fix home dir** — `chown z6m:z6m /home/z6m /home/z6m/.claude` (non-recursive, instant). Claude writes `~/.claude.json` here.
3. **Copy config** — copies all top-level files from the staged `~/.claude/` dir, skipping `.credentials.json` (bind-mounted) and `mcp-needs-auth-cache.json` (causes MCP OAuth browser hang).
4. **Drop privileges** — `exec gosu z6m "$@"` for a clean setuid+exec with proper TTY passthrough.

### Orchestrator

The orchestrator (`/usr/local/bin/orchestrator` inside the container) dispatches tasks to background Claude agents:

- **Read-only tasks** (`<prompt>`) — run in parallel, Edit/Write tools disabled
- **Write tasks** (`edit: <prompt>`) — serialized via file lock, one at a time
- **Session tracking** — each task's Claude session ID is captured for later `resume`

REPL commands: `list`, `logs <id>`, `attach <id>`, `resume <id>`, `wait [id]`, `kill <id>`, `session`, `sessions`, `help`, `quit`

## Debugging History

Key issues encountered and their root causes during development:

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| Container files owned by UID 1001 | z6m's default UID doesn't match host user | Entrypoint remaps z6m's UID to `HOST_UID` via sed |
| `claude` hangs at UID 1000 | `ubuntu` user at UID 1000 in Ubuntu 25.10 — `getpwuid(1000)` returned wrong user | `userdel ubuntu` before UID remap |
| 60s startup delay | `usermod -u` traverses 1.4GB Rust toolchain in `/home/z6m` to reown files | Use `sed` on `/etc/passwd` instead (instant, no traversal) |
| `claude` silently hangs (no output) | `EACCES` writing `~/.claude.json` — home dir owned by old UID after remap | `chown z6m:z6m /home/z6m` (non-recursive) |
| `runuser`/`setpriv` break interactive TTY | Both create PAM sessions or alter process groups | Use `gosu` (clean setuid+exec, Docker standard) |
| `resume` prompts for login | Only `.credentials.json` was copied; interactive mode needs `settings.json` etc. | Copy all top-level files from `~/.claude/` |
| Interactive `claude` shows ERR_BAD_RESPONSE | OAuth token goes stale — host refreshes it, container has old copy | Bind-mount `.credentials.json` read-write (not copy) |
| Interactive `claude` starts guided init | Missing `~/.claude.json` (setup-complete marker + preferences) | Bind-mount `~/.claude.json` from host |
| `mcp-needs-auth-cache.json` causes hang | Triggers MCP OAuth browser flow for Gmail/Calendar in headless container | Skip copying this file in entrypoint |
| `groupdel` fails before `userdel` | Can't delete a group that's still a user's primary group | Delete user first, then group |
| `mv /home/z6m` fails during remap | Volume mount at `/home/z6m/.claude/projects` prevents moving parent | Use `sed` instead of `mv`+`usermod`+`mv` trick |
| `stream-json` output empty | Missing `--verbose` flag | Add `--verbose` when using `--output-format stream-json` with `-p` |

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu 25.10 image with GCC-14, Rust 1.88, Node.js, Claude CLI, CMake |
| `entrypoint.sh` | Root entrypoint: UID remap, credential setup, privilege drop via gosu |
| `run.sh` | Host-side script: builds image, mounts volumes, runs container |
| `orchestrator.sh` | In-container task orchestrator with REPL, parallel dispatch, session tracking |
| `AGENTS.md` | Claude skill file with project context and coding conventions |

## Auth

Two methods, in order of precedence:

1. **OAuth subscription** (default) — run `claude auth login` on your host machine. The credentials at `~/.claude/.credentials.json` are bind-mounted into the container.
2. **API key** — `export ANTHROPIC_API_KEY=sk-ant-...` before running `./run.sh`.

## Requirements

- Docker
- Claude Code CLI on host (for initial `claude auth login`)
