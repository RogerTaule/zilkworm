# AGENTS.md — z6m Claude Workspace Skill

## Project Overview

**z6m** (zilkworm) is a high-performance Ethereum execution engine with ZK-proving
capabilities. It consists of:

- **zilk_core/** — C++23 core library: EVM execution, state transitions, Merkle
  Patricia Trie (MPT), RLP encoding/decoding, and blockchain data structures.
- **prover/** — Rust workspace for zkVM guest programs and provers (SP1/Hypercube).
- **qemu_runner/** — RISC-V bare-metal runner for QEMU-based testing of the C++ core.
- **third_party/** — Git submodules: evmone, intx, eest-fixtures.

## Repository Layout

```
z6m/
├── CMakeLists.txt          # Top-level CMake (C++23, Ninja)
├── Makefile                # Convenience targets (prover, tests)
├── prover/                 # Rust prover workspace
│   ├── Cargo.toml
│   ├── rust-toolchain.toml # Rust 1.88.0
│   ├── common/             # Shared Rust crate
│   ├── guest_hypercube/    # zkVM guest (rv64)
│   ├── guest_turbo/        # zkVM guest (rv32)
│   ├── prover_hypercube/   # Prover binary (Hypercube)
│   └── prover_turbo/       # Prover binary (Turbo)
├── qemu_runner/            # RISC-V bare-metal QEMU runner
├── zilk_core/              # C++23 core library
│   ├── core/               # Core data structures & EVM
│   └── dev/                # Dev utilities, CLI tools
├── third_party/
│   ├── evmone/             # Fork of evmone (branch: hyper1)
│   │   └── evmc/           # EVM-C interface
│   ├── intx/               # 256-bit integer library
│   └── eest-fixtures/      # Ethereum execution test fixtures
└── tools/claude/           # Dockerfile, orchestrator, entrypoint
```

## Git Submodules

All submodules **must** be initialized before building:

```bash
git submodule update --init --recursive
```

| Submodule     | Path                        | URL                                           | Branch |
| ------------- | --------------------------- | --------------------------------------------- | ------ |
| evmone        | `third_party/evmone`        | `https://github.com/erigontech/zevmone.git`   | hyper1 |
| intx          | `third_party/intx`          | `https://github.com/chfast/intx.git`          | master |
| eest-fixtures | `third_party/eest-fixtures` | `https://github.com/erigontech/eest-fixtures` | main   |
| evmc (nested) | `third_party/evmone/evmc`   | `https://github.com/somnathb1/zevmc.git`      | hyper1 |

## Build Instructions

### C++ Core (zilk_core)

```bash
# Configure
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=/usr/bin/gcc \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# Build all
cmake --build build

# Build specific target
cmake --build build --target state_transition

# Run EEST blockchain tests
cmake -B build/eest -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
    -DTESTS_DIR=third_party/eest-fixtures/blockchain_tests
cmake --build build/eest
ctest --test-dir build/eest --parallel
```

### Rust Prover

```bash
# Build guest (must come first — generates ELF binary for prover)
cd prover/guest_hypercube && cargo prove build

# Build prover
cargo build --release --manifest-path prover/prover_hypercube/Cargo.toml

# Self-test
prover/target/release/z6m_prover execute --is-test \
    --file-name third_party/eest-fixtures/blockchain_tests/static/state_tests/stExample/add11.json
```

## Current Branch

The workspace checks out branch **`mpt_new`** which implements memory-optimized
stateless Merkle tree update (PR #2).

## Coding Conventions

- **C++23** standard, compiled with GCC 14+ or Clang 16+.
- CMake ≥ 3.28 with Ninja generator preferred.
- Rust 1.88.0 (pinned in `prover/rust-toolchain.toml`).
- Follow existing code style in each sub-project.
- Unit tests use CTest (C++) and `cargo test` (Rust).

## Chat Orchestrator

Available at `/usr/local/bin/orchestrator` inside the container. Tasks
dispatch to **background** Claude agents and the prompt returns immediately.

### Task types

| Prefix | Behaviour | Parallelism |
| ------ | --------- | ----------- |
| _(none)_ | Read-only — Edit/Write/NotebookEdit tools disabled | Unlimited parallel |
| `edit:` | Write — full tool access | Serialized (max 1 at a time) |

### Sessions

Sessions persist task logs and metadata to `./temp/orch_sessions/` on the host (mounted
at `/data` in the container). Each session is a named directory containing
its tasks.

```bash
orchestrator                     # resume last session (creates first if none)
orchestrator new [name]          # create a new session
orchestrator --list              # pick a session interactively
```

The `sessions` and `session` REPL commands show session info from within
the REPL.

### REPL commands

```
<prompt>              dispatch read-only agent
edit: <prompt>        dispatch write agent (queued if one is already running)
status                show all tasks in current session
logs <id>             show task output
wait [id]             block until task(s) finish
kill <id>             kill a running task
session               show current session info
sessions              list all sessions with last-used timestamps
help                  show commands
quit                  drop to shell (kills running tasks)
```

### CLI modes

```bash
# Interactive REPL (resumes last session)
orchestrator

# New session
orchestrator new my-feature

# Pick session from list
orchestrator --list

# One-shot (dispatches in last session, waits, prints output)
orchestrator "explain the MPT implementation"

# Parallel from file (one task per line, prefix edit: for write tasks)
orchestrator --parallel tasks.txt
```

Session data is stored at `./temp/orch_sessions/<session-name>/` on the host.

## Authentication

Claude Code auth is passed into the container at runtime (never baked into
the image). Two methods, in order of precedence:

### 1. Subscription credentials (recommended)

Mount your local OAuth credentials file (created by `claude auth login` on
the host) into the container read-only:

```bash
docker run -v ~/.claude/.credentials.json:/tmp/claude-credentials.json:ro ...
```

The helper script `run.sh` does this automatically.

### 2. API key

Pass an API key via environment variable:

```bash
docker run -e ANTHROPIC_API_KEY=sk-ant-... ...
```

## Quick Start

```bash
# Build and launch interactive shell (uses your subscription automatically)
tools/claude/run.sh

# Build and launch the orchestrator
tools/claude/run.sh orchestrator

# One-shot task
tools/claude/run.sh orchestrator "explain the MPT implementation"

# Just build the image
tools/claude/run.sh --build-only
```

## Environment Variables

| Variable            | Purpose                                                         |
| ------------------- | --------------------------------------------------------------- |
| `ANTHROPIC_API_KEY` | API key auth (fallback when subscription credentials not found) |
| `Z6M_AUTO_PULL`     | Set to `1` to auto-pull latest code on container start          |

## Persistent Data (`/data`)

The `/data` directory is a host-mounted volume that **survives container restarts**.
Agents **must** use it to persist work products so nothing is lost when the
container is recreated.

### Directory layout

```
/data/
├── patches/
│   ├── <name>.patch          # current version of each patch
│   ├── <name>.summary.md     # human-readable summary for each patch
│   └── old/                  # superseded versions (auto-rotated)
│       ├── <name>_v001.patch
│       ├── <name>_v001.summary.md
│       └── ...
├── MEMORY.md                 # shared multi-agent coordination file (see below)
└── <session-dir>/            # orchestrator session data (automatic)
```

### Patch & summary workflow

1. When you produce a patch (diff, formatted patch, etc.), write it to
   `/data/patches/<descriptive-name>.patch`.
2. Write a companion `/data/patches/<descriptive-name>.summary.md` with:
   - One-line title
   - What changed and why
   - Files affected
   - Build / test status
3. Before overwriting an existing patch, **rotate** the old version:
   ```bash
   mkdir -p /data/patches/old
   # Find next version number
   n=$(ls /data/patches/old/<name>_v*.patch 2>/dev/null | wc -l)
   ver=$(printf "v%03d" $((n + 1)))
   mv /data/patches/<name>.patch     /data/patches/old/<name>_${ver}.patch
   mv /data/patches/<name>.summary.md /data/patches/old/<name>_${ver}.summary.md
   ```
4. Never delete patches from `old/`.

### MEMORY.md — multi-agent coordination

`/data/MEMORY.md` is a **shared file** that all agents (across tasks and sessions)
can read and write. Use it to coordinate work, avoid duplication, and share
discoveries.

Structure:

```markdown
# Agent Memory

## Current Goals
- <high-level objectives the team is working towards>

## Decisions
- <architectural or design decisions made, with rationale>

## Discoveries
- <important findings about the codebase, bugs, patterns>

## In Progress
- <what is currently being worked on and by which task ID>

## Blocked / Needs Attention
- <items that need human input or are stuck>
```

Rules:
- **Read MEMORY.md at the start of every task** to understand current context.
- **Update it when you finish** — move your item out of "In Progress", record
  decisions or discoveries.
- Keep entries concise (1-2 lines each). Remove stale entries.
- Do not duplicate information already in session task logs.

## Read-Only Host Mounts (`/mnt/`)

When `run.sh` is invoked with directory arguments after `orchestrator` (or `orc`),
those host directories are mounted **read-only** into the container at
`/mnt/<basename>`. For example:

```bash
./run.sh orc /mnt/nodes_wd_8tb/witness_blocks
# → available inside container at /mnt/witness_blocks (read-only)
```

Agents can read files under `/mnt/` but cannot modify them. Use these mounts
to access large datasets, witness blocks, or reference material without copying
them into the workspace.

## Task Execution Protocol

Every time a task is given, follow this exact workflow:

1. **Plan** — Create a plan for the task (scope, approach, risks)
2. **Protocol** — Define the steps, success criteria, and verification method
3. **Summary** — Write a brief summary of what will be done
4. **Persist** — Write the plan+protocol+summary to `./temp/<task_title>.md` in the current working directory
5. **Delegate** — Spin a background subagent (or multiple parallel agents) to execute the plan
6. **Orchestrate** — The main agent thread ONLY tracks progress, reports summaries, and launches follow-up agents. NEVER do file reads/edits/builds inline in the main thread.
7. **Update** — When agents complete, update the task file with results and status

## Agent Guidelines

1. Always verify submodules are initialised before attempting a build.
2. Use `compile_commands.json` (in `build/`) for accurate code intelligence.
3. The C++ code uses deep template metaprogramming — read headers carefully.
4. Test changes with `cmake --build build` before marking tasks complete.
5. For Rust changes, run `cargo check` in the prover workspace first.
6. Persist all patches and summaries to `/data/patches/` (see above).
7. Read `/data/MEMORY.md` before starting work; update it when done.
8. The main conversation thread should be an orchestrator: launch agents, report summaries, merge via agents. Minimize inline file reads/edits in the main thread.
9. NEVER use the main agent chat interface for direct code work — always delegate to subagents.
10. When background agents complete, spin another agent to summarize results and merge code — don't do merges inline.
