#!/usr/bin/env bash
# Checks that the shipped Claude Code resolves the `fable` model alias to
# Claude Fable 5.2, by recording the model id of the turn it sends to
# recording_provider.py. A nixpkgs bump that moves the default Fable on
# should update EXPECTED_MODEL.
# Usage: fable-model.sh <vibes checkout>
set -euo pipefail

VIBES="$1"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$VIBES/agent-command.sh"
. "$TEST_DIR/fixture.sh"

EXPECTED_MODEL="claude-fable-5-2"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

export HOME="$SCRATCH/home"
mkdir -p "$HOME/.claude" "$SCRATCH/work"
echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"

start_provider "$SCRATCH/provider.log" "$SCRATCH/requests" "$SCRATCH/port"
set_agent_command claude 0
AGENT_COMMAND+=(--model fable)
claude_status=0
fixture_turn "$SCRATCH/work" || claude_status=$?
kill "$PROVIDER_PID"
if [ "$claude_status" -ne 0 ]; then
    echo "FATAL: claude exited with status $claude_status" >&2
    exit 1
fi

sent_model="$(jq -rs 'map(select(.path | startswith("/v1/messages")) | .body | select(.system))
                      | if length == 0 then error("claude sent no /v1/messages request") else .[0].model end' \
    "$SCRATCH/requests"/*.json)"
echo "fable alias sent model: $sent_model"
if [ "$sent_model" != "$EXPECTED_MODEL" ]; then
    echo "FAIL: --model fable sent $sent_model, expected $EXPECTED_MODEL" >&2
    exit 1
fi
echo "PASS"
