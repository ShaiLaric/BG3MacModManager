// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BG3MacModManager",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "BG3MacModManager",
            path: "Sources/BG3MacModManager",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "BG3MacModManagerTests",
            dependencies: ["BG3MacModManager"],
            path: "Tests/BG3MacModManagerTests"
        )
    ]
)
