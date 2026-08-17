#!/usr/bin/env node
// MCP server for iOS simulators and Android emulators.
// A thin typed layer over the `sim` CLI in the repo root — the CLI stays
// the single source of truth for device logic.
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const SIM = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "sim");

function runSim(args, { input, timeoutMs = 120_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(SIM, args, { stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    let err = "";
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`sim ${args.join(" ")} timed out after ${timeoutMs / 1000}s`));
    }, timeoutMs);
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", (e) => { clearTimeout(timer); reject(e); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(out.trim());
      else reject(new Error(err.trim() || out.trim() || `sim exited with code ${code}`));
    });
    if (input) child.stdin.write(input);
    child.stdin.end();
  });
}

async function listDevices() {
  return JSON.parse(await runSim(["ls", "--json"])).devices;
}

const norm = (s) => s.toLowerCase().replace(/[ _-]/g, "");

// Resolve a loose name to exactly one device, mirroring the CLI's rules:
// exact id wins, otherwise normalized substring match must be unique.
async function resolveDevice(name, { preferBooted = false } = {}) {
  const devices = await listDevices();
  const exact = devices.find((d) => d.id === name);
  if (exact) return exact;
  const q = norm(name);
  // Match display name or id — Android AVDs can have a pretty display name
  // ("Pixel 9 Pro XL") on top of their restricted id (Pixel_9_Pro_XL).
  let matches = devices.filter((d) => norm(d.name).includes(q) || norm(d.id).includes(q));
  // For booted-only operations (screenshot, app clear), a unique booted
  // match settles ambiguity — e.g. one booted "iPhone 17 Pro Max" among
  // three runtimes.
  if (preferBooted && matches.length > 1) {
    const booted = matches.filter((d) => d.state === "booted");
    if (booted.length >= 1) matches = booted;
  }
  if (matches.length === 1) return matches[0];
  if (matches.length === 0) {
    throw new Error(`No device matches "${name}". Use list_devices to see what exists.`);
  }
  throw new Error(
    `"${name}" is ambiguous. Matches: ` +
      matches.map((d) => `${d.name} (${d.os}, id: ${d.id})`).join("; ") +
      ". Retry with the exact id or a more specific name."
  );
}

const text = (t) => ({ content: [{ type: "text", text: t }] });
const nameArg = {
  name: z.string().describe(
    "Device name (loose match: case, spaces, underscores, dashes ignored — e.g. 'pixel 9a', '16e') or exact id (simulator UDID / AVD name)"
  ),
};

const server = new McpServer({ name: "simulators", version: "1.8.0" });

server.registerTool(
  "list_devices",
  {
    title: "List simulators and emulators",
    description:
      "List every iOS simulator and Android emulator on this Mac with platform, name, id, OS version, state (booted/off), favorite flag, and adb serial. Call this first to see what exists or to resolve an ambiguous name.",
    annotations: { readOnlyHint: true },
  },
  async () => text(JSON.stringify(await listDevices(), null, 2))
);

server.registerTool(
  "boot_device",
  {
    title: "Boot a device",
    description:
      "Boot an iOS simulator or Android emulator. Android resumes its quick-boot snapshot; use cold_boot_device for a fresh start. Booting an already-booted iOS simulator just brings its window to the front.",
    inputSchema: nameArg,
  },
  async ({ name }) => {
    const d = await resolveDevice(name);
    return text(await runSim(["boot", d.id]));
  }
);

server.registerTool(
  "cold_boot_device",
  {
    title: "Cold boot (restart) a device",
    description:
      "Fully restart a device. iOS: shutdown then boot. Android: kills the emulator, waits for adb to release it (can take ~20s), then relaunches without the quick-boot snapshot. Use this when an emulator is wedged or misbehaving.",
    inputSchema: nameArg,
  },
  async ({ name }) => {
    const d = await resolveDevice(name);
    return text(await runSim(["cold", d.id], { timeoutMs: 180_000 }));
  }
);

server.registerTool(
  "shutdown_device",
  {
    title: "Shut down a device",
    description: "Shut down one iOS simulator or Android emulator.",
    inputSchema: nameArg,
  },
  async ({ name }) => {
    const d = await resolveDevice(name);
    return text(await runSim(["kill", d.id]));
  }
);

server.registerTool(
  "erase_device",
  {
    title: "Erase a device (factory reset)",
    description:
      "Factory reset a device, deleting ALL apps and data on it. This cannot be undone — confirm with the user before calling. The device is left shut down (iOS) or wiped and booting fresh (Android).",
    inputSchema: nameArg,
    annotations: { destructiveHint: true },
  },
  async ({ name }) => {
    const d = await resolveDevice(name);
    return text(await runSim(["erase", d.id], { input: "y\n", timeoutMs: 180_000 }));
  }
);

server.registerTool(
  "boot_favorites",
  {
    title: "Boot favorite devices",
    description:
      "Boot every device the user marked as favorite (iOS and Android together). The right tool for requests like 'launch my favorite simulators'. Set cold=true to cold boot (fully restart) them instead. Already-running favorites are left alone.",
    inputSchema: {
      cold: z.boolean().optional().describe("Cold boot (full restart) instead of a normal boot"),
    },
  },
  async ({ cold }) =>
    text(await runSim([cold ? "cold" : "boot", "favs"], { timeoutMs: 300_000 }))
);

server.registerTool(
  "shutdown_all",
  {
    title: "Shut down everything",
    description: "Shut down every running iOS simulator and Android emulator.",
  },
  async () => text((await runSim(["kill", "all"], { timeoutMs: 180_000 })) || "Everything shut down.")
);

server.registerTool(
  "screenshot_device",
  {
    title: "Screenshot a device",
    description:
      "Take a screenshot of a booted simulator/emulator and return it as an image, so you can see what's currently on the device's screen. Omit name when exactly one device is booted. Ambiguous names prefer the booted match.",
    inputSchema: {
      name: z.string().optional().describe("Device name or id; omit if only one device is booted"),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ name }) => {
    const args = ["shot"];
    if (name) {
      const d = await resolveDevice(name, { preferBooted: true });
      args.push(d.id);
    }
    const tmp = path.join(os.tmpdir(), `sim-shot-${process.pid}-${Date.now()}.png`);
    args.push("--out", tmp);
    await runSim(args);
    // Downscale so the image stays light in the model's context.
    await new Promise((resolve, reject) => {
      const p = spawn("/usr/bin/sips", ["-Z", "1200", tmp]);
      p.on("close", (c) => (c === 0 ? resolve() : reject(new Error("sips resize failed"))));
      p.on("error", reject);
    });
    const data = fs.readFileSync(tmp).toString("base64");
    fs.unlinkSync(tmp);
    return { content: [{ type: "image", data, mimeType: "image/png" }] };
  }
);

server.registerTool(
  "list_device_models",
  {
    title: "List creatable device models",
    description:
      "List the device models and OS versions available for creating a new simulator (iOS: device types + runtimes) or emulator (Android: device definitions + installed system images). Use before create_device.",
    inputSchema: { platform: z.enum(["ios", "android"]) },
    annotations: { readOnlyHint: true },
  },
  async ({ platform }) => text(await runSim(["models", platform, "--json"]))
);

server.registerTool(
  "create_device",
  {
    title: "Create a device",
    description:
      "Create a new iOS simulator or Android emulator. model: an iOS device type (e.g. 'iPhone 17 Pro') or Android device definition id (e.g. 'pixel_9'). os: an iOS version (e.g. '26.2') or Android API level (e.g. '36'). Missing Android system images are downloaded, which can take minutes. The device is created shut down — boot it separately.",
    inputSchema: {
      platform: z.enum(["ios", "android"]),
      model: z.string().describe("Device model — see list_device_models"),
      os: z.string().describe("iOS version or Android API level"),
      name: z.string().optional().describe("Custom device name (defaults to a sensible one)"),
    },
  },
  async ({ platform, model, os: osVersion, name }) => {
    const args = ["create", platform, model, osVersion];
    if (name) args.push("--name", name);
    return text(await runSim(args, { timeoutMs: 900_000 }));
  }
);

server.registerTool(
  "rename_device",
  {
    title: "Rename a device",
    description:
      "Rename a simulator or emulator. Any name works on both platforms (spaces included): iOS renames the simulator directly, Android edits the AVD's display name while its underlying id stays stable. Works on running devices.",
    inputSchema: {
      name: z.string().describe("Current device name or id"),
      new_name: z.string().describe("The new name"),
    },
  },
  async ({ name, new_name }) => {
    const d = await resolveDevice(name);
    return text(await runSim(["rename", d.id, new_name], { timeoutMs: 180_000 }));
  }
);

server.registerTool(
  "delete_device",
  {
    title: "Delete a device (permanent)",
    description:
      "Permanently delete a simulator or emulator, including all of its data. This cannot be undone — confirm with the user before calling.",
    inputSchema: nameArg,
    annotations: { destructiveHint: true },
  },
  async ({ name }) => {
    const d = await resolveDevice(name);
    return text(await runSim(["rm", d.id], { input: "y\n" }));
  }
);

server.registerTool(
  "clear_app_data",
  {
    title: "Clear an app's data & cache",
    description:
      "Reset one app to a fresh-install state on a booted device (Android: pm clear; iOS: reinstall in place). `app` is a name hint or an exact bundle/package id. Destructive to that app's data — confirm with the user first. If several apps match the hint, the call fails and lists the candidates: ask the user which one they mean, then retry with the exact id. `device` is required only when more than one device is booted.",
    inputSchema: {
      app: z.string().describe("App name hint, or exact bundle id (iOS) / package id (Android)"),
      device: z.string().optional().describe("Device name or id; omit if only one device is booted"),
    },
    annotations: { destructiveHint: true },
  },
  async ({ app, device }) => {
    const args = ["clear", app];
    if (device) {
      const d = await resolveDevice(device, { preferBooted: true });
      args.push("--device", d.id);
    }
    return text(await runSim(args, { timeoutMs: 180_000 }));
  }
);

// Shared inputs for per-app tools. Ambiguous app hints fail with the
// candidate list — relay the choices to the user, then retry with the id.
const appArgs = {
  app: z.string().describe("App name hint, or exact bundle id (iOS) / package id (Android)"),
  device: z.string().optional().describe("Device name or id; omit if only one device is booted"),
};

async function appCommand(cmd, app, device, extra = {}) {
  const args = [cmd, app];
  if (device) {
    const d = await resolveDevice(device, { preferBooted: true });
    args.push("--device", d.id);
  }
  return runSim(args, extra);
}

server.registerTool(
  "list_apps",
  {
    title: "List installed apps",
    description:
      "List the user-installed apps on a booted device as JSON ({id, label}). Use it to see what's installed or to resolve an app hint before other per-app tools.",
    inputSchema: {
      device: z.string().optional().describe("Device name or id; omit if only one device is booted"),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ device }) => {
    const args = ["apps", "--json"];
    if (device) {
      const d = await resolveDevice(device, { preferBooted: true });
      args.push("--device", d.id);
    }
    return text(await runSim(args));
  }
);

server.registerTool(
  "launch_app",
  {
    title: "Launch an app",
    description: "Launch an app on a booted device. Fails if it's already running on iOS — use relaunch_app to restart.",
    inputSchema: appArgs,
  },
  async ({ app, device }) => text(await appCommand("launch", app, device))
);

server.registerTool(
  "quit_app",
  {
    title: "Stop an app",
    description: "Stop (force-quit) a running app on a booted device.",
    inputSchema: appArgs,
  },
  async ({ app, device }) => text(await appCommand("quit", app, device))
);

server.registerTool(
  "relaunch_app",
  {
    title: "Relaunch (restart) an app",
    description:
      "Force-stop and relaunch an app on a booted device — e.g. to restart a wedged React Native app without touching Metro or rebooting the device.",
    inputSchema: appArgs,
  },
  async ({ app, device }) => text(await appCommand("relaunch", app, device))
);

server.registerTool(
  "uninstall_app",
  {
    title: "Uninstall an app",
    description:
      "Remove an app and all of its data from a booted device. Destructive and not undoable — confirm with the user first.",
    inputSchema: appArgs,
    annotations: { destructiveHint: true },
  },
  async ({ app, device }) => text(await appCommand("uninstall", app, device, { input: "y\n" }))
);

server.registerTool(
  "install_app",
  {
    title: "Install an app",
    description:
      "Install an app package onto a booted device: a .app bundle (iOS simulator build) or a .apk (Android). The platform is inferred from the file extension; device is only needed when several devices of that platform are booted.",
    inputSchema: {
      path: z.string().describe("Absolute path to a .app bundle or .apk"),
      device: z.string().optional().describe("Device name or id"),
    },
  },
  async ({ path: pkgPath, device }) => {
    const args = ["install", pkgPath];
    if (device) {
      const d = await resolveDevice(device, { preferBooted: true });
      args.push("--device", d.id);
    }
    return text(await runSim(args, { timeoutMs: 300_000 }));
  }
);

server.registerTool(
  "open_url",
  {
    title: "Open a URL / deep link",
    description:
      "Open a URL or deep link (https://…, myapp://…) on booted devices. With no device given it opens on EVERY booted device — handy for testing a deep link on iOS and Android at once.",
    inputSchema: {
      url: z.string().describe("The URL or deep link to open"),
      device: z.string().optional().describe("Device name or id; omit to open on all booted devices"),
    },
  },
  async ({ url, device }) => {
    const args = ["url", url];
    if (device) {
      const d = await resolveDevice(device, { preferBooted: true });
      args.push("--device", d.id);
    }
    return text(await runSim(args));
  }
);

server.registerTool(
  "set_app_permission",
  {
    title: "Set an app permission",
    description:
      "Grant, revoke, or reset a permission for an app on a booted device. Friendly names map per platform: camera, microphone, location, location-always, photos, contacts, calendar, notifications (Android), motion/reminders/media-library/siri/all (iOS). Raw android.permission.* or simctl service names pass through. On Android, reset behaves as revoke, and the permission must be declared in the app's manifest.",
    inputSchema: {
      action: z.enum(["grant", "revoke", "reset"]),
      permission: z.string().describe("Friendly name (e.g. 'camera') or raw platform permission"),
      ...appArgs,
    },
  },
  async ({ action, permission, app, device }) => {
    const args = ["perm", action, permission, app];
    if (device) {
      const d = await resolveDevice(device, { preferBooted: true });
      args.push("--device", d.id);
    }
    return text(await runSim(args));
  }
);

server.registerTool(
  "self_update",
  {
    title: "Update the simulator tools",
    description:
      "Update this toolset itself (the sim CLI, the Simulators menu bar app, and this MCP server) to the latest version from GitHub. Pulls the repo and rebuilds only what changed; the updated MCP server code takes effect in the next session. Use when the user asks to update their simulator tools.",
  },
  async () => text(await runSim(["update"], { timeoutMs: 600_000 }))
);

await server.connect(new StdioServerTransport());
