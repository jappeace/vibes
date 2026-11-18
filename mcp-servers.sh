# Sourced by claude.sh and by the google-mcp check, so the check exercises the
# server map the container gets.

# Prints the MCP server map (JSON, Claude Code's `mcpServers` shape) on
# stdout. Arguments: the Google service-account key on the host, and the path
# it is mounted at in the container. The Google Analytics and Search Console
# servers are included only when the host key exists; when it is missing, one
# line on stderr says so. A key without `project_id` aborts.
#
# Decision: the key is bind-mounted read-only and only its path goes into the
# MCP config. Rejected: passing the JSON in an env var, which would land in
# ~/.claude.json where the agent reads it.
# The two flags set to false also keep the requested OAuth scopes at
# analytics.readonly and webmasters.readonly. submit_sitemap has no flag of
# its own; that scope is what makes Google refuse it.
# Usage: mcp_servers_config <host key path> <container key path>
mcp_servers_config() {
    local base_servers='{"playwright":{"command":"playwright-mcp","args":["--headless","--no-sandbox","--isolated","--ignore-https-errors","--executable-path","/usr/local/bin/chromium"]},"hoogle":{"command":"mcp-hoogle","args":["serve"]},"tmux":{"command":"tmux-mcp-rs","args":[]}}'
    if [ ! -f "$1" ]; then
        echo "No Google service-account key at $1: the google-analytics and search-console MCP servers are not registered." >&2
        echo "$base_servers"
        return 0
    fi
    local project_id
    if ! project_id="$(jq -er '.project_id | strings' "$1")"; then
        echo "Error: $1 has no project_id; expected a Google service-account key (JSON)." >&2
        return 1
    fi
    jq -n --argjson base "$base_servers" --arg key "$2" --arg project "$project_id" '$base + {
        "google-analytics": {
            command: "analytics-mcp",
            args: [],
            env: {
                GOOGLE_APPLICATION_CREDENTIALS: $key,
                GOOGLE_CLOUD_PROJECT: $project,
                ANALYTICS_MCP_ALLOW_WRITE: "false"
            }
        },
        "search-console": {
            command: "mcp-search-console",
            args: [],
            env: {
                GSC_CREDENTIALS_PATH: $key,
                GSC_SKIP_OAUTH: "true",
                GSC_ALLOW_DESTRUCTIVE: "false"
            }
        }
    }'
}
