// swift-tools-version: 5.9
import PackageDescription

/// AGPL-3.0 OMR core for omr-sheet-cam.
/// Product / module name: `OMRHomrIOS` (import OMRHomrIOS).
///
/// ONNX Runtime on iOS / macOS: the ORT **C API** (`ORTCSession`, same wrapper as Linux) from the
/// official ONNX Runtime 1.24.2 `onnxruntime.xcframework` (pod-archive-onnxruntime-c-1.24.2.zip;
/// headers include `onnxruntime_c_api.h` and `coreml_provider_factory.h`), linked as a SwiftPM
/// `binaryTarget`. The local `CONNXRuntimeApple` C target re-exports the C headers to Swift.
/// Declared only when the manifest is evaluated on an Apple host (Apple-only binary xcframework,
/// so Linux resolution never fetches it). On Linux the backend is `ORTCSession` over the
/// `CONNXRuntime` system library (see the block at the end of this file).
///
/// Artifact: microsoft/onnxruntime-swift-package-manager now returns 404 (2026-11-19), so the exact zip
/// it pointed at (https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip) is mirrored
/// unmodified on this repo's `ort-1.24.2` release. The checksum is the one that package's 1.24.2
/// manifest declared; SwiftPM verifies it on download. MIT, see NOTICE. Linux `ort.lock` is 1.30.0.
#if canImport(Darwin)
let ortTargetDeps: [Target.Dependency] = [
    .target(name: "onnxruntime", condition: .when(platforms: [.iOS, .macOS])),
    .target(name: "CONNXRuntimeApple", condition: .when(platforms: [.iOS, .macOS])),
]
let ortExtraTargets: [Target] = [
    .binaryTarget(
        name: "onnxruntime",
        url: "https://github.com/yishengjiang99/omr-sheet-cam/releases/download/ort-1.24.2/pod-archive-onnxruntime-c-1.24.2.zip",
        checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"
    ),
    .target(
        name: "CONNXRuntimeApple",
        dependencies: [
            .target(name: "onnxruntime", condition: .when(platforms: [.iOS, .macOS])),
        ],
        path: "Sources/CONNXRuntimeApple",
        linkerSettings: [
            .linkedFramework("CoreML", .when(platforms: [.iOS, .macOS])),
            .linkedFramework("Foundation", .when(platforms: [.iOS, .macOS])),
            .linkedLibrary("c++", .when(platforms: [.iOS, .macOS])),
        ]
    ),
]
#else
let ortTargetDeps: [Target.Dependency] = []
let ortExtraTargets: [Target] = []
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
    targets: [
        .target(
            name: "OMRHomrIOS",
            dependencies: ["OMRPNG"] + ortTargetDeps,
            path: "Sources/OMRHomrIOS",
            exclude: [
                "Resources/README.md", // docs only; not a bundled resource
            ],
            resources: [
                .copy("Resources/Tokenizers"),
                .copy("Resources/Vocab"),
            ]
        ),
        // Pure-Swift PNG reader (inflate + unfilter), all platforms; not a product. OMRHomrIOS uses it
        // for `StaffTensor.fromStaffImage(pngURL:)` / `(pngData:)` / `fromPage(pngURL:geometry:)` so iOS
        // and Linux decode PNGs identically (no ImageIO, no color management).
        .target(
            name: "OMRPNG",
            path: "Sources/OMRPNG"
        ),
        .executableTarget(
            name: "omr-test",
            dependencies: ["OMRHomrIOS"],
            path: "Sources/omr-test"
        ),
        .testTarget(
            name: "OMRHomrIOSTests",
            dependencies: ["OMRHomrIOS", "OMRPNG"],
            path: "Tests/OMRHomrIOSTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ] + ortExtraTargets
)

// MARK: - Linux ONNX Runtime C API (branch ios/ort-c-linux) — self-contained, cherry-pick as one hunk.
//
// Adds the `CONNXRuntime` system library (Sources/CONNXRuntime: module.modulemap + shim.h) and
// links `OMRHomrIOS` against the official libonnxruntime fetched by `scripts/fetch-ort` into
// <repo>/third_party/onnxruntime. Linux only; Apple platforms keep the ORT xcframework + CoreML and
// never see these settings. Enabled automatically when the fetched header exists, so
// `swift build` / `swift test` stay green (ORTCSession compiled out) before fetch-ort runs.
//   OMR_ORT_C=0            force off     OMR_ORT_C=1  force on (error if headers missing)
//   OMR_ORT_ROOT=<dir>     use another ORT install (<dir>/include, <dir>/lib)
// Manual flags (e.g. with OMR_ORT_ROOT unset but headers elsewhere): `scripts/fetch-ort --print-flags`.
import Foundation

#if os(Linux)
let ortCRoot: String = ProcessInfo.processInfo.environment["OMR_ORT_ROOT"]
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../third_party/onnxruntime").standardizedFileURL.path
let ortCEnabled: Bool = {
    switch ProcessInfo.processInfo.environment["OMR_ORT_C"] {
    case "0": return false
    case "1": return true
    default: return FileManager.default.fileExists(atPath: ortCRoot + "/include/onnxruntime_c_api.h")
    }
}()
if ortCEnabled {
    package.targets.append(.systemLibrary(name: "CONNXRuntime", path: "Sources/CONNXRuntime"))
    for target in package.targets where target.name == "OMRHomrIOS" {
        target.dependencies.append(.target(name: "CONNXRuntime", condition: .when(platforms: [.linux])))
        target.swiftSettings = (target.swiftSettings ?? []) + [
            .unsafeFlags(["-Xcc", "-I\(ortCRoot)/include"], .when(platforms: [.linux])),
        ]
        target.linkerSettings = (target.linkerSettings ?? []) + [
            .unsafeFlags(
                ["-L\(ortCRoot)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(ortCRoot)/lib"],
                .when(platforms: [.linux])
            ),
        ]
    }
}
#endif
