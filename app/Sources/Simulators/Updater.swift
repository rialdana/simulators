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

    /// Run `sim update` fully detached: it kills this app, rebuilds it, and
    /// relaunches it, so the updater must outlive the app process.
    static func installUpdate() {
        guard let sim = simPath else { return }
        Shell.runDetached("'\(sim)' update")
    }
}

@MainActor
enum UpdateFlow {
    static func run() async {
        do {
            let status = try await Updater.check()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            if status.commitsBehind == 0 {
                alert.messageText = "You're up to date"
                alert.informativeText = "Simulators \(status.current) is the latest version."
                alert.runModal()
            } else {
                let s = status.commitsBehind == 1 ? "" : "s"
                alert.messageText = "Update available"
                alert.informativeText =
                    "\(status.latest) is available — you have \(status.current) " +
                    "(\(status.commitsBehind) commit\(s) behind).\n\n" +
                    "Simulators will update itself and relaunch if the app changed."
                alert.addButton(withTitle: "Update Now")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    Updater.installUpdate()
                }
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
