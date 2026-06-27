#!/bin/sh
set -xe

rm -f /nix/var/nix/daemon-socket/socket

mkdir -p /var/log/nix/

# Set up root SSH for nix remote builds to host
# builder-ssh-config is baked into the image at /etc/nix/builder-ssh-config
# builder_key is mounted at runtime (it's a secret)
mkdir -p /root/.ssh
cp /tmp/builder_key /root/.ssh/builder_key
chmod 600 /root/.ssh/builder_key
cp /etc/nix/builder-ssh-config /root/.ssh/config
chmod 600 /root/.ssh/config

(
    export CURL_CA_BUNDLE="/etc/ssl/certs/ca-bundle.crt"
    export PATH="/nix/var/nix/profiles/default/bin:/bin:/usr/bin"
    export HOME="/root"

    echo "Starting Nix daemon in the background..."
    # The Double-Fork Trick: (command &)
    # This orphans the daemon so Docker's init system (PID 1) adopts it and cleans up zombies.
    nix-daemon --daemon >/var/log/nix-daemon.log 2>&1 &
)

# Wait for the daemon to actually create the socket
while [ ! -S /nix/var/nix/daemon-socket/socket ]; do
  sleep 0.1
done

# Open the socket so the unprivileged Claude user can talk to it
chmod 666 /nix/var/nix/daemon-socket/socket

# Nix store makes all paths 0555 (read-only). dockerTools.buildImage preserves
# those permissions in the Docker layer, so build-time chmod is ineffective.
# Fix permissions at runtime where we actually have a writable filesystem.
chown ${CLAUDE_UID}:${CLAUDE_GID} /home/claude
chmod 755 /home/claude

if ! grep -q "x:${CLAUDE_UID}:" /etc/passwd; then
    echo "claude:x:${CLAUDE_UID}:${CLAUDE_GID}:Claude User:/home/claude:/bin/sh" >> /etc/passwd
fi

echo "Nix daemon is live. Dropping privileges..."

# Start the shared Playwright MCP server as the claude user, in the background,
# before handing off to claude. Both the main agent and nested gate critics then
# connect to one warm browser over HTTP (see claude.sh MCP_CONFIG) instead of
# each cold-spawning chromium. Poll for the listener (up to 50 * 0.2s ~= 10s when
# the port stays closed, since curl fails fast on connection-refused; a reachable
# server exits the loop at once), then hand off regardless. We only need to know
# the port is accepting connections, so any HTTP status counts: this playwright-mcp
# answers a bare GET on "/" (or "/mcp") with 400 in well under curl's 1s --max-time.
su-exec ${CLAUDE_UID}:${CLAUDE_GID} playwright-mcp-sidecar >/tmp/playwright-mcp.log 2>&1 &
playwright_wait=0
while [ "$playwright_wait" -lt 50 ] && ! curl -s -o /dev/null --max-time 1 http://127.0.0.1:9223/; do
    playwright_wait=$((playwright_wait + 1))
    sleep 0.2
done

# Execute the main command as the host user mapping
exec su-exec ${CLAUDE_UID}:${CLAUDE_GID} "$@"
