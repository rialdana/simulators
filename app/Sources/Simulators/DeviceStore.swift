import Foundation
import Combine
import AppKit

@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = []
    @Published var busy: Set<String> = []
    @Published var favorites: Set<String> = Favorites.load()
    @Published var lastError: String?
    @Published var showCreateSheet = false

    private var timer: Timer?

    init() {
        Task { await refresh() }
        // Cheap polling keeps the menu and window current even when devices
        // are booted/killed from outside the app (CLI, Xcode, Android Studio).
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshIfIdle() }
        }
    }

    var bootedCount: Int { devices.filter(\.booted).count }

    var iosRuntimes: [String] {
        var seen = Set<String>()
        return devices.filter { $0.platform == .ios }.map(\.os).filter { seen.insert($0).inserted }
    }

    func refresh() async {
        devices = await DeviceLoader.loadAll()
        // Re-read so favorites toggled from the CLI show up here too.
        favorites = Favorites.load()
    }

    func isFavorite(_ device: Device) -> Bool {
        favorites.contains(device.id)
    }

    func toggleFavorite(_ device: Device) {
        if favorites.contains(device.id) {
            favorites.remove(device.id)
        } else {
            favorites.insert(device.id)
        }
        Favorites.save(favorites)
    }

    /// Favorites first (in device order), then everything else.
    var favoriteDevices: [Device] { devices.filter { favorites.contains($0.id) } }

    private func refreshIfIdle() async {
        guard busy.isEmpty else { return }
        await refresh()
    }

    func boot(_ d: Device) { perform(d) { try await Actions.boot(d) } }
    func coldBoot(_ d: Device) { perform(d) { try await Actions.coldBoot(d) } }
    func shutdown(_ d: Device) { perform(d) { try await Actions.shutdown(d) } }
    func erase(_ d: Device) { perform(d) { try await Actions.erase(d) } }

    /// Screenshot to ~/Desktop and reveal the file in Finder.
    func screenshot(_ d: Device) {
        perform(d) {
            let path = try await SimCLI.run(["shot", d.id])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    /// Permanently delete a simulator/AVD (the CLI cleans favorites too).
    func deleteDevice(_ d: Device) {
        perform(d) { try await SimCLI.run(["rm", d.id], input: "y\n") }
    }

    func shutdownAll() {
        let snapshot = devices
        busy.formUnion(snapshot.filter(\.booted).map(\.id))
        Task {
            await Actions.shutdownAll(snapshot)
            await refresh()
            busy.subtract(snapshot.map(\.id))
        }
    }

    private func perform(_ device: Device, _ op: @escaping () async throws -> Void) {
        guard !busy.contains(device.id) else { return }
        busy.insert(device.id)
        Task {
            do { try await op() } catch { lastError = error.localizedDescription }
            await refresh()
            busy.remove(device.id)
        }
    }
}
