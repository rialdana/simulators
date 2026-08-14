import Foundation

enum DeviceLoader {
    static func loadAll() async -> [Device] {
        async let ios = loadIOS()
        async let android = loadAndroid()
        return await ios + android
    }

    static func loadIOS() async -> [Device] {
        guard let json = try? await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"]),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = root["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var result: [Device] = []
        for key in runtimes.keys.sorted(by: runtimeSort) where key.contains("iOS") {
            let os = prettyRuntime(key)
            for entry in runtimes[key] ?? [] {
                guard let name = entry["name"] as? String,
                      let udid = entry["udid"] as? String else { continue }
                let state = entry["state"] as? String ?? "Shutdown"
                result.append(Device(
                    platform: .ios, name: name, id: udid, os: os,
                    booted: state == "Booted", serial: nil
                ))
            }
        }
        return result
    }

    static func loadAndroid() async -> [Device] {
        guard let emulator = SDKPaths.emulator else { return [] }

        // Newer emulators print INFO/crash-report noise; AVD names are
        // restricted to this character set, so filter to that.
        let raw = (try? await Shell.run(emulator, ["-list-avds"])) ?? ""
        let avds = raw.split(whereSeparator: \.isNewline).map(String.init)
            .filter { $0.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil }
        guard !avds.isEmpty else { return [] }

        var running: [String: String] = [:]  // AVD name -> adb serial
        if let adb = SDKPaths.adb {
            let out = (try? await Shell.run(adb, ["devices"])) ?? ""
            let serials = out.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                let l = String(line)
                return l.hasPrefix("emulator-") ? l.components(separatedBy: .whitespaces).first : nil
            }
            for serial in serials {
                // The emulator console replies with \r\n endings. In Swift,
                // "\r\n" is ONE grapheme cluster, so split(separator: "\n")
                // never matches it — split on Character.isNewline instead.
                let name = ((try? await Shell.run(adb, ["-s", serial, "emu", "avd", "name"])) ?? "")
                    .split(whereSeparator: \.isNewline)
                    .first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                if !name.isEmpty { running[name] = serial }
            }
        }

        return avds.map { avd in
            Device(
                platform: .android, name: displayName(for: avd), id: avd, os: "Android",
                booted: running[avd] != nil, serial: running[avd]
            )
        }
    }

    /// AVDs have an optional free-form display name (avd.ini.displayname in
    /// config.ini) alongside their restricted-charset id — show the pretty one.
    private static func displayName(for avd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let avdHome = ProcessInfo.processInfo.environment["ANDROID_AVD_HOME"] ?? "\(home)/.android/avd"
        var config = "\(avdHome)/\(avd).avd/config.ini"
        if !FileManager.default.fileExists(atPath: config),
           let ini = try? String(contentsOfFile: "\(avdHome)/\(avd).ini", encoding: .utf8),
           let pathLine = ini.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("path=") }) {
            config = String(pathLine.dropFirst("path=".count)) + "/config.ini"
        }
        guard let text = try? String(contentsOfFile: config, encoding: .utf8) else { return avd }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("avd.ini.displayname=") {
            let value = String(line.dropFirst("avd.ini.displayname=".count))
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return avd
    }

    /// com.apple.CoreSimulator.SimRuntime.iOS-26-2 -> "iOS 26.2"
    private static func prettyRuntime(_ key: String) -> String {
        let short = key.components(separatedBy: ".SimRuntime.").last ?? key
        let parts = short.split(separator: "-").map(String.init)
        guard parts.count > 1 else { return short }
        return "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
    }

    private static func runtimeSort(_ a: String, _ b: String) -> Bool {
        func version(_ key: String) -> [Int] {
            (key.components(separatedBy: ".SimRuntime.").last ?? key)
                .split(separator: "-").dropFirst().compactMap { Int($0) }
        }
        let va = version(a), vb = version(b)
        for (x, y) in zip(va, vb) where x != y { return x < y }
        return va.count < vb.count
    }
}
