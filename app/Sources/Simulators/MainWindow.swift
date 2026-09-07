import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var store: DeviceStore
    @EnvironmentObject private var updates: UpdateModel
    @State private var search = ""
    @State private var filter: PlatformFilter = .all
    @State private var pending: PendingAction?
    @State private var showConfirm = false

    enum PendingAction {
        case erase(Device)
        case delete(Device)

        var device: Device {
            switch self {
            case .erase(let d), .delete(let d): return d
            }
        }
        var title: String {
            switch self {
            case .erase(let d): return "Erase \(d.name)?"
            case .delete(let d): return "Delete \(d.name)?"
            }
        }
    }

    enum PlatformFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case ios = "iOS"
        case android = "Android"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            content
                // The platform filter lives in a scope bar under the toolbar
                // rather than in it: a segmented control there is ~220pt, which
                // pushed the action buttons into an overflow menu at the
                // default window width.
                .safeAreaInset(edge: .top, spacing: 0) { filterBar }
                .navigationTitle("Simulators")
                .toolbar { toolbarContent }
                .searchable(text: $search, prompt: "Search devices")
        }
        .safeAreaInset(edge: .bottom) { statusBar }
        .onAppear {
            WindowActivation.windowOpened()
            // Opened from the menu bar's "Check for Updates…": run it now that
            // there's a window for the progress sheet to attach to.
            updates.runRequestedCheck()
        }
        .onChange(of: updates.checkRequested) { _, requested in
            if requested { updates.runRequestedCheck() }
        }
        .onDisappear { WindowActivation.windowClosed() }
        .sheet(isPresented: $store.showCreateSheet) {
            CreateDeviceSheet().environmentObject(store)
        }
        .sheet(isPresented: activityBinding) {
            ProgressSheet(activity: activity ?? Activity("Working…"))
        }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: $showConfirm,
            presenting: pending
        ) { action in
            switch action {
            case .erase(let device):
                Button("Erase All Content & Settings", role: .destructive) { store.erase(device) }
            case .delete(let device):
                Button("Delete Permanently", role: .destructive) { store.deleteDevice(device) }
            }
        } message: { action in
            switch action {
            case .erase(let device):
                Text("This deletes all apps and data on \(device.name). You can't undo this.")
            case .delete(let device):
                Text("This removes \(device.name) from this Mac entirely, including all of its data. You can't undo this.")
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
        .frame(minWidth: 500, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        if store.devices.isEmpty {
            ContentUnavailableView(
                "No Devices Found",
                systemImage: "iphone.slash",
                description: Text("No iOS simulators or Android AVDs were detected on this Mac.")
            )
        } else if sections.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            List {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.devices) { device in
                            DeviceRow(
                                device: device,
                                onErase: { pending = .erase(device); showConfirm = true },
                                onDelete: { pending = .delete(device); showConfirm = true }
                            )
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                            if section.title == Self.favoritesTitle {
                                Spacer()
                                Button("Cold Boot All") { store.coldBootFavorites() }
                                    .buttonStyle(.link)
                                    .disabled(store.activity != nil)
                                    .help("Restart every favorite from a cold boot, all at once")
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
        }
    }

    private var filterBar: some View {
        Picker("Platform", selection: $filter) {
            ForEach(PlatformFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The "New Device" toolbar button is hidden for now; CreateDeviceSheet
        // is still presented by store.showCreateSheet when it returns.
        ToolbarItem {
            Button {
                store.shutdownAll()
            } label: {
                Label("Shut Down All", systemImage: "power")
            }
            .help("Shut down every simulator and emulator")
            .disabled(store.bootedCount == 0)
        }
        ToolbarItem {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh the device list")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var statusBar: some View {
        HStack {
            Text("\(store.bootedCount) booted · \(store.devices.count) devices")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let version = updates.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Toolset version — sim CLI, app, and MCP server update together")
            }
            Button("Check for Updates…") { Task { await updates.checkForUpdates() } }
                .controlSize(.small)
                .disabled(updates.phase != .idle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// Whatever window-wide work is in flight: an update check or install
    /// first, otherwise a device-store operation. Drives the progress sheet.
    private var activity: Activity? {
        updates.phase.activity ?? store.activity
    }

    private var activityBinding: Binding<Bool> {
        // Read-only: the sheet can't be dismissed by the user, only by the
        // work finishing.
        Binding(get: { activity != nil }, set: { _ in })
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    private static let favoritesTitle = "★ Favorites"

    private var sections: [(title: String, devices: [Device])] {
        let query = Device.normalize(search)
        let visible = store.devices.filter { device in
            switch filter {
            case .all: break
            case .ios: guard device.platform == .ios else { return false }
            case .android: guard device.platform == .android else { return false }
            }
            return query.isEmpty
                || device.normalizedName.contains(query)
                || Device.normalize(device.os).contains(query)
        }

        var result: [(title: String, devices: [Device])] = []
        let favorites = visible.filter { store.isFavorite($0) }
        if !favorites.isEmpty {
            result.append((title: Self.favoritesTitle, devices: favorites))
        }

        var order: [String] = []
        var grouped: [String: [Device]] = [:]
        for device in visible where !store.isFavorite(device) {
            if grouped[device.os] == nil {
                order.append(device.os)
                grouped[device.os] = []
            }
            grouped[device.os]?.append(device)
        }
        result += order.map { (title: $0, devices: grouped[$0] ?? []) }
        return result
    }
}

struct DeviceRow: View {
    @EnvironmentObject private var store: DeviceStore
    let device: Device
    let onErase: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.title3)
                .foregroundStyle(device.booted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(.medium)
                HStack(spacing: 5) {
                    Circle()
                        .fill(device.booted ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                    Text(device.booted ? "Booted" : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if store.busy.contains(device.id) {
                ProgressView()
                    .controlSize(.small)
            } else {
                actionButtons
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button {
                store.toggleFavorite(device)
            } label: {
                Image(systemName: store.isFavorite(device) ? "star.fill" : "star")
                    .foregroundStyle(store.isFavorite(device) ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help(store.isFavorite(device) ? "Remove from favorites" : "Add to favorites")

            if device.booted {
                Button {
                    store.screenshot(device)
                } label: {
                    Label("Screenshot", systemImage: "camera")
                        .labelStyle(.iconOnly)
                }
                .help("Screenshot to the Desktop and reveal it in Finder")

                Button {
                    store.coldBoot(device)
                } label: {
                    Label("Cold Boot", systemImage: "arrow.counterclockwise")
                }
                .help("Shut down completely, then boot fresh")

                Button {
                    store.shutdown(device)
                } label: {
                    Label("Shut Down", systemImage: "power")
                }
            } else {
                Button {
                    store.boot(device)
                } label: {
                    Label("Boot", systemImage: "play.fill")
                }
            }

            Menu {
                if !device.booted {
                    Button("Cold Boot") { store.coldBoot(device) }
                }
                if device.booted && device.platform == .ios {
                    Button("Show in Simulator") { store.boot(device) }
                }
                Button("Rename…") { RenameFlow.run(device, store: store) }
                Divider()
                Button("Erase All Content & Settings…", role: .destructive) { onErase() }
                Button("Delete Device…", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
