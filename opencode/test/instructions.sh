#!/usr/bin/env bash
# Checks that OpenCode, started with the config agent-command.sh writes, sends
# the global and the project CLAUDE.md in the turn's system prompt. OpenCode
# 2.x reads only AGENTS.md unless `instructions` names other files.
# Usage: instructions.sh <vibes checkout>
set -euo pipefail

VIBES="$1"
TEST_DIR="$VIBES/claude-code/test"
. "$VIBES/agent-command.sh"
. "$TEST_DIR/fixture.sh"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

export HOME="$SCRATCH/home"
mkdir -p "$HOME/.claude" "$HOME/.config/opencode" "$SCRATCH/project"
echo "GLOBAL-RULES-CANARY" > "$HOME/.claude/CLAUDE.md"
echo "PROJECT-RULES-CANARY" > "$SCRATCH/project/CLAUDE.md"
git -C "$SCRATCH/project" init -q

start_provider "$SCRATCH/provider.log" "$SCRATCH/requests" "$SCRATCH/port"
write_opencode_config "$SCRATCH" '{}' "anthropic/claude-opus-5-5"
# Only the provider endpoint differs from the launcher's config.
jq --arg url "$PROVIDER_URL/v1" \
    '. + {provider: {anthropic: {options: {baseURL: $url, apiKey: "fixture"}}}}' \
    "$SCRATCH/opencode.json" > "$HOME/.config/opencode/opencode.json"

opencode_status=0
(cd "$SCRATCH/project" && OPENCODE_DISABLE_MODELS_FETCH=1 \
    timeout 120 opencode --standalone run hi < /dev/null > "$SCRATCH/run.log" 2>&1) \
    || opencode_status=$?
kill "$PROVIDER_PID"
if [ "$opencode_status" -ne 0 ]; then
    echo "FATAL: opencode exited with status $opencode_status:" >&2
    cat "$SCRATCH/run.log" >&2
    exit 1
fi

system="$(jq -rs 'map(.body | select(.model == "claude-opus-5-5") | .system | tostring)
                  | if length == 0 then error("opencode sent no claude-opus-5-5 turn") else .[0] end' \
    "$SCRATCH/requests"/*.json)"
for canary in GLOBAL-RULES-CANARY PROJECT-RULES-CANARY; do
    if [[ "$system" != *"$canary"* ]]; then
        echo "FAIL: the system prompt lacks $canary" >&2
        exit 1
    fi
done
echo "PASS"
