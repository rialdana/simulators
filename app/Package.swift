// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Simulators",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Simulators",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
