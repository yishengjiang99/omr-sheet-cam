# TODO — AI Camera - Music Reader
_Last updated: 2026-10-06 7:52 PM PT by OMR iOS_

Shared task list: whoever pushes to `main` updates it in the same commit as the work. Details go in commit messages or `docs/`. Tip (see latest main). App Review still has **build 15** (do not cancel). Listing/privacy optimized for tip (IAP+telemetry); do not sync listing to ASC until a matching binary is submitted. Redeploy live privacy/support HTML.

## Locked constraints
- Decoder fp32 on ORT CPU EP; encoder + SegNet fp16 on CoreML EP with CPU fallback
- MIDI: SMF format 1, 480 TPQ
- AGPL package `Packages/omr-homr-ios` stays isolated from the app
- Apple ORT SPM pinned `exact: "1.24.2"`

## Now (in progress)
- [ ] Full-page OMR perf later: Core ML encoder offline experiment + fixed-batch-8 SegNet (commits 5–6); optional page locator / stateful decoder (7–8) — OMR iOS
- [ ] v1.0 build 15 in App Review (WAITING_FOR_REVIEW, submitted 2026-09-28 ~8:30 PM PT / 03:30 UTC; listing = captioned peach screenshots + rewritten copy, no Sweden). Check with read-only **ASC status** only; do NOT re-run cancel/submit while waiting — Chief of Staff — submit run 36373908988; status rechecked 2026-10-04 ~9:10 AM PT (run 37215746872)
- [ ] Real-device page parse verdict on latest TestFlight (after recognition-always-on / Library-home fix): 3–5 real sheet photos → parse time + peak `phys_footprint` from Copy as prompt; pass/fail per photo — OMR iOS + User
- [ ] Real-photo accuracy spot check (2–3 photos, color preprocessing path; diagnostics `preprocess_mode`) — OMR Core + User
- [ ] Regression fixtures (2026-09-27 audit): tuplet rounding, key signatures + accidentals, multi-row/grand-staff timing — OMR Core
- [ ] Memory warning re-warm (~10 s); revisit after device numbers — OMR iOS
- [ ] Confirm ASC subscription products `com.ragnus.vp.pro.monthly` / `com.ragnus.vp.pro.yearly` match StoreKitManager + `OMRSheetCam.storekit` — OMR iOS
- [ ] Real-device IAP smoke on new TestFlight: free quota 5/day → paywall; Restore Purchases — OMR iOS + User

## Next
- [ ] ASC console App Privacy: publish answers in `docs/asc/app-privacy.md` (not "Data Not Collected") before next IAP binary submit — User
- [ ] Redeploy `docs/asc/web/privacy.html` + `support.html` to grepawk.com/music-reader/ (live pages still claim no analytics/no IAP) — User / web
- [ ] Real-device CoreML cache numbers (encoder/SegNet cold vs warm) — OMR iOS + User
- [ ] Bump Apple ORT to `exact: "1.30.0"` once upstream tags it — OMR Core — blocked upstream

## Blocked / waiting on user
- [ ] App Review outcome for build 15 — User
- [ ] SF2 playback on a real device via latest TestFlight (latency, interruptions, route changes, level meter, playlist; Sheet-mode highlight timing on speaker + Bluetooth) — User
- [ ] Optional: written OK from the homr authors (liebharc) for App Store distribution of the AGPL port + ONNX weights — Yisheng
- [ ] Add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture (needs the Mac) — User

## Done (recent)
- [x] Parallel staff decode: staffPool + maxStaffConcurrency (iPhone default 2); StaffDecodeTiming; docs/plans/staff-decode-concurrency.md — OMR iOS — 2026-10-06 7:52 PM PT
- [x] Fixture `camera.die_letzte_kompanie` (real photo Die Letzte Kompanie, snapshot tier) — OMR iOS — 2026-10-06 7:50 PM PT
- [x] EncoderContext.castToFP32ForDecoder: single preallocated fp32 buffer (no intermediate [Float]) — OMR iOS — 2026-10-06 7:46 PM PT
- [x] Decoder parity tests (generic vs zero-copy exact match) + StaffDecodeTiming / bound metrics; cacheSwiftBytes=0 — OMR iOS — 2026-10-06 7:45 PM PT
- [x] Decoder KV-cache zero-copy via ORT I/O Binding (`ORTBoundDecoderRunner` / `ORTCDecoderBinding`); generic path behind `OMR_DECODER_GENERIC=1`; gate-1 oracle green — OMR iOS — 2026-10-06 7:42 PM PT
- [x] Sheet Follow: fit-to-page default; no auto zoom/pan during Follow/playback (highlight only) — OMR iOS — 2026-10-06 7:40 PM PT
- [x] ASO listing + privacy honesty: metadata/LISTING/COPY, PrivacyInfo.xcprivacy, app-privacy.md, paywall copy, AGENTS App Store rules; check_copy OK — ASC listing agent — 2026-10-06 7:15 PM PT
- [x] Recognition always on (removed Experimental toggle + cleared legacy UserDefaults key); Library home with how-it-works art + Camera/Photos CTAs (camera no longer first screen) — OMR iOS — 2026-10-06 6:38 PM PT
- [x] IAP/telemetry on main: Analytics, StoreKitManager, ScanQuota, PaywallView, StoreKit config, `docs/omr-iap-xcode-prompt.md`; pbxproj linked with non-colliding IDs (prior D1…001 collided with PBXTargetDependency) — OMR iOS — 2026-10-06
- [x] TestFlight build 17 VALID (grand-staff timing / re-warm copy / per-staff diagnostics) — TF run 37172044074 `ca26f6d` — 2026-10-04
- [x] TestFlight build 17 VALID (grand-staff timing / re-warm copy / per-staff diagnostics) — TF run 37172044074 `ca26f6d` — 2026-10-04
- [x] Playback: Follow defaults off so the scan photo stays still — `d2ed1ef` — 2026-10-04
- [x] Grand-staff hand timing + warmup re-warm copy + per-staff recognition diagnostics — `2ae417b` — 2026-10-04
- [x] CI: add missing `isRewarm` to RecognitionProgress — `ca26f6d` — 2026-10-04
- [x] TestFlight build 16 VALID + assigned Internal Testing (tester sync only `yisheng.jiang@gmail.com`) — TF run 37155733709 `66a866d`; assign runs 37156573471 / 37156693129; export-compliance run 37156465510 — 2026-10-03
- [x] ASC assign Internal Testing: `create_group` / `group_name` / `only_email` (default only that address, never whole team) — `1de253a`, `f0e32a8` — 2026-10-03
- [x] Color preprocessing like homr: color photos decode to RGBX → `parsePage(rgbx:)` autocrop on BGR, Pillow resize in color, then BGR2GRAY + CLAHE; gray scans keep gray path — `e46eeb0` (+ build fixes `ac595d4`, `bc3c8c7`) — 2026-10-03
- [x] SF2 player fidelity (GeneralUser GS) via shared SF2Engine ([sf2player-swift](https://github.com/yishengjiang99/sf2player-swift)): modulators, filter Q, pitch bend, CC1/7/10/11, GM drums ch 10 — `8cdc8bc`, `66a866d` — 2026-10-03
- [x] A–B loop + per-hand mute/solo; held notes re-sound after seek/pause/loop wrap — `fa63bcf` — 2026-10-03
- [x] Note highlighting (homr image positions + notehead boxes; Player Sheet mode) — `86adbb9` — 2026-10-03
