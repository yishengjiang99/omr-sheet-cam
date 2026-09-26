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
- [ ] Playlist (samples + every recognized scan saved to Application Support/playlist, swipe-delete scans), Player prev/next + elapsed/total + lock-free live level meter, pinned pulsing Play on Result, Debug screenshot deep links — OMR iOS — this commit, waiting on ios-sim
- [x] Page pipeline port (homr 7d97c3c `detect_staffs_in_image` + `parse_staffs`): page → SegNet → staffs → per-staff decode → SMF + noteLayout — OMR Core — oracle fixtures in `9839f13`
  - [x] M1: page preprocessing (autocrop, PIL bicubic resize, CLAHE) + SegNet tiling/merge: all 9 oracle pages byte-identical (crop, resized, CLAHE) and 0 SegNet class mismatches; `omr-test segnet-page --compare` — `5fd4ff3`
  - [x] M2: symbol boxes + staff detection + brace/grand-staff → `StaffGeometry` (`PagePipeline.detectStaffs` → `PageStaffLayout`): identical to homr on all 9 oracle pages (every symbol box list, note-head height, staff grids, grand staffs, ensured rows, per-staff geometry + regions); cv2 5.0.0 shape ports (hull, minAreaRect, fitEllipse, intersectConvexConvex, fillPoly, ellipse kernels) exact vs `page_cv2/shapes.json`; `omr-test detect-staffs` — `f9ca549`, ios-sim run 36270574216 green
  - [x] M3: `OMRHomrIOS.parseSheetMusicWithLayout(gray8:width:height:)` (+ `(gray8:width:height:session:)`, `(png:)`, `input:` with `staffOnly: false` for PNG; non-PNG → `unsupportedImageFormat`), `PageInferenceSession` (`load()` from bundle `models/` / `OMR_MODELS_DIR`, or the app's warmed backends), noise mask, per-staff crop/dewarp + decode, position filter, `remove_duplicated_symbols` port, one SMF track per staff (grand staff = 2); `omr-test parse-page --compare` — this commit
  - [x] M4 gate: C-scale page end-to-end 1 staff, 12/12 tokens (== `oracle.c_scale_staff/expected.tokens.json`), valid SMF (8 notes); all 9 oracle pages identical to homr (staff canvases SHA-256, raw + filtered tokens, voices: edit 0); Linux CPU ~4–6 s/page, peak RSS ~1.3 GB (ORT CPU sessions; 12 MP input adds <30 MB) — this commit
- [ ] Swap `StubRecognitionService` for the page path — M3 landed: feed the upright capture as `gray8` to `parseSheetMusicWithLayout(gray8:width:height:)` or build `PageInferenceSession(segnet:encoder:decoder:vocabulary:)` from `WarmedModels` (JPEG via `input:` throws `unsupportedImageFormat`); page iOS peak memory not measured yet — OMR iOS
- [ ] In-app diagnostics: `DiagnosticsLog` (JSONL in Application Support, 2000 entries / 5 MB cap, os_log mirror; warmup, Gate-1, capture, camera, recognition, playback, feedback), Log screen (filters, Clear), "Copy as prompt" (≤4 KB Markdown), visual OMR compare + accuracy feedback on Result + Diagnostics → Compare Gate-1 staff — OMR iOS — `e853f3c` pushed, not yet built on CI (Actions billing block below)

## Next
- [ ] SF2Player gaps inherited from gbk: pitch bend, drum channel 10, the file's own CC7/10/11, SF2 modulators, filter Q; gbk export's master dynamics not ported — OMR iOS
- [ ] SF2Player seek doesn't retrigger notes held across the seek point — OMR iOS
- [ ] CoreML compiled-model cache: package `cacheDirectory: URL?`; app uses `<AppSupport>/coreml-cache/<sha256>/`, excluded from backup — OMR iOS + OMR Core — on hold until the real-device warmup number is in
- [ ] Bump Apple ORT to `exact: "1.30.0"` to match `ort.lock` once upstream tags it (microsoft/onnxruntime-swift-package-manager#46) — OMR Core — blocked upstream

## Blocked / waiting on user
- [ ] GitHub Actions jobs not starting: "recent account payments have failed or your spending limit needs to be increased" (Billing & plans). ios-sim runs 36268535216 (`9839f13`), 36269031273 (`f38272a`), 36269132629 (`e853f3c`, re-run too) never started — User — resolved: ios-sim run 36269240737 on `7432a87` green 1:41 PM PT
- [ ] SF2 playback on a real device (latency, interruptions, headphone unplug, route changes, level meter, playlist prev/next) — User
- [ ] Pick a license for SF2Player / gbk (gbk has no LICENSE; package is "all rights reserved" for now) — User
- [ ] Build 4 Warmup + Gate-1 screenshots from a real device — User
- [ ] Publish Support/Privacy pages? Drafts in docs/asc/web/, proposed at grepawk.com/music-reader/ — User
- [ ] AGPL implications before going public — User
- [ ] Replace marketing screenshots with real captures before App Store submission — User
- [ ] Add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture (needs the Mac) — User

## Done (recent)
- [x] Page pipeline M3 + M4 (`parseSheetMusicWithLayout(gray8:width:height:)`, `PageInferenceSession`, `omr-test parse-page`): all 9 oracle pages identical to homr end to end, 110 tests — this commit — 2026-09-26
- [x] SF2 player wired into the app (Result "Play sample" + Diagnostics → `PlayerView`, bundled sweden.midi + GeneralUser-GS.sf2), ios-sim green — `f38272a`, run 36269240737 — 2026-09-26
- [x] Page pipeline M2 (`PagePipeline.detectStaffs(segmentation:width:height:)` → `PageStaffLayout`): identical to homr staff detection on 9 pages, 104 tests — this commit — 2026-09-26
- [x] Page pipeline M1 (`PagePipeline.preprocess(gray8:width:height:)`, `SegNetSession`): exact vs homr on 9 pages, 92 tests — `5fd4ff3` — 2026-09-26
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
