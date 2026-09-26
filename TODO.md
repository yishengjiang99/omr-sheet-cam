# omr-sheet-cam TODO

This is the single shared task list. Everyone who pushes to `main` updates it in the same commit as the work, whether they add a line, tick it off, or move it. Keep it short. Put details in commit messages or `docs/`.

Owners: **Core** = OMR Core (the AGPL package `omr-homr-ios`, fixtures, `omr-test`), **iOS** = OMR iOS (app shell, Linux ORT C wrapper), **CoS** = Chief of Staff, **Yisheng** = needs the user.

Priority is **implementation first**. Keep test tooling to what's needed to prove real output.

## Now: Gate 1, where Swift decoder tokens exactly match the homr oracle
- [ ] **iOS**: Linux ONNX Runtime C wrapper `ORTCSession` on `ios/ort-c-linux`. It conforms to `ORTSessionBackend`, runs on CPU only, returns fp16 bytes uncast, and gets the ORT library through a pinned fetch.
- [ ] **Core**: Merge `ios/ort-c-linux`, then run `omr-test decode-staff fixtures/oracle.c_scale_staff/staff.npy` on Linux and post the raw tokens.
- [ ] **Core**: Gate 1 passes when `decodeStaff(tensor:)` output equals the 12 tokens in `fixtures/oracle.c_scale_staff/expected.tokens.json`, with a real exit code.
- [ ] **iOS**: Point `Tests/Gate1StaffTokenMatchTests.swift` at `fixtures/oracle.c_scale_staff/`, loading `staff.npy` and running `decodeStaff`.

## Next
- [ ] **Core**: Port homr's staff preprocessing. `staff.png` to tensor must match `staff.npy`; report the max abs diff.
- [ ] **Yisheng**: When the Mac is online, add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture.
- [ ] **Yisheng**: Get the app target compiled once with `xcodebuild test` on a Mac or CI (still never compiled).
- [ ] Bundle the models in the app, plus warmup and memory on a real device (build-order step 2).

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
