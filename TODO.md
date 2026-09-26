# omr-sheet-cam TODO

This is the single shared task list. Everyone who pushes to `main` updates it in the same commit as the work, whether they add a line, tick it off, or move it. Keep it short. Put details in commit messages or `docs/`.

Owners: **Core** = OMR Core (the AGPL package `omr-homr-ios`, fixtures, `omr-test`), **iOS** = OMR iOS (app shell, Linux ORT C wrapper), **CoS** = Chief of Staff, **Yisheng** = needs the user.

Priority is **implementation first**. Keep test tooling to what's needed to prove real output.

## Now: Gate 1, where Swift decoder tokens exactly match the homr oracle
- [x] **iOS** (merged by **Core** into `main`): Linux ONNX Runtime C wrapper `ORTCSession` on `ios/ort-c-linux`. It conforms to `ORTSessionBackend`, runs on CPU only, returns fp16 bytes uncast, and gets the ORT library through a pinned fetch.
- [x] **Core**: Merge `ios/ort-c-linux`, then run `omr-test decode-staff fixtures/oracle.c_scale_staff/staff.npy` on Linux and post the raw tokens (12 symbols, token_edit=0, exit 0).
- [x] **Core**: Gate 1 passes when `decodeStaff(tensor:)` output equals the 12 tokens in `fixtures/oracle.c_scale_staff/expected.tokens.json`, with a real exit code. PASSED on Linux ORT 1.30.0 CPU: exact match (all 6 fields), `omr-test` exit 0; `Gate1ORTCTests` in `swift test` (52/52).
- [x] **iOS**: Point `Tests/Gate1StaffTokenMatchTests.swift` at `fixtures/oracle.c_scale_staff/`, loading `staff.npy` and running `decodeStaff` over `ORTObjCSession` (encoder `OMR_ENCODER_PROVIDER` coreml|cpu, decoder cpu; CoreML mismatch logs CPU-encoder max-abs diff). Typechecked + run on Linux via ORTCSession harness; never compiled for iOS.
- [x] **Core**: fp16 blocker. `ORTObjCSession` can't bind float16, so iOS now uses the ORT **C API**. `ORTCSession` compiles on Apple against the SPM xcframework's C headers (`CONNXRuntimeApple` target): fp16 via `ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16`, and `.coreML` runs `OrtSessionOptionsAppendExecutionProvider_CoreML` (MLProgram + CPU/GPU, CPU EP kept as fallback) for encoder/SegNet only. `DecoderSession` rejects non-CPU backends, `.coreML` throws on Linux, and `ORTObjCSession` is deprecated. Verified: the 1.24.2 xcframework has both headers, and `OrtGetApiBase` + `..._CoreML` are defined (T) in ios-arm64 and simulator arm64/x86_64.
- [x] **Core**: Apple compile of `ORTCSession` / `CONNXRuntimeApple` checked on macOS CI: ios-sim run 36263560275 (d6f4f2e) passes on the iOS simulator, 7 tests with 1 skipped. The ORT duplicate-link error was fixed app-side in a9ae69a; my `.dynamic` product workaround was reverted.
- [x] **iOS**: App Gate-1 test on `ORTCSession` (encoder `.coreML` default / `.cpu` via `OMR_ENCODER_PROVIDER`, decoder fp32 `.cpu`; skips only if models missing). ios-sim.yml run 36263874805 (8452060, Xcode 26.6, iPhone 17 / iOS 26.5 sim, ORT 1.24.2): **Gate-1 PASS 12/12 on CoreML EP**; 7/7 tests pass. `DISABLE_DIAMOND_PROBLEM_DIAGNOSTIC` removed, not needed.
- [x] **Core**: Deprecated `ORTObjCSession` (onnxruntime-objc) deleted from the package; nothing in the app, tests or package referenced it. Apple SPM pin stays `exact: "1.24.2"` (its `onnxruntime` product is still how the xcframework gets linked) and `CONNXRuntimeApple` stays.
- [ ] **OMR iOS**: run Gate1StaffTokenMatchTests via xcodebuild on Mac simulator + physical iPhone (needs Mac online)
- [ ] **OMR iOS**: in-app "Run Gate-1" for TestFlight testers. npy run: bundled `gate1/` fixtures → package `StaffInferenceSession(encoder:decoder:vocabulary:).decodeStaff` on warmed `ModelWarmup` sessions (encoder CoreML, decoder CPU), `Gate1RunnerTests`; png run via Core's `StaffTensor.fromStaffImage(pngURL:)` (a2e43b9) + png-vs-npy max diff. ios-sim run 36265054473 FAILED in the package (blocks build 4): `Packages/omr-homr-ios/Sources/OMRPNG/PNGDecoder.swift:27:17: error: the compiler is unable to type-check this expression in reasonable time` (Xcode 26.6; OMRPNG now built for iOS since a2e43b9). **Core** to split that expression.
- [x] **OMR iOS**: CI iOS simulator build + Gate-1 CoreML test (macos-latest). `.github/workflows/ios-sim.yml` + shared scheme `OMRSheetCam`. Green: run 36263560275 (d6f4f2e, Xcode 26.6, iPhone 17 / iOS 26.5): build OK, 7 tests, 6 passed, 1 skipped (Gate-1: ORTObjCSession no fp16). Fix a9ae69a: tests link OMRHomrIOS via host app. Run 36263874805: 7/7 pass, Gate-1 PASS 12/12 (CoreML EP).

## Next
- [x] **Core**: Pin Apple SPM onnxruntime exactly. Now `exact: "1.24.2"` (was `from:`). 1.30.0 is **not tagged** on onnxruntime-swift-package-manager; newest tag is 1.24.2, see docs/ORT-LINUX.md "iOS version gap".
- [ ] **Core**: iOS/Linux ORT gap: iOS SPM is 1.24.2 and `ort.lock` is 1.30.0 (1.24.2 encoder context differed by up to 0.0039). Bump to `exact: "1.30.0"` once upstream tags it (open PR microsoft/onnxruntime-swift-package-manager#46).
- [x] **Core**: Port homr's staff preprocessing (`StaffTensor.fromStaffImage`: homr canvas + cv2 INTER_LINEAR port + `ConvertToArray`; pure Swift). `omr-test preprocess-staff staff.png --compare staff.npy`: max/mean abs diff **0/0** (bit-exact), tolerance one gray level (0.0225639). `decode-staff staff.png` gives the 12 tokens exactly, exit 0. Resize and gray conversion are bit-exact against cv2 5.0.0 on 11 cases.
- [x] **Core**: The staff crop and dewarp (`prepare_staff_image`: region, dewarp, `remove_black_contours_at_edges_of_image`) is ported (`StaffPrepare`, `StaffTensor.fromPage`); page + explicit staff geometry → tensor → decode is 12/12 on the C-scale page.
  - [x] **Core**: Oracle `fixtures/oracle.c_scale_prepare/` (homr 7d97c3c, cv2 5.0.0): page, geometry.json, pre-canvas `prepared.png/.npy`, dewarp intermediates, plus a `warped/` case with bent geometry and edge blobs. `tools/oracle/export_prepare_staff.py`.
  - [x] **Core**: Swift `StaffPrepare.prepareStaffImage` + `StaffTensor.fromPage` (`Geometry/StaffPrepare.swift`, `Geometry/OpenCVGeometry.swift`): pure Swift ports of cv2 Subdiv2D, getAffineTransform (LUImpl), warpAffine INTER_LINEAR 8UC1 (float32/FMA kernel), fillConvexPoly, boundingRect, findContours bboxes. Bit-exact on both oracle cases (C-scale page and `warped/`): max abs diff 0.
  - [x] **Core**: `omr-test prepare-staff <page.png> --geometry J [--compare prepared.npy]` (both oracle cases: max_abs_diff 0) and `omr-test decode-staff page.png --geometry J` (12/12). `StaffPrepareTests` (11): seeded cv2 5.0.0 / homr refs (`tools/oracle/export_dewarp_refs.py` → `Tests/.../Fixtures/staff_prepare_cv2/refs.json`): warpAffine 64 cases covering every SIMD tail length, getAffineTransform 200 (exact doubles), fillConvexPoly 150, Subdiv2D simplices 40, remove_black_contours 40; plus both page oracles byte-identical.
  - [ ] **Core**: `StaffGeometry` (grid x/y per line + all staffs' y ranges) is explicit input until SegNet + staff detection are ported (see "Geometry and SegNet tiling" below).
  - [ ] **Core**: Bit-exactness targets cv2 5.0.0 x86_64 AVX2 (the oracle build). The Swift port is deterministic on every platform; cv2's ARM/NEON path wasn't checked. The warpAffine scalar-tail contraction (`fma(x,M0,y*M1)+M2`) matches all 64 refs.
- [x] **Core**: Public PNG helper: `StaffTensor.fromStaffImage(pngURL:)`, `fromStaffImage(pngData:)`, `fromPage(pngURL:geometry:)` (+ `StaffPrepare.prepareStaffImage(pngURL:geometry:)`). Decodes with the package's pure-Swift `OMRPNG` (internal target, now an `OMRHomrIOS` dependency on all platforms; no ImageIO/CoreGraphics, no color management/gamma) then cv2 imread + BGR2GRAY, so iOS and Linux decode identically. staff.png → tensor == staff.npy (max abs diff 0). Unsupported/malformed PNGs throw `StaffTensor.PNGLoadError` (16-bit, sub-byte, interlaced, >65536 px side / >2^27 px, decompression bomb, 3000-mutation fuzz). `omr-test decode-staff/preprocess-staff/prepare-staff` use these entry points. Fix: Xcode 26.6 "unable to type-check in reasonable time" on the RGB→gray line (OMRPNG is now compiled for iOS); split that and other mixed-cast arithmetic chains (OMRPNG, OpenCVGeometry, StaffPrepare, StaffPreprocessing, StaffTensor) into typed intermediates, output bit-identical.
- [ ] **iOS**: Wire a png Gate-1 run in the app: `StaffTensor.fromStaffImage(pngURL: fixtures/oracle.c_scale_staff/staff.png)` → `decodeStaff` (encoder CoreML, decoder CPU) must give the same 12/12 tokens as the staff.npy run.
- [ ] **Yisheng**: When the Mac is online, add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture.
- [ ] **Yisheng**: Get the app target compiled once with `xcodebuild test` on a Mac or CI (still never compiled).
- [x] **OMR iOS**: bundle models into app for on-device run (step 2: warmup + memory). Build phase copies the models.lock files into `OMRSheetCam.app/models/` (98 MB; fails if missing unless test-only with `OMR_MODELS_DIR`). `ModelWarmup` (detached, SegNet/Encoder `.coreML`, Decoder `.cpu`, one dummy run each, `Logger` category `warmup`, `phys_footprint`) + UI debug line; `ModelWarmupTests`. ios-sim run 36264666784 green, 8/8 (sim only: total 11413 ms, encoder create 9764 ms, peak 259 MB; no CoreML main-thread warning). TestFlight build 3 (a4c2e06) already includes it. Next: on-device numbers.
- [x] **TestFlight**: build 3 (1.0, commit `a4c2e06`) VALID and in internal testing (group Internal Testers, yisheng.jiang@gmail.com invited). `ios-testflight.yml` bundles models via `scripts/fetch-models`, fails unless ASC processing is VALID. Listing + screenshots pushed to ASC (`docs/asc/`). Open: publish support/privacy pages (`docs/asc/web/`), then run `docs/asc/push_listing.py`.

## Later (build order 3–5, blocked until Gate 1 passes)
- [ ] Geometry and SegNet tiling in the AGPL package
- [ ] Capture UI and player UI
- [ ] Parity against oracle and web fixtures, including the `ORACLE_REPORT.md` misreads (`piano.grand` read as one staff, the `clefs.bass` F clef)
- [ ] `camera.deskew` input image

## Done
- [x] Repo, team, and App Store identity (`AI Camera - Music Reader`, `com.ragnus.vp`)
- [x] AGPL package scaffold, tokenizers, `vocabulary.json`, and a decode loop matched to homr `ScoreDecoder.generate`
- [x] Swift 6.4 on the shared Linux computer. `swift build` / `swift test` are green on Linux (41/41 at `5d3b43a`).
- [x] SMF writer with one track per staff, `renderTokens` (MIDI + noteLayout from one note list), headless `SMFNoteReader`
- [x] 7 synthetic fixtures with GT and LilyPond-rendered `input.png`
- [x] `scripts/fetch-models` + `models.lock` (SegNet 308 fp16, encoder 465 fp16, decoder 465 fp32, SHA-256 pinned, no LFS)
- [x] homr oracle for the C-scale staff (12 symbols) plus `ORACLE_REPORT.md`
- [x] `ORTSessionBackend` protocol, Encoder/Decoder sessions wired to it, `ORTObjCSession` for iOS
- [x] Thin `omr-test` runner + `scripts/omr-test`
- [x] **Core**: Gate-1 entry `StaffTensor` (`loadNPY`: npy v1/v2/v3, `<f4`/`<f2`/`<f8`, C order) + `StaffInferenceSession(encoder:decoder:vocabulary:)` + `decodeStaff(tensor:)` (51/51 tests on Linux)
