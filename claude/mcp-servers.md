# MCP Servers

What Claude Code actually has registered (`claude mcp list`), plus the personal server folders
in `~/Code/000-config/003-mcp-servers/` (separate projects — not vendored here). This manifest
records what to re-register on a new machine.

## Registered (user scope, `~/.claude.json`)

| Server | Launch | Purpose |
|---|---|---|
| discord-me | `uv run --directory ~/Code/002-engenious/mcp_and_services/discord-me-mcp python -m discord_me_mcp` | Discord as Juan (used by `post-as-me`) — the only global MCP server |

Project-scoped servers live with their project (e.g. `002-engenious/marketing_agent` registers
`marketing-agent`, `marketing-agent-http`, `hubspot`, `marketing-agent-gcp`). The `claude.ai …`
connectors (Gmail, Calendar, Drive, Docs, …) and plugin MCPs (`context7`, `atlassian`) come with the
claude.ai login / plugins — nothing to register.

## `003-mcp-servers/` (present, not registered)

| Folder | What |
|---|---|
| `001-job-assistant-client` | Node stdio→SSE bridge (`node client.js [sse-url]`) to the job-assistant (career-navigator) backend's `/mcp/sse` |
| `002-memory-mcp` | only a `memory.json` data file (for `@modelcontextprotocol/server-memory`), no code |

## Restore on a new machine

1. Restore `000-config/003-mcp-servers/` and `002-engenious/mcp_and_services/discord-me-mcp/` (they live outside this repo).
2. Register with Claude Code (user scope, absolute `$HOME` path — `~` isn't expanded inside the JSON):
   ```bash
   claude mcp add -s user discord-me -- uv run --directory "$HOME/Code/002-engenious/mcp_and_services/discord-me-mcp" python -m discord_me_mcp
   ```
   See each server's own README for its exact launch command. Any API keys go in
   `~/.secrets` or the server's own `.env` — **never** in this repo.

## Enabled Claude Code plugins (from `claude/settings.json`)

`context7`, `superpowers`, `code-simplifier`, `frontend-design`, `atlassian` (all `@claude-plugins-official`).
Re-enable via the plugin marketplace; they are not vendored here.
