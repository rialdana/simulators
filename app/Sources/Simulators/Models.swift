import Foundation

struct Device: Identifiable, Hashable {
    enum Platform: String {
        case ios = "iOS"
        case android = "Android"
    }

    let platform: Platform
    let name: String
    let id: String          // simulator UDID, or AVD name for Android
    let os: String          // "iOS 26.2" or "Android"
    var booted: Bool
    var serial: String?     // adb serial (emulator-5554) when an emulator is running

    var symbol: String {
        switch platform {
        case .ios: return name.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone"
        case .android: return "smartphone"
        }
    }

    /// "iPhone 16e · 26.2" for iOS, plain AVD name for Android.
    var menuLabel: String {
        platform == .ios ? "\(name) · \(os.replacingOccurrences(of: "iOS ", with: ""))" : name
    }

    var normalizedName: String { Device.normalize(name) }

    /// Loose matching, same rules as the `sim` CLI: case-insensitive,
    /// spaces/underscores/dashes ignored.
    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !" _-".contains($0) }
    }
}

enum SDKPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    // GUI apps don't inherit shell env vars, so the default path matters.
    static var androidSDK: String {
        let env = ProcessInfo.processInfo.environment
        return env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"] ?? "\(home)/Library/Android/sdk"
    }

    static var emulator: String? {
        let path = "\(androidSDK)/emulator/emulator"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static var adb: String? {
        [
            "\(androidSDK)/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
