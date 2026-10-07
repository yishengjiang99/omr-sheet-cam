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

- **Layer A — Tokens:** dewarped staff → homr streams; **hard gate** `oracle.c_scale_staff` — Swift decode of `staff.png` must equal the Python homr export exactly (12 symbols with homr `7d97c3c` + `models.lock`). Export: `tools/oracle/export_staff_tokens.py`; cross-check vs hand-authored GT in `ORACLE_REPORT.md`; per-fixture `oracle.tokens.json` (reference only).
- **Layer B — MIDI:** tokens → SMF / canonical notes; writer-only asserts sorted `(tick, pitch, duration, staff)` == `expected.notes.csv`.
- **Layer C — Layout (soft):** highlight count == sounding notes (not ship-gated on IoU). Package helper `OMRHomrIOS.renderTokens` builds MIDI + `noteLayout` from one note list; Linux check: `python3 tools/oracle/check_note_layout.py`.

Canonicalize (Layer B): C4=MIDI 60; lift `#` +1 / `b` −1; `note_4`=480 TPQ ticks; one dot ×1.5; two dots ×1.75; `chord` = shared onset; rests advance cursor; barlines/clefs no-ops (clef after music resets onset for sequential grand-staff dumps). SMF format 1, 480 TPQ, metrical.

## Pack status

| ID | Tier | Tokens | Notes CSV | Image |
|----|------|--------|-----------|-------|
| `mono.c_major_scale` | exact_tokens | complete (writer GT) | complete | LilyPond `input.png` (200 dpi gray) |
| `mono.sharps_flats` | exact_tokens | complete | complete | LilyPond `input.png` (200 dpi gray) |
| `mono.rhythms` | exact_tokens | complete | complete | LilyPond `input.png` (200 dpi gray) |
| `mono.rests` | exact_tokens | complete | complete | LilyPond `input.png` (200 dpi gray) |
| `poly.chord` | exact_tokens | complete | complete | LilyPond `input.png` (200 dpi gray) |
| `clefs.bass` | exact_tokens | complete | complete | LilyPond `input.png` (200 dpi gray) |
| `piano.grand` | exact_midi | complete | complete | LilyPond `input.png` (200 dpi gray) |
| `camera.deskew` | midi_distance (≤2 / 16 notes) | stub | complete (scale mirror) | synthetic ~15° rotate + keystone of scale |
| `camera.die_letzte_kompanie` | snapshot | awaiting_oracle_export | — | real photo `input.jpg` (Die Letzte Kompanie) |
| `oracle.c_scale_staff` | exact_tokens (Gate 1, 12/12) | complete (Python homr export) | derived from oracle tokens | `staff.png` 256×1280 + `staff.npy` |

Images are rendered from `fixtures/<id>/source.ly` by `tools/fixtures/render_fixtures.py`
(LilyPond 2.24, A4, 200 dpi grayscale). The script also checks LilyPond's MIDI for the same
source against `expected.notes.csv`, and derives `camera.deskew/input.png` deterministically
(seed 15). Live Layer A oracle compare is a follow-up.
