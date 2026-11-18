# Sourced by claude.sh and by the claude-code and opencode checks, so they
# exercise the exact command and config the container runs.

# Sets AGENT_COMMAND for agent $1 (claude|opencode) and vanilla flag $2 (0|1).
#
# Decision: configured Claude Code instances get an empty system prompt, which
# drops the ~6k characters of bundled directives (auto-memory writing
# instructions included; MEMORY.md is still loaded); the identity line, tools,
# CLAUDE.md, skills and environment block are still sent. Rejected:
# --append-system-prompt (removes nothing), a trimmed copy via
# --system-prompt-file (drifts from upstream) and --bare (also drops
# CLAUDE.md, hooks and the OAuth login).
# --vanilla keeps the stock prompt because it exists to show stock Claude.
set_agent_command() {
    AGENT_COMMAND=("$1")
    if [ "$1" = claude ] && [ "$2" -eq 0 ]; then
        AGENT_COMMAND+=(--system-prompt "")
    fi
}

# Decision: opencode's global config is derived from MCP_CONFIG with jq
# instead of being a second hand-maintained server list, so both harnesses
# always get the same MCP servers. `permission: "allow"` is opencode's
# bypassPermissions: the container is the sandbox, exactly as for claude.
# The optional --model pins the launch default: /models remembers choices under
# ~/.local/state/opencode, which is not persisted across container launches.
# Without --model, retain model discovery because ChatGPT plan access varies.
# autoupdate is off because the binary comes from nix. OpenCode 2.x reads
# only AGENTS.md on its own, so `instructions` names CLAUDE.md: the global
# rules and each project's own, found upward from the working directory.
# The file is written into the per-launch config snapshot and bind-mounted
# read-only like CLAUDE.md, so the agent cannot widen its own permissions.
# Usage: write_opencode_config <config dir> <MCP_CONFIG json> <model or "">
write_opencode_config() {
    jq -n --argjson mcp "$2" --arg model "$3" '{
        "$schema": "https://opencode.ai/config.json",
        autoupdate: false,
        permission: "allow",
        instructions: ["~/.claude/CLAUDE.md", "CLAUDE.md"],
        mcp: ($mcp | with_entries(.value = {
            type: "local",
            command: ([.value.command] + .value.args),
            environment: (.value.env // {}),
            enabled: true
        }))
    } + (if $model != "" then {model: $model} else {} end)' > "$1/opencode.json"
}
