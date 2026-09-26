# Fixtures

See [docs/TESTING.md](../docs/TESTING.md) for schema, `match_tier`, and the required pack.

Layout per id:

```
fixtures/<id>/
  input.png
  input.jpg              # optional
  expected.tokens.json
  expected.midi          # optional
  expected.notes.csv
  meta.yaml
```

Stubs for the required pack land here first; LilyPond/Verovio fills `input.png` + GT next.
