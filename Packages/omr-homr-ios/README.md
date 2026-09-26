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
| C-scale oracle fixtures | Schema + stubs on `fixtures/oracle.c_scale_staff/` — **22/22 tokens blocked** on onnx/homr-research |
| Writer-only Layer B | `WriterOnlyFixtureTests` vs repo-root `fixtures/` (7 synthetics complete) |
| Tokens → MIDI + `noteLayout` (Layer C) | `OMRHomrIOS.renderTokens` — one shared note list; `midi-fallback` (no boxes) until attention lands |
| ONNX models in repo | **Blocked** (download from upstream release) |
| ORT Swift bindings | **Blocked** |
| SegNet / full-page geometry / App UI | Out of scope (do not start) |

### Remaining blockers

1. Bundle Encoder fp16 + Decoder fp32 ONNX from [onnx_checkpoints](https://github.com/liebharc/homr/releases/tag/onnx_checkpoints) (LFS / release assets; do not requantize decoder).
2. Wire ORT Swift sessions (CoreML EP encoder + CPU-only decoder).
3. Export real 22/22 oracle tokens into `fixtures/oracle.c_scale_staff/` from `~/workspace/homr-research` (do not invent).
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

Builds and tests on Linux too (Swift 6.x toolchain; `CGRect` comes from swift-corelibs-foundation there).

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

## Tokens → MIDI + noteLayout (Layer C helper)

`OMRHomrIOS.renderTokens(_:staffIndexOffset:boxProvider:writer:) -> ParseSheetMusicResult`
(`Sources/OMRHomrIOS/Layout/TokenRender.swift`) writes the SMF **and** `noteLayout` from ONE
shared list (`SymbolMIDIMapping.orderedNoteEvents`), so there is exactly one layout entry per
sounding note (rests: none; chord members: one each, shared onset).

```swift
let symbols = fixture.symbols.map { EncodedSymbol(oracleFields: $0) }  // or decoded tokens
let r = OMRHomrIOS.renderTokens(symbols)             // grand staff OK; staff 0 = top
XCTAssertEqual(r.layoutSource, .midiFallback)        // no attention boxes yet; pageRect == .null
XCTAssertEqual(r.noteLayout.count, soundingNoteCount) // Layer C: highlight count == notes
let k = r.noteLayout[i].noteIndex                    // == i == i-th note-on in r.midi
```

- **Ordering (stable, total):** ascending `(onsetTicks, staffIndex, midiNote)`, tie-break
  `(durationTicks, symbolIndex)`. The SMF has a conductor track 0 plus one track per staff
  (track `staffIndex + 1`, top to bottom); merging note-ons across staff tracks by
  `(tick, track)` gives the same order, so `noteLayout[k]` ↔ k-th merged note-on.
- Each entry carries `noteIndex`, `symbolIndex` (into the input symbols), `staffIndex`,
  `onsetTicks`, `durationTicks`, `midiNote`, and `pageRect` (`.null` = no box; never fabricated).
- Pieces: `SymbolMIDIMapping.orderedNoteEvents(from:tpq:staffIndexOffset:)` and
  `NoteLayout.midiFallback(from:)`.
- Attention seam: pass a `NoteBoxProvider`; if it returns a real rect for every note,
  `layoutSource == .attention`, otherwise it stays `.midiFallback`.
- Linux mirror of the fixture check: `python3 tools/oracle/check_note_layout.py`.

## Layout

```
Sources/OMRHomrIOS/
  PublicAPI.swift
  Types/          NoteLayout, EncodedSymbol, OracleSymbolSequence, parse I/O
  Layout/         TokenRender (renderTokens: tokens → MIDI + noteLayout, NoteBoxProvider seam)
  Tokenizer/      Vocabulary + TokenizerLoader
  Inference/      Encoder/Decoder stubs, DecoderLoop, StaffInputSpec, StaffInferenceSession
  MIDI/           SMFWriter (format 1, 480 TPQ) + SymbolMIDIMapping
  Resources/
    Vocab/vocabulary.json          # Vocabulary() export
    Tokenizers/tokenizer_*.json    # upstream HF WordLevel copies
Tests/OMRHomrIOSTests/
  WriterOnlyFixtureTests.swift     # Layer B: tokens → notes.csv (no image)
  RenderTokensLayoutTests.swift    # Layer C: noteLayout 1:1 with MIDI notes per fixture
  Fixtures/                        # legacy oracle hook path (see repo-root fixtures/)

Repo-root `fixtures/` (consumed by package tests):
  mono.c_major_scale, mono.sharps_flats, mono.rhythms, mono.rests,
  poly.chord, clefs.bass, piano.grand, camera.deskew, oracle.c_scale_staff
  See fixtures/README.md + docs/TESTING.md.
```

## Upstream

- Code / algorithms: https://github.com/liebharc/homr (AGPL-3.0)
- Checkpoints: https://github.com/liebharc/homr/releases/tag/onnx_checkpoints
- Oracle exporter workspace (dev machine): `~/workspace/homr-research`
