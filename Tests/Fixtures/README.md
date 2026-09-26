# App test fixtures

Gate-1 (`Tests/Gate1StaffTokenMatchTests.swift`) reads the repo-root fixture directly via `#filePath`:

- `fixtures/oracle.c_scale_staff/staff.npy`: NCHW `[1,1,256,1280]` staff tensor
- `fixtures/oracle.c_scale_staff/expected.tokens.json`: homr oracle symbols (six fields)
- models: `<repo>/models/` from `scripts/fetch-models` (names in `models.lock`), or `OMR_MODELS_DIR` (`TEST_RUNNER_OMR_MODELS_DIR` under xcodebuild)

Works on Mac / simulator (checkout readable). Skips on a device without these files. Do not copy or invent tokens here.
