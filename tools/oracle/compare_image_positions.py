#!/usr/bin/env python3
"""Compare homr (export_image_positions.py) vs Swift (OMR_POSITIONS_OUT) per-symbol image positions.

    python tools/oracle/compare_image_positions.py homr.json swift.json [--tol PX]
Exits 1 when any matched symbol differs by more than --tol pixels (default 3).
"""
import json
import math
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
tol = float(sys.argv[sys.argv.index("--tol") + 1]) if "--tol" in sys.argv else 3.0
if "--tol" in sys.argv:
    args.remove(sys.argv[sys.argv.index("--tol") + 1])
homr, swift = (json.load(open(p))["staffs"] for p in args[:2])
worst, n, bad = 0.0, 0, 0
for si, (hs, ss) in enumerate(zip(homr, swift)):
    if len(hs) != len(ss):
        print(f"staff {si}: symbol count differs homr={len(hs)} swift={len(ss)} (comparing common prefix)")
    for i, (h, s) in enumerate(zip(hs, ss)):
        if h.get("image") is None or s.get("image") is None:
            if (h.get("image") is None) != (s.get("image") is None):
                print(f"staff {si} #{i}: presence differs homr={h['image']} swift={s['image']} ({h['symbol']})")
                bad += 1
            continue
        d = math.dist(h.get("image"), s.get("image"))
        n += 1
        worst = max(worst, d)
        if d > tol:
            bad += 1
            print(f"staff {si} #{i} {h['symbol']}: homr={h['image']} swift={s['image']} d={d:.2f}")
if len(homr) != len(swift):
    print(f"staff count differs homr={len(homr)} swift={len(swift)}")
print(f"{n} positions compared, worst {worst:.2f} px, {bad} over {tol} px")
sys.exit(1 if bad else 0)
