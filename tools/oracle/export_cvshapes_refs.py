#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Port of liebharc/homr @ 7d97c3cee4ad772b50266fdf9dc78bbf9064701e (AGPL-3.0): test inputs mirror homr's cv2 call
# sites (bounding_boxes.py, staff_detection.py, brace_dot_detection.py, noise_filtering.py).
"""Export OpenCV 5.0.0 reference outputs for the Swift page-pipeline shape primitives (Page/CVShapes.swift).

REFERENCE / CROSS-CHECK ONLY (offline tooling, not linked into the app). Writes
Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/page_cv2/shapes.json (seeded, small):

  rect      cv2.minAreaRect / cv2.convexHull on random int point sets (duplicates, collinear, tiny)
            and on findContours(RETR_TREE, CHAIN_APPROX_SIMPLE) contours of random blobs
  boxpts    cv2.boxPoints on random float32 RotatedRects
  ellpoly   cv2.ellipse2Poly(center, axes, angle, 0, 360, 1)
  fit       cv2.fitEllipse on blob contours (>= 5 points; compared with a tolerance)
  icc       cv2.intersectConvexConvex(p.astype(float32), q.astype(float32))[0] on int boxPoints /
            ellipse2Poly polygons (homr's do_polygons_overlap inputs)
  rri       cv2.rotatedRectangleIntersection(r1, r2)[0] != INTERSECT_NONE
  ppt       cv2.pointPolygonTest(int polygon, int point, False)
  kernels   cv2.getStructuringElement(MORPH_ELLIPSE, k) for homr's kernel sizes
  morph     cv2.erode / cv2.dilate of random 0/1 masks with those kernels
  fill      (drawContours(FILLED) mask > 0).sum(axis=1) as in homr brace_dot_detection
  noise     homr noise_filtering.create_grid on random 0/255 masks

usage: HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python tools/oracle/export_cvshapes_refs.py
"""
import base64
import json
import os
import sys
from pathlib import Path

import cv2
import numpy as np

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/page_cv2"
HOMR_ROOT = Path(os.environ.get("HOMR_ROOT", "/workspace/homr-upstream"))
sys.path.insert(0, str(HOMR_ROOT))
from homr.noise_filtering import create_grid  # noqa: E402


def b64(a: np.ndarray) -> str:
    return base64.b64encode(np.ascontiguousarray(a, dtype=np.uint8).tobytes()).decode()


def rr(r) -> list[float]:
    (cx, cy), (w, h), a = r
    return [float(cx), float(cy), float(w), float(h), float(a)]


def blobs(rng: np.random.Generator, h: int, w: int, n: int) -> np.ndarray:
    img = np.zeros((h, w), np.uint8)
    for _ in range(n):
        kind = rng.integers(0, 3)
        cx, cy = int(rng.integers(0, w)), int(rng.integers(0, h))
        if kind == 0:
            ax = (int(rng.integers(1, 12)), int(rng.integers(1, 9)))
            cv2.ellipse(img, (cx, cy), ax, float(rng.uniform(0, 180)), 0, 360, 1, -1)
        elif kind == 1:
            box = ((cx, cy), (float(rng.uniform(1, 60)), float(rng.uniform(1, 6))), float(rng.uniform(-30, 30)))
            cv2.fillPoly(img, [cv2.boxPoints(box).astype(np.int32)], 1)
        else:
            img[cy:cy + int(rng.integers(1, 5)), cx:cx + int(rng.integers(1, 5))] = 1
    return img


def main() -> int:
    rng = np.random.default_rng(20260926)
    out: dict = {"opencv": cv2.__version__}

    rect = []
    for t in range(400):
        n = int(rng.integers(1, 40))
        span = int(rng.choice([1, 2, 3, 10, 100, 2000]))
        pts = rng.integers(0, span + 1, size=(n, 2)).astype(np.int32)
        if t % 7 == 0:  # collinear
            k = rng.integers(-3, 4)
            xs = rng.integers(0, span + 1, size=n)
            pts = np.stack([xs, xs * k + 5], 1).astype(np.int32)
        rect.append({"pts": pts.tolist(), "hull": cv2.convexHull(pts).reshape(-1, 2).tolist(),
                     "rect": rr(cv2.minAreaRect(pts))})
    contours_all = []
    for t in range(12):
        img = blobs(rng, 120, 200, 25)
        cs, _ = cv2.findContours(img, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
        for c in cs:
            c2 = c.reshape(-1, 2)
            contours_all.append(c2)
            rect.append({"pts": c2.tolist(), "hull": cv2.convexHull(c).reshape(-1, 2).tolist(),
                         "rect": rr(cv2.minAreaRect(c))})
    out["rect"] = rect

    boxpts = []
    for _ in range(300):
        r = ((float(np.float32(rng.uniform(-50, 3000))), float(np.float32(rng.uniform(-50, 3000)))),
             (float(np.float32(rng.uniform(0, 400))), float(np.float32(rng.uniform(0, 60)))),
             float(np.float32(rng.choice([rng.uniform(-90, 0), rng.uniform(-180, 180), 0.0, -90.0, 45.0]))))
        boxpts.append({"rect": rr(r), "pts": cv2.boxPoints(r).astype(np.float64).tolist()})
    out["boxpts"] = boxpts

    ell = []
    for _ in range(200):
        c = (int(rng.integers(-5, 2000)), int(rng.integers(-5, 2000)))
        ax = (int(rng.integers(0, 40)), int(rng.integers(0, 40)))
        a = int(rng.integers(-400, 400))
        ell.append({"c": list(c), "ax": list(ax), "a": a, "poly": cv2.ellipse2Poly(c, ax, a, 0, 360, 1).tolist()})
    out["ellpoly"] = ell

    fit = []
    for c in contours_all:
        if len(c) >= 5:
            fit.append({"pts": c.tolist(), "rect": rr(cv2.fitEllipse(c))})
    out["fit"] = fit

    def rand_poly() -> np.ndarray:
        if rng.random() < 0.6:
            r = ((float(rng.uniform(0, 80)), float(rng.uniform(0, 80))),
                 (float(rng.uniform(0, 60)), float(rng.uniform(0, 20))), float(rng.uniform(-90, 0)))
            return cv2.boxPoints(r).astype(np.int64)
        return cv2.ellipse2Poly((int(rng.integers(0, 80)), int(rng.integers(0, 80))),
                                (int(rng.integers(0, 20)), int(rng.integers(0, 12))), int(rng.integers(-90, 90)), 0, 360, 1)

    icc = []
    for _ in range(600):
        p, q = rand_poly(), rand_poly()
        area, _ = cv2.intersectConvexConvex(p.astype(np.float32), q.astype(np.float32))
        icc.append({"p": p.tolist(), "q": q.tolist(), "area": float(area)})
    out["icc"] = icc

    rri = []
    for _ in range(600):
        def rrand():
            return ((float(np.float32(rng.uniform(0, 60))), float(np.float32(rng.uniform(0, 60)))),
                    (float(np.float32(rng.choice([rng.uniform(0, 80), 0.0, 1.0]))), float(np.float32(rng.uniform(0, 12)))),
                    float(np.float32(rng.choice([rng.uniform(-45, 45), 0.0, -90.0]))))
        a, b = rrand(), rrand()
        rri.append({"a": rr(a), "b": rr(b), "hit": int(cv2.rotatedRectangleIntersection(a, b)[0]) != cv2.INTERSECT_NONE})
    out["rri"] = rri

    ppt = []
    for _ in range(500):
        p = rand_poly()
        pt = (int(rng.integers(-2, 90)), int(rng.integers(-2, 90)))
        if rng.random() < 0.3:
            pt = tuple(int(v) for v in p[rng.integers(0, len(p))])
        ppt.append({"poly": p.tolist(), "pt": list(pt), "r": float(cv2.pointPolygonTest(p, (float(pt[0]), float(pt[1])), False))})
    out["ppt"] = ppt

    sizes = [(1, 2), (1, 5), (5, 35), (5, 3), (9, 3), (3, 3), (7, 7), (2, 1)]
    out["kernels"] = [{"k": list(k), "m": cv2.getStructuringElement(cv2.MORPH_ELLIPSE, k).tolist()} for k in sizes]
    morph = []
    for k in sizes:
        for _ in range(3):
            h, w = int(rng.integers(1, 60)), int(rng.integers(1, 70))
            src = (rng.random((h, w)) < rng.uniform(0.05, 0.7)).astype(np.uint8)
            kern = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, k)
            morph.append({"k": list(k), "w": w, "h": h, "src": b64(src),
                          "erode": b64(cv2.erode(src, kern)), "dilate": b64(cv2.dilate(src, kern))})
    out["morph"] = morph

    fill = []
    for c in contours_all[:400]:
        x, y, w, h = cv2.boundingRect(c)
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.drawContours(mask, [c - (x, y)], -1, 255, thickness=cv2.FILLED)
        fill.append({"pts": c.tolist(), "rows": (mask > 0).sum(axis=1).tolist()})
    out["fill"] = fill

    noise = []
    for _ in range(6):
        h, w = int(rng.integers(20, 90)), int(rng.integers(20, 90))
        g = (255 * (rng.random((h, w)) < rng.uniform(0.0, 0.5))).astype(np.uint8)
        M, N = h // 20, w // 20
        noise.append({"w": w, "h": h, "img": b64(g), "grid": create_grid(g, M, N).tolist()})
    out["noise"] = noise

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "shapes.json").write_text(json.dumps(out, separators=(",", ":")))
    print("wrote", OUT / "shapes.json", {k: len(v) for k, v in out.items() if isinstance(v, list)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
