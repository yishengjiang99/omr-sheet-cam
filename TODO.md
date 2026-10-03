# TODO — AI Camera - Music Reader
_Last updated: 2026-10-03 PT by OMR iOS (build 16 work)_

Shared task list: whoever pushes to `main` updates it in the same commit as the work. Details go in commit messages or `docs/`.

## Locked constraints
- Decoder fp32 on ORT CPU EP; encoder + SegNet fp16 on CoreML EP with CPU fallback
- MIDI: SMF format 1, 480 TPQ
- AGPL package `Packages/omr-homr-ios` stays isolated from the app
- Apple ORT SPM pinned `exact: "1.24.2"`

## Now (in progress)
- [ ] v1.0 build 15 in App Review (WAITING_FOR_REVIEW, submitted 2026-09-28 ~8:30 PM PT / 03:30 UTC; listing = captioned peach screenshots + rewritten copy, no Sweden). Check with read-only **ASC status** only; do NOT re-run cancel/submit while waiting — Chief of Staff — submit run 36373908988, status run 36374044212
- [ ] Real-device page parse verdict: 3–5 real sheet photos → parse time + peak `phys_footprint` from Copy as prompt; pass/fail per photo — OMR iOS + User
- [ ] Real-photo accuracy spot check (2–3 photos); if systematically off, file against color-preprocessing gap — OMR Core
- [ ] Failed-parse UX: say why when known (no staff vs no notes) + guidance — OMR iOS
- [ ] Note highlighting: unblock `noteLayout.pageRect` (OMR Core) → boxes on Result — OMR Core + OMR iOS
- [ ] Regression fixtures (2026-09-27 audit): tuplet rounding, key signatures + accidentals, multi-row/grand-staff timing — OMR Core
- [ ] Memory warning re-warm (~10 s); revisit after device numbers — OMR iOS

## Next
- [ ] Color-photo preprocessing gap (app grays before `PagePipeline`; upstream homr autocrops on BGR) — OMR Core
- [ ] Swap in post-ship ASO copy (`docs/asc/COPY.md` → PENDING) as features ship; rerun `docs/asc/check_copy.py` — OMR iOS
- [ ] SF2Player gaps (pitch bend, drum ch 10, CC7/10/11, modulators, filter Q; seek across held notes) — OMR iOS
- [ ] Real-device CoreML cache numbers (encoder/SegNet cold vs warm) — OMR iOS + User
- [ ] Bump Apple ORT to `exact: "1.30.0"` once upstream tags it — OMR Core — blocked upstream

## Blocked / waiting on user
- [ ] App Review outcome for build 15 — User
- [ ] SF2 playback on a real device (latency, interruptions, route changes, level meter, playlist) — User
- [ ] Optional: written OK from the homr authors (liebharc) for App Store distribution of the AGPL port + ONNX weights — Yisheng
- [ ] Add the original 22-token C-scale image from `~/workspace/homr-research` as a second oracle fixture (needs the Mac) — User

## Done (recent)
- [x] Build 16 quick fixes: "Play a sample" + Library sample = public-domain Ode to Joy (`fixtures/samples/ode-to-joy.mid`, `scripts/samples/make-ode-to-joy-midi.py`; gbk parity ref `fixtures/sf2/ode-to-joy.gbk.json`), old copyrighted MIDI deleted; Theme cream/coralSoft adapt to Dark Mode (Player text readable); SegNetTests expects padded batch 8; ios-sim also runs PlaylistStoreTests, SF2PlayerAppTests, Build16Tests — 2026-10-03
- [x] v1.0 build 15 resubmitted WAITING_FOR_REVIEW after pull-from-review + captioned listing (hero mockup first, no Sweden) — `7f68a2f`, cancel `50cf2cf`/`258986c`, submit run 36373908988 — 2026-09-28
- [x] Listing repeatable from repo: `docs/asc/screenshots/en-US/`, `docs/asc/metadata/en-US/`; submit syncs listing; ios-sim skips listing-only pushes — `7f68a2f` — 2026-09-28
- [x] Playlist: auto-advance only in playlist mode (scan/sample play once) — `dd13ea5` — 2026-09-27
- [x] Warmup progress: replay on attach, encoder-step interpolate, ticking ETA ("Warming up… x%") — `bef0fdb`, `b9e4a97`, `1d0e6ea` — 2026-09-27
- [x] Reading screen real recognition progress ("Reading music… 42%") — `affe62c` — 2026-09-27
- [x] Try sample picture: public-domain Ode to Joy (LilyPond) replaces copyrighted Sweden sheet — `ba3564c` (supersedes `d1d9d05`) — 2026-09-27
- [x] Support/Privacy/Terms live at grepawk.com/music-reader/ (pages also in finalcut `public/music-reader/`) — 2026-09-27
- [x] Manual ASC submit + cancel-review + listing-upload workflows — `bf5bff9`, `1d0a257`, `258986c` — 2026-09-27
- [x] Recognition on by default (`RecognitionGate.defaultEnabled = true`) after SegNet CoreML NeuralNetwork fix — `36f75c0`, `83c335d` — 2026-09-27
- [x] Compile fix `lastEncoderMs`/`lastDecoderMs` `public internal(set)` — `4d46162` — 2026-09-27
