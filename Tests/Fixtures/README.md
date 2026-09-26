# App test fixtures

## C-scale staff oracle (Gate-1)

Prefer the package fixture path (source of truth):

`Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/c_scale_staff_oracle/`

| File | Purpose |
|------|---------|
| `staff.png` | Single engraved staff (C major scale) |
| `oracle_tokens.json` | Ordered `EncodedSymbol` dicts from Python homr |

App tests look there first, then fall back to `Tests/Fixtures/c_scale_staff_oracle/` if you copy fixtures locally for the Xcode test target.

Do **not** invent tokens to force a match. Export from `~/workspace/homr-research`.
