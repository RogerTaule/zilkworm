#!/usr/bin/env bash
# ===========================================================================
#  z6m Claude Workspace – Build & Run
#
#  Usage:
#    ./run.sh                          # build image and start interactive shell
#    ./run.sh orchestrator             # start the chat orchestrator
#    ./run.sh orchestrator "fix build" # one-shot task
#    ./run.sh --build-only             # just build the image
#
#  Auth: Uses your local Claude subscription credentials (~/.claude/.credentials.json).
#        Falls back to ANTHROPIC_API_KEY env var if set.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE_NAME="z6m-workspace"
CONTAINER_NAME="z6m-agent-$(date +%s)-${RANDOM}"
CLAUDE_CONFIG_DIR="$HOME/.claude"
SESSION_DIR="${REPO_ROOT}/temp/orch_sessions"
CLAUDE_SESSIONS_DIR="${REPO_ROOT}/temp/claude_sessions"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${CYAN}[z6m]${NC} $*"; }
ok()  { echo -e "${GREEN}[z6m]${NC} $*"; }
err() { echo -e "${RED}[z6m]${NC} $*" >&2; }

# ── Build the Docker image ─────────────────────────────────────────────────
build_image() {
    log "Building Docker image: ${IMAGE_NAME}"
    docker build \
        -f "$SCRIPT_DIR/Dockerfile" \
        -t "$IMAGE_NAME" \
        "$REPO_ROOT"
    ok "Image built: ${IMAGE_NAME}"
}

# ── Run the container ──────────────────────────────────────────────────────
run_container() {
    local docker_args=(
        docker run --rm -it
        --name "$CONTAINER_NAME"
        --hostname z6m-agent
        -e HOST_UID="$(id -u)"
        -e HOST_GID="$(id -g)"
    )

    if [[ -d "$CLAUDE_CONFIG_DIR" ]]; then
        log "Mounting Claude config dir (~/.claude/)."
        docker_args+=(-v "$CLAUDE_CONFIG_DIR:/tmp/claude-config:ro")
        # Mount credentials read-write so OAuth token refreshes propagate
        # between host and container (avoids stale-token ERR_BAD_RESPONSE).
        if [[ -f "$CLAUDE_CONFIG_DIR/.credentials.json" ]]; then
            docker_args+=(-v "$CLAUDE_CONFIG_DIR/.credentials.json:/home/z6m/.claude/.credentials.json")
        fi
        # Mount ~/.claude.json (setup-complete marker + preferences).
        # Without this, interactive claude starts the guided init flow.
        if [[ -f "$HOME/.claude.json" ]]; then
            docker_args+=(-v "$HOME/.claude.json:/home/z6m/.claude.json")
        fi
    elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        log "Passing ANTHROPIC_API_KEY."
        docker_args+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
    else
        err "No Claude auth found!"
        err "  Expected: ~/.claude/ dir (run 'claude auth login' first)"
        err "  Or set:   export ANTHROPIC_API_KEY=sk-ant-..."
        exit 1
    fi

    # Mount host timezone so the container matches the host clock/region
    if [[ -f /etc/localtime ]]; then
        docker_args+=(-v /etc/localtime:/etc/localtime:ro)
    fi
    if [[ -f /etc/timezone ]]; then
        docker_args+=(-v /etc/timezone:/etc/timezone:ro)
    fi

    mkdir -p "$SESSION_DIR"
    docker_args+=(-v "$SESSION_DIR:/data")

    mkdir -p "$CLAUDE_SESSIONS_DIR"
    docker_args+=(-v "$CLAUDE_SESSIONS_DIR:/home/z6m/.claude/projects")

    if [[ "${Z6M_AUTO_PULL:-0}" == "1" ]]; then
        docker_args+=(-e "Z6M_AUTO_PULL=1")
    fi

    docker_args+=("$IMAGE_NAME")

    if [[ $# -gt 0 ]]; then
        docker_args+=("$@")
    fi

    log "Starting container: ${CONTAINER_NAME}"
    "${docker_args[@]}"
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    case "${1:-}" in
        --build-only)
            build_image
            ;;
        --help|-h)
            echo "Usage: $0 [--build-only | --help | <cmd...>]"
            echo ""
            echo "  (no args)               Build & start interactive bash shell"
            echo "  orchestrator             Build & start the chat orchestrator"
            echo "  orchestrator \"task\"      Build & run one-shot task"
            echo "  --build-only             Just build the Docker image"
            echo ""
            echo "Auth: Place Claude credentials at ~/.claude/.credentials.json"
            echo "      (run 'claude auth login' on host), or set ANTHROPIC_API_KEY."
            ;;
        *)
            build_image
            run_container "$@"
            ;;
    esac
}

main "$@"
