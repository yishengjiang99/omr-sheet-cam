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

## Addendum: agent / CLI TDD loop

```
============================================================
ADDENDUM — AGENT / CLI TDD LOOP
============================================================

The plan above is executable by a coding agent on the command line
ONLY after fixtures and a non-interactive compare CLI exist.
Do not ask the agent to photograph pages, open MuseScore, play audio,
or "see if it sounds right."

Agents can loop on anything that is:
- files in git (or one deterministic fetch script)
- one command
- pass/fail via exit code
- diffs on stdout
- no camera, no GUI, no human listening

----------------------------------------------------------
CLI-ABLE VS NOT
----------------------------------------------------------

Yes (TDD every edit or every inference change):
- Writer-only: expected.tokens.json → MIDI → diff expected.notes.csv
- Encoder/decoder on a checked-in staff PNG vs committed oracle tokens
- Geometry on synthetic PNG vs known staffCount / dewarp shape
- Full-page synthetic PNG → MIDI note list
- Already-downloaded Camera-PrIMuS / OLiMPiC / homr-datasets files

No (not part of the agent loop):
- Print and photograph camera.deskew
- Listen to playback
- Layout IoU / highlight UX as a ship gate
- Hunting new sheet music mid-run

Playback smoke, if present, is a headless parser:
parse_midi(bytes).notes == expected.notes
Do not require a browser or iOS simulator for unit green.

----------------------------------------------------------
WHAT TO ADD BEFORE AN AGENT CAN LOOP
----------------------------------------------------------

1. Check in a minimal fixture pack (or a one-shot fetch):
   - C-scale staff PNG used for the 22/22 oracle
   - expected.tokens.json from that run (commit the tokens; do not
     require live Python homr on every unit run)
   - expected.notes.csv
   - the seven synthetic IDs (mono.*, poly.chord, clefs.bass,
     piano.grand) as small rendered PNGs + GT
   Agents will not browse PrIMuS during a TDD turn.

2. One entrypoint, platform-agnostic in name:

   omr-test fixtures/<id>
   omr-test --tier exact_tokens --no-onnx
   omr-test --tier exact_tokens
   omr-test --tier midi_distance --fetch

   Exit 0 = that fixture's match_tier passed.
   Print token edit distance and MIDI edit distance every time.

3. Pin weights + tokenizer JSON on disk for ONNX tests.
   Mark ONNX tests slow. Writer-only tests must be instant.

4. Compare MIDI as CSV/JSON note lists, not SMF-byte equality
   and not a notation GUI.

----------------------------------------------------------
AGENT TDD LOOP
----------------------------------------------------------

Red: add or extend fixtures/<id>/expected.notes.csv (and tokens
     if match_tier is exact_tokens).
Run: omr-test fixtures/<id>   # expect non-zero
Implement the writer / geometry / decode path.
Run: omr-test fixtures/<id>   # expect 0
Repeat. Do not add UI work until exact_tokens fixtures pass.

Recommended cadence:
  every edit     → omr-test --tier exact_tokens --no-onnx
  inference edit → omr-test --tier exact_tokens
  explicit/night → omr-test --tier midi_distance --fetch

exact_tokens  → fail build on any token or MIDI mismatch
exact_midi    → fail on MIDI mismatch only
midi_distance → fail only above meta.yaml threshold
snapshot      → upload artifacts, never fail CI

First agent task: implement omr-test + C-scale + writer-only
fixtures so `omr-test --tier exact_tokens --no-onnx` is green,
then make `omr-test fixtures/mono.c_major_scale` green with ONNX.
Stop if the command is not runnable; do not improvise a camera lab.
```
