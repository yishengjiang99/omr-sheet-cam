# omr-sheet-cam

Standalone native iOS/iPadOS app: photo of engraved Western sheet music → on-device Optical Music Recognition (liebharc/homr) → SMF MIDI + note highlights.

**Not** optical mark recognition (bubble sheets).

## Open in Xcode

Open **`OMRSheetCam.xcodeproj`** (iOS 17+, links local package `Packages/omr-homr-ios` → product `OMRHomrIOS`).

App identity (locked): see `docs/asc/APP_IDENTITY.md` — display name **AI Camera - Music Reader**, bundle id `com.ragnus.vp`.

Gate-1 shell only: no capture UI yet. Blocked on onnx_checkpoints + C-scale fixtures + ORT bindings.


## Locked pipeline

Camera / Photos → optional Vision crop → SegNet fp16 (CoreML) → staff geometry + dewarp (CPU) → Encoder fp16 (CoreML) → cast context fp16→fp32 → Decoder fp32 (ORT CPU) → SMF MIDI + `noteLayout` → local playback + highlights.

## Packages

| Package | License | Contents |
|---------|---------|----------|
| `omr-homr-ios` | AGPL-3.0 | OMR, geometry, tokenizers, decode loop, MIDI writer |
| App (`OMRSheetCam`) | TBD (separate from AGPL) | Gate-1 shell; consumes `midi` + `noteLayout` only |

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

## Build order

1. Staff-only encoder + decoder + C-scale oracle token match (**stop until match**)
2. Bundle models, CoreML warmup, memory budget on device
3. Geometry + SegNet tiling (AGPL package)
4. Capture UI + player UI
5. Parity vs oracle / web fixtures

## Models

From [homr onnx_checkpoints](https://github.com/liebharc/homr/releases/tag/onnx_checkpoints):

- SegNet fp16 (~28.7 MB)
- Encoder fp16 (~26.5 MB)
- Decoder fp32 (~47 MB) — do **not** requantize; ORT CPU only

Fetch the pinned files into `models/` (git-ignored) with `scripts/fetch-models`; exact
asset names + SHA-256 live in `models.lock` (`<sha256>  <filename>  <url>`). The script is
idempotent and exits non-zero on any download or hash mismatch. ONNX files are never committed.

Oracle workspace (exporter only, not iOS runtime): `~/workspace/homr-research`

## AGPL notice

A line-by-line port of geometry / tokenizers / decode loop is AGPL. App Store distribution is legally messy under AGPL; see `Packages/omr-homr-ios/NOTICE` and product decision Option A. Do not copy homr into a proprietary target silently.
