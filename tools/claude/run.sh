#!/usr/bin/env bash
# ===========================================================================
#  z6m Claude Workspace – Build & Run
#
#  Usage:
#    ./run.sh                          # build image and start interactive shell
#    ./run.sh orchestrator             # start the chat orchestrator
#    ./run.sh orc                      # same (orc is an alias)
#    ./run.sh orchestrator "fix build" # one-shot task
#    ./run.sh orc /path/to/blocks      # mount dir read-only at /mnt/blocks
#    ./run.sh --build-only             # just build the image
#
#  Directory mounts:
#    Any argument after orchestrator/orc that is an existing host directory
#    is mounted read-only in the container at /mnt/<basename>.
#    Non-directory arguments are treated as task prompts (existing behavior).
#
#  Auth: Uses your local Claude subscription credentials (~/.claude/.credentials.json).
#        Falls back to ANTHROPIC_API_KEY env var if set.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

IMAGE_NAME="z6m-workspace"
CONTAINER_NAME="z6m-agent-$(date +%s)-${RANDOM}"
CLAUDE_CONFIG_DIR="$HOME/.claude"
SP1_HOME_DIR="$HOME/.sp1"
SP1_WIP_DIR="$(cd "$REPO_ROOT/.." && pwd)/sp1-wip"
SESSION_DIR="${REPO_ROOT}/temp/orch_sessions"
CLAUDE_SESSIONS_DIR="${REPO_ROOT}/temp/claude_sessions"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
log() { echo -e "${CYAN}[z6m]${NC} $*"; }
ok()  { echo -e "${GREEN}[z6m]${NC} $*"; }
err() { echo -e "${RED}[z6m]${NC} $*" >&2; }

# ── List sessions & containers, offer interactive attach ──────────────────
list_and_attach() {
    local entries=()
    local i=0

    echo ""
    echo -e "  ${BOLD}Running containers${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
    local has_containers=false
    while IFS='|' read -r cname cstatus; do
        [[ -z "$cname" ]] && continue
        has_containers=true
        (( i++ )) || true
        entries+=("${i}|container|${cname}")
        echo -e "  ${GREEN}$(printf '%3d' "$i")${NC}  $(printf '%-40s' "$cname") $cstatus"
    done < <(docker ps --filter "name=z6m-agent-" --format '{{.Names}}|{{.Status}}' 2>/dev/null)
    if ! $has_containers; then
        echo -e "  ${DIM}(none)${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}Orchestrator sessions${NC}  ${DIM}(${SESSION_DIR})${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
    local has_sessions=false
    if [[ -d "$SESSION_DIR" ]]; then
        for dir in "$SESSION_DIR"/*/; do
            [[ -d "$dir" ]] || continue
            has_sessions=true
            local sname created last_used task_count
            sname=$(basename "$dir")
            created=$(sed -n '1p' "${dir}.meta" 2>/dev/null || echo "?")
            last_used=$(sed -n '2p' "${dir}.meta" 2>/dev/null || echo "?")
            created=$(date -d "$created" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$created")
            last_used=$(date -d "$last_used" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$last_used")
            task_count=$(find "${dir}tasks" -name "*.meta" 2>/dev/null | wc -l) || task_count=0
            (( i++ )) || true
            entries+=("${i}|session|${sname}")
            echo -e "  ${CYAN}$(printf '%3d' "$i")${NC}  $(printf '%-30s' "$sname")  ${DIM}tasks:${NC}$(printf '%-3s' "$task_count")  ${DIM}last:${NC}${last_used}"
        done
    fi
    if ! $has_sessions; then
        echo -e "  ${DIM}(none)${NC}"
    fi

    echo ""
    if [[ ${#entries[@]} -eq 0 ]]; then
        log "Nothing to connect to. Start with: ./run.sh orchestrator"
        return
    fi

    echo -ne "  ${BOLD}Select [1-${i}]${NC} (or q to quit): "
    read -r choice
    [[ "$choice" == "q" || -z "$choice" ]] && return

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > i )); then
        err "Invalid selection: $choice"
        return 1
    fi

    local selected="${entries[$((choice - 1))]}"
    local sel_type sel_target
    IFS='|' read -r _ sel_type sel_target <<< "$selected"

    case "$sel_type" in
        container)
            log "Attaching to container: ${sel_target}"
            log "Type 'exit' or Ctrl+D to return. Container keeps running."
            echo ""
            echo -ne "  Run ${BOLD}orchestrator${NC} or ${BOLD}bash${NC}? [o/b] "
            read -r shell_choice
            case "$shell_choice" in
                o|orc|orchestrator)
                    docker exec -it --detach-keys="" -u z6m -w /workspace \
                        "$sel_target" orchestrator
                    ;;
                *)
                    docker exec -it --detach-keys="" -u z6m -w /workspace \
                        "$sel_target" bash
                    ;;
            esac
            ;;
        session)
            log "Starting new container for session: ${sel_target}"
            build_image
            run_container orchestrator "$sel_target"
            ;;
    esac
}

# ── Build the Docker image ─────────────────────────────────────────────────
build_image() {
    log "Building Docker image: ${IMAGE_NAME}"
    docker build \
        -f "$REPO_ROOT/tools/claude/Dockerfile" \
        --build-context "sp1_home=$SP1_HOME_DIR" \
        --build-context "sp1_wip=$SP1_WIP_DIR" \
        --build-arg "CLAUDE_CACHEBUST=$(date +%s)" \
        -t "$IMAGE_NAME" \
        "$REPO_ROOT"
    ok "Image built: ${IMAGE_NAME}"
}

# ── Run the container ──────────────────────────────────────────────────────
run_container() {
    # Separate directory args (to mount) from command args (to exec).
    local mount_dirs=()
    local cmd_args=()
    for arg in "$@"; do
        if [[ -d "$arg" ]]; then
            mount_dirs+=("$arg")
        else
            cmd_args+=("$arg")
        fi
    done

    local docker_args=(
        docker run -d
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

    # Mount extra host directories read-only at /mnt/<basename>
    for dir in "${mount_dirs[@]}"; do
        local resolved
        resolved="$(cd "$dir" && pwd)"
        local bname
        bname="$(basename "$resolved")"
        log "Mounting ${resolved} → /mnt/${bname} (read-only)"
        docker_args+=(-v "${resolved}:/mnt/${bname}:ro")
    done

    docker_args+=("$IMAGE_NAME")

    # Always start with a long-running sleep so the container stays alive.
    # We then exec into it to run the user's command or an interactive shell.
    docker_args+=(sleep infinity)

    log "Starting container: ${CONTAINER_NAME}"
    "${docker_args[@]}" >/dev/null

    # Wait for the entrypoint to finish UID remapping and chowns before exec-ing.
    local retries=0
    while ! docker exec "$CONTAINER_NAME" test -f /proc/1/status 2>/dev/null; do
        sleep 0.2
        (( retries++ > 25 )) && { err "Container failed to start."; exit 1; }
    done
    # Entrypoint execs gosu→sleep, so once PID 1 is sleep the setup is done.
    while [[ "$(docker exec "$CONTAINER_NAME" cat /proc/1/comm 2>/dev/null)" != "sleep" ]]; do
        sleep 0.2
        (( retries++ > 25 )) && { err "Entrypoint did not finish in time."; exit 1; }
    done

    log "Type 'exit' or Ctrl+D to leave. Container keeps running. Reattach: ./run.sh list"

    if [[ ${#cmd_args[@]} -gt 0 ]]; then
        log "Executing: ${cmd_args[*]}"
        docker exec -it --detach-keys="" -u z6m -w /workspace \
            "$CONTAINER_NAME" "${cmd_args[@]}"
    else
        docker exec -it --detach-keys="" -u z6m -w /workspace \
            "$CONTAINER_NAME" bash
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    case "${1:-}" in
        --build-only)
            build_image
            ;;
        list|ls)
            list_and_attach
            ;;
        clean)
            log "Removing all z6m-agent containers..."
            local containers
            containers=$(docker ps -a --filter "name=z6m-agent-" --format '{{.Names}}' 2>/dev/null || true)
            if [[ -z "$containers" ]]; then
                ok "No z6m-agent containers found."
            else
                echo "$containers" | while read -r name; do
                    docker rm -f "$name" 2>/dev/null && ok "Removed: $name" || warn "Failed to remove: $name"
                done
            fi
            ;;
        --help|-h)
            echo "Usage: $0 [list | clean | --build-only | --help | <cmd...>]"
            echo ""
            echo "  (no args)               Build & start interactive bash shell"
            echo "  orchestrator (orc)       Build & start the chat orchestrator"
            echo "  orchestrator \"task\"      Build & run one-shot task"
            echo "  orchestrator /path/dir   Mount dir read-only at /mnt/<basename>"
            echo "  list (ls)               Show containers & sessions, attach interactively"
            echo "  --build-only             Just build the Docker image"
            echo "  clean                    Remove all z6m-agent containers"
            echo ""
            echo "Directory mounts:"
            echo "  Any arg after orchestrator/orc that is an existing host directory"
            echo "  is mounted read-only at /mnt/<basename> inside the container."
            echo "  Non-directory args are treated as task prompts."
            echo ""
            echo "Auth: Place Claude credentials at ~/.claude/.credentials.json"
            echo "      (run 'claude auth login' on host), or set ANTHROPIC_API_KEY."
            ;;
        orc)
            shift
            build_image
            run_container orchestrator "$@"
            ;;
        *)
            build_image
            run_container "$@"
            ;;
    esac
}

main "$@"
