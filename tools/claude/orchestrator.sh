#!/usr/bin/env bash
# ===========================================================================
#  z6m Chat Orchestrator
#  Dispatches tasks to background Claude Code agents with read/write safety.
#  Sessions persist to disk at /data (mount from host: ./temp/orch_sessions).
#
#  Host directories passed to run.sh are mounted read-only under /mnt/.
#  For example: ./run.sh orc /path/to/blocks  →  available at /mnt/blocks
#  Agents can read these paths but cannot modify them.
#
#  Usage:
#    orchestrator                     # resume last session (or create first)
#    orchestrator new [name]          # create a new session
#    orchestrator --list              # pick a session interactively
#    orchestrator "analyze the code"  # one-shot read-only task (last session)
#    orchestrator --parallel task.txt # run tasks from file in parallel
#
#  REPL commands:
#    <prompt>              dispatch read-only agent (parallel, no file edits)
#    edit: <prompt>        dispatch write agent (serialized, one at a time)
#    list                  show all tasks in current session
#    logs <id>             show full output of a completed task
#    attach <id>           stream live output of a running task (Ctrl+C to detach)
#    resume <id>           open interactive session to continue a task
#    wait [id]             block until task(s) complete
#    kill <id>             kill a running task
#    session               show current session info
#    sessions              list all sessions
#    help / quit
# ===========================================================================
set -euo pipefail

WORKSPACE="/workspace"
DATA_DIR="${Z6M_DATA_DIR:-/data}"
LAST_SESSION_FILE="${DATA_DIR}/.last_session"

# These get set by init_session()
SESSION_DIR=""
TASK_DIR=""
WRITE_LOCK=""
NEXT_ID_FILE=""

# Stream-json processor script (written to temp at startup, cleaned on exit)
STREAM_PROCESSOR="/tmp/z6m_stream_proc_$$.py"

# ── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()  { echo -e "${CYAN}[orchestrator]${NC} $*"; }
ok()   { echo -e "${GREEN}[orchestrator]${NC} $*"; }
warn() { echo -e "${YELLOW}[orchestrator]${NC} $*"; }
err()  { echo -e "${RED}[orchestrator]${NC} $*" >&2; }

# ── Stream-json processor ────────────────────────────────────────────────────
# Converts claude --output-format stream-json to human-readable text, and
# extracts the session_id into a sidecar file for later resumption.
write_stream_processor() {
    cat > "$STREAM_PROCESSOR" << 'PYEOF'
#!/usr/bin/env python3
"""Converts Claude stream-json to human-readable text.
argv[1]: path to write the session_id (created on first event that has one)
"""
import sys, json

session_file = sys.argv[1] if len(sys.argv) > 1 else None
session_id_written = False

for raw in sys.stdin:
    raw = raw.rstrip('\n\r')
    if not raw:
        continue
    try:
        ev = json.loads(raw)
    except json.JSONDecodeError:
        # Not JSON – pass through (e.g. plain error messages from stderr)
        print(raw, flush=True)
        continue

    t = ev.get('type', '')

    # Capture session_id from the first event that carries it
    if not session_id_written and session_file:
        sid = ev.get('session_id', '')
        if sid:
            try:
                with open(session_file, 'w') as f:
                    f.write(sid)
                session_id_written = True
            except Exception:
                pass

    if t == 'assistant':
        for block in ev.get('message', {}).get('content', []):
            bt = block.get('type', '')
            if bt == 'text':
                text = block.get('text', '')
                if text:
                    sys.stdout.write(text)
                    sys.stdout.flush()
            elif bt == 'tool_use':
                name = block.get('name', '?')
                inp  = block.get('input', {})
                hint = ''
                for key in ('command', 'path', 'file_path', 'pattern',
                            'query', 'prompt', 'new_string', 'old_string'):
                    if key in inp:
                        val  = str(inp[key]).replace('\n', ' ')
                        hint = '(' + (val[:80] + '…' if len(val) > 80 else val) + ')'
                        break
                print(f'\n[{name} {hint}]', flush=True)

    elif t == 'tool_use':
        # Top-level tool_use events (some versions emit these separately)
        name = ev.get('name', '?')
        inp  = ev.get('input', {})
        hint = ''
        for key in ('command', 'path', 'file_path', 'pattern', 'query', 'prompt'):
            if key in inp:
                val  = str(inp[key]).replace('\n', ' ')
                hint = '(' + (val[:80] + '…' if len(val) > 80 else val) + ')'
                break
        print(f'\n[{name} {hint}]', flush=True)

    elif t == 'result' and ev.get('is_error'):
        msg = ev.get('error', '') or ev.get('result', '')
        if msg:
            print(f'\n[error: {msg}]', flush=True)
PYEOF
    chmod +x "$STREAM_PROCESSOR"
}

# ══════════════════════════════════════════════════════════════════════════════
#  SESSION MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

# Create a new session, return its name on stdout.
# Status messages go to stderr so they don't corrupt the return value.
create_session() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        name="session-$(date +%Y%m%d-%H%M%S)"
    fi

    local dir="${DATA_DIR}/${name}"
    if [[ -d "$dir" ]]; then
        err "Session '${name}' already exists."
        return 1
    fi

    mkdir -p "${dir}/tasks"
    printf '%s\n%s\n' "$(date -Iseconds)" "$(date -Iseconds)" > "${dir}/.meta"
    echo "$name" > "$LAST_SESSION_FILE"

    ok "Created session: ${name}" >&2
    echo "$name"
}

touch_session() {
    local dir="$SESSION_DIR"
    [[ -d "$dir" ]] || return 0
    local created
    created=$(sed -n '1p' "${dir}/.meta" 2>/dev/null || date -Iseconds)
    printf '%s\n%s\n' "$created" "$(date -Iseconds)" > "${dir}/.meta"
    local name
    name=$(basename "$dir")
    echo "$name" > "$LAST_SESSION_FILE"
}

last_session_name() {
    if [[ -f "$LAST_SESSION_FILE" ]]; then
        local name
        name=$(cat "$LAST_SESSION_FILE")
        if [[ -d "${DATA_DIR}/${name}" ]]; then
            echo "$name"
            return 0
        fi
    fi
    echo ""
}

init_session() {
    local name="$1"
    SESSION_DIR="${DATA_DIR}/${name}"
    TASK_DIR="${SESSION_DIR}/tasks"
    WRITE_LOCK="${SESSION_DIR}/.write_lock"
    NEXT_ID_FILE="${TASK_DIR}/.next_id"
    mkdir -p "$TASK_DIR"
    touch_session
}

list_sessions() {
    local current
    current=$(last_session_name)
    local found=false

    printf "\n  ${BOLD}%-4s %-28s %-22s %-22s %s${NC}\n" \
        "" "SESSION" "CREATED" "LAST USED" "TASKS"
    printf "  %-4s %-28s %-22s %-22s %s\n" \
        "" "───────────────────────────" "─────────────────────" "─────────────────────" "─────"

    for dir in "$DATA_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        [[ -f "${dir}/.meta" ]] || continue
        found=true

        local name
        name=$(basename "$dir")
        local created last_used task_count marker
        created=$(sed -n '1p' "${dir}/.meta" 2>/dev/null || echo "?")
        last_used=$(sed -n '2p' "${dir}/.meta" 2>/dev/null || echo "?")
        task_count=$(find "${dir}/tasks" -name "*.meta" 2>/dev/null | wc -l)
        created=$(date  -d "$created"  '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$created")
        last_used=$(date -d "$last_used" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$last_used")

        marker="  "
        if [[ "$name" == "$current" ]]; then
            marker="${GREEN}* ${NC}"
        fi
        printf "  ${marker}%-28s %-22s %-22s %s\n" \
            "$name" "$created" "$last_used" "$task_count"
    done

    $found || echo "  (no sessions)"
    echo ""
}

pick_session() {
    local sessions=()
    for dir in "$DATA_DIR"/*/; do
        [[ -d "$dir" && -f "${dir}/.meta" ]] || continue
        sessions+=("$(basename "$dir")")
    done

    if [[ ${#sessions[@]} -eq 0 ]]; then
        warn "No sessions found. Creating a new one." >&2
        local name
        name=$(create_session)
        echo "$name"
        return 0
    fi

    list_sessions >&2

    while true; do
        echo -n -e "  ${CYAN}Enter session name (or 'new' to create): ${NC}" >&2
        read -r choice
        if [[ "$choice" == "new" ]]; then
            echo -n -e "  ${CYAN}Session name (blank for auto): ${NC}" >&2
            read -r sname
            local name
            name=$(create_session "$sname")
            echo "$name"
            return 0
        fi
        for s in "${sessions[@]}"; do
            if [[ "$s" == "$choice" ]]; then
                echo "$choice"
                return 0
            fi
        done
        err "Unknown session: ${choice}" >&2
    done
}

resolve_session() {
    local name
    name=$(last_session_name)
    if [[ -z "$name" ]]; then
        log "No previous session. Creating one."
        name=$(create_session)
    else
        log "Resuming session: ${BOLD}${name}${NC}"
    fi
    init_session "$name"
}

# ══════════════════════════════════════════════════════════════════════════════
#  TASK MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

next_id() {
    local id
    id=$(cat "$NEXT_ID_FILE" 2>/dev/null || echo 1)
    echo $((id + 1)) > "$NEXT_ID_FILE"
    printf "%03d" "$id"
}

# Meta file: pid / type / status / prompt
write_meta() {
    local id="$1" pid="$2" type="$3" status="$4" prompt="$5"
    printf '%s\n%s\n%s\n%s\n' "$pid" "$type" "$status" "$prompt" \
        > "${TASK_DIR}/${id}.meta"
}

read_meta() {
    local id="$1" metafile="${TASK_DIR}/${id}.meta"
    [[ -f "$metafile" ]] || return 1
    META_PID=$(sed -n '1p' "$metafile")
    META_TYPE=$(sed -n '2p' "$metafile")
    META_STATUS=$(sed -n '3p' "$metafile")
    META_PROMPT=$(sed -n '4p' "$metafile")
}

set_status() {
    local id="$1" new_status="$2"
    local metafile="${TASK_DIR}/${id}.meta"
    [[ -f "$metafile" ]] || return 1
    local pid type prompt
    pid=$(sed -n '1p' "$metafile")
    type=$(sed -n '2p' "$metafile")
    prompt=$(sed -n '4p' "$metafile")
    write_meta "$id" "$pid" "$type" "$new_status" "$prompt"
}

pid_alive() { kill -0 "$1" 2>/dev/null; }

refresh_statuses() {
    for metafile in "$TASK_DIR"/*.meta; do
        [[ -f "$metafile" ]] || continue
        local id
        id=$(basename "$metafile" .meta)
        read_meta "$id" || continue
        if [[ "$META_STATUS" == "running" ]] && ! pid_alive "$META_PID"; then
            local rc=0
            [[ -f "${TASK_DIR}/${id}.rc" ]] && rc=$(cat "${TASK_DIR}/${id}.rc")
            set_status "$id" "$([[ $rc -eq 0 ]] && echo done || echo failed)"
        fi
    done
}

acquire_write_lock() {
    local id="$1"
    if [[ -f "$WRITE_LOCK" ]]; then
        local lock_pid lock_id
        lock_id=$(sed -n '1p' "$WRITE_LOCK")
        lock_pid=$(sed -n '2p' "$WRITE_LOCK")
        pid_alive "$lock_pid" && return 1
        rm -f "$WRITE_LOCK"
    fi
    printf '%s\n%s\n' "$id" "$$" > "$WRITE_LOCK"
    return 0
}

release_write_lock() { rm -f "$WRITE_LOCK"; }

# ── Dispatch a task to a background Claude agent ────────────────────────────
dispatch_agent() {
    local task="$1"
    local task_type="$2"  # "read" or "write"
    local id
    id=$(next_id)
    local logfile="${TASK_DIR}/${id}.log"
    local session_file="${TASK_DIR}/${id}.session"

    local claude_args=(-p --verbose --dangerously-skip-permissions --output-format stream-json)
    [[ "$task_type" == "read" ]] && claude_args+=(--disallowedTools "Edit,Write,NotebookEdit")
    claude_args+=(-- "$task")

    (
        cd "$WORKSPACE"

        if [[ "$task_type" == "write" ]]; then
            while ! acquire_write_lock "$id"; do sleep 2; done
            set_status "$id" "running"
            printf '%s\n%s\n' "$id" "$$" > "$WRITE_LOCK"
        fi

        # Run claude, pipe stream-json through the processor.
        # Stderr goes directly to log; processed stdout appended to log.
        # PIPESTATUS[0] captures claude's exit code.
        set +e
        claude "${claude_args[@]}" 2>>"$logfile" \
            | python3 "$STREAM_PROCESSOR" "$session_file" >> "$logfile"
        local claude_rc=${PIPESTATUS[0]}
        set -e

        echo "$claude_rc" > "${TASK_DIR}/${id}.rc"

        [[ "$task_type" == "write" ]] && release_write_lock
        exit "$claude_rc"
    ) &
    local bg_pid=$!

    local initial_status="running"
    if [[ "$task_type" == "write" && -f "$WRITE_LOCK" ]]; then
        local lock_id
        lock_id=$(sed -n '1p' "$WRITE_LOCK" 2>/dev/null || echo "")
        [[ -n "$lock_id" && "$lock_id" != "$id" ]] && initial_status="queued"
    fi

    write_meta "$id" "$bg_pid" "$task_type" "$initial_status" "$task"
    touch_session

    local type_label
    [[ "$task_type" == "read" ]] \
        && type_label="${DIM}read-only${NC}" \
        || type_label="${YELLOW}write${NC}"

    if [[ "$initial_status" == "queued" ]]; then
        log "  [${BOLD}${id}${NC}] ${type_label} — queued (write agent running)"
    else
        log "  [${BOLD}${id}${NC}] ${type_label} — dispatched"
    fi
    log "  ${DIM}${task}${NC}"
}

# ── Verify Claude CLI is available ──────────────────────────────────────────
preflight_check() {
    if ! command -v claude &>/dev/null; then
        err "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
        exit 1
    fi
    mkdir -p "$DATA_DIR"
    write_stream_processor
}

# ── Status display ───────────────────────────────────────────────────────────
show_status() {
    refresh_statuses

    local session_name
    session_name=$(basename "$SESSION_DIR")
    echo ""
    echo -e "  ${BOLD}Session: ${session_name}${NC}"

    local found=false
    printf "\n  ${BOLD}%-5s %-9s %-7s %-8s %s${NC}\n" \
        "ID" "STATUS" "TYPE" "SESSION" "PROMPT"
    printf "  %-5s %-9s %-7s %-8s %s\n" \
        "───" "────────" "──────" "───────" "──────────────────────────"

    for metafile in "$TASK_DIR"/*.meta; do
        [[ -f "$metafile" ]] || continue
        found=true
        local id
        id=$(basename "$metafile" .meta)
        read_meta "$id" || continue

        local status_color="$NC"
        case "$META_STATUS" in
            running) status_color="$CYAN"   ;;
            done)    status_color="$GREEN"  ;;
            failed)  status_color="$RED"    ;;
            queued)  status_color="$YELLOW" ;;
        esac

        # Indicate if task has a resumable session
        local has_session="no"
        [[ -f "${TASK_DIR}/${id}.session" && -s "${TASK_DIR}/${id}.session" ]] \
            && has_session="${GREEN}yes${NC}"

        local short_prompt="${META_PROMPT:0:46}"
        [[ ${#META_PROMPT} -gt 46 ]] && short_prompt="${short_prompt}…"

        printf "  %-5s ${status_color}%-9s${NC} %-7s %-8b %s\n" \
            "$id" "$META_STATUS" "$META_TYPE" "$has_session" "$short_prompt"
    done

    $found || echo "  (no tasks)"
    echo ""
}

# ── Show logs ────────────────────────────────────────────────────────────────
show_logs() {
    local id="$1"
    local logfile="${TASK_DIR}/${id}.log"
    [[ -f "$logfile" ]] || { err "No log for task ${id}"; return 1; }
    echo ""
    echo -e "  ${BOLD}── logs for task ${id} ──${NC}"
    cat "$logfile"
    echo -e "  ${BOLD}── end ──${NC}"
    echo ""
}

# ── Attach to a running task (live tail, Ctrl+C to detach) ──────────────────
attach_task() {
    local id="$1"
    read_meta "$id" || { err "Unknown task: ${id}"; return 1; }

    local logfile="${TASK_DIR}/${id}.log"
    [[ -f "$logfile" ]] || { err "No log for task ${id}"; return 1; }

    if [[ "$META_STATUS" != "running" && "$META_STATUS" != "queued" ]]; then
        # Already done — just show the log
        show_logs "$id"
        return 0
    fi

    log "Attaching to task ${id} — Ctrl+C to detach (task keeps running)."
    echo ""

    tail -f "$logfile" &
    local tail_pid=$!

    local detached=false
    # Temporarily override INT to detach instead of triggering full cleanup
    trap 'detached=true' INT

    while ! $detached; do
        read_meta "$id" 2>/dev/null || break
        if [[ "$META_STATUS" != "running" && "$META_STATUS" != "queued" ]]; then
            break
        fi
        pid_alive "$META_PID" || break
        sleep 0.5
    done

    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    trap - INT   # restore default

    echo ""
    if $detached; then
        log "Detached. Task ${id} still running — use 'attach ${id}' to reconnect."
    else
        refresh_statuses
        read_meta "$id" 2>/dev/null || true
        ok "Task ${id} finished (${META_STATUS:-unknown})."
    fi
}

# ── Resume a completed task interactively ───────────────────────────────────
resume_task() {
    local id="$1"
    read_meta "$id" || { err "Unknown task: ${id}"; return 1; }

    if [[ "$META_STATUS" == "running" || "$META_STATUS" == "queued" ]]; then
        warn "Task ${id} is still running — use 'attach ${id}' to follow it live."
        warn "You can resume it after it finishes."
        return 1
    fi

    local session_file="${TASK_DIR}/${id}.session"
    if [[ ! -f "$session_file" || ! -s "$session_file" ]]; then
        err "No session ID saved for task ${id}."
        err "  (Tasks dispatched before session tracking was added cannot be resumed.)"
        return 1
    fi

    local session_id
    session_id=$(cat "$session_file")

    log "Resuming task ${id} — session: ${DIM}${session_id}${NC}"
    log "Continue the conversation normally. Type /exit to return to the orchestrator."
    echo ""

    # Run interactive claude session — takes over stdin/stdout until user exits.
    # The EXIT trap on the orchestrator will NOT fire here; it fires when the
    # orchestrator itself exits, not when this child process returns.
    claude --resume "$session_id" --dangerously-skip-permissions

    echo ""
    log "Returned from session for task ${id}."
}

# ── Wait for task(s) ─────────────────────────────────────────────────────────
wait_for_tasks() {
    local target_id="${1:-}"
    local interrupted=false
    trap 'interrupted=true' INT

    if [[ -n "$target_id" ]]; then
        read_meta "$target_id" || { trap - INT; err "Unknown task: ${target_id}"; return 1; }
        if [[ "$META_STATUS" == "done" || "$META_STATUS" == "failed" ]]; then
            trap - INT
            ok "Task ${target_id} already finished (${META_STATUS})."
            return 0
        fi
        log "Waiting for task ${target_id}... (Ctrl+C to stop waiting)"
        while ! $interrupted && pid_alive "$META_PID"; do sleep 1; done
        trap - INT
        if $interrupted; then
            log "Stopped waiting. Task ${target_id} still running."
        else
            refresh_statuses; read_meta "$target_id"
            ok "Task ${target_id} finished (${META_STATUS})."
        fi
    else
        log "Waiting for all tasks... (Ctrl+C to stop waiting)"
        local any_running=true
        while ! $interrupted && $any_running; do
            any_running=false
            refresh_statuses
            for metafile in "$TASK_DIR"/*.meta; do
                [[ -f "$metafile" ]] || continue
                local id
                id=$(basename "$metafile" .meta)
                read_meta "$id" || continue
                if [[ "$META_STATUS" == "running" || "$META_STATUS" == "queued" ]]; then
                    any_running=true; break
                fi
            done
            $any_running && sleep 1
        done
        trap - INT
        if $interrupted; then
            log "Stopped waiting. Tasks still running in background."
        else
            ok "All tasks finished."
        fi
    fi
}

# ── Kill a task ──────────────────────────────────────────────────────────────
kill_task() {
    local id="$1"
    read_meta "$id" || { err "Unknown task: ${id}"; return 1; }

    if [[ "$META_STATUS" != "running" && "$META_STATUS" != "queued" ]]; then
        warn "Task ${id} is not running (status: ${META_STATUS})."
        return 0
    fi

    if pid_alive "$META_PID"; then
        kill "$META_PID" 2>/dev/null || true
        pkill -P "$META_PID" 2>/dev/null || true
    fi
    set_status "$id" "failed"

    if [[ "$META_TYPE" == "write" && -f "$WRITE_LOCK" ]]; then
        local lock_id
        lock_id=$(sed -n '1p' "$WRITE_LOCK" 2>/dev/null || echo "")
        [[ "$lock_id" == "$id" ]] && release_write_lock
    fi

    ok "Killed task ${id}."
}

# ── Parallel mode ────────────────────────────────────────────────────────────
run_parallel() {
    local taskfile="$1"
    [[ -f "$taskfile" ]] || { err "Task file not found: $taskfile"; exit 1; }

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == edit:* ]]; then
            local prompt="${line#edit:}"; prompt="${prompt# }"
            dispatch_agent "$prompt" "write"
        else
            dispatch_agent "$line" "read"
        fi
    done < "$taskfile"

    wait_for_tasks
}

# ── Interactive REPL ─────────────────────────────────────────────────────────
interactive_repl() {
    local session_name
    session_name=$(basename "$SESSION_DIR")
    log "z6m Orchestrator – Session: ${BOLD}${session_name}${NC}"
    log "Tasks run in background. Type 'help' for commands."
    echo ""

    trap 'cleanup_on_exit' TERM

    while true; do
        refresh_statuses

        # Ctrl+C during prompt just cancels the current line and loops back.
        trap '' INT
        echo -n -e "${CYAN}z6m> ${NC}"
        if ! read -r input; then
            # EOF (Ctrl+D) — exit the REPL
            echo ""
            break
        fi
        trap - INT
        [[ -z "$input" ]] && continue

        # Normalise id argument: strip leading zeros for arithmetic, re-pad to 3
        norm_id() { printf "%03d" "$((10#${1}))" 2>/dev/null || echo "$1"; }

        case "$input" in
            quit|exit) break ;;

            help)
                echo ""
                echo -e "  ${BOLD}Task commands:${NC}"
                echo "  <prompt>              dispatch read-only agent (parallel)"
                echo "  edit: <prompt>        dispatch write agent (serialized)"
                echo "  list                  show all tasks (SESSION col = resumable)"
                echo "  logs <id>             show full output of a task"
                echo "  attach <id>           stream live output (Ctrl+C to detach)"
                echo "  resume <id>           open interactive session to continue a task"
                echo "  wait [id]             block until task(s) finish"
                echo "  kill <id>             kill a running task"
                echo ""
                echo -e "  ${BOLD}Session commands:${NC}"
                echo "  session               show current session info"
                echo "  sessions              list all sessions"
                echo ""
                echo "  help / quit (drops to shell)"
                echo ""
                ;;

            list|status) show_status ;;

            session)
                echo ""
                local sname created last_used task_count
                sname=$(basename "$SESSION_DIR")
                created=$(sed -n '1p'  "${SESSION_DIR}/.meta" 2>/dev/null || echo "?")
                last_used=$(sed -n '2p' "${SESSION_DIR}/.meta" 2>/dev/null || echo "?")
                task_count=$(find "$TASK_DIR" -name "*.meta" 2>/dev/null | wc -l)
                created=$(date  -d "$created"  '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$created")
                last_used=$(date -d "$last_used" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$last_used")
                echo -e "  ${BOLD}Session:${NC}    $sname"
                echo -e "  ${BOLD}Created:${NC}    $created"
                echo -e "  ${BOLD}Last used:${NC}  $last_used"
                echo -e "  ${BOLD}Tasks:${NC}      $task_count"
                echo -e "  ${BOLD}Data dir:${NC}   $SESSION_DIR"
                echo ""
                ;;

            sessions) list_sessions ;;

            logs\ *)    show_logs   "$(norm_id "${input#logs }")"   ;;
            attach\ *)  attach_task "$(norm_id "${input#attach }")" ;;
            resume\ *)  resume_task "$(norm_id "${input#resume }")" ;;
            wait)       wait_for_tasks ;;
            wait\ *)    wait_for_tasks "$(norm_id "${input#wait }")" ;;
            kill\ *)    kill_task   "$(norm_id "${input#kill }")"   ;;

            edit:\ *|edit:*)
                local prompt="${input#edit:}"; prompt="${prompt# }"
                [[ -z "$prompt" ]] && { err "Usage: edit: <prompt>"; continue; }
                dispatch_agent "$prompt" "write"
                ;;

            *)  dispatch_agent "$input" "read" ;;
        esac
    done
}

# ── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup_on_exit() {
    rm -f "$STREAM_PROCESSOR"
    refresh_statuses
    local running=0
    for metafile in "$TASK_DIR"/*.meta; do
        [[ -f "$metafile" ]] || continue
        local id
        id=$(basename "$metafile" .meta)
        read_meta "$id" || continue
        [[ "$META_STATUS" == "running" || "$META_STATUS" == "queued" ]] && ((running++))
    done

    if [[ $running -gt 0 ]]; then
        warn "Killing ${running} running task(s)..."
        for metafile in "$TASK_DIR"/*.meta; do
            [[ -f "$metafile" ]] || continue
            local id
            id=$(basename "$metafile" .meta)
            read_meta "$id" || continue
            if [[ "$META_STATUS" == "running" || "$META_STATUS" == "queued" ]]; then
                kill "$META_PID" 2>/dev/null || true
                pkill -P "$META_PID" 2>/dev/null || true
            fi
        done
    fi

    release_write_lock
    ok "Bye!"
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════
main() {
    preflight_check

    case "${1:-}" in
        new)
            shift
            local name
            name=$(create_session "${1:-}")
            init_session "$name"
            interactive_repl
            cleanup_on_exit
            log "Dropping to shell. Run 'orchestrator' to re-enter."
            exec bash
            ;;
        --list)
            local name
            name=$(pick_session)
            init_session "$name"
            interactive_repl
            cleanup_on_exit
            log "Dropping to shell. Run 'orchestrator' to re-enter."
            exec bash
            ;;
        --parallel)
            shift
            resolve_session
            run_parallel "${1:?Usage: orchestrator --parallel <taskfile>}"
            ;;
        "")
            resolve_session
            interactive_repl
            cleanup_on_exit
            log "Dropping to shell. Run 'orchestrator' to re-enter."
            exec bash
            ;;
        *)
            resolve_session
            dispatch_agent "$*" "read"
            wait_for_tasks
            local latest
            latest=$(ls -t "$TASK_DIR"/*.log 2>/dev/null | head -1)
            [[ -n "$latest" ]] && cat "$latest"
            ;;
    esac
}

main "$@"
