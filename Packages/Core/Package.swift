// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        // The only third-party dependency allowed without asking (CLAUDE.md).
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.6.0"),
    ],
    targets: [
        .target(name: "Core", dependencies: [.product(name: "TOMLKit", package: "TOMLKit")]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
