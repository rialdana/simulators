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
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.menu)

        Window("Simulators", id: "main") {
            MainWindow()
                .environmentObject(store)
        }
        .defaultSize(width: 600, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        if store.bootedCount > 0 {
            Label {
                Text("\(store.bootedCount)")
            } icon: {
                Image(systemName: "iphone.gen3")
            }
            .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "iphone.gen3")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only by default; the dock icon appears while the main
        // window is open (see WindowActivation).
        NSApp.setActivationPolicy(.accessory)
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
