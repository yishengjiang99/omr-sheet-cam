#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Export OpenCV / homr reference outputs for the Swift StaffPrepare primitives (OpenCVGeometry.swift).

REFERENCE / CROSS-CHECK ONLY (offline tooling, not linked into the app). Writes
Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/staff_prepare_cv2/refs.json (seeded, small):

  warp      cv2.warpAffine(src, M, (w, h), INTER_LINEAR, BORDER_CONSTANT, borderValue=b) on random
            uint8 sources; near-identity, dewarp-like, rotations/scales; widths hit the 16-px SIMD
            body and every scalar-tail length
  affine    cv2.getAffineTransform(src_tri, dst_tri) (float32 in, float64 out, compared exactly)
  poly      cv2.fillConvexPoly(zeros, tri.astype(int32), 255) incl. partly outside the mask
  delaunay  homr staff_dewarping.DelaunayTriangulation(points).simplices on grid-like point sets
  contours  homr staff_parsing.remove_black_contours_at_edges_of_image on random blob images

usage: HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python tools/oracle/export_dewarp_refs.py
"""
import base64
import json
import os
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/staff_prepare_cv2"
HOMR_ROOT = Path(os.environ.get("HOMR_ROOT", "/workspace/homr-upstream"))
sys.path.insert(0, str(HOMR_ROOT))
from homr.staff_dewarping import DelaunayTriangulation  # noqa: E402
from homr.staff_parsing import remove_black_contours_at_edges_of_image  # noqa: E402


def b64(a: np.ndarray) -> str:
    return base64.b64encode(np.ascontiguousarray(a, dtype=np.uint8).tobytes()).decode()


def main() -> int:
    rng = np.random.default_rng(20260926)
    refs: dict = {"opencv": cv2.__version__, "numpy": np.__version__,
                  "homr_commit": subprocess.check_output(["git", "-C", str(HOMR_ROOT), "rev-parse", "HEAD"], text=True).strip()}

    warp = []
    for t in range(64):
        sh, sw = int(rng.integers(6, 32)), int(rng.integers(6, 48))
        src = rng.integers(0, 256, (sh, sw), dtype=np.uint8)
        if t % 3 == 0:  # smooth, staff-like content
            src = cv2.GaussianBlur(src, (5, 5), 0)
        kind = t % 4
        if kind == 0:
            M = np.array([[1, 0, 0], [0, 1, 0]], np.float64) + rng.normal(0, 1e-3, (2, 3))
        elif kind == 1:  # dewarp-like: shear in y only, from a triangle pair
            s = np.float32([[0, 0], [40, 0], [0, 25]]) + rng.integers(0, 3, (3, 2)).astype(np.float32)
            d = s + np.float32([[0, 0], [0, rng.integers(-6, 7)], [0, rng.integers(-3, 4)]])
            M = cv2.getAffineTransform(s, d)
        elif kind == 2:
            a = rng.uniform(-0.5, 0.5)
            k = rng.uniform(0.6, 1.6)
            M = np.array([[k * np.cos(a), -k * np.sin(a), rng.uniform(-10, 10)],
                          [k * np.sin(a), k * np.cos(a), rng.uniform(-10, 10)]])
        else:
            M = rng.uniform(-1.5, 1.5, (2, 3)) + np.array([[1, 0, 0], [0, 1, 0]])
            M[:, 2] = rng.uniform(-20, 20, 2)
        w = int(16 * rng.integers(0, 6) + (t % 16)) or 1
        h = int(rng.integers(1, 20))
        b = int(rng.choice([0, 1, 255]))
        dst = cv2.warpAffine(src, M, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=b)
        warp.append({"src_w": sw, "src_h": sh, "src": b64(src), "M": [float(v) for v in M.ravel()],
                     "w": w, "h": h, "border": b, "dst": b64(dst)})
    refs["warp"] = warp

    affine = []
    for _ in range(200):
        s = (rng.uniform(0, 900, (3, 2)) if rng.random() < 0.5 else rng.integers(0, 900, (3, 2))).astype(np.float32)
        d = (s + rng.normal(0, 5, (3, 2))).astype(np.float32)
        affine.append({"src": s.ravel().tolist(), "dst": d.ravel().tolist(),
                       "M": [float(v) for v in cv2.getAffineTransform(s, d).ravel()]})
    refs["affine"] = affine

    poly = []
    for _ in range(150):
        w, h = int(rng.integers(1, 64)), int(rng.integers(1, 40))
        tri = rng.uniform(-5, [w + 5, h + 5], (3, 2)).astype(np.float32)
        pts = tri.astype(np.int32)
        m = np.zeros((h, w), np.uint8)
        cv2.fillConvexPoly(m, pts, 255)
        poly.append({"w": w, "h": h, "pts": pts.ravel().tolist(), "mask": b64(m)})
    refs["poly"] = poly

    delaunay = []
    for t in range(40):
        W, H = int(rng.integers(100, 900)), int(rng.integers(60, 400))
        nl = int(rng.integers(0, 6))
        lines = [[(0, 0), (W, 0)]]
        for i in range(nl):
            y = int(2 + i * H / 6)
            xs = list(range(2 + 80 * int(rng.integers(0, 2)), W - 10, 80))
            ln = [(x, int(y + rng.integers(-8, 9) * (t % 2))) for x in xs]
            if len(ln) > 2:
                lines.append([(0, ln[0][1])] + ln + [(W, ln[-1][1])])
        lines.append([(0, H), (W, H)])
        pts = np.concatenate(lines).astype(np.float32)
        try:
            simp = DelaunayTriangulation(pts).simplices.tolist()
        except Exception as e:  # noqa: BLE001
            simp = None
            print("delaunay failed", e)
        delaunay.append({"points": pts.ravel().tolist(), "simplices": simp})
    refs["delaunay"] = delaunay

    contours = []
    for t in range(40):
        h, w = int(rng.integers(16, 56)), int(rng.integers(16, 80))
        g = np.full((h, w), 255, np.uint8)
        for _ in range(int(rng.integers(1, 8))):
            x0, y0 = int(rng.integers(-10, w)), int(rng.integers(-10, h))
            x1, y1 = x0 + int(rng.integers(2, 50)), y0 + int(rng.integers(2, 40))
            g[max(0, y0):max(0, y1), max(0, x0):max(0, x1)] = int(rng.integers(0, 120))
            if rng.random() < 0.4:  # hollow it out
                g[max(0, y0 + 3):max(0, y1 - 3), max(0, x0 + 3):max(0, x1 - 3)] = 255
        noise = rng.random((h, w)) < 0.05
        g[noise] = rng.integers(0, 256, int(noise.sum()), dtype=np.uint8)
        unit = float(rng.uniform(2, 12))
        out = remove_black_contours_at_edges_of_image(g.copy(), unit)
        contours.append({"w": w, "h": h, "unit": unit, "src": b64(g), "dst": b64(out)})
    refs["contours"] = contours

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "refs.json").write_text(json.dumps(refs) + "\n")
    print(f"wrote {OUT / 'refs.json'} ({(OUT / 'refs.json').stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
