# Simulators

Tools for managing iOS simulators and Android emulators, built for React
Native development where you're constantly booting, rebooting, and
cold-booting devices. Two front-ends, same behavior:

- **`sim`** — a CLI, symlinked onto your PATH
- **Simulators.app** — a menu bar app + searchable window, in `/Applications`

Plus an MCP server so AI agents (Claude Code, Cursor, Codex) can drive both.

## Prerequisites

Everything is detected at runtime and `sim doctor` reports exactly what's
missing with a fix hint, so the fastest path is: install Xcode, run
`./install.sh`, run `sim doctor`, fix what it flags.

**Required**

| Need | Why | How to get it |
| ---- | --- | ------------- |
| macOS 15 (Sequoia) or newer | the app targets macOS 15 | — |
| Xcode 16 or newer — the full app, not just the Command Line Tools | `xcrun simctl` and the iOS simulator runtimes; the Swift 6 toolchain that compiles Simulators.app | App Store, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and `sudo xcodebuild -license accept` |
| at least one iOS runtime | otherwise there are no simulators to manage | Xcode ▸ Settings ▸ Components, or `xcodebuild -downloadPlatform iOS` |
| `jq` | parses `simctl` JSON everywhere | ships with macOS 15 (`/usr/bin/jq`); older: `brew install jq` |
| `git` | `sim update`, `sim version`, and the app's updater work on the clone | comes with Xcode |

**Optional — Android.** Without an SDK you get iOS-only mode.

| Need | Why | How to get it |
| ---- | --- | ------------- |
| Android SDK with `emulator` and `platform-tools` (`adb`) | boot, cold boot, kill, apps, logs, permissions on emulators | **Android Studio** installs all of it to the default location. Without Android Studio see below. |
| `avdmanager` + `sdkmanager` (cmdline-tools) | `sim create android`, `sim models android`, and downloading system images (`sim rm` falls back to deleting the AVD folder without it) | Android Studio ▸ SDK Manager ▸ SDK Tools ▸ "Android SDK Command-line Tools (latest)", or `brew install --cask android-commandlinetools` |
| a `java` on PATH (or `JAVA_HOME`), JDK 17+ | `avdmanager` and `sdkmanager` are Java programs; Android Studio's bundled JDK isn't on PATH | `brew install --cask temurin` |

The SDK is found via `$ANDROID_HOME`, then `$ANDROID_SDK_ROOT`, then
`~/Library/Android/sdk`. `adb` is taken from `<sdk>/platform-tools/adb`, or
from PATH if that's missing. Android Studio itself is never required — it's
just the easiest way to get an SDK.

Without Android Studio, this produces a working SDK at the default path:

```
brew install --cask android-commandlinetools temurin
yes | sdkmanager --sdk_root="$HOME/Library/Android/sdk" --licenses
sdkmanager --sdk_root="$HOME/Library/Android/sdk" "platform-tools" "emulator" "cmdline-tools;latest"
sim create android pixel_9 36      # downloads the system image, creates the AVD
```

**Optional — MCP server for AI agents**

| Need | Why | How to get it |
| ---- | --- | ------------- |
| Node.js 18+ and `npm` | runs `mcp/server.js` and installs its two dependencies | `brew install node` |
| an MCP client | Claude Code (`claude` CLI), Cursor, or Codex | whichever you use; `sim mcp` registers with every one it finds |

**Homebrew** is not strictly required, but every fix hint from `sim doctor`
uses it, and `install.sh` links `sim` into `/opt/homebrew/bin` (falling back
to `/usr/local/bin`). If neither is writable it prints the `ln -s` to run
yourself.

## Install

```
git clone https://github.com/rialdana/simulators.git
cd simulators
./install.sh
sim doctor
```

`install.sh` never prompts and exits non-zero on failure, so it's safe to run
unattended. In order it:

1. Checks for Xcode and the Swift toolchain, and stops with a clear message
   if they're missing.
2. Symlinks `sim` into `/opt/homebrew/bin` (or `/usr/local/bin`). The CLI
   runs straight out of the clone — keep the clone where it is, since
   `sim update` and the app find the repo through that symlink.
3. Runs `sim mcp`: installs the MCP server's dependencies with `npm ci` and
   registers the server with every supported client found on the machine
   (Claude Code, Cursor, Codex). If `node` is missing, or no client is
   installed yet, it prints what to run later and carries on.
   `SIM_NO_MCP=1 ./install.sh` skips this step entirely.
4. Builds Simulators.app from source with `swift build`, ad-hoc signs it,
   installs it to `/Applications` (or `~/Applications`), and launches it.
   Look for the iPhone icon in the menu bar.

Run `./install.sh` again anytime to update everything. Everything compiles
locally in a few seconds, so there is no Gatekeeper friction and nothing to
trust beyond the source you can read.

`sim doctor` exits non-zero when something required is broken (✗); the ○
lines are optional pieces or advice. Restart your MCP client afterwards so it
picks up the new server.

### Installing with an AI agent

The whole setup is scriptable, so you can hand this repo to an agent. In
Claude Code (or Cursor / Codex) paste:

> Set up https://github.com/rialdana/simulators on this Mac: follow the
> README's Prerequisites and Install sections, then run `sim doctor` and fix
> anything it flags.

The agent will clone the repo, install whatever prerequisites are missing,
run `./install.sh`, and iterate on `sim doctor` until it's clean. Once the
MCP server is registered (and the client restarted), the same agent can
drive your simulators directly — see [AI agents (MCP)](#ai-agents-mcp).

## Updating

```
sim update
```

One command, run from anywhere. It pulls the latest version of the clone
and rebuilds only what changed: the CLI and MCP server run straight out of
the repo (so the pull alone updates them), the app is recompiled and
relaunched only when `app/` changed, and MCP dependencies are reinstalled
when they moved. Updating also trues up the MCP: a registration pointing at
an old checkout is re-pointed, and an install that predates automatic MCP
setup gets registered on its next update — but if you removed the server
from a client yourself, it stays removed there. `sim version` shows what
you're on, and `git pull && ./install.sh` is the manual equivalent.

The pull is `--ff-only`, so local edits in the clone make it fail with a
message rather than merging; commit or stash them first.

The app has the same mechanism built in: **Check for Updates…** (in the
menu bar, the window's status bar, or the Simulators application menu)
opens the main window, fetches the repo behind a progress sheet, tells you
what version is available, and runs the update for you — keeping the sheet
up while it works (quitting and relaunching itself if the app changed) and
confirming with an "App updated" alert when it's done. The current version
is always visible at the bottom of the menu and in the window's status bar.

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
shut down, erase), a Favorites section with **Cold Boot All**, a Running
section for quick access, Shut Down All, and "Open Simulators…" which opens
the main window. The window lists every device grouped by iOS runtime and
Android, with search (loose matching, like the CLI), an All/iOS/Android
filter, and per-row action buttons. State refreshes every 5 seconds, so
devices booted from Xcode, Android Studio, or the CLI show up too. There's
a "Start at Login" toggle and a "Check for Updates…" item in the menu.

Anything window-wide that takes a while — checking for or installing an
update, Shut Down All, Cold Boot All — shows a progress sheet with a spinner
on the window until it finishes; per-device actions show a spinner on their
row instead.

The full device lifecycle lives here too: booted devices have a
**Screenshot** action (saves to the Desktop and reveals the file in
Finder), and every device has **Delete Device…** behind a confirmation.
Device creation (the same flow as `sim create`) is built but hidden from
the menu bar and toolbar for now; use `sim create` in the meantime.

## Favorites

Star the devices you actually use. Favorites float to the top everywhere: a
★ Favorites section pinned first in the window and the menu bar, and listed
first in the CLI. Toggle them with the star button on a window row, the
"Add to Favorites" item in a menu bar submenu, or `sim fav <name>`.
`sim boot favs`, `sim cold favs`, and `sim kill favs` act on all of them.
**Cold Boot All** — at the bottom of the menu bar's Favorites section and in
the window's Favorites header — restarts every favorite at once (the
equivalent of `sim cold favs`, run in parallel).

Favorites are stored as one device id per line in
`~/.config/sim/favorites`, shared by the app, the CLI, and the MCP server —
star something in one and it shows starred in the others.

## AI agents (MCP)

Tell Claude "launch my favorite simulators" and it happens. Three layers,
use whichever fits:

- **`sim ls --json`** — machine-readable device list (platform, name, id,
  os, state, favorite, adb serial). Any agent with shell access can drive
  the CLI directly; ambiguous names fail non-interactively with the
  candidate ids, so scripts never hang on a picker.
- **`CLAUDE.md`** (also linked as **`AGENTS.md`**) — teaches Claude Code,
  Cursor and Codex the commands and when to reach for them the moment they
  work in this repo.
- **`mcp/server.js`** — an MCP (Model Context Protocol) stdio server
  exposing typed tools: `list_devices`, `boot_device`, `cold_boot_device`,
  `shutdown_device`, `erase_device` and `delete_device` (flagged
  destructive), `boot_favorites`, `shutdown_all`, `screenshot_device`,
  `list_device_models`, `create_device`, `rename_device`,
  `clear_app_data` and `uninstall_app` (destructive), `list_apps`,
  `launch_app`, `quit_app`, `relaunch_app`, `install_app`, `open_url`,
  `set_app_permission`, `app_logs`, `doctor`, and `self_update`. It shells
  out to `sim`, so all layers share one implementation. Works with any MCP
  client (Claude Code, Claude Desktop, Cursor, ...).

`screenshot_device` returns the actual image, so Claude can *see* the
simulator screen — "boot my favorites, screenshot both, and tell me if the
layout is broken on Android" works end to end. And `create_device` means
"create a Pixel 9 with Android 36 and boot it" needs no Android Studio.

`./install.sh` sets this up for you — it installs the server's dependencies
and registers it with every supported client it finds on the machine:

| Client      | Detected by                               | Registered in                                       |
| ----------- | ----------------------------------------- | --------------------------------------------------- |
| Claude Code | the `claude` CLI                          | `claude mcp add --scope user` (`~/.claude.json`)    |
| Cursor      | `~/.cursor` or `/Applications/Cursor.app` | `~/.cursor/mcp.json`                                |
| Codex       | `~/.codex` or the `codex` CLI             | `~/.codex/config.toml`, `[mcp_servers.simulators]`  |

Restart the client afterwards and the tools appear (in Claude Code, `/mcp`
lists them). To (re)do it on its own, or for a client you install later:

```
sim mcp                 # every client found on this machine
sim mcp cursor codex    # just these, whether or not they are installed yet
sim mcp --reinstall     # also reinstall the server's npm dependencies
```

It's idempotent: it installs deps if they're missing, registers the server
with each client that doesn't know it, and re-points a registration that's
aimed at a moved or older checkout. Existing entries in those config files
are left alone. `sim doctor` reports one line per installed client, so a
server that was never registered shows up as a warning instead of looking
healthy.

For other MCP clients, configure a stdio server with command `node` and
args `["<repo>/mcp/server.js"]`.

## sim (CLI)

`sim help` prints this list; it's the header of the `sim` script itself.

```
sim                    interactive menu
sim ls                 list devices and their state
sim boot [name]        boot a device (Android resumes its quick-boot snapshot)
sim cold [name]        cold boot: full shutdown, then a fresh start
sim kill [name|all]    shut down a device, or everything
sim erase [name]       factory reset a device (asks for confirmation)
sim fav [name]         toggle a favorite (marked ★, listed first)
sim boot favs          boot every favorite (also works: cold favs, kill favs)
sim ls --json          machine-readable device list (for scripts and agents)
sim shot [name]        screenshot a booted device (to ~/Desktop, or --out <path>)
sim create ...         create a device: sim create ios|android <model> <os> [--name <n>]
                       (interactive when run with no arguments)
sim rm <name|id>       delete a simulator/AVD permanently (asks first)
sim rename <name> <new>  rename a device (Android: edits the display name)
sim clear <app>        reset an app to fresh-install state (data + cache);
                       app is a name hint or bundle/package id; add
                       --device <name> when several devices are booted
sim apps               list user apps on a booted device (--json)
sim launch <app>       launch an app (also: sim quit, sim relaunch)
sim uninstall <app>    remove an app entirely (asks first)
sim install <path>     install a .app bundle or .apk on a booted device
sim url <link>         open a URL/deep link on all booted devices
sim perm <grant|revoke|reset> <permission> <app>   e.g. perm grant camera allball
sim logs <app>         app's native logs: stream live (tty), dump recent
                       (piped), or capture the next N secs with --for <n>
sim doctor             check the environment and report what's missing
sim mcp [client...]    install + register the MCP server with Claude Code,
                       Cursor and Codex — whichever is installed (install does this)
sim models [platform]  list creatable models and OS versions (--json)
sim update             pull the latest version and rebuild what changed
sim version            show the installed version
sim <name>             shorthand for `sim boot <name>`
```

Common aliases work too: `start`, `restart`/`reboot`, `shutdown`/`stop`/
`down`, `wipe`/`reset`, `star`, `screenshot`, `new`, `remove`, `log`,
`upgrade`.

Creating devices needs no Android Studio: `sim create ios "iPhone 17 Pro"
26.2` uses simctl, and `sim create android pixel_9 36` uses avdmanager,
downloading the system image first if it's missing. `avdmanager` only sees
system images when it lives inside the SDK, so if the only copy on the
machine is Homebrew's, `sim` uses its `sdkmanager` to install cmdline-tools
into the SDK once (~150 MB) and carries on. `sim models ios|android` lists
what you can pass.

Names match loosely — case-insensitive, and spaces/underscores/dashes are
ignored:

```
sim boot 16e           # boots iPhone 16e
sim cold pixel9a       # cold boots Pixel_9a
sim kill all           # shuts down every simulator and emulator
```

If a name matches more than one device (e.g. the same iPhone across several
iOS runtimes), you get a numbered picker. When stdin isn't a terminal —
scripts, agents — `sim` instead exits non-zero listing the candidates with
their ids, so nothing hangs; retry with the exact id from `sim ls --json`.

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
- `sim perm grant camera allball` grants/revokes/resets permissions. Friendly
  names — `camera`, `microphone`, `location`, `location-always`, `photos`,
  `contacts`, `calendar`, `notifications`, `motion`, `reminders`,
  `media-library`, `siri`, `all` — map to each platform's real permission
  ids; raw `android.permission.*` or simctl service names pass through. On
  Android `reset` means revoke, and the permission has to be declared in the
  app's manifest.
- `sim logs allball` shows the app's **native** logs (crashes, native
  modules — RN `console.log` lives in Metro). On a terminal it streams
  live; piped it dumps recent history (last 2 minutes on iOS, 300 lines on
  Android); `--for 10` captures the next ten seconds while you reproduce
  something. On Android the app must be running, since logcat filters by
  its pid.

`sim doctor` checks the whole environment — Xcode and iOS runtimes, jq,
Android SDK, emulator, adb, avdmanager, Java, emulator DNS setting, the
toolset's own install state, Node, and whether the MCP server is registered
with each installed client — and prints fix hints for anything missing.
Point a peer at it when their machine misbehaves.

Android devices show their **display name** ("Pixel 9 Pro XL") everywhere,
like Android Studio does. `sim rename` edits that display name — spaces and
anything else allowed, even while the emulator runs — while the underlying
AVD id (`Pixel_9_Pro_XL`, what adb and the emulator use) stays stable and
visible in `sim ls --json`. Creating a device with a spacey `--name` does
the same split automatically. Matching accepts either form.

## What "cold boot" means per platform

- **iOS**: `simctl shutdown` followed by `simctl boot` — a full restart.
- **Android**: kills the emulator, waits for it to disappear from adb (up to
  ~20 s), then relaunches with `-no-snapshot-load` so it boots from scratch
  instead of restoring the quick-boot snapshot.

## Android emulator DNS

The emulator has no resolver of its own. When it starts it snapshots the
Mac's DNS servers and forwards to them for the rest of its life — it never
re-reads them. So connecting or disconnecting a VPN, or switching Wi-Fi,
silently kills name resolution inside every running emulator: requests to
an IP keep working, hostnames stop resolving, and anything that relies on
a hostname — FCM push (a persistent socket to `mtalk.google.com`), analytics,
your API by name — goes quiet with no error in the app. It looks like a
backend problem until you cold boot the emulator and everything arrives.

`sim` and the app therefore launch every emulator with
`-dns-server 8.8.8.8,1.1.1.1`, so name resolution no longer depends on the
network state at launch. Change it in `~/.config/sim/config`
(`key=value` lines, shared by the CLI and the app):

```
# up to 4 comma-separated servers
android_dns=8.8.8.8,1.1.1.1
# or keep the emulator's own behavior — needed when your VPN blocks outside
# DNS, or your app relies on hostnames that only the VPN's resolver knows
android_dns=host
```

`SIM_ANDROID_DNS` in the environment overrides the file for one shell.
`sim doctor` shows the effective setting. Only emulators launched by `sim`,
the app, or the MCP server get the flag — one started from Android Studio
doesn't — and a running emulator picks it up on its next cold boot.

## Configuration and files

Everything user-specific lives in `~/.config/sim/` (honours
`$XDG_CONFIG_HOME`) and is shared by the CLI, the app, and the MCP server:

| File | Contents |
| ---- | -------- |
| `favorites` | one device id per line |
| `config` | `key=value` settings, `#` comments, last value wins — today just `android_dns` |
| `mcp-registered.<client>` | markers for the clients `sim mcp` registered with, so `sim update` won't re-add a server you removed on purpose |
| `update-state.json` | transient, written by the app while it updates itself |

Environment variables:

| Variable | Effect |
| -------- | ------ |
| `ANDROID_HOME`, `ANDROID_SDK_ROOT` | where the Android SDK is (default `~/Library/Android/sdk`) |
| `SIM_ANDROID_DNS` | overrides `android_dns` for one shell (`host` to disable pinning) |
| `SIM_NO_MCP=1` | makes `install.sh` skip MCP setup |
| `XDG_CONFIG_HOME` | relocates `~/.config/sim` |

## Development

- `sim` — the whole CLI, one bash script (bash 3.2 compatible, so the macOS
  system bash is fine). It runs straight from the clone via the PATH
  symlink, so edits are live.
- `app/` — the SwiftUI app. Rebuild and reinstall after changing it with
  `app/build.sh`.
- `mcp/` — the MCP server (Node, stdio); it shells out to `sim`, so device
  logic lives in one place. `sim mcp --reinstall` refreshes its
  dependencies.
- `install.sh` — the one-shot installer; `sim update` is the incremental
  version of the same steps.
- `CLAUDE.md` — instructions for AI agents working in this repo; `AGENTS.md`
  is a symlink to it so Cursor and Codex read the same file.

Don't move the clone or copy `sim` out of it: `sim update`, `sim version`,
the app's updater, and the MCP registration all resolve the repo through
the symlink on your PATH.

## Uninstall

```
# turn off "Start at Login" in the menu bar first, then:
pkill -x Simulators
rm -rf /Applications/Simulators.app ~/Applications/Simulators.app
rm -f /opt/homebrew/bin/sim /usr/local/bin/sim
claude mcp remove simulators                  # Claude Code
# Cursor: delete the "simulators" entry from ~/.cursor/mcp.json
# Codex:  delete the [mcp_servers.simulators] table from ~/.codex/config.toml
rm -rf ~/.config/sim                          # favorites and settings
```

Then delete the clone. Your simulators and AVDs are untouched — they belong
to Xcode and the Android SDK.
