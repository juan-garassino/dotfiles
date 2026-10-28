# MCP Servers

What Claude Code actually has registered (`claude mcp list`), plus the personal server folders
in `~/Code/000-config/003-mcp-servers/` (separate projects — not vendored here). This manifest
records what to re-register on a new machine.

## Registered (user scope, `~/.claude.json`)

| Server | Launch | Purpose |
|---|---|---|
| discord-me | `uv run --directory ~/Code/002-engenious/mcp_and_services/discord-me-mcp python -m discord_me_mcp` | Discord as Juan (used by `post-as-me`) |
| blender | `uvx mcp-for-blender` | Drives the live Blender (bpy, viewport screenshots) — see *Blender + parametric design* below |

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

## Blender + parametric design (Sverchok)

Blender is the `blender` app in `packages/linux-apps.sh` (snap, `5.2lts/stable`, classic). On top of it:

1. **Sverchok** (Grasshopper-style node editor, `nortikin/sverchok`): download the `master` zip, unpack it as
   `~/.config/blender/<ver>/scripts/addons/sverchok`, then
   `blender -b --python-expr "import addon_utils, bpy; addon_utils.enable('sverchok', default_set=True); bpy.ops.wm.save_userpref()"`.
   v1.4.0 declares Blender 3.5+ and runs on 5.2. Run downloaded add-on code yourself (Claude's auto mode blocks it).
2. **MCP** (`ahujasid/mcp-for-blender`, formerly `blender-mcp` — `uvx blender-mcp` still works):
   `uvx mcp-for-blender setup` → pick Claude Code; it installs the add-on and registers
   `claude mcp add -s user blender -- uvx mcp-for-blender`. In Blender: N-panel → **BlenderMCP** → Connect.
   For auto-reconnect set `scene.blendermcp_auto_start_server = True` and save the .blend (per file).
   Telemetry defaults off; asset libraries / 3D generators are off until enabled in the add-on prefs.
3. **Prefs:** autosave to `~/.local/share/blender-autosave` (default `/tmp` is wiped at boot — work was lost once).
   On the 2015 MBP (Iris Pro) use Solid shading only — EEVEE material preview crashes Blender; render with Cycles CPU.

Sverchok-via-bpy gotchas (Sverchok 1.4): the tree evaluates **asynchronously** — read `socket.sv_get()` in the next
call, not right after `tree.force_update()`; `SvInsetSpecialMk2` defaults to `offset_mode='CENTER'` (inset = window
scale factor) — use `'SIDES'` for a frame width in metres; vector inputs to `SvFormulaNodeMk5` produced no data —
use `SvVectorMathNodeMK3` (`DISTANCE`) + `SvMapRangeNode`; a draggable attractor = Empty → `SvGetObjectsDataMK5`
(`object_names.add().object_pointer = obj`) → `SvMatrixOutNodeMK2` Location; many boxes = unit `SvBoxNodeMk2` +
`SvMatrixInNodeMK4` (location + scale lists) → `ListJoinNode` → `SvMeshViewer` (`is_merge=True`, matrix input);
`SvMeshViewer` material_idx only sticks once the mesh has enough material slots (re-run the tree after adding them).

## Enabled Claude Code plugins (from `claude/settings.json`)

`context7`, `superpowers`, `code-simplifier`, `frontend-design`, `atlassian` (all `@claude-plugins-official`).
Re-enable via the plugin marketplace; they are not vendored here.
