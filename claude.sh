#!/usr/bin/env bash
# Container launcher for a claude-env instance.
#
# On Linux: uses systemd-nspawn (fast, uses host nix-daemon directly).
# On macOS: uses Docker (cross-builds the image via nixos/nix container).
#
# systemd-nspawn and the stale-machine cleanup below require sudo. Suggested
# sudoers lines (see readme.md, "Sudoers rules for the launcher"):
#     YOUR_USER ALL=(root) NOPASSWD: /run/current-system/sw/bin/systemd-nspawn
#     YOUR_USER ALL=(root) NOPASSWD: /run/current-system/sw/bin/systemctl reset-failed machine-*.scope
#     YOUR_USER ALL=(root) NOPASSWD: /run/current-system/sw/bin/systemctl stop machine-*.scope
#     YOUR_USER ALL=(root) NOPASSWD: /run/current-system/sw/bin/machinectl terminate *

set -xe

if [ -z "$1" ]; then
    echo "Error: Instance name required."
    echo "Usage: $0 <instance_name> [--vanilla] [--agent claude|opencode] [--model provider/model]"
    exit 1
fi

INSTANCE_NAME="$1"
shift

# The machine the instance runs on, passed in as $HOSTNAME: the container's
# own hostname is the instance name, and local data (migration databases,
# dumps) lives on this machine's ../vibes/$INSTANCE_NAME, so the tracker
# names both.
HOST_NAME="$(hostname)"

VANILLA=0
AGENT=claude
OPENCODE_MODEL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --vanilla) VANILLA=1 ;;
        --agent)
            shift
            AGENT="${1:?--agent needs a value: claude or opencode}" ;;
        --model)
            shift
            OPENCODE_MODEL="${1:?--model needs a provider/model value, for example openai/gpt-6-astra}" ;;
        *) echo "Error: unknown argument '$1'"; exit 1 ;;
    esac
    shift
done

# Decision: the harness is a launcher flag (`--agent opencode`) on the same
# instance name, not a separate launcher script. Everything else about an
# instance (container, vibes clone, character, GitHub bot, ssh key, MCP
# servers) is harness-independent, and opencode reads ~/.claude/CLAUDE.md
# (through `instructions` in its config) and ~/.claude/skills, so the
# existing config mounts carry over unchanged. Alternative considered: a copy
# of this script per harness. Rejected: the nspawn/docker plumbing is the
# bulk of the file and would drift. Only the final command, opencode's config
# file and its state directory differ. `codex` (the OpenAI CLI) is not wired:
# Jappie prefers opencode for the experiment.
case "$AGENT" in
    claude|opencode) ;;
    *) echo "Error: unknown agent '$AGENT' (expected claude or opencode)"; exit 1 ;;
esac

if [ -n "$OPENCODE_MODEL" ] && [ "$AGENT" != opencode ]; then
    echo "Error: --model configures OpenCode. Add --agent opencode or remove --model."
    exit 1
fi

# shellcheck source=agent-command.sh
. "$(pwd)/agent-command.sh"
set_agent_command "$AGENT" "$VANILLA"

mkdir -p "../vibes/$INSTANCE_NAME"

# Decision: shared read-only "aanleveringen" (client deliveries) inbox, mounted
# into every instance at /home/claude/aanleveringen. Chosen as a single fixed
# absolute host path ($HOME/aanleveringen) rather than a sibling of the
# per-instance ../vibes/<name> dirs, because Syncthing (jappeace/linux-config)
# needs a stable absolute path to sync this folder across work-machine,
# lenovo-amd-2022 and lenovo-tablet, and both repos must name the same path.
# The paths line up because claude.sh runs on the host as jappie, so $HOME
# here is /home/jappie, matching the /home/jappie/aanleveringen the Syncthing
# config hard-codes.
# Read-only into the instance: files arrive host-side via Syncthing (merchant
# uploads from Elizabeth/kruidje and Ellen/waardegebaar), instances only read.
# Alternative considered: a per-instance writable share, rejected so a runaway
# instance cannot corrupt the synced source of truth.
AANLEVERINGEN_DIR="$HOME/aanleveringen"
mkdir -p "$AANLEVERINGEN_DIR"

INSTANCE_DIR="$(pwd)/instances/$INSTANCE_NAME"
INSTANCE_JSON="$(pwd)/instances/${INSTANCE_NAME}.json"

# Decision: opencode keeps its state (auth.json with the ChatGPT OAuth
# token, the session database, logs) under ~/.local/share/opencode. It is
# persisted per instance in instances/<name>-opencode, a sibling of
# instances/<name>, and not inside it: instances/<name> is bind-mounted as
# ~/.claude, so anything placed there would surface in Claude Code's state
# directory. The directory is created even for --agent claude so a later
# switch finds it in place.
OPENCODE_DATA_DIR="$(pwd)/instances/${INSTANCE_NAME}-opencode"
mkdir -p "$OPENCODE_DATA_DIR"

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
MCP_CONFIG='{"playwright":{"command":"playwright-mcp","args":["--headless","--no-sandbox","--isolated","--ignore-https-errors","--executable-path","/usr/local/bin/chromium"]},"hoogle":{"command":"mcp-hoogle","args":["serve"]},"tmux":{"command":"tmux-mcp-rs","args":[]}}'
UPDATED_JSON=$(jq --argjson mcp "$MCP_CONFIG" 'del(.mcpServers) | .mcpServers = $mcp | if .projects then .projects |= map_values(del(.mcpServers)) else . end' "$INSTANCE_JSON")
echo "$UPDATED_JSON" > "$INSTANCE_JSON"

# Decision: opencode's own models.dev fetch is disabled
# (OPENCODE_DISABLE_MODELS_FETCH=1) and the catalogue is the file nix bakes
# into the image at /etc/opencode/models.json (OPENCODE_MODELS_PATH), see
# modelsDev in default.nix. Observed on lenovo-tablet (2026-09-12): the TUI
# died at startup with "Failed to fetch models.dev: Refusing to release:
# lock is compromised (metadata missing)". The forked background refresh in
# opencode 1.x (packages/core/src/models-dev.ts + util/flock.ts) takes a file
# lock, and a failed release there is an Effect defect that disposes the
# whole instance; the same code is `orDie` on the network fetch, so no
# route to models.opencode.ai kills it the same way. With the refresh
# disabled no lock is taken and no network is needed at startup. Both
# variables are passed on the launcher side rather than baked into the
# image's environment because nspawn's --setenv list replaces the
# environment wholesale (same reason as the nix-path note in default.nix).
OPENCODE_MODELS_ENV=("OPENCODE_DISABLE_MODELS_FETCH=1" "OPENCODE_MODELS_PATH=/etc/opencode/models.json")

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
        cp -a "$(pwd)/docs" "$CONFIG_SNAPSHOT/docs"
        CONFIG_MOUNTS+=("-v" "$CONFIG_SNAPSHOT/CLAUDE.md:/home/claude/.claude/CLAUDE.md")
        CONFIG_MOUNTS+=("-v" "$CONFIG_SNAPSHOT/skills:/home/claude/.claude/skills")
        CONFIG_MOUNTS+=("-v" "$CONFIG_SNAPSHOT/docs:/home/claude/.claude/docs:ro")
    fi

    # Harness-specific mounts: opencode's read-only config and its state dir.
    # opencode treats its working directory as the project; the docker image's
    # WorkingDir is already /home/claude (see the nspawn note on why not the
    # vibes clone).
    AGENT_MOUNTS=()
    if [ "$AGENT" = "opencode" ]; then
        write_opencode_config "$CONFIG_SNAPSHOT" "$MCP_CONFIG" "$OPENCODE_MODEL"
        AGENT_MOUNTS+=("-v" "$CONFIG_SNAPSHOT/opencode.json:/home/claude/.config/opencode/opencode.json:ro")
        AGENT_MOUNTS+=("-v" "$OPENCODE_DATA_DIR:/home/claude/.local/share/opencode")
        for models_var in "${OPENCODE_MODELS_ENV[@]}"; do
            AGENT_MOUNTS+=("-e" "$models_var")
        done
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
        -e HOSTNAME="$HOST_NAME" \
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
        "${AGENT_MOUNTS[@]}" \
        -v "$(pwd)/../vibes/$INSTANCE_NAME":/home/claude/vibes \
        `# shared read-only client-deliveries inbox, synced by Syncthing host-side` \
        -v "$AANLEVERINGEN_DIR":/home/claude/aanleveringen:ro \
        `# character is snapshotted (above) and mounted even in vanilla mode` \
        -v "$CONFIG_SNAPSHOT/character":/home/claude/character \
        --rm \
        claude-env:latest \
        "${AGENT_COMMAND[@]}"
}

# ---------------------------------------------------------------------------
# Stale machine cleanup (Linux/nspawn)
# ---------------------------------------------------------------------------
# Decision: clear leftover systemd state before launching instead of letting
# systemd-nspawn fail with "Machine '<name>' already exists" and making the
# user retry. An unclean exit (Ctrl-C, closed terminal, host kill) leaves two
# kinds of debris behind even though no container is running anymore:
#   1. machine-<name>.scope stuck in systemd's "failed" state, and
#   2. a systemd-machined registration whose teardown is still in flight.
# Alternatives considered: --keep-unit (changes the cgroup layout for no
# gain) and documenting `machinectl terminate` as a manual fixup (that manual
# retry is exactly the annoyance this removes). A machine whose leader
# process is still alive is genuinely running: refuse to double-launch it
# rather than killing it. Liveness is checked via /proc/<leader>, not
# `kill -0`, because the leader is root-owned and kill -0 from the invoking
# user reports EPERM, which would misread a live machine as dead.
clear_stale_machine() {
    MACHINE_SCOPE="machine-${INSTANCE_NAME}.scope"

    if systemctl is-failed --quiet "$MACHINE_SCOPE"; then
        sudo systemctl reset-failed "$MACHINE_SCOPE"
    fi

    if ! machinectl show "$INSTANCE_NAME" > /dev/null 2>&1; then
        return 0
    fi

    # Leader is a uint32 PID on the D-Bus machine object; it serializes to
    # "0" when unset, so 0 means "no leader recorded", not pid 0.
    LEADER_PID=$(machinectl show "$INSTANCE_NAME" --property=Leader --value)
    if [ -n "$LEADER_PID" ] && [ "$LEADER_PID" != "0" ] && [ -d "/proc/$LEADER_PID" ]; then
        echo "Error: instance '$INSTANCE_NAME' is already running (leader pid $LEADER_PID)." >&2
        echo "Stop it first with: sudo machinectl terminate $INSTANCE_NAME" >&2
        exit 1
    fi

    # The registration is stale (leader gone). Tear it down and wait for
    # machined to drop it so the launch below cannot race the cleanup.
    # terminate can itself fail when machined drops the record between the
    # check above and this call; the poll below is the real verification.
    sudo machinectl terminate "$INSTANCE_NAME" || sudo systemctl stop "$MACHINE_SCOPE" || true
    for _ in $(seq 1 30); do
        if ! machinectl show "$INSTANCE_NAME" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "Error: machine '$INSTANCE_NAME' is still registered after 30s of cleanup." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# systemd-nspawn backend (Linux)
# ---------------------------------------------------------------------------
launch_nspawn() {
    clear_stale_machine
    NIX_ARGS_ARRAY=(./default.nix --arg uid "$(id -u)" --arg gid "$(id -g)")

    # Build the rootfs env and the entrypoint script, keeping the result
    # symlinks as GC roots under gcroots/ instead of passing --no-out-link.
    # Without a root the closure is unreferenced the instant nix-build returns,
    # so a `nix-collect-garbage` from any instance deletes the toolchain out
    # from under every running machine: a GC run inside a container only sees
    # its own /proc, not the other containers' live processes, so their
    # binaries look unreferenced and get collected, leaving dangling /bin/git
    # and friends. The roots live in the checkout (not /tmp) so they survive
    # reboots and re-launches, and nix-build still prints the store path to
    # stdout so ENV_PATH/ENTRYPOINT_PATH are unchanged. Re-launching an instance
    # overwrites its own root; only distinct instance names accumulate roots.
    GCROOTS_DIR="$(pwd)/gcroots"
    mkdir -p "$GCROOTS_DIR"
    ENV_PATH=$(nix-build "${NIX_ARGS_ARRAY[@]}" -A env --out-link "$GCROOTS_DIR/${INSTANCE_NAME}-env")
    ENTRYPOINT_PATH=$(nix-build "${NIX_ARGS_ARRAY[@]}" -A entrypoint --out-link "$GCROOTS_DIR/${INSTANCE_NAME}-entrypoint")

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
        "$RUNTIME_ROOT/home/claude/aanleveringen" \
        "$RUNTIME_ROOT/home/claude/character" \
        "$RUNTIME_ROOT/home/claude/.config/opencode" \
        "$RUNTIME_ROOT/home/claude/.local/share/opencode"
    touch "$RUNTIME_ROOT/home/claude/.claude.json"
    touch "$RUNTIME_ROOT/home/claude/.config/opencode/opencode.json"

    # Snapshot configuration outside the rootfs so host checkouts cannot change
    # a running session's instructions or referenced docs. Character is included
    # in vanilla mode too; the Stop gate binary comes from the image.
    CONFIG_SNAPSHOT="/tmp/claude-config.${INSTANCE_NAME}.$$"
    mkdir -p "$CONFIG_SNAPSHOT"
    cp -a "$(pwd)/character" "$CONFIG_SNAPSHOT/character"

    # Cleanup is best-effort. If nspawn left a mount-point dir or a root-owned
    # entry we can't reach, leave it; /tmp clears on reboot anyway.
    trap 'rm -rf "$RUNTIME_ROOT" "$CONFIG_SNAPSHOT" 2>/dev/null || true' EXIT

    # Vanilla mode skips the project's CLAUDE.md, docs and skills mounts.
    CONFIG_BINDS=()
    if [ "$VANILLA" -eq 0 ]; then
        cp -a "$(pwd)/CLAUDE.md" "$CONFIG_SNAPSHOT/CLAUDE.md"
        cp -a "$(pwd)/skills" "$CONFIG_SNAPSHOT/skills"
        cp -a "$(pwd)/docs" "$CONFIG_SNAPSHOT/docs"
        CONFIG_BINDS+=("--bind-ro=$CONFIG_SNAPSHOT/CLAUDE.md:/home/claude/.claude/CLAUDE.md")
        CONFIG_BINDS+=("--bind-ro=$CONFIG_SNAPSHOT/skills:/home/claude/.claude/skills")
        CONFIG_BINDS+=("--bind-ro=$CONFIG_SNAPSHOT/docs:/home/claude/.claude/docs")
    fi

    # Harness-specific binds: opencode's read-only config and its state dir.
    # The ChatGPT login (/connect in the TUI) opens a browser URL and waits
    # for a localhost callback; nspawn shares the host network namespace
    # here (no --private-network), so opening the URL in the host browser
    # completes the login inside the container.
    # Decision: opencode gets --chdir=/home/claude; claude keeps nspawn's
    # default cwd "/" because Claude Code keys its per-project memory on the
    # cwd and moving it would orphan every instance's memory. opencode treats
    # the cwd as its project: "/" made it index the container root (seen in
    # the ryan log as directory=/), and /home/claude/vibes was tried first
    # but its project scan over the whole clone tree hung a prompt for >90s
    # in a test. The home dir bootstraps in under a second; opencode logs a
    # warning that its file picker skips home directories, which is fine.
    # The agent cds into a repo under ~/vibes itself, or is given one as
    # `opencode <project>`.
    AGENT_BINDS=()
    if [ "$AGENT" = "opencode" ]; then
        write_opencode_config "$CONFIG_SNAPSHOT" "$MCP_CONFIG" "$OPENCODE_MODEL"
        AGENT_BINDS+=("--bind-ro=$CONFIG_SNAPSHOT/opencode.json:/home/claude/.config/opencode/opencode.json")
        AGENT_BINDS+=("--bind=$OPENCODE_DATA_DIR:/home/claude/.local/share/opencode")
        AGENT_BINDS+=("--chdir=/home/claude")
        for models_var in "${OPENCODE_MODELS_ENV[@]}"; do
            AGENT_BINDS+=("--setenv=$models_var")
        done
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
    # --system-call-filter=perf_event_open lets `perf stat/record` work
    # inside the instance (nspawn's default seccomp filter blocks the
    # syscall, which reduced the 1br performance hunt to ablation
    # guesswork). kernel.perf_event_paranoid still applies on top, so
    # this only enables self-profiling, not system-wide snooping.
    # (No `exec sudo …` — we want the EXIT trap to run after nspawn returns.)
    sudo systemd-nspawn \
        --machine="$INSTANCE_NAME" \
        --hostname="$INSTANCE_NAME" \
        --directory="$RUNTIME_ROOT" \
        --as-pid2 \
        --system-call-filter=perf_event_open \
        --resolv-conf=bind-host \
        --bind=/nix \
        --bind="$INSTANCE_JSON:/home/claude/.claude.json" \
        --bind="$INSTANCE_DIR:/home/claude/.claude" \
        --bind="$(pwd)/settings.json:/home/claude/.claude/settings.json" \
        "${CONFIG_BINDS[@]}" \
        "${AGENT_BINDS[@]}" \
        --bind="$(pwd)/../vibes/$INSTANCE_NAME:/home/claude/vibes" \
        `# shared read-only client-deliveries inbox, synced by Syncthing host-side` \
        --bind-ro="$AANLEVERINGEN_DIR:/home/claude/aanleveringen" \
        `# character is snapshotted (above) and mounted even in vanilla mode` \
        --bind-ro="$CONFIG_SNAPSHOT/character:/home/claude/character" \
        --bind-ro="$HOME/.ssh/sloth:/home/claude/.ssh/id_ed25519" \
        --tmpfs=/tmp:rw,mode=1777 \
        --setenv=INSTANCE_NAME="$INSTANCE_NAME" \
        --setenv=HOSTNAME="$HOST_NAME" \
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
        "$ENTRYPOINT_PATH" "${AGENT_COMMAND[@]}"
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
