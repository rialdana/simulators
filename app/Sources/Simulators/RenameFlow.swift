import AppKit
import Foundation

/// Rename dialog usable from both the menu bar and the window: an NSAlert
/// with a text field, then `sim rename` via the store.
@MainActor
enum RenameFlow {
    static func run(_ device: Device, store: DeviceStore) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rename \(device.name)"
        alert.informativeText = device.platform == .android
            ? "This edits the emulator's display name — spaces are fine, it works while running, and the underlying AVD id stays the same."
            : "The simulator keeps its data and settings."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = device.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != device.name else { return }
        store.rename(device, to: newName)
    }
}
