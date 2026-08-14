# Simulators

Tools for managing iOS simulators and Android emulators on this Mac. Use
them whenever a task involves launching, restarting, or resetting a
simulator/emulator — e.g. React Native development, a wedged emulator, or
"launch my favorite simulators".

## The `sim` CLI (on PATH)

- `sim ls --json` — machine-readable list. Each device: `platform`
  (ios/android), `name`, `id` (simulator UDID / AVD name), `os`, `state`
  (booted/off), `favorite`, `serial` (adb serial when running). Prefer this
  over parsing the human-readable `sim ls`.
- `sim boot <name|id>` — boot a device (Android resumes its snapshot;
  booting a booted iOS simulator just brings the window forward).
- `sim cold <name|id>` — cold boot, a full restart. iOS: shutdown + boot.
  Android: kills the emulator, waits for adb to release it (up to ~20s),
  relaunches with `-no-snapshot-load`. Use when an emulator is wedged.
- `sim kill <name|id>` / `sim kill all` — shut down one device / everything.
- `sim erase <name|id>` — factory reset. Prompts for confirmation on stdin;
  it is destructive, so confirm with the user before piping `y`.
- `sim boot favs` / `sim cold favs` / `sim kill favs` — act on every
  favorite. `sim fav <name|id>` toggles a favorite.
- `sim update` — update the toolset itself (git pull + rebuild what
  changed). `sim version` shows the installed version.

Names match loosely (case, spaces, underscores, dashes ignored). If a name
is ambiguous and stdin is not a TTY, `sim` exits non-zero listing the
candidates with their ids — retry with the exact `id` from `sim ls --json`.

## MCP server

`mcp/server.js` exposes the same operations as typed MCP tools over stdio:
`list_devices`, `boot_device`, `cold_boot_device`, `shutdown_device`,
`erase_device` (destructive), `boot_favorites`, `shutdown_all`,
`self_update`. Register in Claude Code with:

```
claude mcp add --scope user simulators -- node <repo>/mcp/server.js
```

## Repo layout

- `sim` — the bash CLI (single file, no dependencies beyond simctl/adb/jq)
- `app/` — SwiftUI menu bar app + window; rebuild with `app/build.sh`
- `mcp/` — MCP server (Node, stdio) that shells out to `sim`
- Favorites live in `~/.config/sim/favorites` (one device id per line),
  shared by the CLI, the app, and the MCP server.
