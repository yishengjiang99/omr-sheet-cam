// swift-tools-version: 5.9
import PackageDescription

/// Scan feature shared by omr-sheet-cam and gbk (AGPL-3.0).
///   OMRScanKit  no UI: model warmup, page recognition, progress/cancel, failure taxonomy.
///   OMRScanUI   SwiftUI: capture, reading card, import, `OMRScanFlow`.
/// `OMRScanKit` re-exports `OMRHomrIOS` (the core, `Packages/omr-homr-ios`), so hosts need only
/// these two products. SwiftPM cannot depend on a subfolder of a remote repo, hence this root manifest.
let package = Package(
    name: "OMRScan",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OMRScanKit", targets: ["OMRScanKit"]),
        .library(name: "OMRScanUI", targets: ["OMRScanUI"]),
    ],
    dependencies: [
        .package(path: "Packages/omr-homr-ios"),
    ],
    targets: [
        .target(
            name: "OMRScanKit",
            dependencies: [.product(name: "OMRHomrIOS", package: "omr-homr-ios")],
            path: "Sources/OMRScanKit"
        ),
        .target(
            name: "OMRScanUI",
            dependencies: ["OMRScanKit"],
            path: "Sources/OMRScanUI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OMRScanKitTests",
            dependencies: ["OMRScanKit"],
            path: "Tests/OMRScanKitTests"
        ),
        .testTarget(
            name: "OMRScanUITests",
            dependencies: ["OMRScanUI", "OMRScanKit"],
            path: "Tests/OMRScanUITests"
        ),
    ]
)
