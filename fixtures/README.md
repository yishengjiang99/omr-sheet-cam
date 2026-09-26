# Fixtures

Platform-agnostic OMR ground truth. Schema and scoring rules: [docs/TESTING.md](../docs/TESTING.md).

Package writer-only tests (`Packages/omr-homr-ios`) resolve this directory from the repo root via `#filePath`.

## Layout

```
fixtures/<id>/
  input.png              # optional (LilyPond / Verovio / camera follow-up)
  input.jpg              # optional
  expected.tokens.json   # required for staff-level / writer-only
  expected.midi          # optional SMF
  expected.notes.csv     # tick,pitch,duration,staff — Layer B compare source
  meta.yaml              # clef, key, time, source, license, match_tier
```

### `expected.tokens.json`

```json
{
  "source": "…",
  "status": "complete | stub | awaiting_oracle_export",
  "symbols": [
    {
      "rhythm": "note_4",
      "pitch": "C4",
      "lift": "_",
      "articulation": "_",
      "slur": "_",
      "position": "upper"
    }
  ]
}
```

Token strings must exist in `Packages/omr-homr-ios/.../Resources/Vocab/vocabulary.json` (homr `Vocabulary()`). Do **not** invent vocab.

### `match_tier`

| Tier | CI behavior |
|------|-------------|
| `exact_tokens` | Fail on any token or MIDI mismatch |
| `exact_midi` | Fail on MIDI mismatch only; tokens reported |
| `midi_distance` | Fail only above `midi_distance_threshold` in `meta.yaml` |
| `snapshot` | Upload artifacts; never fail CI |

## Layers (brief)

- **Layer A — Tokens:** dewarped staff → homr streams; **hard gate** `oracle.c_scale_staff` **22/22** vs Python homr (blocked on onnx / homr-research export).
- **Layer B — MIDI:** tokens → SMF / canonical notes; writer-only asserts sorted `(tick, pitch, duration, staff)` == `expected.notes.csv`.
- **Layer C — Layout (soft):** highlight count == sounding notes (not ship-gated on IoU).

Canonicalize (Layer B): C4=MIDI 60; lift `#` +1 / `b` −1; `note_4`=480 TPQ ticks; one dot ×1.5; two dots ×1.75; `chord` = shared onset; rests advance cursor; barlines/clefs no-ops (clef after music resets onset for sequential grand-staff dumps). SMF format 1, 480 TPQ, metrical.

## Pack status

| ID | Tier | Tokens | Notes CSV | Image |
|----|------|--------|-----------|-------|
| `mono.c_major_scale` | exact_tokens | complete (writer GT) | complete | TODO LilyPond |
| `mono.sharps_flats` | exact_tokens | complete | complete | TODO |
| `mono.rhythms` | exact_tokens | complete | complete | TODO |
| `mono.rests` | exact_tokens | complete | complete | TODO |
| `poly.chord` | exact_tokens | complete | complete | TODO |
| `clefs.bass` | exact_tokens | complete | complete | TODO |
| `piano.grand` | exact_midi | complete | complete | TODO |
| `camera.deskew` | midi_distance (≤2 / 16 notes) | stub | complete (scale mirror) | TODO ~15° photo |
| `oracle.c_scale_staff` | exact_tokens (22/22 gate) | awaiting_oracle_export | empty | blocked onnx/homr-research |

LilyPond/Verovio image generation and live Layer A oracle compare are follow-ups.
