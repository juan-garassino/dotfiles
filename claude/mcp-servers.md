# MCP Servers

Personal Model Context Protocol servers live in `~/Code/000-config/003-mcp-servers/`
(separate projects — not vendored here). This manifest records what to re-register on a
new machine.

| Server | Path | Purpose |
|---|---|---|
| job-assistant-client | `003-mcp-servers/001-job-assistant-client` | Job-assistant MCP client |
| memory-mcp | `003-mcp-servers/002-memory-mcp` | Persistent memory MCP server |
| weather-mcp | `003-mcp-servers/003-weather-mcp` | Weather data MCP server |

## Restore on a new machine

1. Restore `000-config/003-mcp-servers/` (clone/copy — it lives outside this repo).
2. Register each with Claude Code:
   ```bash
   claude mcp add <name> -- <command to launch the server>
   ```
   See each server's own README for its exact launch command. Any API keys go in
   `~/.secrets` or the server's own `.env` — **never** in this repo.

## Enabled Claude Code plugins (from `claude/settings.json`)

`context7`, `superpowers`, `code-simplifier`, `frontend-design` (all `@claude-plugins-official`).
Re-enable via the plugin marketplace; they are not vendored here.
