# TODO — AI Camera - Music Reader
_Last updated: 2026-09-26 PT by OMR iOS_

Shared task list: whoever pushes to `main` updates it in the same commit as the work. Details go in commit messages or `docs/`.

## Locked constraints
- Decoder fp32 on ORT CPU EP; encoder + SegNet fp16 on CoreML EP with CPU fallback
- MIDI: SMF format 1, 480 TPQ
- AGPL package `Packages/omr-homr-ios` stays isolated from the app
- Apple ORT SPM pinned `exact: "1.24.2"`

## Now (in progress)
- [ ] TestFlight build 4 in internal testing: Run Gate-1 (npy + png) + warmup diagnostics — OMR iOS — `c2950ae`, run 36265488038, VALID 12:21 PM PT
- [ ] SF2 player wired into the app (Result "Play sample" + Diagnostics → `PlayerView`, bundled sweden.midi + GeneralUser-GS.sf2): waiting on ios-sim — OMR iOS — `466c22d` + this commit
- [ ] Page pipeline port (homr 7d97c3c `detect_staffs_in_image` + `parse_staffs`): page → SegNet → staffs → per-staff decode → SMF + noteLayout — OMR Core — oracle fixtures in `9839f13`
  - [ ] M1: page preprocessing (autocrop, PIL bicubic resize, CLAHE) + SegNet tiling/merge, exact vs oracle
  - [ ] M2: symbol boxes + staff detection + brace/grand-staff → `StaffGeometry`
  - [ ] M3: `parseSheetMusicWithLayout` page path (PNG + `gray8:width:height:`) + `omr-test parse-page`
  - [ ] M4 gate: C-scale page end-to-end, 12/12 tokens, valid SMF; edit distances vs homr on other fixtures
- [ ] Swap `StubRecognitionService` for the page path once M3 lands (feed upright capture as `gray8`) — OMR iOS
- [ ] In-app diagnostics: `DiagnosticsLog` (JSONL in Application Support, 2000 entries / 5 MB cap, os_log mirror; warmup, Gate-1, capture, camera, recognition, playback, feedback), Log screen (filters, Clear), "Copy as prompt" (≤4 KB Markdown), visual OMR compare + accuracy feedback on Result + Diagnostics → Compare Gate-1 staff — OMR iOS — ios-sim pending

## Next
- [ ] SF2Player gaps inherited from gbk: pitch bend, drum channel 10, the file's own CC7/10/11, SF2 modulators, filter Q; gbk export's master dynamics not ported — OMR iOS
- [ ] SF2Player seek doesn't retrigger notes held across the seek point — OMR iOS
- [ ] CoreML compiled-model cache: package `cacheDirectory: URL?`; app uses `<AppSupport>/coreml-cache/<sha256>/`, excluded from backup — OMR iOS + OMR Core — on hold until the real-device warmup number is in
- [ ] Bump Apple ORT to `exact: "1.30.0"` to match `ort.lock` once upstream tags it (microsoft/onnxruntime-swift-package-manager#46) — OMR Core — blocked upstream

## Blocked / waiting on user
- [ ] SF2 playback on a real device (latency, interruptions, headphone unplug, route changes) — User
- [ ] Pick a license for SF2Player / gbk (gbk has no LICENSE; package is "all rights reserved" for now) — User
- [ ] Build 4 Warmup + Gate-1 screenshots from a real device — User
- [ ] Publish Support/Privacy pages? Drafts in docs/asc/web/, proposed at grepawk.com/music-reader/ — User
- [ ] AGPL implications before going public — User
- [ ] Replace marketing screenshots with real captures before App Store submission — User
- [ ] Add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture (needs the Mac) — User

## Done (recent)
- [x] `Packages/SF2Player` (non-AGPL gbk port): c_scale + sweden render bit-identical PCM to gbk (SHA-256), 44 Linux tests; GeneralUser-GS.sf2 pinned in models.lock — `466c22d` — 2026-09-26
- [x] homr page-pipeline oracle fixtures: 8 fixtures + synthetic 12 MP page-on-table (`tools/oracle/export_page_pipeline.py`) — `9839f13` — 2026-09-26
- [x] Camera → Result → Player flow: AVCaptureSession, tap focus/expose, torch, PhotosPicker, "Recognition coming soon" stub, Play sample (C scale), Diagnostics sheet; Player is a placeholder — `b1df33e`, ios-sim run 36268276336 16/16 — 2026-09-26
- [x] TestFlight build 4 VALID (Run Gate-1 npy + png, warmup diagnostics) — `c2950ae`, run 36265488038 — 2026-09-26
- [x] OMRPNG Xcode type-check fix; sim CI green — `c2950ae`, run 36265297500 — 2026-09-26
- [x] In-app Run Gate-1 (npy on warmed sessions, png vs npy diff) — `b82e54b`, `eac69aa` — 2026-09-26
- [x] Public PNG entry points `StaffTensor.fromStaffImage(pngURL:/pngData:)`, `fromPage(pngURL:geometry:)` — `a2e43b9` — 2026-09-26
- [x] Staff crop + dewarp port matches homr, 0 pixels different — `c80c04c`, `247c39a` — 2026-09-26
- [x] Step 2 models + warmup + memory: 98 MB models; sim warmup 11.4s (9.8s encoder CoreML compile), peak 259 MB — `1f2aa91`, run 36264666784 — 2026-09-26
- [x] TestFlight build 3 VALID, internal testers — `a4c2e06` — 2026-09-26
- [x] Old ObjC ORT session (`ORTObjCSession`) deleted — `f5be12d` — 2026-09-26
- [x] Gate 1 passes 12/12: Linux ORT CPU and iOS sim (macOS CI) with encoder on CoreML EP — `bd9074e`, run 36263874805 — 2026-09-26
