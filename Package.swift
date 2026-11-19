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
    targets: [
        // ONNX Runtime 1.24.2 xcframework, same artifact + checksum as Packages/omr-homr-ios (see the
        // comment there; Linux uses 1.30.0 via ort.lock).
        .binaryTarget(
            name: "onnxruntime",
            url: "https://github.com/yishengjiang99/omr-sheet-cam/releases/download/ort-1.24.2/pod-archive-onnxruntime-c-1.24.2.zip",
            checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"
        ),
        // The homr port. Sources stay in Packages/omr-homr-ios (its own package keeps the tests and the
        // omr-test runner); a remote package cannot depend on a local sub-package, so this manifest
        // builds the same sources directly. Keep the two manifests' target settings in sync.
        .target(
            name: "OMRHomrIOS",
            dependencies: [
                "OMRPNG",
                "onnxruntime",
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
            dependencies: ["onnxruntime"],
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
