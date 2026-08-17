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

## Updating

```
sim update
```

One command, run from anywhere. It pulls the latest version of the clone
and rebuilds only what changed: the CLI and MCP server run straight out of
the repo (so the pull alone updates them), the app is recompiled and
relaunched only when `app/` changed, and MCP dependencies are reinstalled
only when they moved. `sim version` shows what you're on, and
`git pull && ./install.sh` is the manual equivalent.

The app has the same mechanism built in: **Check for Updates…** in the menu
bar fetches the repo, tells you what version is available, and runs the
update for you (quitting and relaunching itself if the app changed).

Releases are tagged (`vX.Y.Z`) with notes on the
[Releases page](https://github.com/rialdana/simulators/releases). You can
also just ask your AI agent to update — the MCP server exposes a
`self_update` tool.

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
the CLI show up too. There's a "Start at Login" toggle and a
"Check for Updates…" item in the menu.

The full device lifecycle lives here too: booted devices have a
**Screenshot** action (saves to the Desktop and reveals the file in
Finder), every device has **Delete Device…** behind a confirmation, and
**New Device…** (menu bar item or the + toolbar button) opens a sheet with
platform/model/OS pickers — the same creation flow as `sim create`,
including automatic system-image downloads.

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
  `shutdown_device`, `erase_device` and `delete_device` (flagged
  destructive), `boot_favorites`, `shutdown_all`, `screenshot_device`,
  `list_device_models`, `create_device`, `rename_device`,
  `clear_app_data` and `uninstall_app` (destructive), `list_apps`,
  `launch_app`, `quit_app`, `relaunch_app`, `install_app`, `open_url`,
  `set_app_permission`, and `self_update`. It shells out
  to `sim`, so all layers share one implementation. Works with any MCP
  client (Claude Code, Claude Desktop, Cursor, ...).

`screenshot_device` returns the actual image, so Claude can *see* the
simulator screen — "boot my favorites, screenshot both, and tell me if the
layout is broken on Android" works end to end. And `create_device` means
"create a Pixel 9 with Android 36 and boot it" needs no Android Studio.

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
sim shot [name]        screenshot a booted device (to ~/Desktop, or --out <path>)
sim create ...         create a device (interactive, or ios|android <model> <os>)
sim rm <name>          delete a simulator/AVD permanently (asks first)
sim rename <name> <new>  rename a device (spaces fine, works while running)
sim clear <app>        reset one app to fresh-install state (data + cache)
sim apps               list user apps on a booted device (--json)
sim launch <app>       launch an app (also: sim quit, sim relaunch)
sim uninstall <app>    remove an app entirely (asks first)
sim install <path>     install a .app bundle or .apk
sim url <link>         open a URL/deep link on all booted devices
sim perm <action> <permission> <app>   grant/revoke/reset a permission
sim models [platform]  list creatable models and OS versions (--json)
sim <name>             shorthand for `sim boot <name>`
```

Creating devices needs no Android Studio: `sim create ios "iPhone 17 Pro"
26.2` uses simctl, and `sim create android pixel_9 36` uses avdmanager —
downloading the system image first if it's missing, and installing
cmdline-tools into the SDK automatically the first time (via Homebrew's
`android-commandlinetools` if nothing else is available).

Names match loosely — case-insensitive, and spaces/underscores/dashes are
ignored:

```
sim boot 16e           # boots iPhone 16e
sim cold pixel9a       # cold boots Pixel_9a
sim kill all           # shuts down every simulator and emulator
```

If a name matches more than one device (e.g. the same iPhone across several
iOS runtimes), you get a numbered picker.

Per-app actions all share the same shape: pass an app name hint or an exact
bundle/package id (`sim relaunch allball`). If several apps match you're
shown the candidates and asked to choose; when several devices are booted,
add `--device <name>`.

- `sim clear` resets a single app instead of the whole device — Android
  uses `pm clear`; iOS reinstalls the same .app in place, a true
  fresh-install state.
- `sim relaunch` force-stops and relaunches — the fix for a wedged RN app
  when Metro itself is fine. `sim launch` and `sim quit` are the halves.
- `sim uninstall` / `sim install <path>` remove an app or drop a
  `.app`/`.apk` build onto a device (platform inferred from the extension).
- `sim url myapp://profile/123` opens a deep link on **every** booted
  device at once — iOS and Android side by side.
- `sim perm grant camera allball` grants/revokes/resets permissions, with
  friendly names (camera, microphone, location, photos, contacts, calendar,
  notifications…) mapped to each platform's real permission ids.

Android devices show their **display name** ("Pixel 9 Pro XL") everywhere,
like Android Studio does. `sim rename` edits that display name — spaces and
anything else allowed, even while the emulator runs — while the underlying
AVD id (`Pixel_9_Pro_XL`, what adb and the emulator use) stays stable and
visible in `sim ls --json`. Creating a device with a spacey `--name` does
the same split automatically. Matching accepts either form.

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
