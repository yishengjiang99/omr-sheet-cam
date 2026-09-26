# omr-homr-ios

AGPL-3.0 Swift package (`import OMRHomrIOS`) for on-device Optical Music
Recognition compatible with [liebharc/homr](https://github.com/liebharc/homr).

**Do not** link this package into a proprietary App Store target without an
AGPL-compliant distribution plan. See `NOTICE` and `LICENSE`.

## Module / product name

| SPM | Value |
|-----|--------|
| Package name | `omr-homr-ios` |
| Library product | `OMRHomrIOS` |
| Swift module | `OMRHomrIOS` |
| Platforms | iOS 17+, macOS 14+ (tests) |

## Gate-1 status (this scaffold)

Scaffold only — **stop condition** is staff-only **C-scale oracle token match**.

| Area | Status |
|------|--------|
| Public API stub `parseSheetMusicWithLayout` | Present (throws until models+oracle) |
| Tokenizer / vocabulary assets from upstream | Bundled (`Resources/`) |
| Decoder loop structure (`decoder_inference.py`) | Scaffolded; ORT step not faked |
| Encoder CoreML EP + Decoder ORT CPU wiring | Compile-safe stubs + TODOs |
| SMF format 1 @ 480 TPQ writer | Minimal real writer + tests |
| C-scale oracle fixtures | Placeholder path — **blocked** |
| ONNX models in repo | **Blocked** (download from upstream release) |
| SegNet / full-page geometry / App UI | Out of scope (do not start) |

## Model execution providers (locked)

| Model | Precision | EP |
|-------|-----------|-----|
| Encoder | fp16 | CoreML EP, CPU fallback |
| Decoder | fp32 | ORT **CPU only** — never GPU/WebGPU/Metal/CoreML; do not requantize |
| SegNet | fp16 | CoreML EP (post gate-1) |

Context cast: encoder fp16 → fp32 before decoder.

## Build notes

```bash
cd Packages/omr-homr-ios
swift test
# or open the package in Xcode 15+ / iOS 17 SDK
```

Linux CI cannot compile Swift here; run tests on macOS.

No App UI code lives in this package. App target under repo `Sources/App` must
only consume `midi` + `noteLayout`.

## Stable API

```swift
import OMRHomrIOS

let result = try OMRHomrIOS.parseSheetMusicWithLayout(
    input: ParseSheetMusicInput(imageData: png, staffOnly: true)
)
// result.midi          // SMF format 1, 480 TPQ
// result.noteLayout
// result.layoutSource  // .attention | .midiFallback
// result.staffCount
// result.warnings
```

## Layout

```
Sources/OMRHomrIOS/
  PublicAPI.swift
  Types/          NoteLayout, EncodedSymbol, parse I/O
  Tokenizer/      Vocabulary + TokenizerLoader
  Inference/      Encoder/Decoder session stubs, DecoderLoop, StaffInferenceSession
  MIDI/           SMFWriter (format 1, 480 TPQ)
  Resources/
    Vocab/vocabulary.json          # Vocabulary() export
    Tokenizers/tokenizer_*.json    # upstream HF WordLevel copies
Tests/OMRHomrIOSTests/
  Fixtures/c_scale_staff_oracle/   # oracle hook (empty until research export)
```

## Upstream

- Code / algorithms: https://github.com/liebharc/homr (AGPL-3.0)
- Checkpoints: https://github.com/liebharc/homr/releases/tag/onnx_checkpoints
- Oracle exporter workspace (dev machine): `~/workspace/homr-research`
