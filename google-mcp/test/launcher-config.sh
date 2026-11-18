#!/usr/bin/env bash
# Checks which MCP servers the launcher registers depending on the host's
# Google key, and that opencode gets the same server environment as Claude Code.
# Usage: launcher-config.sh <vibes checkout>
set -euo pipefail

VIBES="$1"
. "$VIBES/agent-command.sh"
. "$VIBES/mcp-servers.sh"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
CONTAINER_KEY=/run/secrets/key.json

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

without_key="$(mcp_servers_config "$SCRATCH/absent.json" "$CONTAINER_KEY" 2> "$SCRATCH/stderr")"
if jq -e 'has("google-analytics") or has("search-console")' <<< "$without_key" > /dev/null; then
    fail "Google servers registered without a key"
fi
grep -q "$SCRATCH/absent.json" "$SCRATCH/stderr" || fail "missing key not reported"

echo '{"type": "service_account"}' > "$SCRATCH/no-project.json"
if mcp_servers_config "$SCRATCH/no-project.json" "$CONTAINER_KEY" > /dev/null 2>&1; then
    fail "a key without project_id was accepted"
fi

echo '{"type": "service_account", "project_id": "vibes-check"}' > "$SCRATCH/key.json"
with_key="$(mcp_servers_config "$SCRATCH/key.json" "$CONTAINER_KEY")"
jq -e --arg key "$CONTAINER_KEY" '
    ."google-analytics".env.GOOGLE_APPLICATION_CREDENTIALS == $key
    and ."google-analytics".env.GOOGLE_CLOUD_PROJECT == "vibes-check"
    and ."search-console".env.GSC_CREDENTIALS_PATH == $key' <<< "$with_key" > /dev/null \
    || fail "Google servers do not point at the mounted key: $with_key"

write_opencode_config "$SCRATCH" "$with_key" ""
# Without its environment an opencode server starts but cannot find the key.
jq -e --argjson servers "$with_key" \
    '.mcp | to_entries | all(.value.environment == ($servers[.key].env // {}))' \
    "$SCRATCH/opencode.json" > /dev/null \
    || fail "opencode servers lack their environment: $(cat "$SCRATCH/opencode.json")"

echo "PASS"
