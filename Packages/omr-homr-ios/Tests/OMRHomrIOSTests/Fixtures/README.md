# Fixtures

## C-scale staff oracle (gate-1 stop condition)

Path: `Fixtures/c_scale_staff_oracle/`

Expected contents (not yet checked in — produce from `~/workspace/homr-research` on the
dev machine / oracle exporter):

| File | Purpose |
|------|---------|
| `staff.png` | Single engraved staff image (C major scale) |
| `oracle_tokens.json` | Ordered list of `EncodedSymbol` dicts from Python homr staff decode |
| `oracle_midi.mid` | Optional SMF format 1 @ 480 TPQ reference |

### `oracle_tokens.json` shape

```json
{
  "source": "liebharc/homr Staff2Score.predict",
  "staff": "c_scale",
  "symbols": [
    {
      "rhythm": "clef_G2",
      "pitch": ".",
      "lift": ".",
      "articulation": ".",
      "slur": ".",
      "position": "upper"
    },
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

Gate-1 passes when Swift staff-only decode emits the same `symbols` sequence
(string-equal per field) as this oracle. Do **not** invent tokens to force a match.
