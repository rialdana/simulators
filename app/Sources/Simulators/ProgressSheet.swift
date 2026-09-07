import SwiftUI

/// What a window-wide, long-running operation is doing right now — the copy
/// shown in the progress sheet while it runs.
struct Activity: Equatable {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

/// The standard macOS "something is happening" sheet: an indeterminate
/// spinner beside a one-line status, attached to the window and not
/// dismissable — it goes away when the work does.
struct ProgressSheet: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.headline)
                if let detail = activity.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 400)
        .interactiveDismissDisabled()
    }
}

/// Alerts that attach to the main window as sheets when it's on screen, and
/// fall back to a standalone modal alert when it isn't (menu-bar-only mode,
/// or the relaunch after an update).
@MainActor
enum Dialogs {
    static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window.canBecomeMain && !window.isSheet && !(window is NSPanel)
        }
    }

    @discardableResult
    static func alert(_ title: String, _ text: String, buttons: [String] = ["OK"]) async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        if let window = mainWindow {
            // Let a progress sheet finish sliding out before the alert attaches.
            for _ in 0..<20 where window.attachedSheet != nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            NSApp.activate(ignoringOtherApps: true)
            return await alert.beginSheetModal(for: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
