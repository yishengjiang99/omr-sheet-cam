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

## Gate-1 readiness (current)

Fidelity pass on the staff-only decode loop — **no ONNX weights**, **no UI/geometry**.

| Area | Status |
|------|--------|
| Public API `parseSheetMusicWithLayout` + `ParseSheetMusicInput(staffOnly:)` | Present; throws `staffOnlyGate1NotReady` until models+oracle |
| Tokenizer / vocabulary assets from upstream | Bundled (`Resources/`); ids match `Vocabulary()` |
| Decoder loop vs `decoder_inference.py` | Step order, BOS/nonote seeds, EOS stop, `cache_len`, full→reduced context aligned |
| fp16→fp32 context cast seam | `EncoderContext.castToFP32ForDecoder()` widens IEEE754 binary16 |
| Staff-only input assumptions | `StaffInputSpec` NCHW `[1,1,256,1280]`, mean/std from `ConvertToArray` |
| Oracle compare hook | `OracleSymbolSequence` / `decodeStaffOracleSequence` (no invented vocab) |
| SMF format 1 @ 480 TPQ | Writer + 4/4 meta; `SymbolMIDIMapping` interprets tokenizer `note_*`/`C4` strings only |
| Encoder CoreML EP + Decoder ORT CPU wiring | Compile-safe stubs + TODOs |
| C-scale oracle fixtures | Placeholder path — **blocked** |
| ONNX models in repo | **Blocked** (download from upstream release) |
| ORT Swift bindings | **Blocked** |
| SegNet / full-page geometry / App UI | Out of scope (do not start) |

### Remaining blockers

1. Bundle Encoder fp16 + Decoder fp32 ONNX from [onnx_checkpoints](https://github.com/liebharc/homr/releases/tag/onnx_checkpoints) (LFS / release assets; do not requantize decoder).
2. Wire ORT Swift sessions (CoreML EP encoder + CPU-only decoder).
3. Drop C-scale fixtures into `Tests/.../Fixtures/c_scale_staff_oracle/` from `~/workspace/homr-research`.
4. Run oracle token match (`OracleSymbolSequence`); only then leave Gate-1.

## Model execution providers (locked)

| Model | Precision | EP |
|-------|-----------|-----|
| Encoder | fp16 | CoreML EP, CPU fallback |
| Decoder | fp32 | ORT **CPU only** — never GPU/WebGPU/Metal/CoreML; do not requantize |
| SegNet | fp16 | CoreML EP (post gate-1) |

Context cast: encoder fp16 → fp32 before decoder (`staff2score.py` seam).

Staff tile fed to the encoder: NCHW **`[1, 1, 256, 1280]`** after normalize
(mean `0.7931`, std `0.1738`).

## Build notes

```bash
cd Packages/omr-homr-ios
swift test
# or open the package in Xcode 15+ / iOS 17 SDK
```

Linux CI cannot compile Swift here; run tests on macOS.

No App UI code lives in this package. App target under repo `Sources/App` (when
present) must only consume `midi` + `noteLayout`, plus optional oracle hooks.

## Stable API

```swift
import OMRHomrIOS

let result = try OMRHomrIOS.parseSheetMusicWithLayout(
    input: ParseSheetMusicInput(imageData: png, staffOnly: true)
)
// Until models land, expect OMRError.staffOnlyGate1NotReady / modelsNotBundled

// Oracle / token compare hook (once ORT step runner is bound):
// let seq = try session.decodeStaffOracleSequence(normalizedStaffImage:tile, stepRunner: ort)
// seq.mismatches(vs: expectedFromFixture)
```

## Layout

```
Sources/OMRHomrIOS/
  PublicAPI.swift
  Types/          NoteLayout, EncodedSymbol, OracleSymbolSequence, parse I/O
  Tokenizer/      Vocabulary + TokenizerLoader
  Inference/      Encoder/Decoder stubs, DecoderLoop, StaffInputSpec, StaffInferenceSession
  MIDI/           SMFWriter (format 1, 480 TPQ) + SymbolMIDIMapping
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
