# Linux ONNX Runtime C-API path (`ORTCSession`)

Linux-only backend for `ORTSessionBackend` (`Packages/omr-homr-ios/Sources/OMRHomrIOS/Inference/ORTBackend.swift`)
so the package and the `omr-test` runner can run real ORT sessions on Linux.
iOS/macOS keep `onnxruntime-objc` + CoreML and never compile this path.

| Piece | Path |
|-------|------|
| Pinned release + SHA-256 | `ort.lock` (repo root, `models.lock` format; ONNX Runtime **1.30.0**, same as the onnxruntime-objc 1.30.0 pod and pip onnxruntime used by the Python oracle) |
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

## Locked rules

- CPU execution provider only: `ORTCSession` never appends an EP; `init` throws unless `provider == .cpu`.
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
