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
        .library(name: "OMRHomrIOS", targets: ["OMRHomrIOS"]),
        .library(name: "OMRScanKit", targets: ["OMRScanKit"]),
        .library(name: "OMRScanUI", targets: ["OMRScanUI"]),
    ],
    dependencies: [
        // Exact pin shared with Packages/omr-homr-ios (iOS 1.24.2; Linux uses 1.30.0 via ort.lock).
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
    ],
    targets: [
        // The homr port. Sources stay in Packages/omr-homr-ios (its own package keeps the tests and the
        // omr-test runner); a remote package cannot depend on a local sub-package, so this manifest
        // builds the same sources directly. Keep the two manifests' target settings in sync.
        .target(
            name: "OMRHomrIOS",
            dependencies: [
                "OMRPNG",
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                "CONNXRuntimeApple",
            ],
            path: "Packages/omr-homr-ios/Sources/OMRHomrIOS",
            exclude: ["Resources/README.md"],
            resources: [
                .copy("Resources/Tokenizers"),
                .copy("Resources/Vocab"),
            ]
        ),
        .target(name: "OMRPNG", path: "Packages/omr-homr-ios/Sources/OMRPNG"),
        .target(
            name: "CONNXRuntimeApple",
            dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")],
            path: "Packages/omr-homr-ios/Sources/CONNXRuntimeApple",
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "OMRScanKit",
            dependencies: ["OMRHomrIOS"],
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
