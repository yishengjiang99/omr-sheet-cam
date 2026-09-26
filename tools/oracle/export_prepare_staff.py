#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# omr-sheet-cam — homr oracle EXPORTER (offline tooling, NOT part of the iOS runtime).
# Copyright (C) 2026 the omr-sheet-cam authors.
#
# Drives liebharc/homr (AGPL-3.0, https://github.com/liebharc/homr) at run time.
# Nothing from this file is linked into the app.
"""Export a homr ``staff_parsing.prepare_staff_image`` oracle (staff crop + dewarp).

REFERENCE / CROSS-CHECK ONLY. The gate is the Swift ``omr-test prepare-staff``.

Runs homr's own page pipeline on ``fixtures/mono.c_major_scale/input.png`` (same
setup as ``export_staff_tokens.py``: models.lock checkpoints, ORT CPU EP) and
captures, for the single detected staff, exactly what ``prepare_staff_image``
consumes and produces. Nothing in homr is changed; module functions are wrapped
to record their arguments and results.

Writes ``fixtures/oracle.c_scale_prepare/``:

* ``page.png``          uint8 grayscale page handed to ``prepare_staff_image``
                        (``staff_image`` arg = homr's CLAHE-preprocessed page)
* ``geometry.json``     the Staff fields ``prepare_staff_image`` uses (grid points
                        x / y[] / angle, plus the StaffRegions (min_y, max_y) list),
                        and derived values (min/max, average_unit_size, region) for checks
* ``dewarp_in.png``     after ``cv2.resize`` + first crop (input to dewarp)
* ``dewarp.json``       dewarp control points (src/dst) + triangles (Subdiv2D order)
* ``dewarp_out.png``    ``StaffDewarping.dewarp`` output
* ``prepared.png/.npy`` final pre-canvas image (after the second crop and
                        ``remove_black_contours_at_edges_of_image``)
* ``canvas.png``        ``center_image_on_canvas(prepared, image_dimensions)`` (256x1280)
* ``meta.json``         homr commit, cv2 / numpy versions, sha256s, canvas size

usage::

    scripts/fetch-models
    HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python \\
        tools/oracle/export_prepare_staff.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_staff_tokens as est  # noqa: E402

REPO = est.REPO
OUT = REPO / "fixtures" / "oracle.c_scale_prepare"
SOURCE = "mono.c_major_scale"
EXPORTER = "tools/oracle/export_prepare_staff.py"


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def f(v: Any) -> float:
    return float(v)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument(
        "--homr-root", type=Path, default=Path(os.environ.get("HOMR_ROOT", "/workspace/homr-upstream"))
    )
    args = ap.parse_args()
    h = est.Homr(args.homr_root, est.locked_models())
    if h.commit() != est.HOMR_COMMIT:
        raise SystemExit(f"homr checkout is {h.commit()}, pinned {est.HOMR_COMMIT}")

    import cv2
    from PIL import Image

    import homr.staff_parsing as sp

    cap: dict[str, Any] = {"calls": 0, "crops": [], "center": []}
    orig_prepare = sp.prepare_staff_image
    orig_crop = sp.crop_image_and_return_new_top
    orig_dewarp_staff_image = sp.dewarp_staff_image
    orig_remove = sp.remove_black_contours_at_edges_of_image
    orig_center = sp.center_image_on_canvas

    def prepare(debug, index, staff, staff_image, regions):  # noqa: ANN001
        cap["calls"] += 1
        cap["index"] = index
        cap["staff"] = staff
        cap["page"] = np.array(staff_image, copy=True)
        cap["regions"] = [(f(a), f(b)) for a, b in regions.centers]
        cap["region"] = [int(v) for v in sp._calculate_region(staff, regions)]
        res = orig_prepare(debug, index, staff, staff_image, regions)
        cap["returned_staff"] = res[1]
        return res

    def crop(image, *xy):  # noqa: ANN001
        out, top = orig_crop(image, *xy)
        cap["crops"].append({"args": [f(v) for v in xy], "top": [int(v) for v in top],
                             "in_shape": list(image.shape), "out": np.array(out, copy=True)})
        return out, top

    def dewarp_staff_image(image, staff, index, debug):  # noqa: ANN001
        d = orig_dewarp_staff_image(image, staff, index, debug)
        cap["dewarp_staff"] = staff
        cap["dewarp"] = d
        cap["dewarp_in"] = np.array(image, copy=True)
        cap["dewarp_out"] = d.dewarp(np.array(image, copy=True))
        return d

    def remove(gray, unit_size):  # noqa: ANN001
        cap["remove_in"] = np.array(gray, copy=True)
        cap["remove_unit"] = f(unit_size)
        out = orig_remove(gray, unit_size)
        cap["remove_out"] = np.array(out, copy=True)
        return out

    def center(image, canvas_size, *a, **k):  # noqa: ANN001
        out = orig_center(image, canvas_size, *a, **k)
        cap["center"].append({"in": np.array(image, copy=True), "size": [int(v) for v in canvas_size],
                              "out": np.array(out, copy=True)})
        return out

    sp.prepare_staff_image = prepare
    sp.crop_image_and_return_new_top = crop
    sp.dewarp_staff_image = dewarp_staff_image
    sp.remove_black_contours_at_edges_of_image = remove
    sp.center_image_on_canvas = center
    try:
        res = h.run_page(REPO / "fixtures" / SOURCE / "input.png")
    finally:
        sp.prepare_staff_image = orig_prepare
        sp.crop_image_and_return_new_top = orig_crop
        sp.dewarp_staff_image = orig_dewarp_staff_image
        sp.remove_black_contours_at_edges_of_image = orig_remove
        sp.center_image_on_canvas = orig_center

    if cap["calls"] != 1 or len(res["staffs"]) != 1:
        raise SystemExit(f"expected one staff, got calls={cap['calls']} staffs={len(res['staffs'])}")
    page = cap["page"]
    if page.dtype != np.uint8 or page.ndim != 2:
        raise SystemExit(f"page is {page.dtype} {page.shape}, expected uint8 grayscale")
    staff = cap["staff"]
    prepared = cap["remove_out"]
    center_calls = [c for c in cap["center"] if c["out"].shape == (256, 1280)]
    canvas = center_calls[0]["out"]
    if not np.array_equal(canvas, res["staffs"][0]["canvas"]):
        raise SystemExit("captured canvas != canvas fed to the encoder")
    if not np.array_equal(center_calls[0]["in"], prepared):
        raise SystemExit("center_image_on_canvas input != remove_black_contours output")
    gate_png = REPO / "fixtures" / "oracle.c_scale_staff" / "staff.png"
    same_as_gate = bool(np.array_equal(np.array(Image.open(gate_png)), canvas))

    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(page, "L").save(OUT / "page.png", optimize=True)
    Image.fromarray(cap["dewarp_in"], "L").save(OUT / "dewarp_in.png", optimize=True)
    Image.fromarray(cap["dewarp_out"].astype(np.uint8), "L").save(OUT / "dewarp_out.png", optimize=True)
    Image.fromarray(prepared, "L").save(OUT / "prepared.png", optimize=True)
    np.save(OUT / "prepared.npy", prepared)
    Image.fromarray(canvas, "L").save(OUT / "canvas.png", optimize=True)
    for name in ("page.png", "dewarp_in.png", "dewarp_out.png", "prepared.png", "canvas.png"):
        back = np.array(Image.open(OUT / name))
        src = {"page.png": page, "dewarp_in.png": cap["dewarp_in"], "dewarp_out.png": cap["dewarp_out"],
               "prepared.png": prepared, "canvas.png": canvas}[name]
        if not np.array_equal(back, src):
            raise SystemExit(f"{name} does not round-trip")

    geometry = {
        "description": "homr Staff / StaffRegions fields consumed by staff_parsing.prepare_staff_image "
                       "(page pixel coordinates). Floats are Python repr (exact float64 round-trip).",
        "index": cap["index"],
        "grid": [{"x": f(p.x), "y": [f(v) for v in p.y], "angle": f(p.angle)} for p in staff.grid],
        "regions": [list(r) for r in cap["regions"]],
        "is_grandstaff": bool(staff.is_grandstaff),
        "derived": {
            "min_x": f(staff.min_x), "max_x": f(staff.max_x),
            "min_y": f(staff.min_y), "max_y": f(staff.max_y),
            "average_unit_size": f(staff.average_unit_size),
            "region": cap["region"],
            "canvas_size": center_calls[0]["size"],
            "remove_black_contours_unit_size": cap["remove_unit"],
        },
    }
    (OUT / "geometry.json").write_text(json.dumps(geometry, indent=1) + "\n")

    d = cap["dewarp"]
    tform = d.tform
    dewarp = {
        "description": "PiecewiseAffineTransform built by staff_dewarping.dewarp_staff_image on dewarp_in.png "
                       "(src/dst control points, float32; triangles = Subdiv2D order as index triples).",
        "src": tform.src_points.tolist() if tform is not None else None,
        "dst": tform.dst_points.tolist() if tform is not None else None,
        "triangles": tform.triangulation.simplices.tolist() if tform is not None else None,
        "affine": [None if m is None else m.tolist() for m in tform.affine_matrices] if tform is not None else None,
        "staff_grid": [{"x": f(p.x), "y": [f(v) for v in p.y]} for p in cap["dewarp_staff"].grid],
        "crops": [{"args": c["args"], "top": c["top"], "in_shape": c["in_shape"],
                   "out_shape": list(c["out"].shape)} for c in cap["crops"]],
    }
    (OUT / "dewarp.json").write_text(json.dumps(dewarp) + "\n")

    meta = {
        "exporter": EXPORTER,
        "source_image": f"fixtures/{SOURCE}/input.png",
        "source_image_sha256": est.sha256(REPO / "fixtures" / SOURCE / "input.png"),
        "homr_repo": "https://github.com/liebharc/homr",
        "homr_commit": h.commit(),
        "opencv": cv2.__version__,
        "opencv_python_wheel": "opencv-python==5.0.0.93",
        "numpy": np.__version__,
        "python": sys.version.split()[0],
        "checkpoints": est.checkpoint_meta(h.models),
        "page_shape": list(page.shape),
        "prepared_shape": list(prepared.shape),
        "canvas_size_wh": center_calls[0]["size"],
        "prepared_sha256": sha256_bytes(prepared.tobytes()),
        "canvas_equals_oracle_c_scale_staff_png": same_as_gate,
        "symbols": [est.sym_dict(s) for s in res["staffs"][0]["raw"]],
    }
    (OUT / "meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    export_warped(page, staff, cap["regions"], cv2)
    print(json.dumps({k: meta[k] for k in ("page_shape", "prepared_shape", "canvas_size_wh",
                                           "canvas_equals_oracle_c_scale_staff_png")}), file=sys.stderr)
    print(f"{len(meta['symbols'])} symbols", file=sys.stderr)
    return 0


class _NoDebug:
    debug = False

    def write_image_with_fixed_suffix(self, *_a: Any, **_k: Any) -> None:
        pass


def export_warped(page: np.ndarray, staff: Any, regions: list[tuple[float, float]], cv2: Any) -> None:
    """Synthetic case ``warped/``: same page, bent staff geometry + black edge blobs.

    The C-scale staff is straight, so its dewarp is the identity. This case feeds homr's
    ``prepare_staff_image`` a perturbed grid (y += 7*sin, per-point) so the piecewise-affine
    warp, Subdiv2D triangulation, triangle masks and ``remove_black_contours_at_edges_of_image``
    all do real work. Inputs are synthetic; the output is still homr + cv2's own result.
    """
    from PIL import Image

    import homr.staff_parsing as sp
    from homr.model import MultiStaff, Staff, StaffPoint
    from homr.staff_regions import StaffRegions

    grid = []
    for p in staff.grid:
        dy = 7.0 * np.sin((p.x - staff.min_x) / 90.0)
        grid.append(StaffPoint(float(p.x), [float(v + dy) for v in p.y], float(p.angle)))
    bent = Staff(grid)
    other = Staff([StaffPoint(float(p.x), [float(v + 400.0) for v in p.y], float(p.angle)) for p in staff.grid])
    img = np.array(page, copy=True)
    img[320:380, 560:700] = 0      # solid block across the right + bottom crop edges -> removed
    img[270:285, 40:52] = 0        # small block on the left edge (below threshold) -> kept
    img[100:200, 300:360] = 0      # frame across the top edge (mostly hollow) -> kept
    img[103:197, 303:357] = 255
    regions_obj = StaffRegions([MultiStaff([bent], []), MultiStaff([other], [])])
    out: dict[str, Any] = {}
    orig_center = sp.center_image_on_canvas

    def center(image, canvas_size, *a, **k):  # noqa: ANN001
        out["prepared"] = np.array(image, copy=True)
        out["size"] = [int(v) for v in canvas_size]
        return orig_center(image, canvas_size, *a, **k)

    sp.center_image_on_canvas = center
    try:
        canvas, _ = sp.prepare_staff_image(_NoDebug(), 0, bent, img, regions_obj)
    finally:
        sp.center_image_on_canvas = orig_center
    d = OUT / "warped"
    d.mkdir(exist_ok=True)
    Image.fromarray(img, "L").save(d / "page.png", optimize=True)
    Image.fromarray(out["prepared"], "L").save(d / "prepared.png", optimize=True)
    np.save(d / "prepared.npy", out["prepared"])
    Image.fromarray(canvas, "L").save(d / "canvas.png", optimize=True)
    geometry = {
        "description": "synthetic bent staff (y += 7*sin((x-min_x)/90)) + a second staff 400 px below "
                       "(regions); see export_prepare_staff.py export_warped",
        "index": 0,
        "grid": [{"x": float(p.x), "y": [float(v) for v in p.y], "angle": float(p.angle)} for p in bent.grid],
        "regions": [list(c) for c in regions_obj.centers],
        "is_grandstaff": False,
        "derived": {"min_x": float(bent.min_x), "max_x": float(bent.max_x), "min_y": float(bent.min_y),
                    "max_y": float(bent.max_y), "average_unit_size": float(bent.average_unit_size),
                    "region": [int(v) for v in sp._calculate_region(bent, regions_obj)],
                    "canvas_size": out["size"]},
    }
    (d / "geometry.json").write_text(json.dumps(geometry, indent=1) + "\n")
    print(f"warped: prepared {out['prepared'].shape} canvas_size {out['size']}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
