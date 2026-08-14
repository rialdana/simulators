#!/usr/bin/env node
// MCP server for iOS simulators and Android emulators.
// A thin typed layer over the `sim` CLI in the repo root — the CLI stays
// the single source of truth for device logic.
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
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
async function resolveDevice(name) {
  const devices = await listDevices();
  const exact = devices.find((d) => d.id === name);
  if (exact) return exact;
  const q = norm(name);
  const matches = devices.filter((d) => norm(d.name).includes(q));
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

const server = new McpServer({ name: "simulators", version: "1.1.0" });

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
  "self_update",
  {
    title: "Update the simulator tools",
    description:
      "Update this toolset itself (the sim CLI, the Simulators menu bar app, and this MCP server) to the latest version from GitHub. Pulls the repo and rebuilds only what changed; the updated MCP server code takes effect in the next session. Use when the user asks to update their simulator tools.",
  },
  async () => text(await runSim(["update"], { timeoutMs: 600_000 }))
);

await server.connect(new StdioServerTransport());
