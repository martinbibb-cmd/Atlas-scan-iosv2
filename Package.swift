// swift-tools-version: 5.9
// Atlas Scan V2 — Swift Package
// Core business-logic library (AtlasScanCore) is platform-agnostic and fully
// unit-testable on macOS/Linux. The iOS app source lives under App/ and is
// built with Xcode using AtlasScanCore as a local package dependency.

import PackageDescription

let package = Package(
    name: "AtlasScanV2",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AtlasScanCore",
            targets: ["AtlasScanCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AtlasScanCore",
            dependencies: [],
            path: "Sources/AtlasScanCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AtlasScanCoreTests",
            dependencies: ["AtlasScanCore"],
            path: "Tests/AtlasScanCoreTests"
        )
    ]
)
