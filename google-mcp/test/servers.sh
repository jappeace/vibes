#!/usr/bin/env bash
# Starts both Google MCP servers from the server map mcp-servers.sh builds,
# with a throwaway service-account key whose token endpoint is local, and
# checks that they come up read-only and authenticate with that key.
# Needs analytics-mcp, mcp-search-console, jq, openssl and python3 on PATH.
# Usage: servers.sh <vibes checkout>
set -euo pipefail

VIBES="$1"
TEST_DIR="$VIBES/google-mcp/test"
. "$VIBES/mcp-servers.sh"

SCRATCH="$(mktemp -d)"
trap 'kill "$TOKEN_PID" 2>/dev/null || true; rm -rf "$SCRATCH"' EXIT
export HOME="$SCRATCH/home"
mkdir -p "$HOME"

python3 "$TEST_DIR/token_endpoint.py" "$SCRATCH/port" 2> "$SCRATCH/token_endpoint.log" &
TOKEN_PID=$!
for _ in $(seq 1 50); do
    if [ -s "$SCRATCH/port" ]; then break; fi
    sleep 0.1
done
if [ ! -s "$SCRATCH/port" ]; then
    if kill -0 "$TOKEN_PID" 2> /dev/null; then state="still running"; else state="exited"; fi
    echo "FAIL: token_endpoint.py did not write a port within 5s (process $state). Its stderr:" >&2
    cat "$SCRATCH/token_endpoint.log" >&2
    exit 1
fi

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$SCRATCH/private.pem" 2> /dev/null
jq -n --rawfile private_key "$SCRATCH/private.pem" \
    --arg token_uri "http://127.0.0.1:$(cat "$SCRATCH/port")/token" '{
        type: "service_account",
        project_id: "vibes-check",
        private_key_id: "0",
        private_key: $private_key,
        client_email: "check@vibes-check.iam.gserviceaccount.com",
        client_id: "0",
        token_uri: $token_uri
    }' > "$SCRATCH/key.json"

servers="$(mcp_servers_config "$SCRATCH/key.json" "$SCRATCH/key.json")"

fail() {
    echo "FAIL: $1" >&2
    echo "$2" >&2
    exit 1
}

analytics="$(python3 "$TEST_DIR/mcp_client.py" "$(jq -c '."google-analytics"' <<< "$servers")" \
    '[{"name": "create_property_annotation", "arguments": {}}]')"
jq -e '.tools | index("run_report")' <<< "$analytics" > /dev/null \
    || fail "analytics-mcp does not offer run_report" "$analytics"
# analytics-mcp names all of its write tools create_*.
jq -e '.tools | map(select(startswith("create_"))) == []' <<< "$analytics" > /dev/null \
    || fail "analytics-mcp offers write tools" "$analytics"
jq -e '.calls[0].isError and (.calls[0].content[0].text | contains("disabled"))' <<< "$analytics" > /dev/null \
    || fail "analytics-mcp did not refuse a write tool" "$analytics"

console="$(python3 "$TEST_DIR/mcp_client.py" "$(jq -c '."search-console"' <<< "$servers")" \
    '[{"name": "list_properties", "arguments": {}},
      {"name": "add_site", "arguments": {"site_url": "https://example.com/"}}]')"
jq -e '.calls[0].content[0].text | contains("invalid_grant")' <<< "$console" > /dev/null \
    || fail "mcp-search-console did not authenticate with the mounted key" "$console"
jq -e '.calls[1].content[0].text | contains("GSC_ALLOW_DESTRUCTIVE")' <<< "$console" > /dev/null \
    || fail "mcp-search-console did not refuse a destructive tool" "$console"

echo "PASS"
