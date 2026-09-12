// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "CodexAccountMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "codex-account-menu", targets: ["CodexAccountMenu"])
    ],
    targets: [
        .executableTarget(
            name: "CodexAccountMenu"
        ),
        .testTarget(
            name: "CodexAccountMenuTests",
            dependencies: ["CodexAccountMenu"]
        )
    ]
)
