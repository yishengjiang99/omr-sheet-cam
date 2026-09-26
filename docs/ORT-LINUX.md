# ONNX Runtime C-API path (`ORTCSession`): Linux, plus iOS / macOS

`ORTCSession` backs `ORTSessionBackend` (`Packages/omr-homr-ios/Sources/OMRHomrIOS/Inference/ORTBackend.swift`)
on Linux (this document) and, since 2026-09-26, on iOS / macOS too (see "Apple (C API)" below).
The onnxruntime-objc `ORTObjCSession` was removed (the ObjC API has no Float16 element type).

| Piece | Path |
|-------|------|
| Pinned release + SHA-256 | `ort.lock` (repo root, `models.lock` format; ONNX Runtime **1.30.0**, same as the onnxruntime-objc 1.30.0 pod and pip onnxruntime used by the Python oracle; the iOS SwiftPM pin is still 1.24.2, see below) |
| Fetch + verify + install | `scripts/fetch-ort` → `third_party/onnxruntime/{include,lib}` (gitignored) |
| System library | `Packages/omr-homr-ios/Sources/CONNXRuntime/{module.modulemap,shim.h}` |
| Swift wrapper | `Packages/omr-homr-ios/Sources/OMRHomrIOS/Inference/ORTC/ORTCSession.swift` (`#if canImport(CONNXRuntime)`) |
| Manifest wiring | self-contained block at the end of `Packages/omr-homr-ios/Package.swift` |

## Build

```bash
scripts/fetch-ort                        # x86_64 or aarch64; verifies SHA-256; idempotent
cd Packages/omr-homr-ios && swift build  # auto-detects ../../third_party/onnxruntime on Linux
```

Package.swift enables `CONNXRuntime` on Linux only when the fetched header exists, so builds
without ORT stay green (ORTCSession is compiled out). Overrides: `OMR_ORT_C=0|1`, `OMR_ORT_ROOT=<dir>`.
It adds `-Xcc -I<ort>/include` and `-L<ort>/lib -Xlinker -rpath -Xlinker <ort>/lib` as
Linux-conditional `unsafeFlags` (fine for the root package and local path dependencies).
Manual equivalent for another package that reuses the modulemap: `scripts/fetch-ort --print-flags`.

## iOS version gap (SwiftPM)

`Packages/omr-homr-ios/Package.swift` pins `onnxruntime-swift-package-manager` to `exact: "1.24.2"`.
That is the newest tag published there (`git ls-remote --tags https://github.com/microsoft/onnxruntime-swift-package-manager`
on 2026-09-26: `v1.15.0` … `v1.19.2`, `1.20.0`, `1.24.1`, `1.24.2`; no `1.24.3`, no `1.30.0`).
The 1.30.0 bump exists only as open PR microsoft/onnxruntime-swift-package-manager#46 (branch
`edgchen1/update_to_ort_1.30`, untagged), which points at
`https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.30.0.zip`
(SHA-256 `e6f1670c14406fd9f082bb400ab197a9b0a9646058ca6366e440642e2b54a2ea`; the archive is live, HTTP 200).

Gap: iOS runs ORT **1.24.2**, Linux and the Python oracle run **1.30.0**. On Linux, 1.24.2 gave an fp16
encoder context that differed from 1.30.0 / Python homr by up to 0.0039. Once a `1.30.0` tag is published,
switch to `exact: "1.30.0"`. Don't pin to the PR branch or a revision; it isn't a release.

## Apple (C API)

- Module: `CONNXRuntimeApple` (a C target in `Packages/omr-homr-ios/Sources/CONNXRuntimeApple`) includes
  `<onnxruntime/onnxruntime_c_api.h>` and `<onnxruntime/coreml_provider_factory.h>` from the
  `onnxruntime.xcframework` binary target of onnxruntime-swift-package-manager (pulled in by its
  `onnxruntime` product). The framework has no module map, so the C target re-exports it.
- `.cpu` means the default CPU EP. `.coreML` calls `OrtSessionOptionsAppendExecutionProvider_CoreML(options, 0x010 | 0x020)`
  (MLProgram, CPU+GPU), and the CPU EP stays registered as fallback. Use it for encoder and SegNet only;
  `DecoderSession` rejects any backend that reports a non-CPU provider.
- CoreML compiled-model cache: `ORTCSession(modelURL:provider: .coreML, cacheDirectory:cacheKey:)`. With a
  `cacheDirectory` the EP is appended through `SessionOptionsAppendExecutionProvider("CoreML", …)` with
  `ModelFormat=MLProgram`, `MLComputeUnits=CPUAndGPU` (same as the flags above) and `ModelCacheDirectory`, and the
  model is loaded from bytes with `COREML_CACHE_KEY` (default: the file's SHA-256) appended to `metadata_props`,
  because ORT 1.24.2 otherwise keys the cache on a hash of the model *path*, which changes with every iOS app update.
  `cacheDirectory == nil` keeps the legacy call above unchanged. `.cpu` + `cacheDirectory` throws. Details and caller
  obligations (no invalidation on model change, crash-safety, one creator per model at a time) are in the doc comment
  of that initializer and in `CoreMLModelCache.swift`.
- Verified on 2026-09-26 against `pod-archive-onnxruntime-c-1.24.2.zip` (SHA-256 `f7100a99…600b54`, which matches
  the SPM 1.24.2 checksum): `Headers/` has `onnxruntime_c_api.h` (ORT_API_VERSION 24) and
  `coreml_provider_factory.h`. The slices are static archives (`prelinked_objects.o`). `llvm-nm -g --defined-only`
  shows `T _OrtGetApiBase` and `T _OrtSessionOptionsAppendExecutionProvider_CoreML` in ios-arm64 (arm64) and in
  ios-arm64_x86_64-simulator (arm64 and x86_64). The unreleased 1.30.0 archive from PR #46 (SHA-256 `e6f1670c…54a2ea`,
  ORT_API_VERSION 30) passes the same checks.
- **Not compiled yet.** This host is Linux, so the Apple build is pending macOS CI.

## Locked rules

- Linux: CPU execution provider only. `ORTCSession` never appends an EP there, and `init` throws unless `provider == .cpu`.
- Raw bytes only (float32 / float16 / int64 / int32). No dtype casts in the backend; the single
  fp16 → fp32 context cast is `EncoderContext.castToFP32ForDecoder()`.
- Decoder: fp32 on CPU. Encoder / SegNet: fp16 model on Linux CPU (CoreML only on iOS).
- Threads: `init(modelURL:provider:)` uses 1 intra-op thread (override `OMR_ORT_INTRA_OP_THREADS`)
  because ORT's default multi-threaded pool gave run-to-run different decoder logits for identical
  inputs (Swift and Python ORT 1.30). Use `init(modelURL:provider:intraOpThreads:)` to trade for speed.

## Usage

```swift
let enc = try ORTCSession(modelURL: encoderFP16URL, provider: .cpu)
let ctx16 = try enc.run(inputs: ["input": ORTTensor(type: .float16, shape: [1, 1, 256, 1280], data: tileHalf)],
                        outputNames: ["output"])["output"]!              // float16 [1, 1280, 512]
let ctx = EncoderContext(bytes: ctx16.data, dtype: .float16, shape: ctx16.shape).castToFP32ForDecoder()
let dec = try ORTCSession(modelURL: decoderFP32URL, provider: .cpu)
// feed rhythms/pitchs/lifts/articulations/slurs int64 [1,1], context float32 [1,S,512],
// cache_len int64 [1], cache_in0..31 float32 [1,8,L,64]; read out_* + cache_out0..31.
```
