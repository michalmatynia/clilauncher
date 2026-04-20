// swift-tools-version: 5.9
import PackageDescription

let strictTypeSafetySettings: [SwiftSetting] = [
    // Surface isolation and Sendable issues while the package stays on Swift 5 mode.
    .unsafeFlags([
        "-Xfrontend", "-warn-concurrency",
        "-Xfrontend", "-strict-concurrency=complete"
    ])
]

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
            path: "Sources/GeminiLauncherNative",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: strictTypeSafetySettings
        ),
        .testTarget(
            name: "CLILauncherNativeTests",
            dependencies: [
                "GeminiLauncherNative"
            ],
            path: "Tests/CLILauncherNativeTests",
            swiftSettings: strictTypeSafetySettings
        )
    ]
)
