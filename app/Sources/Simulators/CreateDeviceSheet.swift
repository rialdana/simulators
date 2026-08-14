import SwiftUI

/// "New Device…" sheet: platform → model → OS version pickers, populated
/// from `sim models <platform> --json`, creating via `sim create`.
struct CreateDeviceSheet: View {
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.dismiss) private var dismiss

    @State private var platform: Device.Platform = .ios
    @State private var iosModels: [ModelItem] = []
    @State private var iosVersions: [ModelItem] = []
    @State private var androidDefs: [String] = []
    @State private var androidImages: [String] = []
    @State private var model = ""
    @State private var osChoice = ""
    @State private var customName = ""
    @State private var loading = false
    @State private var creating = false
    @State private var errorText: String?

    struct ModelItem: Decodable, Hashable {
        let name: String
        let id: String
    }
    private struct IOSModels: Decodable {
        let models: [ModelItem]
        let os_versions: [ModelItem]
    }
    private struct AndroidModels: Decodable {
        let models: [String]
        let images_installed: [String]
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Platform", selection: $platform) {
                    Text("iOS").tag(Device.Platform.ios)
                    Text("Android").tag(Device.Platform.android)
                }
                .pickerStyle(.segmented)

                if loading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading available models…").foregroundStyle(.secondary)
                    }
                } else if platform == .ios {
                    Picker("Model", selection: $model) {
                        ForEach(iosModels, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Picker("iOS Version", selection: $osChoice) {
                        ForEach(iosVersions, id: \.name) { Text($0.name).tag($0.name) }
                    }
                } else {
                    Picker("Device", selection: $model) {
                        ForEach(androidDefs, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("System Image", selection: $osChoice) {
                        ForEach(androidImages, id: \.self) {
                            Text($0.replacingOccurrences(of: "system-images;", with: "")).tag($0)
                        }
                    }
                }

                TextField("Name", text: $customName, prompt: Text("Optional — defaults to the model name"))

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if creating {
                    ProgressView().controlSize(.small)
                    Text("Creating…").foregroundStyle(.secondary)
                }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(creating || loading || model.isEmpty || osChoice.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 440, height: 340)
        .task(id: platform) { await loadModels() }
    }

    private func loadModels() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let json = try await SimCLI.run(["models", platform == .ios ? "ios" : "android", "--json"])
            let data = Data(json.utf8)
            if platform == .ios {
                let decoded = try JSONDecoder().decode(IOSModels.self, from: data)
                iosModels = decoded.models
                iosVersions = decoded.os_versions
                model = decoded.models.first(where: { $0.name == "iPhone 17 Pro" })?.name
                    ?? decoded.models.first?.name ?? ""
                osChoice = decoded.os_versions.last?.name ?? ""   // newest runtime
            } else {
                let decoded = try JSONDecoder().decode(AndroidModels.self, from: data)
                androidDefs = decoded.models
                androidImages = decoded.images_installed
                model = decoded.models.first(where: { $0 == "pixel_9" }) ?? decoded.models.first ?? ""
                osChoice = decoded.images_installed.last ?? ""
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func create() {
        creating = true
        errorText = nil
        Task {
            do {
                var args = ["create", platform == .ios ? "ios" : "android", model, osChoice]
                if !customName.isEmpty { args += ["--name", customName] }
                _ = try await SimCLI.run(args, timeout: 900)
                await store.refresh()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            creating = false
        }
    }
}
