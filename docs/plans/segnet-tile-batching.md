# Plan: cut SegNet stage time (tile batching + CPU overhead)

_Status: proposed 2026-09-27, not yet implemented. Do not implement until the user approves._

## Why

Device log (iPhone17,5, app v1.0 build 7, 4284×5712 photo, 2 staves):

```
stages ms: preprocess=298 segnet=12013 staffs=700 decode=10822 render=1
```

SegNet is **50% of the 23.8 s parse**. Staff geometry is 700 ms — the Metal-dewarp
idea is dead; this is the stage to attack. Goal: cut segnet stage substantially
with **zero accuracy change** (tiles are independent; batching cannot change results).

## Background

- `SegNetSession.runTiles` (`Packages/omr-homr-ios/Sources/OMRHomrIOS/Page/SegNet.swift`)
  extracts 320×320 tiles and runs them through the CoreML EP (NeuralNetwork format,
  all compute units) in batches of `tilesPerRun` (default 8, homr's batch size).
- 4284×5712 → 14×18 = **252 tiles → 32 dispatches** at 8/batch ≈ 375 ms/dispatch.
- Per dispatch the work is: CPU pack tiles → `backend.run` (ANE) → CPU argmax
  (6 classes × 102,400 px per tile, scalar Swift loop) → merge.
- We do **not** know the split between ANE time and CPU pack/argmax time. Step 1 measures it.

## Step 1 — instrument (no behavior change)

Split the `segnet` stage timing inside `segment()` / `runTiles()` into three counters:

- `packMs`: building the fp16 input `Data` (the nested py/px Swift loops)
- `runMs`: `backend.run` only
- `argmaxMs`: the per-pixel 6-class argmax loop

Log via the existing `page_parse` stage diagnostics (same channel the 12013 ms number
came from). Run once on device via the Developer "SegNet self-test" or a real photo,
read the split from Copy as prompt. **No optimization until this split is known.**

## Step 2a — if `runMs` dominates: bigger batches

- `tilesPerRun` 8 → 16, then 32. One-line change at the `SegNetSession(backend:)`
  call sites (`PageParse.swift:56`, app warmup path); results are bit-identical
  because tiles are independent (already documented on the property).
- Memory per batch of 32: input 19 MB + output 38 MB transient — fine
  (device had 2.3 GB available at 1.3 GB peak).
- Watch for: ANE recompiles on varying batch sizes (last batch is short: 252 tiles =
  7×32 + 28). If the short batch is disproportionately slow, pad the final batch
  with duplicate tiles and discard the extras — keeps every dispatch at exactly 32.
- The model was opened with NeuralNetwork legacy flags `0x000` precisely because the
  batch dim is dynamic; larger batches stay within the verified configuration
  (no MLProgram, no provider-options change).

## Step 2b — if `packMs`/`argmaxMs` dominate: vectorize the CPU side

- argmax: replace the scalar per-pixel loop with a vectorized pass (vDSP/Accelerate:
  max over the 6 class planes). ~155M scalar iterations for this photo; expected
  several-x speedup.
- packing: the 255-fill + copy loop is parallelizable across tiles (DispatchQueue)
  or via vImage; tiles don't interact.
- Both keep exact argmax semantics (first-maximum wins, NaN handling as in
  `np.argmax`) — verify against the existing oracle, not just "looks right".

## Step 3 — acceptance (all required)

- `omr-test segnet-page --compare`: argmax maps identical to homr on all 9 oracle pages.
- Gate-1 12/12 on ios-sim; C-scale page test green.
- Device: `segnet` stage ms from Copy as prompt, before vs after, same photo.
- No change to model files, EP configuration, or `coreMLLegacyFlags`.

## Explicit non-goals

- No Metal rewrite of staff geometry (700 ms — not the bottleneck).
- No input-resolution reduction, no int8/palettization (accuracy risk, unjustified).
- No change to the merge/mean logic (`merge_patches` parity with homr stays exact).

## Rollback

Every step is a small diff on `SegNet.swift` (+ diagnostics). Revert = restore
`tilesPerRun = 8` / scalar loops. No model, config, or workflow changes involved.
