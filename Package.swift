// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CLILauncherNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CLILauncherNative", targets: ["GeminiLauncherNative"])
    ],
    targets: [
        .executableTarget(
            name: "GeminiLauncherNative",
            path: "Sources/GeminiLauncherNative"
        )
    ]
)
