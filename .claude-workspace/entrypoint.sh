#!/usr/bin/env bash
# ===========================================================================
#  Entrypoint for the z6m Claude workspace container
#
#  Runs as ROOT so it can remap z6m's UID/GID to the host user's UID/GID,
#  ensuring files written to mounted directories are owned by the host user.
#  Then drops privileges to z6m via `gosu` before executing the command.
#
#  Auth precedence:
#    1. Mounted config dir:   -v ~/.claude:/tmp/claude-config:ro  (run.sh does this automatically)
#    2. API key env var:      -e ANTHROPIC_API_KEY=sk-ant-...
# ===========================================================================
set -euo pipefail

CLAUDE_DIR="/home/z6m/.claude"
CRED_FILE="${CLAUDE_DIR}/.credentials.json"
STAGING_DIR="/tmp/claude-config"

# ── UID/GID remapping ──────────────────────────────────────────────────────
# Remap z6m's UID/GID to match the host user so files written to mounted
# volumes are owned by the host user rather than container-internal z6m (UID 1001).
#
# We use userdel for proper removal of conflicting users (e.g. 'ubuntu' at
# UID 1000), then sed to change z6m's UID/GID in /etc/passwd and /etc/group
# (instant — avoids the 60s home-dir traversal that usermod -u does).
HOST_UID="${HOST_UID:-1001}"
HOST_GID="${HOST_GID:-1001}"

Z6M_UID="$(id -u z6m)"
Z6M_GID="$(id -g z6m)"

if [[ "$HOST_UID" != "$Z6M_UID" ]]; then
    # Delete any user that already holds HOST_UID so getpwuid resolves to z6m.
    existing_user="$(getent passwd "$HOST_UID" 2>/dev/null | cut -d: -f1 || true)"
    if [[ -n "$existing_user" && "$existing_user" != "z6m" ]]; then
        userdel "$existing_user" 2>/dev/null || true
    fi
    # Change z6m's UID via sed (no filesystem traversal).
    sed -i "s/^z6m:x:${Z6M_UID}:/z6m:x:${HOST_UID}:/" /etc/passwd
fi

if [[ "$HOST_GID" != "$Z6M_GID" ]]; then
    existing_group="$(getent group "$HOST_GID" 2>/dev/null | cut -d: -f1 || true)"
    if [[ -n "$existing_group" && "$existing_group" != "z6m" ]]; then
        groupdel "$existing_group" 2>/dev/null || true
    fi
    # Change z6m's GID in both passwd and group files.
    sed -i "s/^\(z6m:x:[0-9]*:\)${Z6M_GID}:/\1${HOST_GID}:/" /etc/passwd
    sed -i "s/^z6m:x:${Z6M_GID}:/z6m:x:${HOST_GID}:/" /etc/group
fi

# Fix home dir ownership (non-recursive — just the dir itself, instant).
# Claude writes ~/.claude.json here; without this z6m gets EACCES.
chown z6m:z6m /home/z6m /home/z6m/.claude

# ── Auth: copy mounted Claude config dir or use API key ────────────────────
if [[ -d "$STAGING_DIR" ]]; then
    mkdir -p "$CLAUDE_DIR"
    # Copy all top-level files from the staging dir.
    # Skip:
    #   .credentials.json          – bind-mounted read-write by run.sh
    #   mcp-needs-auth-cache.json  – triggers MCP OAuth browser flow hang
    for src in "$STAGING_DIR"/.* "$STAGING_DIR"/*; do
        [[ -f "$src" ]] || continue
        name="$(basename "$src")"
        [[ "$name" == ".credentials.json" ]] && continue
        [[ "$name" == "mcp-needs-auth-cache.json" ]] && continue
        cp "$src" "${CLAUDE_DIR}/${name}"
        chown z6m:z6m "${CLAUDE_DIR}/${name}"
        chmod 600 "${CLAUDE_DIR}/${name}"
    done
    echo "[entrypoint] Copied Claude config files from ~/.claude/."

    if python3 -c "import json; d=json.load(open('$CRED_FILE')); assert 'claudeAiOauth' in d" 2>/dev/null; then
        echo "[entrypoint] Credential file validated (OAuth subscription)."
    else
        echo "[entrypoint] WARNING: Credential file may not contain valid OAuth data."
    fi
elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "[entrypoint] Using ANTHROPIC_API_KEY (API key auth)."
else
    echo "[entrypoint] WARNING: No Claude auth found!"
    echo "[entrypoint]   Option 1 (subscription): ensure ~/.claude/ exists on host"
    echo "[entrypoint]   Option 2 (API key):      pass -e ANTHROPIC_API_KEY=sk-ant-..."
    echo "[entrypoint] Claude CLI commands will fail without auth."
fi

# ── Pull latest on container start (optional) ──────────────────────────────
if [[ "${Z6M_AUTO_PULL:-0}" == "1" ]]; then
    echo "[entrypoint] Pulling latest changes…"
    gosu z6m bash -c 'cd /workspace && git pull --ff-only || true && git submodule update --init --recursive || true'
fi

# ── Drop privileges and execute command as z6m ─────────────────────────────
exec gosu z6m "$@"
