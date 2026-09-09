import Foundation

enum Actions {
    static func boot(_ device: Device) async throws {
        switch device.platform {
        case .ios:
            if !device.booted {
                try await Shell.run("/usr/bin/xcrun", ["simctl", "boot", device.id])
            }
            try await Shell.run("/usr/bin/open", ["-a", "Simulator"])
        case .android:
            guard !device.booted else { return }
            launchEmulator(device)
        }
    }

    static func coldBoot(_ device: Device) async throws {
        switch device.platform {
        case .ios:
            _ = try? await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", device.id])
            try await Shell.run("/usr/bin/xcrun", ["simctl", "boot", device.id])
            try await Shell.run("/usr/bin/open", ["-a", "Simulator"])
        case .android:
            await killEmulator(device)
            launchEmulator(device, "-no-snapshot-load")
        }
    }

    static func shutdown(_ device: Device) async throws {
        switch device.platform {
        case .ios:
            _ = try? await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", device.id])
        case .android:
            await killEmulator(device)
        }
    }

    static func erase(_ device: Device) async throws {
        switch device.platform {
        case .ios:
            _ = try? await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", device.id])
            try await Shell.run("/usr/bin/xcrun", ["simctl", "erase", device.id])
        case .android:
            await killEmulator(device)
            launchEmulator(device, "-wipe-data", "-no-snapshot-load")
        }
    }

    static func shutdownAll(_ devices: [Device]) async {
        _ = try? await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", "all"])
        for device in devices where device.platform == .android && device.booted {
            await killEmulator(device)
        }
    }

    /// Every emulator launch goes through here so the DNS pin (see
    /// SimConfig.androidDNS) applies to boot, cold boot, and erase alike —
    /// the same flags the `sim` CLI passes.
    private static func launchEmulator(_ device: Device, _ flags: String...) {
        guard let emulator = SDKPaths.emulator else { return }
        var command = "'\(emulator)' -avd '\(device.id)'"
        if let dns = SimConfig.androidDNS {
            command += " -dns-server '\(dns)'"
        }
        for flag in flags {
            command += " \(flag)"
        }
        Shell.runDetached(command)
    }

    /// Kill a running emulator and wait until adb no longer reports it, so a
    /// relaunch doesn't race the dying process.
    private static func killEmulator(_ device: Device) async {
        guard let serial = device.serial, let adb = SDKPaths.adb else { return }
        _ = try? await Shell.run(adb, ["-s", serial, "emu", "kill"])
        for _ in 0..<20 {
            let out = (try? await Shell.run(adb, ["devices"])) ?? ""
            if !out.contains(serial) { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
