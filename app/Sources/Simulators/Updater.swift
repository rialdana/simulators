import Foundation
import AppKit

enum UpdaterError: LocalizedError {
    case repoNotFound
    var errorDescription: String? {
        "Couldn't locate the simulators git clone (the sim CLI should be a symlink into it). Update manually with: git pull && ./install.sh"
    }
}

enum Updater {
    static var simPath: String? {
        ["/opt/homebrew/bin/sim", "/usr/local/bin/sim"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The sim CLI is a symlink into the git clone; resolving it finds the repo.
    static var repoPath: String? {
        guard let sim = simPath,
              let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: sim)
        else { return nil }
        let base = (sim as NSString).deletingLastPathComponent
        let resolved = dest.hasPrefix("/") ? dest : base + "/" + dest
        return ((resolved as NSString).standardizingPath as NSString).deletingLastPathComponent
    }

    struct Status {
        let current: String
        let latest: String
        let commitsBehind: Int
    }

    static func check() async throws -> Status {
        guard let repo = repoPath else { throw UpdaterError.repoNotFound }
        // A stalled network fetch should surface as an error, not a hang.
        try await Shell.run("/usr/bin/git", ["-C", repo, "fetch", "--quiet", "origin"], timeout: 30)
        func describe(_ ref: [String]) async -> String {
            ((try? await Shell.run("/usr/bin/git", ["-C", repo, "describe", "--tags", "--always"] + ref)) ?? "unknown")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let behind = (try? await Shell.run("/usr/bin/git", ["-C", repo, "rev-list", "--count", "HEAD..origin/main"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return Status(
            current: await describe([]),
            latest: await describe(["origin/main"]),
            commitsBehind: Int(behind) ?? 0
        )
    }
}

/// Drives the update UI: the version label, the in-progress indicator, and
/// the "App updated" alert on both sides of a self-replacing update.
@MainActor
final class UpdateModel: ObservableObject {
    static let shared = UpdateModel()

    @Published private(set) var updating = false
    /// Toolset version from `sim version` (e.g. "v1.9.0") — the repo is the
    /// truth, not the bundle: a pull that doesn't touch app/ updates the CLI
    /// and MCP server without rebuilding this binary.
    @Published private(set) var version: String?

    /// `sim update` kills and relaunches this app whenever app/ changed
    /// (build.sh replaces the bundle), so "an update is in flight" can't live
    /// in memory. It lives in this file, written when the update starts;
    /// whichever instance is alive when it ends — this one (app unchanged)
    /// or the relaunched one (app rebuilt) — finds it and reports the result.
    private struct Marker: Codable {
        let fromVersion: String
        let startedAt: Date
    }
    private static var markerURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? "\(SDKPaths.home)/.config"
        return URL(fileURLWithPath: "\(base)/sim/update-state.json")
    }

    func refreshVersion() async {
        version = (try? await SimCLI.run(["version"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Call once at launch: load the version label, and if a marker is
    /// present we're the relaunched half of an update — say how it went.
    func handleLaunch() async {
        await refreshVersion()
        guard let data = try? Data(contentsOf: Self.markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data)
        else { return }
        try? FileManager.default.removeItem(at: Self.markerURL)
        // Far older than any plausible update: a leftover from a crash or a
        // force-quit, not an update that just finished — say nothing.
        guard Date().timeIntervalSince(marker.startedAt) < 30 * 60 else { return }
        if let version, version != marker.fromVersion {
            Self.alert("App updated", "Simulators is now \(version) (was \(marker.fromVersion)).")
        } else {
            Self.alert(
                "Update didn't finish",
                "Simulators is still \(marker.fromVersion). Run `sim update` in Terminal to see what went wrong."
            )
        }
    }

    func checkForUpdates() async {
        do {
            let status = try await Updater.check()
            NSApp.activate(ignoringOtherApps: true)
            if status.commitsBehind == 0 {
                Self.alert("You're up to date", "Simulators \(status.current) is the latest version.")
                return
            }
            let s = status.commitsBehind == 1 ? "" : "s"
            let alert = NSAlert()
            alert.messageText = "Update available"
            alert.informativeText =
                "\(status.latest) is available — you have \(status.current) " +
                "(\(status.commitsBehind) commit\(s) behind).\n\n" +
                "Simulators will update itself and relaunch if the app changed."
            alert.addButton(withTitle: "Update Now")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                install(from: status.current)
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            Self.alert("Couldn't check for updates", error.localizedDescription)
        }
    }

    private func install(from current: String) {
        guard let sim = Updater.simPath else { return }
        let dir = Self.markerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(Marker(fromVersion: current, startedAt: Date())).write(to: Self.markerURL)
        updating = true

        // Not Shell.run: the update may pkill this app to replace it, so the
        // child must not be tied to our pipes or timeout — it has to outlive
        // us. Completion only matters if we're still here to see it.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sim)
        process.arguments = ["update"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { p in
            let code = p.terminationStatus
            Task { @MainActor in await self.finish(exitCode: code, from: current) }
        }
        do {
            try process.run()
        } catch {
            updating = false
            try? FileManager.default.removeItem(at: Self.markerURL)
            Self.alert("Couldn't start the update", error.localizedDescription)
        }
    }

    /// The update finished while we're still running — app/ didn't change
    /// (a rebuild would have replaced this process; handleLaunch covers that).
    private func finish(exitCode: Int32, from current: String) async {
        updating = false
        try? FileManager.default.removeItem(at: Self.markerURL)
        await refreshVersion()
        if exitCode == 0 {
            Self.alert("App updated", "Simulators is now \(version ?? current).")
        } else {
            Self.alert("Update failed", "Run `sim update` in Terminal to see what went wrong.")
        }
    }

    private static func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
