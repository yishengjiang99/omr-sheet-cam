#!/usr/bin/env python3
"""Staff image -> normalized fp32 NCHW [1,1,256,1280] .npy for `omr-test decode-staff`.

Mirrors homr (liebharc/homr main):
  staff_parsing.add_image_into_tr_omr_canvas  (aspect-fit into 1280x256, white canvas,
                                               left-aligned, vertically centered)
  staff2score.ConvertToArray                   (/255, (x - 0.7931) / 0.1738, float32)
Resize uses cv2.resize (INTER_LINEAR) when OpenCV is installed, else PIL BILINEAR (close,
not bit-identical).

The input must already be a cropped staff image (homr crops/dewarps staffs with SegNet first).
`--crop-ink` is a NON-upstream convenience for single-staff synthetic pages (e.g. the fixture
input.png renders): crop to the bounding box of dark pixels plus a margin before the canvas.

usage: staff_png_to_tensor.py IN.png OUT.npy [--crop-ink] [--margin PX] [--debug-png OUT.png]
Needs numpy + pillow (optional opencv-python).
"""
import argparse
import sys

import numpy as np
from PIL import Image

MAX_H, MAX_W = 256, 1280
MEAN, STD = 0.7931, 0.1738


def resize(gray: np.ndarray, w: int, h: int) -> np.ndarray:
    try:
        import cv2  # type: ignore

        return cv2.resize(gray, (w, h))
    except ImportError:
        return np.array(Image.fromarray(gray).resize((w, h), Image.BILINEAR))


def canvas(gray: np.ndarray) -> np.ndarray:
    h, w = gray.shape
    if h / w > MAX_H / MAX_W:
        nw, nh = int(w / h * MAX_H), MAX_H
    else:
        nw, nh = MAX_W, int(h / w * MAX_W)
    r = resize(gray, nw, nh)
    out = np.full((MAX_H, MAX_W), 255, dtype=np.uint8)
    y = (MAX_H - r.shape[0]) // 2
    out[y:y + r.shape[0], 0:r.shape[1]] = r
    return out


def crop_ink(gray: np.ndarray, margin: int) -> np.ndarray:
    ys, xs = np.where(gray < 128)
    if len(ys) == 0:
        return gray
    y0, y1 = max(0, ys.min() - margin), min(gray.shape[0], ys.max() + 1 + margin)
    x0, x1 = max(0, xs.min() - margin), min(gray.shape[1], xs.max() + 1 + margin)
    return gray[y0:y1, x0:x1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--crop-ink", action="store_true")
    ap.add_argument("--margin", type=int, default=20)
    ap.add_argument("--debug-png")
    a = ap.parse_args()
    gray = np.array(Image.open(a.inp).convert("L"))
    if a.crop_ink:
        gray = crop_ink(gray, a.margin)
    c = canvas(gray)
    if a.debug_png:
        Image.fromarray(c).save(a.debug_png)
    x = ((c.astype(np.float64) / 255 - MEAN) / STD).astype(np.float32)[None, None]
    assert x.shape == (1, 1, MAX_H, MAX_W)
    np.save(a.out, np.ascontiguousarray(x))
    print(f"wrote {a.out} {x.shape} {x.dtype}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
