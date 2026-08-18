import SwiftUI
import AppKit

@main
struct SimulatorsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DeviceStore()

    init() {
        DebugCLI.runIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(UpdateModel.shared)
        } label: {
            MenuBarLabel(store: store, updates: UpdateModel.shared)
        }
        .menuBarExtraStyle(.menu)

        Window("Simulators", id: "main") {
            MainWindow()
                .environmentObject(store)
                .environmentObject(UpdateModel.shared)
        }
        .defaultSize(width: 600, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var updates: UpdateModel

    private var symbol: String {
        updates.updating ? "arrow.triangle.2.circlepath" : "iphone.gen3"
    }

    var body: some View {
        if store.bootedCount > 0 {
            Label {
                Text("\(store.bootedCount)")
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: symbol)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only by default; the dock icon appears while the main
        // window is open (see WindowActivation).
        NSApp.setActivationPolicy(.accessory)
        // Load the version label; if an update marker is present we're the
        // relaunched half of an update, so report how it went.
        Task { await UpdateModel.shared.handleLaunch() }
    }
}

enum WindowActivation {
    static func windowOpened() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }
}
