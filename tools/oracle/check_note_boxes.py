#!/usr/bin/env python3
"""Sanity check `omr-test parse-page` OMR_POSITIONS_OUT dumps: every note box should sit on a decoded
symbol of the same pitch (nearest symbol image position to the box center; lift ignored, +-1 semitone).

    python tools/oracle/check_note_boxes.py swift.json [...]
"""
import json
import math
import sys

STEP = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
failed = False
for path in sys.argv[1:]:
    d = json.load(open(path))
    syms = [s for st in d["staffs"] for s in st if s.get("image")]
    ok = bad = 0
    for n in d["notes"]:
        if not n["rect"]:
            bad += 1
            continue
        x, y, w, h = n["rect"]
        s = min(syms, key=lambda s: math.dist(s["image"], (x + w / 2, y + h / 2)))
        parts = s["symbol"].split()
        try:
            midi = 12 * (int(parts[1][-1]) + 1) + STEP[parts[1][0]]
        except (IndexError, KeyError, ValueError):
            midi = None
        if midi is not None and abs(midi - n["midiNote"]) <= 1:
            ok += 1
        else:
            bad += 1
            print(f"{path}: note {n['noteIndex']} midi {n['midiNote']} boxed on {s['symbol']}")
    print(f"{path}: {ok}/{ok + bad} boxes on the right note ({d['layoutSource']})")
    failed |= bad > 0
sys.exit(1 if failed else 0)
