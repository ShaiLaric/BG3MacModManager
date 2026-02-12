// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BG3MacModManager",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "BG3MacModManager",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/BG3MacModManager"
        ),
        .testTarget(
            name: "BG3MacModManagerTests",
            dependencies: ["BG3MacModManager"],
            path: "Tests/BG3MacModManagerTests"
        )
    ]
)
