# ===========================================================================
#  z6m Claude Agent Workspace – Ubuntu 25.10 (Questing Quokka)
#  Purpose: Provides a fully‑initialised z6m dev environment with Claude Code
#           CLI and a lightweight chat orchestrator, ready for autonomous
#           agent workflows.
#
#  Auth: Mount your Claude config dir at runtime (run.sh does this automatically):
#    docker run -v ~/.claude:/tmp/claude-config:ro ...
# ===========================================================================

FROM ubuntu:25.10

LABEL maintainer="erigontech/z6m"
LABEL description="z6m workspace for Claude Code agents"

# ── 0. Env (root phase – install system packages) ──────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── 1. System packages ─────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential gcc g++ cmake ninja-build pkg-config \
    # C++23 capable compiler (GCC 14 ships in 25.10)
    gcc-14 g++-14 \
    # Version control
    git git-lfs \
    # Networking / fetch
    ca-certificates curl wget \
    # Python (needed by some cmake scripts, conan, etc.)
    python3 python3-pip python3-venv \
    # Misc dev utilities
    jq ripgrep fd-find unzip xz-utils file sudo \
    # Node.js (for Claude Code CLI)
    nodejs npm \
    # Docker entrypoint privilege drop (clean setuid+exec, no PAM/session)
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Set GCC-14 as default
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100

# ── 2. Non-root user ────────────────────────────────────────────────────────
#    Claude CLI refuses --dangerously-skip-permissions as root.
#    We create z6m (UID 1001) as the dev user.  At runtime the entrypoint
#    (which runs as root) remaps z6m's UID to match HOST_UID so files written
#    to mounted directories are owned by the host user.
RUN useradd -m -s /bin/bash z6m && \
    echo "z6m ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/z6m

# ── 3. Rust toolchain (installed as z6m user) ──────────────────────────────
ENV CARGO_HOME=/home/z6m/.cargo \
    RUSTUP_HOME=/home/z6m/.rustup \
    PATH="/home/z6m/.cargo/bin:/home/z6m/.local/bin:${PATH}"

USER z6m
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain 1.88.0 --profile default && \
    rustup component add rustfmt rust-src
USER root

# ── 4. Claude Code CLI ─────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ── 5. Prepare workspace and Claude config ──────────────────────────────────
RUN mkdir -p /home/z6m/.claude/projects && chown -R z6m:z6m /home/z6m/.claude && \
    mkdir -p /workspace && chown z6m:z6m /workspace

WORKDIR /workspace
COPY --chown=z6m:z6m . .

# Quick sanity: CMake expects evmc submodule (.git is a file in nested submodules)
RUN test -e third_party/evmone/evmc/.git

# ── 6. Pre-configure CMake (Debug build, for IDE/agent usage) ──────────────
USER z6m
RUN cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=/usr/bin/gcc \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    || true
# NOTE: `|| true` – a configure failure here should NOT block the image build;
#       an agent can fix and re-run.
USER root

# ── 7. Chat orchestrator wrapper ────────────────────────────────────────────
COPY .claude-workspace/orchestrator.sh /usr/local/bin/orchestrator
RUN chmod +x /usr/local/bin/orchestrator

# ── 8. AGENTS.md skill file (Claude convention) ────────────────────────────
COPY --chown=z6m:z6m .claude-workspace/AGENTS.md /workspace/AGENTS.md

# ── 9. Make workspace and home dir writable by any runtime user ─────────────
#    Supports `docker run --user $(id -u):$(id -g)` so mounted volume files
#    are owned by the host user rather than z6m (UID 1001).
#    - /home/z6m itself: needs o+rx so any UID can enter it
#    - /home/z6m/.claude: fully world-writable (token refresh, session writes)
#    - /workspace: fully world-writable (build output, agent edits)
RUN chmod a+rx /home/z6m && chmod -R a+rwX /home/z6m/.claude /workspace

# ── 10. Entrypoint ─────────────────────────────────────────────────────────
COPY .claude-workspace/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Run as root so the entrypoint can remap z6m's UID to the host user's UID
# before dropping privileges via `gosu z6m`.
USER root
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
