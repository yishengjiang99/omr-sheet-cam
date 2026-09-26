# OMR testing plan (locked)

Platform-agnostic fixtures and assertions for the homr-based Optical Music Recognition pipeline.
Same fixtures work for browser worker, native mobile, and desktop. This is sheet-music OMR, not bubble-sheet grading and not OCR.

**Process:** push test/fixture work **directly to `main`** (no PR gate) unless CoS says otherwise.

## Layers (score separately — never one accuracy number)

### Layer A — Tokens
- Input: dewarped staff `[1, 1, 256, 1280]` grayscale, mean `0.7931`, std `0.1738`
- Expected: homr token streams (rhythm, pitch, note, lift, + fifth stream from `decoder_inference.py`)
- Match: exact per stream, or Levenshtein if fixture says so
- **Hard gate:** C-scale oracle staff **22/22** vs Python homr (fp16 encoder → fp32 decoder known-good)

### Layer B — MIDI
- Expected: canonical note list from known notation (not from homr)
- SMF if emitted: format 1, 480 TPQ, metrical division only; conductor + one track/staff; program 0; noteOn/Off only
- Compare after canonicalize (drop events the reference player ignores)
- Match: sorted `(tick, pitch, duration, staff)` equal on unit fixtures

### Layer C — Layout (soft)
- Pass if every sounding MIDI note has a `noteLayout` entry **or** `layoutSource == "midi-fallback"`
- Fail only if highlight count ≠ sounding note count
- Do **not** ship-gate on box IoU

If tokens match and MIDI does not → writer bug. If MIDI matches and tokens do not → fixture export bug. Keep both diffs.

## Fixture layout

```
fixtures/<id>/
  input.png              # renderer output
  input.jpg              # optional camera photo
  expected.tokens.json   # required for staff-level unit tests
  expected.midi          # optional SMF
  expected.notes.csv     # tick,pitch,duration,staff  (compare source)
  meta.yaml              # clef, key, time, source, license, match_tier
```

`match_tier` values:
| Tier | CI behavior |
|------|-------------|
| `exact_tokens` | Fail on any token or MIDI mismatch |
| `exact_midi` | Fail on MIDI mismatch only; tokens reported |
| `midi_distance` | Fail only above threshold in `meta.yaml` |
| `snapshot` | Upload artifacts; never fail CI |

## Required fixture pack (first deliverable)

| ID | Content | Tier |
|----|---------|------|
| `mono.c_major_scale` | treble C4–C5 quarters | exact_tokens |
| `mono.sharps_flats` | C D E F# G Ab B C | exact_tokens |
| `mono.rhythms` | whole half quarter 8th 16th dotted | exact_tokens |
| `mono.rests` | notes with quarter rests | exact_tokens |
| `poly.chord` | C4+E4+G4 quarter | exact_tokens |
| `clefs.bass` | bass-clef scale | exact_tokens |
| `piano.grand` | two staves, 4 simple bars | exact_midi |
| `camera.deskew` | same scale ~15° | midi_distance |

Also include (do not invent): C-scale 22/22 oracle from `~/workspace/homr-research` if present; homr `figures/` as `snapshot`; datasets release as `midi_distance`/`snapshot`; tokenizers from `homr/transformer/*.json`.

No bubble-sheet OMR datasets.

## Test ladder (implement in order)

1. **Encoder/decoder only** — pre-cropped C-scale → tokens == Python oracle; MIDI == `expected.notes.csv`
2. **Writer only** — hand-authored `expected.tokens.json` (no image) → MIDI == `expected.notes.csv`
3. **Geometry** — synthetic page: staffCount, order, dewarp `[1,1,256,1280]`
4. **Full-page synthetic pack** — staffCount + MIDI per `match_tier`
5. **Camera pack** — MIDI pitch-time edit distance ≤ threshold (start ≤2 events / 16 sounding notes)
6. **Playback smoke** — MIDI loads in project player; highlight count == sounding notes

## First deliverable (now)

Fixture schema + C-scale + the seven synthetic IDs above + writer-only test.
Do not add UI tests before those pass.

Report token edit distance and MIDI edit distance on every page test.
