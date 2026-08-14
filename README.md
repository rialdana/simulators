# Simulators

Tools for managing iOS simulators and Android emulators, built for React
Native development where you're constantly booting, rebooting, and
cold-booting devices. Two front-ends, same behavior:

- **`sim`** — a CLI, symlinked onto your PATH
- **Simulators.app** — a menu bar app + searchable window, in `/Applications`

## Install

Requirements: **macOS 15+** and **Xcode** (it provides the iOS simulators
and the Swift toolchain that builds the app). The Android SDK is optional —
without it you just get the iOS side. It's auto-detected at
`~/Library/Android/sdk`, or set `$ANDROID_HOME`.

```
git clone https://github.com/rialdana/simulators.git
cd simulators
./install.sh
```

That links the `sim` CLI onto your PATH, builds Simulators.app from source,
installs it to `/Applications`, and launches it. Look for the iPhone icon
in the menu bar. Run `./install.sh` again anytime to update both.

Everything compiles locally in a few seconds, so there is no Gatekeeper
friction and nothing to trust beyond the source you can read.

### Sharing the built app instead

Zipping `/Applications/Simulators.app` and sending it also works, but the
app isn't notarized, so macOS quarantines downloaded copies. The recipient
has to clear that once:

```
xattr -dr com.apple.quarantine /Applications/Simulators.app
```

(or System Settings → Privacy & Security → "Open Anyway"). Building from
source via `install.sh` avoids this entirely, which is why it's the
recommended path.

## Simulators.app

A native SwiftUI app (source in `app/`). The menu bar icon shows how many
devices are booted and drops down to per-device actions (boot, cold boot,
shut down, erase), a Running section for quick access, Shut Down All, and
"Open Simulators…" which opens the main window. The window lists every
device grouped by iOS runtime and Android, with search (loose matching, like
the CLI), an All/iOS/Android filter, and per-row action buttons. State
refreshes every 5 seconds, so devices booted from Xcode, Android Studio, or
the CLI show up too. There's a "Start at Login" toggle in the menu.

## Favorites

Star the devices you actually use. Favorites float to the top everywhere: a
★ Favorites section pinned first in the window and the menu bar, and listed
first in the CLI. Toggle them with the star button on a window row, the
"Add to Favorites" item in a menu bar submenu, or `sim fav <name>`.

Favorites are stored as one device id per line in
`~/.config/sim/favorites`, shared by the app and the CLI — star something in
one and it shows starred in the other.

## AI agents (MCP)

Tell Claude "launch my favorite simulators" and it happens. Three layers,
use whichever fits:

- **`sim ls --json`** — machine-readable device list (platform, name, id,
  os, state, favorite, adb serial). Any agent with shell access can drive
  the CLI directly; ambiguous names fail non-interactively with the
  candidate ids, so scripts never hang on a picker.
- **`CLAUDE.md`** — teaches Claude Code the commands and when to reach for
  them the moment it works in this repo.
- **`mcp/server.js`** — an MCP (Model Context Protocol) stdio server
  exposing typed tools: `list_devices`, `boot_device`, `cold_boot_device`,
  `shutdown_device`, `erase_device` (flagged destructive), `boot_favorites`,
  and `shutdown_all`. It shells out to `sim`, so all three layers share one
  implementation. Works with any MCP client (Claude Code, Claude Desktop,
  Cursor, ...).

Set it up:

```
cd mcp && npm install
claude mcp add --scope user simulators -- node "$PWD/server.js"
```

For other MCP clients, configure a stdio server with command `node` and
args `["<repo>/mcp/server.js"]`.

Rebuild and reinstall after changing the source:

```
app/build.sh
```

## sim (CLI)

```
sim                    interactive menu (pick a device, pick an action)
sim ls                 list all devices and their state
sim boot [name]        boot a device (Android resumes its quick-boot snapshot)
sim cold [name]        cold boot: full shutdown, then a fresh start
sim kill [name|all]    shut down a device, or everything at once
sim erase [name]       factory reset a device (asks for confirmation)
sim <name>             shorthand for `sim boot <name>`
```

Names match loosely — case-insensitive, and spaces/underscores/dashes are
ignored:

```
sim boot 16e           # boots iPhone 16e
sim cold pixel9a       # cold boots Pixel_9a
sim kill all           # shuts down every simulator and emulator
```

If a name matches more than one device (e.g. the same iPhone across several
iOS runtimes), you get a numbered picker.

## What "cold boot" means per platform

- **iOS**: `simctl shutdown` followed by `simctl boot` — a full restart.
- **Android**: kills the emulator, waits for it to disappear from adb, then
  relaunches with `-no-snapshot-load` so it boots from scratch instead of
  restoring the quick-boot snapshot.

## Requirements

- Xcode command line tools (`xcrun simctl`) for iOS
- Android SDK for Android — found via `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`,
  or the default `~/Library/Android/sdk`
- `jq` (ships with recent macOS)

Either side is optional: with no Android SDK it just manages iOS simulators,
and vice versa.
