# oracle.c_scale_prepare: homr `prepare_staff_image` (staff crop + dewarp)

Reference data for the Swift port of homr's `staff_parsing.prepare_staff_image`
(`Packages/omr-homr-ios/Sources/OMRHomrIOS/Geometry/StaffPrepare.swift`). The Swift
gate is `scripts/omr-test prepare-staff page.png --geometry geometry.json --compare prepared.npy`.

## Provenance

- homr: https://github.com/liebharc/homr at `7d97c3cee4ad772b50266fdf9dc78bbf9064701e` (AGPL-3.0)
- OpenCV: **5.0.0** (`opencv-python==5.0.0.93`, x86_64, AVX2 dispatch, `ALGO_HINT_ACCURATE`), numpy 2.5.3, Python 3.13.5
- Models: the `models.lock` checkpoints (SegNet fp16 is only used to find the staff geometry), ORT CPU EP
- Produced by: `HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python tools/oracle/export_prepare_staff.py`
  (runs homr's own page pipeline on `fixtures/mono.c_major_scale/input.png` and wraps homr module
  functions to record arguments and results; homr is not modified)

## Files (top level = the real C-scale page)

| file | what |
|---|---|
| `page.png` | uint8 grayscale page (1920x2715) that homr passes to `prepare_staff_image` (its CLAHE-preprocessed page) |
| `geometry.json` | the `Staff` fields `prepare_staff_image` reads: `grid` (StaffPoint `x`, `y[5]`, `angle`) and `regions` (every staff's `(min_y, max_y)`, i.e. `StaffRegions.centers`). `derived` holds checks: min/max, `average_unit_size`, `_calculate_region`, canvas size |
| `dewarp_in.png` | after `cv2.resize` by the scale factor and the first crop (region +-10/+-50) |
| `dewarp.json` | `PiecewiseAffineTransform` control points (src/dst), Subdiv2D triangles, per-triangle affine matrices, first/second crop args |
| `dewarp_out.png` | `StaffDewarping.dewarp(dewarp_in)` |
| `prepared.png` / `prepared.npy` | **output before the canvas**: second crop + `remove_black_contours_at_edges_of_image` (uint8, 256x817) |
| `canvas.png` | `center_image_on_canvas(prepared, (817, 256))`: byte-identical to `fixtures/oracle.c_scale_staff/staff.png` |
| `meta.json` | versions, sha256s, the 12 symbols homr decoded from this canvas |

The C-scale staff is straight, so its dewarp is the identity (`src == dst`).

## `warped/` (synthetic geometry, real homr output)

The same page with three black blobs painted in, and a bent staff grid (`y += 7*sin((x - min_x)/90)`)
plus a second staff 400 px lower (so `regions` has two entries). homr's `prepare_staff_image`
is called directly with that geometry. This exercises the non-trivial piecewise-affine warp
(Subdiv2D triangulation, `getAffineTransform`, `warpAffine` INTER_LINEAR, `fillConvexPoly` masks)
and `remove_black_contours_at_edges_of_image` (the block across the right and bottom edges is removed;
the small left-edge block and the hollow frame stay). Files: `page.png`, `geometry.json`,
`prepared.png/.npy`, `canvas.png`.
