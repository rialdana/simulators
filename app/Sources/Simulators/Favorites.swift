import Foundation

/// Favorites are shared with the `sim` CLI through a plain text file:
/// ~/.config/sim/favorites — one device id (simulator UDID or AVD name)
/// per line. Whichever tool writes last wins; both re-read frequently.
enum Favorites {
    static var fileURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? "\(SDKPaths.home)/.config"
        return URL(fileURLWithPath: "\(base)/sim/favorites")
    }

    static func load() -> Set<String> {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Set(
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    static func save(_ favorites: Set<String>) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = favorites.sorted().map { $0 + "\n" }.joined()
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
