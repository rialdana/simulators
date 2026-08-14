import SwiftUI
import ServiceManagement

struct MenuContent: View {
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let booted = store.devices.filter(\.booted)
        let favorites = store.favoriteDevices
        let running = booted.filter { !store.isFavorite($0) }

        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { device in
                    DeviceActionsMenu(device: device, showsOS: true, showsStar: false)
                }
            }
        }

        if !running.isEmpty {
            Section("Running") {
                ForEach(running) { device in
                    DeviceActionsMenu(device: device, showsOS: true)
                }
            }
        }

        Section("Devices") {
            Menu("iOS Simulators") {
                ForEach(store.iosRuntimes, id: \.self) { runtime in
                    Section(runtime) {
                        ForEach(store.devices.filter { $0.platform == .ios && $0.os == runtime }) {
                            DeviceActionsMenu(device: $0, showsOS: false)
                        }
                    }
                }
            }
            Menu("Android Emulators") {
                ForEach(store.devices.filter { $0.platform == .android }) {
                    DeviceActionsMenu(device: $0, showsOS: false)
                }
            }
        }

        Section {
            Button("Shut Down All") { store.shutdownAll() }
                .disabled(booted.isEmpty)
        }

        Section {
            Button("New Device…") {
                store.showCreateSheet = true
                openMainWindow()
            }
            Button("Open Simulators…") { openMainWindow() }
        }

        Section {
            LaunchAtLoginToggle()
            Button("Check for Updates…") { Task { await UpdateFlow.run() } }
            Button("Quit Simulators") { NSApp.terminate(nil) }
        }
    }

    private func openMainWindow() {
        WindowActivation.windowOpened()
        openWindow(id: "main")
        // Re-activate after the window materializes so it comes to the front.
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}

struct DeviceActionsMenu: View {
    @EnvironmentObject private var store: DeviceStore
    let device: Device
    var showsOS: Bool
    var showsStar: Bool = true

    var body: some View {
        Menu {
            if device.booted {
                if device.platform == .ios {
                    Button("Show in Simulator") { store.boot(device) }
                }
                Button("Screenshot") { store.screenshot(device) }
                Button("Cold Boot (Restart)") { store.coldBoot(device) }
                Button("Shut Down") { store.shutdown(device) }
            } else {
                Button("Boot") { store.boot(device) }
                Button("Cold Boot") { store.coldBoot(device) }
            }
            Divider()
            Button(store.isFavorite(device) ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(device)
            }
            Button("Rename…") { RenameFlow.run(device, store: store) }
            Menu("Erase…") {
                Button("Erase All Content & Settings", role: .destructive) { store.erase(device) }
            }
            Menu("Delete…") {
                Button("Delete Device Permanently", role: .destructive) { store.deleteDevice(device) }
            }
        } label: {
            Text(label)
        }
    }

    private var label: String {
        var prefix = device.booted ? "🟢 " : ""
        if showsStar && store.isFavorite(device) { prefix += "★ " }
        return prefix + (showsOS ? device.menuLabel : device.name)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Start at Login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    enabled = newValue
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        ))
    }
}
