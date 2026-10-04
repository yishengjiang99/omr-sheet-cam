# TODO — AI Camera - Music Reader
_Last updated: 2026-10-04 9:07 AM PT by Chief of Staff_

Shared task list: whoever pushes to `main` updates it in the same commit as the work. Details go in commit messages or `docs/`. Tip `d2ed1ef`. App Review still has **build 15**; TestFlight **build 17** is VALID for device testing.

## Locked constraints
- Decoder fp32 on ORT CPU EP; encoder + SegNet fp16 on CoreML EP with CPU fallback
- MIDI: SMF format 1, 480 TPQ
- AGPL package `Packages/omr-homr-ios` stays isolated from the app
- Apple ORT SPM pinned `exact: "1.24.2"`

## Now (in progress)
- [ ] v1.0 build 15 in App Review (WAITING_FOR_REVIEW, submitted 2026-09-28 ~8:30 PM PT / 03:30 UTC; listing = captioned peach screenshots + rewritten copy, no Sweden). Check with read-only **ASC status** only; do NOT re-run cancel/submit while waiting — Chief of Staff — submit run 36373908988; status rechecked 2026-10-04 ~9:10 AM PT (run 37215746872)
- [ ] Real-device page parse verdict on **TestFlight build 17**: 3–5 real sheet photos → parse time + peak `phys_footprint` from Copy as prompt; pass/fail per photo — OMR iOS + User
- [ ] Real-photo accuracy spot check (2–3 photos, color preprocessing path; diagnostics `preprocess_mode`) — OMR Core + User
- [ ] Regression fixtures (2026-09-27 audit): tuplet rounding, key signatures + accidentals, multi-row/grand-staff timing — OMR Core
- [ ] Memory warning re-warm (~10 s); revisit after device numbers — OMR iOS

## Next
- [ ] Swap in post-ship ASO copy (`docs/asc/COPY.md` → PENDING) as features ship; rerun `docs/asc/check_copy.py` — OMR iOS
- [ ] Real-device CoreML cache numbers (encoder/SegNet cold vs warm) — OMR iOS + User
- [ ] Bump Apple ORT to `exact: "1.30.0"` once upstream tags it — OMR Core — blocked upstream

## Blocked / waiting on user
- [ ] App Review outcome for build 15 — User
- [ ] SF2 playback on a real device via TestFlight build 17 (latency, interruptions, route changes, level meter, playlist; Sheet-mode highlight timing on speaker + Bluetooth) — User
- [ ] Optional: written OK from the homr authors (liebharc) for App Store distribution of the AGPL port + ONNX weights — Yisheng
- [ ] Add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture (needs the Mac) — User

## Done (recent)
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
