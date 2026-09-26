// swift-tools-version: 5.9
import PackageDescription

/// AGPL-3.0 OMR core for omr-sheet-cam.
/// Product / module name: `OMRHomrIOS` (import OMRHomrIOS).
///
/// ONNX Runtime: onnxruntime-objc (SwiftPM module `OnnxRuntimeBindings`) backs `ORTObjCSession` on
/// iOS / macOS only. It is declared only when the manifest is evaluated on an Apple host (the
/// package ships an Apple-only binary xcframework, so Linux resolution never fetches it) and
/// the target dependency carries a platform condition as well. On Linux the ORT backend is the
/// app-side `ORTCSession` (ORT C API).
#if canImport(Darwin)
let ortPackages: [Package.Dependency] = [
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.2"),
]
let ortTargetDeps: [Target.Dependency] = [
    .product(
        name: "onnxruntime",
        package: "onnxruntime-swift-package-manager",
        condition: .when(platforms: [.iOS, .macOS])
    ),
]
#else
let ortPackages: [Package.Dependency] = []
let ortTargetDeps: [Target.Dependency] = []
#endif

let package = Package(
    name: "omr-homr-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14), // host-side unit tests / SPM build on Mac
    ],
    products: [
        .library(
            name: "OMRHomrIOS",
            targets: ["OMRHomrIOS"]
        ),
        // Non-interactive fixture runner (repo root: scripts/omr-test).
        .executable(name: "omr-test", targets: ["omr-test"]),
    ],
    dependencies: ortPackages,
    targets: [
        .target(
            name: "OMRHomrIOS",
            dependencies: ortTargetDeps,
            path: "Sources/OMRHomrIOS",
            exclude: [
                "Resources/README.md", // docs only; not a bundled resource
            ],
            resources: [
                .copy("Resources/Tokenizers"),
                .copy("Resources/Vocab"),
            ]
        ),
        .executableTarget(
            name: "omr-test",
            dependencies: ["OMRHomrIOS"],
            path: "Sources/omr-test"
        ),
        .testTarget(
            name: "OMRHomrIOSTests",
            dependencies: ["OMRHomrIOS"],
            path: "Tests/OMRHomrIOSTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
