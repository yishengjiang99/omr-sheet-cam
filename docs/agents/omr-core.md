# OMR Core

Owns `Packages/omr-homr-ios` (AGPL-3.0). Geometry, tiling, decode loop,
tokenizers, MIDI writer. Never copy into a proprietary target.

## Package layout

| Path | Role |
|------|------|
| `Packages/omr-homr-ios/Package.swift` | SPM; product/module `OMRHomrIOS`; iOS 17+ |
| `Sources/OMRHomrIOS/PublicAPI.swift` | `parseSheetMusicWithLayout` stub |
| `Sources/OMRHomrIOS/Tokenizer/` | Loads `vocabulary.json` + HF tokenizer JSON presence |
| `Sources/OMRHomrIOS/Inference/` | Staff-only encoder/decoder stubs + `DecoderLoop` |
| `Sources/OMRHomrIOS/MIDI/SMFWriter.swift` | SMF format 1, 480 TPQ |
| `Sources/OMRHomrIOS/Resources/` | Upstream vocab/tokenizer assets (no invented tokens) |
| `Tests/OMRHomrIOSTests/Fixtures/c_scale_staff_oracle/` | Gate-1 oracle hook |

## Locked rules

- Decoder: ORT CPU only, fp32; never requantize
- Encoder: fp16 CoreML EP + CPU fallback
- MIDI: SMF format 1, 480 TPQ, metrical
- Gate 1: staff-only C-scale oracle token match before SegNet/UI/geometry

## Blockers for next PR

1. Bundle Encoder fp16 + Decoder fp32 ONNX (release assets / LFS)
2. Wire ORT Swift sessions (CPU decoder; CoreML encoder)
3. Drop C-scale oracle fixtures from `~/workspace/homr-research`
4. Match tokens; only then proceed past gate-1
