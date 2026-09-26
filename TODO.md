# TODO — AI Camera - Music Reader
_Last updated: 2026-09-26 PT by OMR Core_

Shared task list: whoever pushes to `main` updates it in the same commit as the work. Details go in commit messages or `docs/`.

## Locked constraints
- Decoder fp32 on ORT CPU EP; encoder + SegNet fp16 on CoreML EP with CPU fallback
- MIDI: SMF format 1, 480 TPQ
- AGPL package `Packages/omr-homr-ios` stays isolated from the app
- Apple ORT SPM pinned `exact: "1.24.2"`

## Now (in progress)
- [ ] TestFlight build 4 in internal testing: Run Gate-1 (npy + png) + warmup diagnostics — OMR iOS — `c2950ae`, run 36265488038, VALID 12:21 PM PT
- [x] Page pipeline port (homr 7d97c3c `detect_staffs_in_image` + `parse_staffs`): page → SegNet → staffs → per-staff decode → SMF + noteLayout — OMR Core — oracle fixtures in `9839f13`
  - [x] M1: page preprocessing (autocrop, PIL bicubic resize, CLAHE) + SegNet tiling/merge: all 9 oracle pages byte-identical (crop, resized, CLAHE) and 0 SegNet class mismatches; `omr-test segnet-page --compare` — `5fd4ff3`
  - [x] M2: symbol boxes + staff detection + brace/grand-staff → `StaffGeometry` (`PagePipeline.detectStaffs` → `PageStaffLayout`): identical to homr on all 9 oracle pages (every symbol box list, note-head height, staff grids, grand staffs, ensured rows, per-staff geometry + regions); cv2 5.0.0 shape ports (hull, minAreaRect, fitEllipse, intersectConvexConvex, fillPoly, ellipse kernels) exact vs `page_cv2/shapes.json`; `omr-test detect-staffs` — `f9ca549`, ios-sim run 36270574216 green
  - [x] M3: `OMRHomrIOS.parseSheetMusicWithLayout(gray8:width:height:)` (+ `(gray8:width:height:session:)`, `(png:)`, `input:` with `staffOnly: false` for PNG; non-PNG → `unsupportedImageFormat`), `PageInferenceSession` (`load()` from bundle `models/` / `OMR_MODELS_DIR`, or the app's warmed backends), noise mask, per-staff crop/dewarp + decode, position filter, `remove_duplicated_symbols` port, one SMF track per staff (grand staff = 2); `omr-test parse-page --compare` — `d0c1536`, ios-sim run 36271119585 green
  - [x] M4 gate: C-scale page end-to-end 1 staff, 12/12 tokens (== `oracle.c_scale_staff/expected.tokens.json`), valid SMF (8 notes); all 9 oracle pages identical to homr (staff canvases SHA-256, raw + filtered tokens, voices: edit 0); Linux CPU ~4–6 s/page, peak RSS ~1.3 GB (ORT CPU sessions; 12 MP input adds <30 MB) — `d0c1536`
- [x] Swap `StubRecognitionService` for the page path: `PageRecognitionService` (ImageIO → `Gray8Image` upright, bytesPerRow == width → `PageInferenceSession` over `ModelWarmup`'s warmed ORT sessions, lazy + reused, FIFO one parse at a time off main, dropped with the warm sessions on memory warning) → playlist + pinned Play; "Couldn't read this page" + Try again; `page_parse` diagnostics (ms, image, staffCount, warnings, phys_footprint before/after/peak, stages, exact error) + "Page parse" in Copy as prompt; sim tests: gray8 orientation/no-padding, decoder parity vs package PNG decode on 9 oracle inputs, C-scale + all oracle pages on the app path — OMR iOS — this commit, waiting on ios-sim
- [ ] Page parse on a real iPhone: time + peak `phys_footprint` from Copy as prompt (Linux CPU ~1.3 GB; jetsam risk) with 3–5 real sheet photos — OMR iOS + User
- [ ] Draw note highlight boxes once `noteLayout.pageRect` carries page positions (hidden while `.null`) — OMR iOS (waiting on OMR Core)
- [ ] Memory warning re-warm costs ~10 s on the next scan; revisit (keep SegNet, drop decoder?) after device numbers — OMR iOS
- [ ] Build 6 player + playlist: ONE app-wide `PlaybackController` (@MainActor, `.environmentObject` from the App) so playback continues across navigation; Library = scans newest first then samples, tap to play, rename (index.json title only) + delete for scans via swipe / long-press / ⋯; Player play/pause, prev/next, seek + times, tempo 0.5–2× (persisted), instrument; mini-player on Scan + Library; consumer redesign (coral, Scan home, Reading, Result pinned Play + Save to Library, Settings with hidden Developer section); About → Source code & license (bundled LICENSE/NOTICE, every NOTICE entry, ORT 1.24.2 ThirdPartyNotices); SF2Player relicensed AGPL-3.0-or-later with SPDX headers — OMR iOS — this commit, waiting on ios-sim
- [ ] In-app diagnostics: `DiagnosticsLog` (JSONL in Application Support, 2000 entries / 5 MB cap, os_log mirror; warmup, Gate-1, capture, camera, recognition, playback, feedback), Log screen (filters, Clear), "Copy as prompt" (≤4 KB Markdown), visual OMR compare + accuracy feedback on Result + Diagnostics → Compare Gate-1 staff — OMR iOS — `e853f3c` pushed, not yet built on CI (Actions billing block below)

## Next
- [x] iOS: 'Open source (AGPL-3.0)' line in the ASC description + `docs/asc/COPY.md` — OMR iOS — `391c898`
- [ ] ASC screenshots from build 6 consumer UI, 1320x2868, upload via workflow, no submit — OMR iOS
- [ ] Swap in post-ship ASO copy (`docs/asc/COPY.md` → PENDING table) as recognition / highlighting / library / level meter / instrument ship; rerun `docs/asc/check_copy.py` — OMR iOS
- [ ] SF2Player gaps inherited from gbk: pitch bend, drum channel 10, the file's own CC7/10/11, SF2 modulators, filter Q; gbk export's master dynamics not ported — OMR iOS
- [ ] SF2Player seek doesn't retrigger notes held across the seek point — OMR iOS
- [ ] CoreML compiled-model cache: package `cacheDirectory: URL?`; app uses `<AppSupport>/coreml-cache/<sha256>/`, excluded from backup — OMR iOS + OMR Core — implementation follows the approved decision in `docs/coreml-tradeoffs.md`
- [ ] Bump Apple ORT to `exact: "1.30.0"` to match `ort.lock` once upstream tags it (microsoft/onnxruntime-swift-package-manager#46) — OMR Core — blocked upstream

## Blocked / waiting on user
- [ ] GitHub Actions jobs not starting: "recent account payments have failed or your spending limit needs to be increased" (Billing & plans). ios-sim runs 36268535216 (`9839f13`), 36269031273 (`f38272a`), 36269132629 (`e853f3c`, re-run too) never started — User — resolved: ios-sim run 36269240737 on `7432a87` green 1:41 PM PT
- [ ] SF2 playback on a real device (latency, interruptions, headphone unplug, route changes, level meter, playlist prev/next) — User
- [x] Pick a license for SF2Player / gbk — User — decided: AGPL-3.0-or-later like the app (`Packages/SF2Player/LICENSE`, SPDX headers), this commit
- [ ] Build 4 Warmup + Gate-1 screenshots from a real device — User
- [ ] Publish Support/Privacy pages? Drafts in docs/asc/web/, proposed at grepawk.com/music-reader/ — User
- [x] AGPL implications before going public — User — decided: repo public, whole app AGPL-3.0-or-later (root LICENSE + NOTICE, this commit)
- [ ] Optional: written OK from the homr authors (liebharc) for App Store distribution of the AGPL port + ONNX weights — Yisheng
- [ ] Replace marketing screenshots with real captures before App Store submission — User
- [ ] Add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture (needs the Mac) — User

## Done (recent)
- [x] CoreML trade-off decision and measurements: keep the ORT CoreML EP plus a persistent model cache; `docs/coreml-tradeoffs.md` — OMR iOS — approved by Yisheng — 2026-09-26
- [x] Root license: `LICENSE` = verbatim GNU AGPL-3.0 (gnu.org text), `NOTICE` = app copyright (AGPL-3.0-or-later, source URL) + third-party credits (homr, homr ONNX weights, oemer, Polyphonic-TrOMR, GeneralUser GS, ONNX Runtime, OpenCV/Pillow/NumPy ports), README `## License` — OMR Core — this commit — 2026-09-26
- [x] Playlist (samples + every recognized scan saved to Application Support/playlist, swipe-delete scans), Player prev/next + elapsed/total + lock-free live level meter, pinned pulsing Play on Result, Debug screenshot deep links — `fea6193`, ios-sim run 36271239029 green (app 39/39, SF2Player 55/55) — 2026-09-26
- [x] ASC copy: "Open source (AGPL-3.0)." in description (metadata, LISTING.md, COPY.md post-ship), check_copy.py re-run — this commit — 2026-09-26
- [x] ASO copy: upload-ready `docs/asc/metadata/en-US/` (fastlane layout) = `LISTING.md`, shipped-now claims only (capture, import, sample SF2 playback, tempo, model self-test); post-ship copy + pending gates + screenshot captions in `docs/asc/COPY.md`; `check_copy.py` — OMR iOS — this commit — 2026-09-26
- [x] Page pipeline M3 + M4 (`parseSheetMusicWithLayout(gray8:width:height:)`, `PageInferenceSession`, `omr-test parse-page`): all 9 oracle pages identical to homr end to end, 110 tests — `d0c1536`, ios-sim run 36271119585 — 2026-09-26
- [x] SF2 player wired into the app (Result "Play sample" + Diagnostics → `PlayerView`, bundled sweden.midi + GeneralUser-GS.sf2), ios-sim green — `f38272a`, run 36269240737 — 2026-09-26
- [x] Page pipeline M2 (`PagePipeline.detectStaffs(segmentation:width:height:)` → `PageStaffLayout`): identical to homr staff detection on 9 pages, 104 tests — `f9ca549`, ios-sim run 36270574216 — 2026-09-26
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
