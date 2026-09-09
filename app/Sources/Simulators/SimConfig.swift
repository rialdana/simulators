import Foundation

/// Settings shared with the `sim` CLI through ~/.config/sim/config:
/// `key=value` lines, `#` comments, last value wins. Resolution order and
/// defaults mirror the CLI exactly so both launch emulators the same way.
enum SimConfig {
    static var fileURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? "\(SDKPaths.home)/.config"
        return URL(fileURLWithPath: "\(base)/sim/config")
    }

    static func value(_ key: String) -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        var found: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            guard trimmed[..<eq].trimmingCharacters(in: .whitespaces) == key else { continue }
            found = String(trimmed[trimmed.index(after: eq)...]).filter { !$0.isWhitespace }
        }
        return found
    }

    /// The emulator snapshots the Mac's DNS servers at launch and never
    /// re-reads them, so a VPN connect/disconnect silently kills name
    /// resolution (and FCM) inside running emulators. Pinning public
    /// resolvers avoids that. `android_dns=host` (or $SIM_ANDROID_DNS=host)
    /// opts back into the emulator's own behavior; the result is nil then.
    static let androidDNSDefault = "8.8.8.8,1.1.1.1"

    static var androidDNS: String? {
        let raw = ProcessInfo.processInfo.environment["SIM_ANDROID_DNS"] ?? value("android_dns") ?? ""
        let chosen = raw.isEmpty ? androidDNSDefault : raw
        if chosen == "host" { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:,-"))
        guard chosen.unicodeScalars.allSatisfy(allowed.contains) else { return androidDNSDefault }
        return chosen
    }
}
