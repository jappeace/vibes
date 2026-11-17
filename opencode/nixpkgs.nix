{ sources }:
# Decision: OpenCode and its models.dev catalogue build from a frozen nixpkgs
# (nixpkgs-opencode, OpenCode 1.19.0) while the rest of the image follows
# nixpkgs-unstable. Unstable moved to OpenCode 2.x, which drops the
# packages/opencode tree no-builtin-directives.patch edits and renames the
# plugin SDK that stopgate.ts types against (@opencode-ai/* to @opencode/*).
# Alternative: port both to 2.x now. Rejected: a separate migration, and it
# would hold back the claude-code bump that motivated this pin split.
# Drop this pin once the port lands.
import sources.nixpkgs-opencode { }
