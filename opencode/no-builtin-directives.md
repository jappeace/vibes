# OpenCode without bundled directives

`package.nix` builds OpenCode with `no-builtin-directives.patch`, so a model
sees only how it was trained plus the user's own instructions. The patch makes
three changes.

1. `session/llm/request.ts` no longer falls back to the per-model system prompt
   (`anthropic.txt`, `gpt.txt`, `codex.txt`, `beast.txt`, `default.txt` and so
   on) when the agent has no prompt of its own. The main `build` agent has
   none, so its system prompt now starts with the environment block.
2. The tool descriptions keep how each tool works (parameters, limits, output
   format, failure modes) and lose the behavioural advice: the shell tool's Git
   and GitHub section, "prefer the dedicated tools", "use Task for open-ended
   searches", "never create documentation files", emoji rules, the todo list's
   usage rules, and similar. The `general` and `explore` subagent
   descriptions (listed in the task tool, in both `agent/agent.ts` and the
   v2 `core/src/plugin/agent.ts`) lose their "use this when" advice.
3. Neither `skill/index.ts` nor the v2 plugin list in
   `core/src/plugin/internal.ts` registers the built-in `customize-opencode`
   skill, so the skill lists hold only skills the user installed.

What still reaches the model:

- the environment block (model name, working directory, platform, date);
- `~/.claude/CLAUDE.md` and project `AGENTS.md`/`CLAUDE.md` files;
- MCP server instructions and the user's skills;
- the descriptions of the tools that remain, including the `apply_patch`
  format specification.

Some text is left alone on purpose because it defines a feature rather than
steering behaviour. The hidden title, summary and compaction agents, and the
`explore` subagent, keep their own prompts. Plan mode keeps its reminders,
since they are what makes it read-only. The Windows shell notes are untouched
because the container only runs bash.

The patch also drops the Git safety rails that jappeace/vibes#124 kept (no
amending, force-pushing, skipping hooks or changing Git config unless asked).
Git policy now comes only from `CLAUDE.md`.

`test/system-prompt.js` runs the patched server against a recording provider
fixture and checks the request: the system prompt starts with the environment
block and contains `~/.claude/CLAUDE.md`, the one skill the fixture installs is
the only skill in both the system prompt and the v2 registry, and no tool
description mentions committing. `check.nix` runs it in CI.

Build the patched package independently of the container:

```sh
nix-build --arg uid "$(id -u)" --arg gid "$(id -g)" -A opencode
./result/bin/opencode --version
```

After pulling this change, rebuild the container environment using the normal
launcher and restart OpenCode inside it. A running process keeps the old binary
and its bundled prompts.

OpenCode builds from the frozen `nixpkgs-opencode` pin (see `nixpkgs.nix`), not
the image's main nixpkgs. When updating that pin, the patch fails the build if
its target text changed.
Regenerate it against the new source, and check the new prompt and tool files
for directives in places the patch does not cover yet.
