#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Export small OpenCV reference outputs for the Swift staff-preprocessing port (StaffPreprocessing).

REFERENCE / CROSS-CHECK ONLY (offline tooling, not linked into the app). Writes into
Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/staff_preprocess_cv2/:

  src_37x131.png, src_40x130.png   random uint8 gray sources (seeded)
  resize_<src>_to_<W>x<H>.bin      raw uint8 of cv2.resize(src, (W, H)) (INTER_LINEAR, as homr calls it)
  crop_real.png                    real staff crop (ink bbox of fixtures/mono.c_major_scale/input.png)
  canvas_crop_real.png             homr staff_parsing.add_image_into_tr_omr_canvas(crop_real)
  rgb_24x40.png, rgb_24x40.gray.bin  RGB source + cv2.cvtColor(cv2.imread(IMREAD_COLOR), COLOR_BGR2GRAY)
  manifest.json                    cv2 / homr versions

usage: HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python tools/oracle/export_preprocess_refs.py
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/staff_preprocess_cv2"
HOMR_ROOT = Path(os.environ.get("HOMR_ROOT", "/workspace/homr-upstream"))
sys.path.insert(0, str(HOMR_ROOT))
from homr.staff_parsing import add_image_into_tr_omr_canvas  # noqa: E402

RESIZES = {
    "src_37x131": [(300, 90), (61, 17), (131, 80), (213, 64)],  # up, down, mixed, 213 = 13*16+5 (SIMD tail)
    "src_40x130": [(65, 20)],  # exact 2x down (OpenCV switches to INTER_AREA)
}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(20260926)
    srcs = {"src_37x131": rng.integers(0, 256, (37, 131), dtype=np.uint8),
            "src_40x130": rng.integers(0, 256, (40, 130), dtype=np.uint8)}
    for name, img in srcs.items():
        cv2.imwrite(str(OUT / f"{name}.png"), img)
        for w, h in RESIZES[name]:
            (OUT / f"resize_{name}_to_{w}x{h}.bin").write_bytes(cv2.resize(img, (w, h)).tobytes())

    page = cv2.cvtColor(cv2.imread(str(REPO / "fixtures/mono.c_major_scale/input.png")), cv2.COLOR_BGR2GRAY)
    ys, xs = np.where(page < 128)
    crop = np.ascontiguousarray(page[max(0, ys.min() - 40):ys.max() + 40, max(0, xs.min() - 20):xs.max() + 20])
    cv2.imwrite(str(OUT / "crop_real.png"), crop)
    cv2.imwrite(str(OUT / "canvas_crop_real.png"), add_image_into_tr_omr_canvas(crop))

    rgb = rng.integers(0, 256, (24, 40, 3), dtype=np.uint8)
    cv2.imwrite(str(OUT / "rgb_24x40.png"), rgb)
    gray = cv2.cvtColor(cv2.imread(str(OUT / "rgb_24x40.png"), cv2.IMREAD_COLOR), cv2.COLOR_BGR2GRAY)
    (OUT / "rgb_24x40.gray.bin").write_bytes(gray.tobytes())

    commit = subprocess.run(["git", "-C", str(HOMR_ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    (OUT / "manifest.json").write_text(json.dumps({
        "generator": "tools/oracle/export_preprocess_refs.py",
        "opencv": cv2.__version__, "numpy": np.__version__, "homr_commit": commit,
        "crop_real_shape": list(crop.shape), "resizes": {k: v for k, v in RESIZES.items()},
    }, indent=2) + "\n")
    print(f"wrote {OUT}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
