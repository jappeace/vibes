# claude-gate

The end-of-turn gate for both vibes harnesses, as one Haskell binary.

It replaces the three bash hooks that used to live in `../hooks`
(`record-edit.sh`, `reset-turn-state.sh`, `stop-gate.sh`). The logic was about
600 lines of bash with embedded `jq`, mostly the transcript walking and JSON
shuffling, which had become hard to read and impossible to test. Here that logic
is typed and unit tested.

## Subcommands

The binary reads one hook JSON object on stdin and dispatches on its argument.
`../settings.json` wires each Claude Code hook to a subcommand:

| Subcommand          | Hook event   | What it does                                                        |
| ------------------- | ------------ | ------------------------------------------------------------------- |
| `claude-gate record` | PostToolUse  | Append the edit to the per-turn review stack (filters binaries etc.) |
| `claude-gate reset`  | UserPromptSubmit | Wipe the previous turn's per-turn state                          |
| `claude-gate stop-gate` | Stop      | Working hours, complexity canary, critique, rule review, then summary reprint |

OpenCode instances run without the gate since the move to OpenCode 2.x: its
plugin API replaced the one the stopgate adapter was written against, and the
adapter was removed. The OpenCode reviewer backend below is kept for a port.

## Reviewer backends

Claude Code hooks default to `CLAUDE_GATE_BACKEND=claude` and keep their existing
Haiku, Opus, and Sonnet models. An OpenCode caller sets
`CLAUDE_GATE_BACKEND=opencode`, `OPENCODE_GATE_MODEL=provider/model`, and
`OPENCODE_GATE_VARIANT` from the worker's latest user message (the removed 1.x
adapter did; a 2.x port has to).

OpenCode launches a fresh `opencode run --format json` session for each review.
Only its completed final answer is interpreted as a verdict. Tool output and
earlier commentary are excluded; provider errors, malformed output, and missing
final answers fail the review even when the CLI exits zero. Nested reviewers
set `OPENCODE_GATE_REVIEWER=1`; an adapter must skip its own hooks when it is
set, to prevent recursive reviews. The canary and rule reviewer have read-only tools; the critic
can run tests. Reviewers cannot delegate to differently configured subagents.

For OpenAI workers, the default models are:

| Phase | Model |
| --- | --- |
| Complexity canary | `openai/gpt-5.6-terra-fast` |
| Adversarial critique | The worker's model and reasoning variant |
| Rule review | `openai/gpt-5.6-luna` |

These choices were tested through the instance's ChatGPT login. Catalogue
presence alone is insufficient: the listed GPT-5.4-mini, GPT-5.3-Codex-Spark,
and GPT-5.4 models were rejected as unsupported by that endpoint. The catalogue
does not expose relative model sizes or subscription-cap weighting.

Other providers inherit their worker model for all three phases.
Optional per-phase model overrides are `OPENCODE_DUMBIFY_MODEL`,
`OPENCODE_CRITIQUE_MODEL`, and `OPENCODE_REVIEWER_MODEL`, all using `provider/model`
names. Use these overrides if an account does not offer the default GPT tiers.
Unavailable models fail visibly rather than silently switching to Astra. A different model
does not inherit the worker's reasoning variant, which it might not support.
The existing `CLAUDE_*_MODEL` overrides apply only to Claude Code reviewers.

## Phases of the Stop gate

- The working-hours check uses a plain clock, no model. When the Stop fires
  outside CLAUDE.md's rest windows (22:45-07:00
  NL, or Sunday) the gate injects one warning per turn ("warning outside
  working hours, see claude.md") and the worker decides what to do with
  it. The Amsterdam clock is computed from the EU DST rule in code, so it
  stays right even without zoneinfo, where a named TZ silently falls back
  to UTC. Disable with `CLAUDE_SKIP_HOURS_CHECK=1`.
- The complexity canary explains changed code for the worker to judge. New edits
  trigger another explanation; no new edits indicate acceptance.
- The adversarial critic checks both edits and claims, including turns with no
  edits. Substantiated `CHALLENGE:` findings are fed back to the worker.
- Rule review claims the turn's review stack and reviews every diff
  in one reviewer call against the rules corpus (global and project `CLAUDE.md`
  plus the skills matching the touched file types). Violations block the Stop
  with the findings so the main-loop model can fix or rebut, and the loop
  repeats until clean.
- The summary reprint runs once the three phases pass. If any of them blocked
  with feedback this turn, the worker's summary now sits above the review
  exchange, so the gate blocks once more and asks the worker to reprint it,
  updated, as its last message. That Stop spawns no reviewer. Infrastructure
  failures and the working-hours warning do not ask for a reprint.

Disable the corresponding phase with `CLAUDE_SKIP_DUMBIFY=1`,
`CLAUDE_SKIP_CRITIQUE=1`, or `CLAUDE_SKIP_RULE_CHECK=1` under either backend.

## Build and test

```
nix-build nix/ci.nix    # builds and tests the binary, runs the claude-code and opencode checks and hlint
```

The container builds this via `callCabal2nix ./gate` in the top-level
`../default.nix`, so the binary ships on `PATH` inside the image.
