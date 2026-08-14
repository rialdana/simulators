import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var store: DeviceStore
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
                .navigationTitle("Simulators")
                .toolbar { toolbarContent }
                .searchable(text: $search, prompt: "Search devices")
        }
        .safeAreaInset(edge: .bottom) { statusBar }
        .onAppear { WindowActivation.windowOpened() }
        .onDisappear { WindowActivation.windowClosed() }
        .sheet(isPresented: $store.showCreateSheet) {
            CreateDeviceSheet().environmentObject(store)
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
                    Section(section.title) {
                        ForEach(section.devices) { device in
                            DeviceRow(
                                device: device,
                                onErase: { pending = .erase(device); showConfirm = true },
                                onDelete: { pending = .delete(device); showConfirm = true }
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Platform", selection: $filter) {
                ForEach(PlatformFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        ToolbarItem {
            Button {
                store.showCreateSheet = true
            } label: {
                Label("New Device", systemImage: "plus")
            }
            .help("Create a new simulator or emulator")
        }
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

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
            result.append((title: "★ Favorites", devices: favorites))
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
