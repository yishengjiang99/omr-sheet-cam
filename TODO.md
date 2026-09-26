# omr-sheet-cam TODO

This is the single shared task list. Everyone who pushes to `main` updates it in the same commit as the work, whether they add a line, tick it off, or move it. Keep it short. Put details in commit messages or `docs/`.

Owners: **Core** = OMR Core (the AGPL package `omr-homr-ios`, fixtures, `omr-test`), **iOS** = OMR iOS (app shell, Linux ORT C wrapper), **CoS** = Chief of Staff, **Yisheng** = needs the user.

Priority is **implementation first**. Keep test tooling to what's needed to prove real output.

## Now: Gate 1, where Swift decoder tokens exactly match the homr oracle
- [x] **iOS** (merged by **Core** into `main`): Linux ONNX Runtime C wrapper `ORTCSession` on `ios/ort-c-linux`. It conforms to `ORTSessionBackend`, runs on CPU only, returns fp16 bytes uncast, and gets the ORT library through a pinned fetch.
- [x] **Core**: Merge `ios/ort-c-linux`, then run `omr-test decode-staff fixtures/oracle.c_scale_staff/staff.npy` on Linux and post the raw tokens (12 symbols, token_edit=0, exit 0).
- [x] **Core**: Gate 1 passes when `decodeStaff(tensor:)` output equals the 12 tokens in `fixtures/oracle.c_scale_staff/expected.tokens.json`, with a real exit code. PASSED on Linux ORT 1.30.0 CPU: exact match (all 6 fields), `omr-test` exit 0; `Gate1ORTCTests` in `swift test` (52/52).
- [x] **iOS**: Point `Tests/Gate1StaffTokenMatchTests.swift` at `fixtures/oracle.c_scale_staff/`, loading `staff.npy` and running `decodeStaff` over `ORTObjCSession` (encoder `OMR_ENCODER_PROVIDER` coreml|cpu, decoder cpu; CoreML mismatch logs CPU-encoder max-abs diff). Typechecked + run on Linux via ORTCSession harness; never compiled for iOS.
- [ ] **Core**: `ORTObjCSession` throws `unsupportedElementType` for float16 (onnxruntime-objc has no fp16 element type), so the pinned fp16 encoder can't run on iOS and the app Gate-1 test skips. Needs an fp16 path or fp32 encoder.
- [ ] **OMR iOS**: run Gate1StaffTokenMatchTests via xcodebuild on Mac simulator + physical iPhone (needs Mac online)

## Next
- [x] **Core**: Pin Apple SPM onnxruntime exactly. Now `exact: "1.24.2"` (was `from:`). 1.30.0 is **not tagged** on onnxruntime-swift-package-manager; newest tag is 1.24.2, see docs/ORT-LINUX.md "iOS version gap".
- [ ] **Core**: iOS/Linux ORT gap: iOS SPM is 1.24.2 and `ort.lock` is 1.30.0 (1.24.2 encoder context differed by up to 0.0039). Bump to `exact: "1.30.0"` once upstream tags it (open PR microsoft/onnxruntime-swift-package-manager#46).
- [x] **Core**: Port homr's staff preprocessing (`StaffTensor.fromStaffImage`: homr canvas + cv2 INTER_LINEAR port + `ConvertToArray`; pure Swift). `omr-test preprocess-staff staff.png --compare staff.npy`: max/mean abs diff **0/0** (bit-exact), tolerance one gray level (0.0225639). `decode-staff staff.png` gives the 12 tokens exactly, exit 0. Resize and gray conversion are bit-exact against cv2 5.0.0 on 11 cases.
- [ ] **Core**: The staff crop and dewarp (`prepare_staff_image`: region, dewarp, `remove_black_contours_at_edges_of_image`) is not ported yet. Only canvas + normalize are, so input must already be a cropped staff.
- [ ] **Yisheng**: When the Mac is online, add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture.
- [ ] **Yisheng**: Get the app target compiled once with `xcodebuild test` on a Mac or CI (still never compiled).
- [ ] **OMR iOS**: bundle models into app for on-device run (step 2: warmup + memory)

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
