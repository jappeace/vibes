#!/usr/bin/env bash
# Container launcher for a claude-env instance.
#
# On Linux: uses systemd-nspawn (fast, uses host nix-daemon directly).
# On macOS: uses Docker (cross-builds the image via nixos/nix container).
#
# systemd-nspawn requires sudo — suggested sudoers line:
#     YOUR_USER ALL=(root) NOPASSWD: /run/current-system/sw/bin/systemd-nspawn

set -xe

if [ -z "$1" ]; then
    echo "Error: Instance name required."
    echo "Usage: $0 <instance_name> [--vanilla]"
    exit 1
fi

INSTANCE_NAME="$1"
shift

VANILLA=0
for arg in "$@"; do
    case "$arg" in
        --vanilla) VANILLA=1 ;;
        *) echo "Error: unknown argument '$arg'"; exit 1 ;;
    esac
done

mkdir -p "../vibes/$INSTANCE_NAME"

INSTANCE_DIR="$(pwd)/instances/$INSTANCE_NAME"
INSTANCE_JSON="$(pwd)/instances/${INSTANCE_NAME}.json"

if [ ! -d "$INSTANCE_DIR" ]; then
    mkdir -p "$INSTANCE_DIR"
fi

if [ -e "$INSTANCE_JSON" ] && [ ! -f "$INSTANCE_JSON" ]; then
    rm -rf "$INSTANCE_JSON"
fi

if [ ! -f "$INSTANCE_JSON" ]; then
    echo "{}" > "$INSTANCE_JSON"
fi

# Claude Code reads MCP servers from ~/.claude.json (not settings.json).
# Clear any stale per-project entries Claude Code writes during sessions.
#
# playwright is a shared HTTP sidecar (started in the entrypoints, see
# default.nix playwrightSidecar) rather than a per-process stdio spawn, so the
# main agent and the nested gate critics share one warm browser on
# 127.0.0.1:9223. Keep that port in sync with default.nix and the entrypoints.
# If a Claude Code version rejects "type":"http", the server also serves legacy
# SSE at /sse ("type":"sse","url":"http://127.0.0.1:9223/sse").
MCP_CONFIG='{"playwright":{"type":"http","url":"http://127.0.0.1:9223/mcp"},"hoogle":{"command":"mcp-hoogle","args":["serve"]},"tmux":{"command":"tmux-mcp-rs","args":[]}}'
UPDATED_JSON=$(jq --argjson mcp "$MCP_CONFIG" 'del(.mcpServers) | .mcpServers = $mcp | if .projects then .projects |= map_values(del(.mcpServers)) else . end' "$INSTANCE_JSON")
echo "$UPDATED_JSON" > "$INSTANCE_JSON"

NIX_ARGS="./default.nix --arg uid $(id -u) --arg gid $(id -g)"

# ---------------------------------------------------------------------------
# Docker backend (macOS)
# ---------------------------------------------------------------------------
launch_docker() {
    DOCKER_PLATFORM_ARGS=()

    if [ "$(uname -s)" != "Darwin" ]; then
        # Linux native: build and load normally
        nix-build $NIX_ARGS
        docker load -i "$(nix-build $NIX_ARGS -A image)"
    else
        # macOS: build inside a Linux Nix container
        ARCH=$(uname -m)

        if [ "$ARCH" = "arm64" ]; then
            DOCKER_PLATFORM_ARGS=("--platform" "linux/arm64")
            docker run --rm \
                -v nix-builder-cache:/nix \
                -v "$(pwd):/workspace" -w /workspace nixos/nix \
                sh -c "nix-build $NIX_ARGS -A image > /dev/null && cat result" | docker load
        else
            DOCKER_PLATFORM_ARGS=("--platform" "linux/amd64")
            docker run --platform linux/amd64 --rm \
                   -v nix-builder-cache:/nix \
                   -v "$(pwd):/workspace" -w /workspace nixos/nix \
                sh -c "nix-build $NIX_ARGS -A image > /dev/null && cat result" | docker load
        fi
    fi

    # Mount /dev/kvm only when available (VirtualBox claims it exclusively)
    KVM_ARGS=()
    if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
        KVM_ARGS=("--device" "/dev/kvm")
    fi

    # Optional Reddit credentials
    REDDIT_SECRET_ARGS=()
    if [ -f ~/.reddit_secret ]; then
        REDDIT_SECRET_ARGS=("-e" "REDDIT_USERNAME=jappeace-sloth" "-e" "REDDIT_PASSWORD=$(cat ~/.reddit_secret)")
    fi

    # Private per-launch copy of the read-only config group, mounted instead of
    # the live $(pwd) paths (see launch_nspawn for the rationale). character is
    # mounted even in vanilla mode, so it is always snapshotted.
    CONFIG_SNAPSHOT="/tmp/claude-config.${INSTANCE_NAME}.$$"
    mkdir -p "$CONFIG_SNAPSHOT"
    cp -a "$(pwd)/character" "$CONFIG_SNAPSHOT/character"
    trap 'rm -rf "$CONFIG_SNAPSHOT" 2>/dev/null || true' EXIT

    # Optional configuration mounts (skipped in vanilla mode)
    CONFIG_MOUNTS=()
    if [ "$VANILLA" -eq 0 ]; then
        cp -a "$(pwd)/CLAUDE.md" "$CONFIG_SNAPSHOT/CLAUDE.md"
        cp -a "$(pwd)/skills" "$CONFIG_SNAPSHOT/skills"
        CONFIG_MOUNTS+=("-v" "$CONFIG_SNAPSHOT/CLAUDE.md:/home/claude/.claude/CLAUDE.md")
        CONFIG_MOUNTS+=("-v" "$CONFIG_SNAPSHOT/skills:/home/claude/.claude/skills")
    fi

    docker run -it \
        --name "$INSTANCE_NAME" \
        --hostname "$INSTANCE_NAME" \
        "${DOCKER_PLATFORM_ARGS[@]}" \
        --shm-size=256m \
        --tmpfs /tmp:rw,exec,mode=1777 \
        --init \
        "${KVM_ARGS[@]}" \
        --dns 8.8.8.8 \
        --add-host=host.docker.internal:host-gateway \
        -e NODE_OPTIONS="--dns-result-order=ipv4first" \
        -e INSTANCE_NAME="$INSTANCE_NAME" \
        -e TERM=xterm-256color \
        -e COLORTERM=truecolor \
        -e GH_TOKEN="$(cat ~/.gh_token)" \
        "${REDDIT_SECRET_ARGS[@]}" \
        -e HOME="/home/claude" \
        -e CLAUDE_UID="$(id -u)" \
        -e CLAUDE_GID="$(id -g)" \
        --ulimit nofile=1048576:1048576 \
        --ulimit nproc=65535:65535 \
        -v "$HOME/.ssh/sloth:/home/claude/.ssh/id_ed25519" \
        -v "$HOME/.ssh/sloth:/tmp/builder_key:ro" \
        -v "$(pwd)/instances/${INSTANCE_NAME}.json":/home/claude/.claude.json \
        -v "$(pwd)/instances/${INSTANCE_NAME}":/home/claude/.claude \
        -v "$(pwd)/settings.json":/home/claude/.claude/settings.json \
        "${CONFIG_MOUNTS[@]}" \
        -v "$(pwd)/../vibes/$INSTANCE_NAME":/home/claude/vibes \
        `# character is snapshotted (above) and mounted even in vanilla mode` \
        -v "$CONFIG_SNAPSHOT/character":/home/claude/character \
        --rm \
        claude-env:latest \
        claude
}

# ---------------------------------------------------------------------------
# systemd-nspawn backend (Linux)
# ---------------------------------------------------------------------------
launch_nspawn() {
    NIX_ARGS_ARRAY=(./default.nix --arg uid "$(id -u)" --arg gid "$(id -g)")

    # Build the rootfs env and the entrypoint script.
    ENV_PATH=$(nix-build "${NIX_ARGS_ARRAY[@]}" -A env --no-out-link)
    ENTRYPOINT_PATH=$(nix-build "${NIX_ARGS_ARRAY[@]}" -A entrypoint --no-out-link)

    # systemd-nspawn writes a `.#machine.<hash>` lock file in the parent dir of
    # --directory= before booting. /nix/store is read-only, so we point it at a
    # per-launch copy under /tmp instead. The env is a tree of symlinks into
    # /nix/store, so `cp -a` is cheap and the copy still references the host store
    # at runtime.
    RUNTIME_ROOT="/tmp/claude-rootfs.${INSTANCE_NAME}.$$"
    mkdir -p "$RUNTIME_ROOT"
    cp -a "$ENV_PATH/." "$RUNTIME_ROOT/"

    # /nix/store paths are mode 0555; cp -a preserves that, leaving the copy's
    # directories read-only — we couldn't unlink their entries during cleanup,
    # nor could the container land bind mounts inside them.
    chmod -R u+w "$RUNTIME_ROOT"

    # /home in the env is a symlink into a /nix/store path. Without replacing
    # it, the container's chown of /home/claude follows the symlink through the
    # --bind=/nix mount and modifies the host nix store. Recreate /home as a
    # fresh user-owned tree, with the bind-mount targets pre-made.
    rm -rf "$RUNTIME_ROOT/home"
    mkdir -p \
        "$RUNTIME_ROOT/home/claude/.ssh" \
        "$RUNTIME_ROOT/home/claude/.claude" \
        "$RUNTIME_ROOT/home/claude/vibes" \
        "$RUNTIME_ROOT/home/claude/character"
    touch "$RUNTIME_ROOT/home/claude/.claude.json"

    # Snapshot the read-only config group (CLAUDE.md, skills, character) into a
    # private per-launch copy and mount THOSE, instead of binding the live
    # $(pwd) paths. Those dirs are shared by every machine launched from this
    # checkout and can be emptied or changed on the host mid-session (a git
    # checkout, another instance): a swapped CLAUDE.md/skills/character changes
    # behaviour underfoot. The snapshot lives outside the rootfs so the agent
    # cannot reach it to edit its own config. The Stop gate itself is no longer
    # mounted: it is the vibes-gate binary baked into the image (see
    # default.nix), so it cannot be disabled by a vanished mount. character is
    # mounted even in vanilla mode, so it is always snapshotted.
    CONFIG_SNAPSHOT="/tmp/claude-config.${INSTANCE_NAME}.$$"
    mkdir -p "$CONFIG_SNAPSHOT"
    cp -a "$(pwd)/character" "$CONFIG_SNAPSHOT/character"

    # Cleanup is best-effort. If nspawn left a mount-point dir or a root-owned
    # entry we can't reach, leave it; /tmp clears on reboot anyway.
    trap 'rm -rf "$RUNTIME_ROOT" "$CONFIG_SNAPSHOT" 2>/dev/null || true' EXIT

    # Vanilla mode skips the project's CLAUDE.md, skills and hooks mounts.
    CONFIG_BINDS=()
    if [ "$VANILLA" -eq 0 ]; then
        cp -a "$(pwd)/CLAUDE.md" "$CONFIG_SNAPSHOT/CLAUDE.md"
        cp -a "$(pwd)/skills" "$CONFIG_SNAPSHOT/skills"
        CONFIG_BINDS+=("--bind-ro=$CONFIG_SNAPSHOT/CLAUDE.md:/home/claude/.claude/CLAUDE.md")
        CONFIG_BINDS+=("--bind-ro=$CONFIG_SNAPSHOT/skills:/home/claude/.claude/skills")
    fi

    REDDIT_SETENV=()
    if [ -f ~/.reddit_secret ]; then
        REDDIT_SETENV+=("--setenv=REDDIT_USERNAME=jappeace-sloth")
        REDDIT_SETENV+=("--setenv=REDDIT_PASSWORD=$(cat ~/.reddit_secret)")
    fi

    KVM_BIND=()
    if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
        KVM_BIND=("--bind=/dev/kvm")
    fi

    # --as-pid2 puts systemd-stub at PID 1 so zombies from chromium/playwright
    # get reaped instead of accumulating.
    # --resolv-conf=bind-host shares the host's /etc/resolv.conf.
    # (No `exec sudo …` — we want the EXIT trap to run after nspawn returns.)
    sudo systemd-nspawn \
        --machine="$INSTANCE_NAME" \
        --hostname="$INSTANCE_NAME" \
        --directory="$RUNTIME_ROOT" \
        --as-pid2 \
        --resolv-conf=bind-host \
        --bind=/nix \
        --bind="$INSTANCE_JSON:/home/claude/.claude.json" \
        --bind="$INSTANCE_DIR:/home/claude/.claude" \
        --bind="$(pwd)/settings.json:/home/claude/.claude/settings.json" \
        "${CONFIG_BINDS[@]}" \
        --bind="$(pwd)/../vibes/$INSTANCE_NAME:/home/claude/vibes" \
        `# character is snapshotted (above) and mounted even in vanilla mode` \
        --bind-ro="$CONFIG_SNAPSHOT/character:/home/claude/character" \
        --bind-ro="$HOME/.ssh/sloth:/home/claude/.ssh/id_ed25519" \
        --tmpfs=/tmp:rw,mode=1777 \
        --setenv=INSTANCE_NAME="$INSTANCE_NAME" \
        --setenv=TERM=xterm-256color \
        --setenv=COLORTERM=truecolor \
        --setenv=HOME=/home/claude \
        --setenv=USER=claude \
        --setenv=PATH=/bin:/nix/var/nix/profiles/default/bin \
        --setenv=SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
        --setenv=NODE_OPTIONS=--dns-result-order=ipv4first \
        --setenv=CLAUDE_UID="$(id -u)" \
        --setenv=CLAUDE_GID="$(id -g)" \
        --setenv=GH_TOKEN="$(cat ~/.gh_token)" \
        "${REDDIT_SETENV[@]}" \
        "${KVM_BIND[@]}" \
        "$ENTRYPOINT_PATH" claude
}

# ---------------------------------------------------------------------------
# Dispatch based on OS
# ---------------------------------------------------------------------------
OS_NAME=$(uname -s)

if [ "$OS_NAME" = "Darwin" ]; then
    launch_docker
else
    launch_nspawn
fi
