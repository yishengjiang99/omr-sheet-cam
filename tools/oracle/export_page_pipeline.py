#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# omr-sheet-cam — homr oracle EXPORTER (offline tooling, NOT part of the iOS runtime).
# Copyright (C) 2026 the omr-sheet-cam authors.
#
# Drives liebharc/homr (AGPL-3.0, https://github.com/liebharc/homr) at run time.
# Nothing from this file is linked into the app.
"""Export homr's page-level pipeline stages (page -> SegNet -> staffs -> tokens).

REFERENCE / CROSS-CHECK ONLY. The gates are the Swift ``omr-test segnet-page`` /
``detect-staffs`` / ``parse-page`` commands and ``PagePipeline*Tests``.

For each fixture page this replays ``homr.main.detect_staffs_in_image`` and
``staff_parsing.parse_staffs`` step by step, calling homr's own functions (nothing is
re-implemented or patched except the model paths / CPU EP, see
``export_staff_tokens.Homr``), and records every intermediate the Swift port
compares against. Writes ``fixtures/oracle.pages/<fixture>/``:

* ``resized.png``       ``autocrop`` + ``resize_image`` output, converted to gray
                        (``cv2.COLOR_BGR2GRAY``; the fixtures are gray, so exact)
* ``preprocessed.png``  ``color_adjust.apply_clahe`` output (SegNet input and the
                        page ``prepare_staff_image`` crops staffs from)
* ``segnet.png``        merged SegNet class map (uint8 0..5, ``merge_patches`` output
                        before the class split): 1 stems_rests, 2 notehead,
                        3 clefs_keys, 4 staff, 5 symbols
* ``stages.json``       autocrop/resize sizes, noise-filter decision, symbol boxes
                        (staff fragments, clefs/keys, bar lines, noteheads), staffs
                        (grids), multi-staff grouping, per-staff ``StaffGeometry`` fed to
                        ``prepare_staff_image`` (grid + regions), canvases' sha256 and
                        the decoded tokens per staff (raw and after homr's position
                        filter), plus homr's final per-voice result
* ``tiles.json``        SegNet unit-test reference: tiles at (0, 0) and (480, 640) of
                        ``preprocessed.png`` and their argmax (uint8, base64), c-scale only

``synthetic.page_on_table`` is generated here (``make_page_on_table``; its ``input.png``
is written next to the outputs): the c-scale page scaled 0.75 on a 4032x3024 (12 MP)
dark gradient "table", placed past 25 % of both sides, so homr's ``autocrop`` really
crops (every real fixture is a full-page view, where autocrop is a no-op).

usage::

    scripts/fetch-models
    HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python \\
        tools/oracle/export_page_pipeline.py [--fixture mono.c_major_scale ...]
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stderr
from pathlib import Path
from typing import Any

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_staff_tokens as est  # noqa: E402

REPO = est.REPO
OUT = REPO / "fixtures" / "oracle.pages"
EXPORTER = "tools/oracle/export_page_pipeline.py"
DEFAULT = ["mono.c_major_scale", "piano.grand", "mono.rhythms", "poly.chord", "clefs.bass",
           "mono.sharps_flats", "mono.rests", "camera.deskew", "synthetic.page_on_table"]


def make_page_on_table(dst: Path) -> None:
    """12 MP synthetic photo: gradient table (40..110, spread so paper white dominates the
    histogram), c-scale page scaled 0.75 (PIL bicubic) pasted at (1300, 780)."""
    from PIL import Image

    w, h = 4032, 3024
    xs = np.arange(w, dtype=np.int32)
    ys = np.arange(h, dtype=np.int32)
    table = (40 + (xs[None, :] * 50) // w + (ys[:, None] * 20) // h).astype(np.uint8)
    page = Image.open(REPO / "fixtures" / "mono.c_major_scale" / "input.png").convert("L")
    page = page.resize((round(page.size[0] * 0.75), round(page.size[1] * 0.75)), Image.BICUBIC)
    canvas = Image.fromarray(table, "L")
    canvas.paste(page, (1300, 780))
    dst.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dst, optimize=True)


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def box(b: Any) -> list[float]:
    (cx, cy), (w, h), a = b.box
    return [float(cx), float(cy), float(w), float(h), float(a)]


def staff_json(s: Any) -> dict[str, Any]:
    return {
        "grid": [{"x": float(p.x), "y": [float(v) for v in p.y], "angle": float(p.angle)} for p in s.grid],
        "min_x": float(s.min_x), "max_x": float(s.max_x), "min_y": float(s.min_y), "max_y": float(s.max_y),
        "average_unit_size": float(s.average_unit_size), "is_grandstaff": bool(s.is_grandstaff),
    }


def save_png(path: Path, a: np.ndarray) -> str:
    from PIL import Image

    Image.fromarray(a, "L").save(path, optimize=True)
    return sha(path.read_bytes())


def run(h: est.Homr, fid: str) -> dict[str, Any]:
    import cv2

    from homr import color_adjust
    from homr.autocrop import autocrop
    from homr.bar_line_detection import detect_bar_lines, prepare_bar_line_image
    from homr.bounding_boxes import create_bounding_ellipses, create_rotated_bounding_boxes
    from homr.brace_dot_detection import find_braces_brackets_and_grand_staff_lines, prepare_brace_dot_image
    from homr.debug import Debug
    from homr.main import get_predictions
    from homr.noise_filtering import create_noise_grid, filter_predictions
    from homr.note_detection import add_notes_to_staffs, combine_noteheads_with_stems
    import homr.segmentation.inference_segnet as seg
    import homr.staff_parsing as sp
    import homr.staff_parsing_tromr as tromr
    from homr.resize import resize_image
    from homr.staff_detection import break_wide_fragments, detect_staff, make_lines_stronger

    if fid.startswith("synthetic."):
        src = OUT / fid / "input.png"
        make_page_on_table(src)
    else:
        src = REPO / "fixtures" / fid / "input.png"
    out = OUT / fid
    out.mkdir(parents=True, exist_ok=True)
    st: dict[str, Any] = {"fixture": fid, "input_image": str(src.relative_to(REPO)), "input_sha256": est.sha256(src)}
    log = io.StringIO()

    # capture merge_patches output (the class map before the per-class split)
    merged_cap: dict[str, Any] = {}
    orig_merge = seg.merge_patches

    def merge_capture(*a: Any, **k: Any) -> np.ndarray:
        r = orig_merge(*a, **k)
        merged_cap["merged"] = r.copy()
        merged_cap["patches"] = len(a[0])
        return r

    seg.merge_patches = merge_capture
    tromr.inference = h.s2s
    captured: list[dict[str, Any]] = []
    orig_prepare = sp.prepare_staff_image
    orig_parse = sp.parse_staff_tromr

    def prepare_capture(debug: Any, index: int, staff: Any, staff_image: Any, regions: Any) -> Any:
        img, st2 = orig_prepare(debug, index, staff, staff_image, regions)
        captured.append({
            "index": index,
            "geometry": {"grid": staff_json(staff)["grid"], "regions": [[float(a), float(b)] for a, b in regions.centers]},
            "is_grandstaff": bool(staff.is_grandstaff),
            "canvas_sha256": sha(np.ascontiguousarray(img).tobytes()),
        })
        return img, st2

    def parse_capture(staff: Any, staff_image: Any, config: Any) -> list:
        raw = list(h.s2s.predict(staff_image))
        res = raw if staff.is_grandstaff else [r for r in raw if not r.position.startswith("lower")]
        captured[-1]["symbols"] = [est.sym_dict(s) for s in raw]
        captured[-1]["symbols_after_position_filter"] = [est.sym_dict(s) for s in res]
        return res

    sp.prepare_staff_image = prepare_capture
    sp.parse_staff_tromr = parse_capture
    try:
        with tempfile.TemporaryDirectory() as td, redirect_stderr(log):
            work = Path(td) / src.name
            shutil.copy(src, work)
            image = cv2.imread(str(work))
            st["input_size"] = [int(image.shape[1]), int(image.shape[0])]
            cropped = autocrop(image)
            st["autocrop"] = {"size": [int(cropped.shape[1]), int(cropped.shape[0])],
                              "cropped": bool(cropped.shape != image.shape)}
            if cropped.shape != image.shape:  # recover the crop origin (homr returns a view)
                off = cropped.__array_interface__["data"][0] - image.__array_interface__["data"][0]
                st["autocrop"]["origin"] = [int((off % image.strides[0]) // image.strides[1]),
                                            int(off // image.strides[0])]
            image = resize_image(cropped)
            st["resized_size"] = [int(image.shape[1]), int(image.shape[0])]
            st["resized_sha256"] = save_png(out / "resized.png", cv2.cvtColor(image, cv2.COLOR_BGR2GRAY))
            preprocessed = color_adjust.apply_clahe(image)
            st["preprocessed_sha256"] = save_png(out / "preprocessed.png", preprocessed)
            predictions = get_predictions(image, preprocessed, str(work), False, True)
            merged = merged_cap["merged"].astype(np.uint8)
            st["segnet"] = {"patches": merged_cap["patches"], "shape": list(merged.shape),
                            "class_counts": [int((merged == c).sum()) for c in range(6)],
                            "png_sha256": save_png(out / "segnet.png", merged)}
            debug = Debug(predictions.original, str(work), False)
            mask = create_noise_grid(255 * predictions.staff, debug)
            st["noise_filter"] = {"applied": mask is not None,
                                  "mask_sha256": None if mask is None else sha(mask.tobytes())}
            predictions = filter_predictions(predictions, debug)
            predictions.staff = make_lines_stronger(predictions.staff, (1, 2))
            st["masks_sha256"] = {k: sha(np.ascontiguousarray(getattr(predictions, k)).tobytes())
                                  for k in ("staff", "symbols", "stems_rest", "notehead", "clefs_keys")}

            noteheads = create_bounding_ellipses(predictions.notehead, min_size=(4, 4))
            staff_fragments = create_rotated_bounding_boxes(
                predictions.staff, skip_merging=True, min_size=(5, 1), max_size=(10000, 100))
            clefs_keys = create_rotated_bounding_boxes(predictions.clefs_keys, min_size=(20, 40), max_size=(1000, 1000))
            stems_rest = create_rotated_bounding_boxes(predictions.stems_rest)
            bar_line_img = prepare_bar_line_image(predictions.stems_rest)
            bar_lines = create_rotated_bounding_boxes(bar_line_img, skip_merging=True, min_size=(1, 5))
            st["symbols"] = {
                "noteheads": [box(b) for b in noteheads],
                "staff_fragments_raw": [box(b) for b in staff_fragments],
                "clefs_keys": [box(b) for b in clefs_keys],
                "stems_rest": [box(b) for b in stems_rest],
                "bar_lines_raw": [box(b) for b in bar_lines],
            }
            staff_fragments = break_wide_fragments(staff_fragments)
            st["symbols"]["staff_fragments"] = [box(b) for b in staff_fragments]
            nws = combine_noteheads_with_stems(noteheads, stems_rest)
            st["symbols"]["noteheads_with_stems"] = [
                {"notehead": box(n.notehead), "stem": None if n.stem is None else box(n.stem),
                 "direction": None if n.stem_direction is None else n.stem_direction.name} for n in nws]
            if len(nws) == 0:
                raise RuntimeError("No noteheads found")
            avg_h = float(np.median([n.notehead.size[1] for n in nws]))
            st["average_note_head_height"] = avg_h
            all_nh = [n.notehead for n in nws]
            all_stems = [n.stem for n in nws if n.stem is not None]
            blr = [l for l in bar_lines if not l.is_overlapping_with_any(all_nh) and not l.is_overlapping_with_any(all_stems)]
            st["symbols"]["bar_lines_or_rests"] = [box(b) for b in blr]
            bar_line_boxes = detect_bar_lines(blr, avg_h)
            st["symbols"]["bar_line_boxes"] = [box(b) for b in bar_line_boxes]
            staffs = detect_staff(debug, predictions.staff, staff_fragments, clefs_keys, bar_line_boxes)
            st["staffs"] = [staff_json(s) for s in staffs]
            brace_dot_img = prepare_brace_dot_image(predictions.symbols, predictions.staff)
            brace_dot = create_rotated_bounding_boxes(brace_dot_img, skip_merging=True, max_size=(100, -1))
            st["symbols"]["brace_dot"] = [box(b) for b in brace_dot]
            add_notes_to_staffs(staffs, nws, predictions.symbols, predictions.notehead)
            multi = find_braces_brackets_and_grand_staff_lines(debug, staffs, brace_dot)
            st["multi_staffs"] = [[staff_json(s) for s in m.staffs] for m in multi]
            st["multi_staff_rows"] = [len(m.staffs) for m in multi]
            ensured = sp._ensure_same_number_of_staffs(multi)
            st["ensured_rows"] = [len(m.staffs) for m in ensured]
            voices = sp.parse_staffs(debug, multi, predictions.preprocessed, config=h.cfg)
            st["staff_inputs"] = captured
            st["voices"] = [[est.sym_dict(s) for s in v] for v in voices]
    finally:
        seg.merge_patches = orig_merge
        sp.prepare_staff_image = orig_prepare
        sp.parse_staff_tromr = orig_parse
    st["log"] = log.getvalue().splitlines()
    return st


def tile0(h: est.Homr, fid: str) -> None:
    """SegNet reference for one 320x320 tile at (0, 0) of preprocessed.png, for unit tests."""
    import cv2
    import homr.segmentation.inference_segnet as seg
    from PIL import Image

    pre = np.array(Image.open(OUT / fid / "preprocessed.png"))
    refs = []
    for (y, x) in [(0, 0), (480, 640)]:
        img = np.transpose(cv2.cvtColor(pre, cv2.COLOR_GRAY2BGR), (2, 0, 1)).astype(np.float32)
        patch = seg.extract_patch(img, y, x, 320)
        if seg._segnet_inference is None:
            seg._segnet_inference = seg.Segnet(True)
        out = seg._segnet_inference.run(np.stack([patch], axis=0))[0]
        am = np.argmax(out, axis=0).astype(np.uint8)
        refs.append({"y": y, "x": x, "argmax": base64.b64encode(am.tobytes()).decode(),
                     "class_counts": [int((am == c).sum()) for c in range(6)],
                     "logits_fp16_sha256": sha(out.astype(np.float16).tobytes())})
    (OUT / fid / "tiles.json").write_text(json.dumps({"source": "preprocessed.png", "win": 320, "tiles": refs}) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fixture", action="append", default=[])
    ap.add_argument("--homr-root", type=Path, default=Path(os.environ.get("HOMR_ROOT", "/workspace/homr-upstream")))
    args = ap.parse_args()
    h = est.Homr(args.homr_root, est.locked_models())
    if h.commit() != est.HOMR_COMMIT:
        raise SystemExit(f"homr checkout is {h.commit()}, pinned {est.HOMR_COMMIT}")
    import cv2
    import onnxruntime
    from PIL import Image as _I
    import PIL

    ids = args.fixture or DEFAULT
    summary = {}
    for fid in ids:
        try:
            st = run(h, fid)
        except Exception as e:  # homr itself failed on this page: record it, keep going
            st = {"fixture": fid, "error": f"{type(e).__name__}: {e}"}
        st["provenance"] = {
            "exporter": EXPORTER, "homr_commit": h.commit(), "checkpoints": est.checkpoint_meta(h.models),
            "precision": {"segnet": "fp16", "encoder": "fp16", "decoder": "fp32", "provider": "CPU"},
            "opencv": cv2.__version__, "numpy": np.__version__, "onnxruntime": onnxruntime.__version__,
            "pillow": PIL.__version__, "python": sys.version.split()[0],
        }
        (OUT / fid).mkdir(parents=True, exist_ok=True)
        (OUT / fid / "stages.json").write_text(json.dumps(st, indent=1) + "\n")
        summary[fid] = {k: st.get(k) for k in ("error", "resized_size", "multi_staff_rows")}
        summary[fid]["staffs"] = len(st.get("staffs", []))
        print(fid, summary[fid], file=sys.stderr)
    if "mono.c_major_scale" in ids:
        tile0(h, "mono.c_major_scale")
    return 0


if __name__ == "__main__":
    sys.exit(main())
