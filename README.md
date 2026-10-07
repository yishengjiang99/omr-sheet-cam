# omr-sheet-cam

Standalone native iOS/iPadOS app: photo of engraved Western sheet music → on-device Optical Music Recognition ([liebharc/homr](https://github.com/liebharc/homr)) → SMF MIDI + note highlights.

**Not** optical mark recognition (bubble sheets).

App identity (locked): see [`docs/asc/APP_IDENTITY.md`](docs/asc/APP_IDENTITY.md) — App Store name **AI Camera - Music Reader**, home-screen display name **SheetCam**, bundle id `com.ragnus.vp`.

## Open in Xcode

Open **`OMRSheetCam.xcodeproj`** (iOS 17+, links local package `Packages/omr-homr-ios` → product `OMRHomrIOS`).

## Locked pipeline

Camera / Photos → optional Vision crop → SegNet fp16 (CoreML EP) → staff geometry + dewarp (CPU) → Encoder fp16 (CoreML EP) → cast context fp16→fp32 → **Decoder fp32 (ORT CPU, zero-copy KV-cache)** → SMF MIDI + `noteLayout` → local playback + highlights.

### Decoder performance (on-device full page)

The decoder no longer copies the 32 KV-cache tensors through Swift `Data` every token step.

| Piece | Behavior |
|-------|----------|
| Default path | `ORTBoundDecoderRunner` — ORT **I/O Binding** (`CreateIoBinding` / `RunWithBinding`). `cache_out*` stay as resident `OrtValue`s and are rebound as `cache_in*` (same idea as upstream `homr` `ScoreDecoder.io_binding`). Only head logits + attention cross to Swift (argmax on native memory). |
| `cacheSwiftBytes` | Instrumentation field: **must be 0** after the initial empty caches (asserted in `DecoderParityTests`). |
| Generic / debug path | Old `ORTCSession.run` alloc+copy path behind `OMR_DECODER_GENERIC=1` or `ORTDecoderStepRunner.forceGenericPath` for exact old-vs-new parity. |
| Timings | `StaffDecodeTiming` (encoder/decoder ms + `DecoderBoundMetrics`: ORT / bind / argmax ms, token count, rebinds, p50/p95). Flows into page `timings` / Copy-as-prompt. |
| Parallel staffs | `PageInferenceSession.staffPool` — each concurrent staff owns its own encoder+decoder ORT session and IoBinding/KV state. Default **concurrency 2 on iPhone**, **1** on Linux / single warmed session; override `OMR_STAFF_CONCURRENCY`. See [`docs/plans/staff-decode-concurrency.md`](docs/plans/staff-decode-concurrency.md). |

Token stream must match the generic path and oracle fixtures exactly (C-scale gate-1 green).

## Docs

- [Staff decode concurrency](docs/plans/staff-decode-concurrency.md) — 1 vs 2 vs 4, session pool, device measurement table
- [CoreML trade-offs](docs/coreml-tradeoffs.md) — ORT CoreML EP + persistent model cache
- [ORT on Linux](docs/ORT-LINUX.md) — `ORTCSession` / `scripts/fetch-ort`

## Packages

| Package | License | Contents |
|---------|---------|----------|
| `omr-homr-ios` | AGPL-3.0 | OMR, geometry, tokenizers, **zero-copy decoder**, page parse, MIDI writer |
| `SF2Player` | AGPL-3.0-or-later | SoundFont 2 synth (gbk port), SMF reader, AVAudioEngine player, level meter |
| App (`OMRSheetCam`) | AGPL-3.0-or-later | Capture, Library, player, IAP/telemetry; consumes `midi` + `noteLayout` |

## Stable API

```swift
parseSheetMusicWithLayout(input:) -> {
  midi: Data,              // SMF format 1, 480 TPQ
  noteLayout: [NoteLayout],
  layoutSource: "attention" | "midi-fallback",
  staffCount: Int,
  warnings: [String]
}
```

## Fixtures

Under `fixtures/` (see `fixtures/README.md`):

- Oracle staff / pages: `oracle.c_scale_staff`, `oracle.pages/*` (exact token / stage GT)
- Real phone photo (snapshot tier, timing / staff-detect / visual QA): **`camera.die_letzte_kompanie`** (`input.jpg` + `meta.yaml`; no expected tokens yet)
- Other camera / synthetic pages: `camera.deskew`, `mono.*`, `piano.grand`, …

## Models

From [homr onnx_checkpoints](https://github.com/liebharc/homr/releases/tag/onnx_checkpoints):

- SegNet fp16 (~28.7 MB)
- Encoder fp16 (~26.5 MB)
- Decoder fp32 (~47 MB) — do **not** requantize; ORT CPU only

Fetch into `models/` (git-ignored) with `scripts/fetch-models`; hashes in `models.lock`. Linux ORT: `scripts/fetch-ort` → `third_party/onnxruntime`.

## License

The whole app is licensed under the [GNU AGPL-3.0](LICENSE) (or later), because it links the AGPL
package `OMRHomrIOS`, whose OMR engine is ported from [liebharc/homr](https://github.com/liebharc/homr).
Third-party credits and licenses (homr, its ONNX models, oemer, Polyphonic-TrOMR, GeneralUser GS,
ONNX Runtime, OpenCV/Pillow/NumPy ports) are in [NOTICE](NOTICE). Corresponding source:
https://github.com/yishengjiang99/omr-sheet-cam
