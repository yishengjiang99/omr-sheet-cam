#!/usr/bin/env python3
"""Layer C (layout) count check on Linux — mirrors OMRHomrIOS.renderTokens.

Swift is not available on Linux CI, so this re-implements, line for line, the package's
`SymbolMIDIMapping.sourcedNoteEvents` + `orderedNoteEvents` + `NoteLayout.midiFallback`
and the `SMFWriter` note-track ordering, then for every fixture with a complete
`expected.tokens.json` and an `expected.notes.csv` asserts:

  1. len(noteLayout) == sounding notes in expected.notes.csv
  2. noteLayout entries (tick, pitch, duration, staff) == the shared MIDI note list, 1:1,
     and that list == expected.notes.csv (as a multiset)
  3. order is (tick, staff, pitch[, duration, symbolIndex]) ascending, noteIndex == k
  4. k-th note-on in the written SMF note track == noteLayout[k]
  5. layoutSource == "midi-fallback" and no box (no attention boxes yet)

Fixtures whose tokens status is not "complete" (stubs / awaiting oracle export) are
reported as SKIP, not failed. Exit code 1 on any failure.

Usage: python3 tools/oracle/check_note_layout.py [fixtures_dir]
"""
from __future__ import annotations

import csv
import json
import math
import struct
import sys
from pathlib import Path

TPQ = 480
NONOTE, EMPTY = ".", "_"


# --- SymbolMIDIMapping mirror -------------------------------------------------------

def midi_note(pitch: str, lift: str) -> int | None:
    if pitch in (NONOTE, EMPTY) or not pitch:
        return None
    base = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}.get(pitch[0].upper())
    try:
        octave = int(pitch[1:])
    except ValueError:
        return None
    if base is None:
        return None
    s = (octave + 1) * 12 + base
    s += {"#": 1, "##": 2, "b": -1, "bb": -2}.get(lift, 0)
    return s if 0 <= s <= 127 else None


def kern_suffix(rhythm: str) -> str | None:
    if rhythm.startswith("note_") or rhythm.startswith("rest_"):
        return rhythm[5:]
    return None


def prior_pow2(n: int) -> int:
    return 1 if n < 1 else 1 << (n.bit_length() - 1)


def dotted(base: float, dots: int) -> float:
    dur, add = base, base / 2
    for _ in range(dots):
        dur += add
        add /= 2
    return dur


def whole_fraction(kern: str) -> float | None:
    if kern.endswith("m"):
        return 1.0
    if "G" in kern:
        return 0.0
    i = 0
    while i < len(kern) and kern[i].isdigit():
        i += 1
    base = int(kern[:i]) if i else 4
    dots = kern[i:].count(".")
    if base == 0:
        return dotted(1.0, dots)
    if base > 0 and base & (base - 1) == 0:
        bd, actual, normal = 1.0 / base, 1.0, 1.0
    else:
        n = prior_pow2(base)
        bd, actual, normal = 1.0 / n, float(base), float(n)
    dur = dotted(bd, dots)
    if actual != normal:
        dur *= normal / actual
    return dur


def duration_ticks(rhythm: str, tpq: int = TPQ) -> int | None:
    k = kern_suffix(rhythm)
    if k is None:
        return None
    w = whole_fraction(k)
    if w is None:
        return None
    return max(0, math.floor(w * 4 * tpq + 0.5))  # Swift .rounded(): half away from zero (x >= 0)


def staff_index(position: str) -> int:
    return 1 if position in ("lower", "lower2") else 0


def sourced_note_events(symbols: list[dict]) -> list[dict]:
    onset = chord_anchor = 0
    share = False
    events: list[dict] = []
    for idx, s in enumerate(symbols):
        r = s["rhythm"]
        if r == "chord":
            share = True
            continue
        if r.startswith("rest_"):
            d = duration_ticks(r)
            onset += TPQ if d is None else d
            share = False
            continue
        if r.startswith("clef_"):
            if events:
                onset = chord_anchor = 0
            share = False
            continue
        if not r.startswith("note_"):
            share = False
            continue
        m = midi_note(s["pitch"], s["lift"])
        if m is None:
            share = False
            continue
        d = duration_ticks(r)
        d = TPQ if d is None else d
        if "G" in (kern_suffix(r) or ""):
            share = False
            continue
        if share:
            tick = chord_anchor
            share = False
        else:
            tick = onset
            chord_anchor = onset
            onset += d
        events.append({"symbolIndex": idx, "tick": tick, "pitch": m,
                       "duration": max(1, d), "staff": staff_index(s["position"])})
    return events


def ordered_note_events(symbols: list[dict], staff_offset: int = 0) -> list[dict]:
    ev = sourced_note_events(symbols)
    for e in ev:
        e["staff"] += staff_offset
    ev.sort(key=lambda e: (e["tick"], e["staff"], e["pitch"], e["duration"], e["symbolIndex"]))
    return ev


def render_tokens(symbols: list[dict]) -> dict:
    ordered = ordered_note_events(symbols)
    layout = [{"noteIndex": k, "symbolIndex": e["symbolIndex"], "midiNote": e["pitch"],
               "onsetTicks": e["tick"], "durationTicks": e["duration"],
               "staffIndex": e["staff"], "pageRect": None} for k, e in enumerate(ordered)]
    return {"midi": write_smf(ordered), "noteLayout": layout, "layoutSource": "midi-fallback",
            "events": ordered}


# --- SMFWriter note-track mirror + reader -------------------------------------------

def vlq(v: int) -> bytes:
    v = max(0, v)
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    return bytes(reversed(out))


def write_smf(notes: list[dict], vel: int = 80) -> bytes:
    inst = []
    for i, n in enumerate(notes):
        inst.append((n["tick"], 1 + i, bytes([0x90, n["pitch"], vel])))
        inst.append((n["tick"] + max(0, n["duration"]), 0, bytes([0x80, n["pitch"], 0x40])))
    inst.sort(key=lambda x: (x[0], x[1]))
    trk, last = bytearray(), 0
    for t, _, b in inst:
        trk += vlq(t - last) + b
        last = t
    trk += vlq(0) + b"\xff\x2f\x00"
    tempo = vlq(0) + b"\xff\x51\x03\x07\xa1\x20" + vlq(0) + b"\xff\x2f\x00"
    out = b"MThd" + struct.pack(">IHHH", 6, 1, 2, TPQ)
    for t in (tempo, bytes(trk)):
        out += b"MTrk" + struct.pack(">I", len(t)) + t
    return out


def note_ons(smf: bytes) -> list[tuple[int, int]]:
    i, track, out = 14, 0, []
    while i + 8 <= len(smf):
        ln = struct.unpack(">I", smf[i + 4:i + 8])[0]
        j, end, tick = i + 8, i + 8 + ln, 0
        while track >= 1 and j < end:
            delta = 0
            while True:
                b = smf[j]; j += 1
                delta = (delta << 7) | (b & 0x7F)
                if not b & 0x80:
                    break
            tick += delta
            st = smf[j]
            if st == 0xFF:
                j += 3 + smf[j + 2]
            else:
                if st & 0xF0 == 0x90 and smf[j + 2] > 0:
                    out.append((tick, smf[j + 1]))
                j += 3
        track += 1
        i = end
    return out


# --- fixture check ------------------------------------------------------------------

def load_csv(path: Path) -> list[tuple[int, int, int, int]]:
    rows = []
    with path.open() as f:
        for row in csv.reader(f):
            if not row or row[0].strip().lower().startswith("tick"):
                continue
            rows.append(tuple(int(c) for c in row[:4]))
    return rows


def check_fixture(d: Path) -> tuple[str, str]:
    tok = json.loads((d / "expected.tokens.json").read_text())
    expected = load_csv(d / "expected.notes.csv")
    if tok.get("status") != "complete" or not tok.get("symbols"):
        return "SKIP", f"tokens status={tok.get('status')!r} symbols={len(tok.get('symbols', []))} (csv notes={len(expected)})"
    res = render_tokens(tok["symbols"])
    layout, events = res["noteLayout"], res["events"]
    errs = []
    if len(layout) != len(expected):
        errs.append(f"count layout={len(layout)} != csv sounding={len(expected)}")
    one_to_one = [(l["onsetTicks"], l["midiNote"], l["durationTicks"], l["staffIndex"]) for l in layout]
    midi_list = [(e["tick"], e["pitch"], e["duration"], e["staff"]) for e in events]
    if one_to_one != midi_list:
        errs.append("layout != shared MIDI note list 1:1")
    if sorted(one_to_one) != sorted(expected):
        errs.append(f"layout notes != csv\n  got={sorted(one_to_one)}\n  exp={sorted(expected)}")
    keys = [(l["onsetTicks"], l["staffIndex"], l["midiNote"]) for l in layout]
    if keys != sorted(keys):
        errs.append("not ordered by (tick, staff, pitch)")
    if [l["noteIndex"] for l in layout] != list(range(len(layout))):
        errs.append("noteIndex != position")
    ons = note_ons(res["midi"])
    if ons != [(l["onsetTicks"], l["midiNote"]) for l in layout]:
        errs.append(f"SMF note-on order != noteLayout order\n  ons={ons}")
    if res["layoutSource"] != "midi-fallback" or any(l["pageRect"] is not None for l in layout):
        errs.append("expected midi-fallback with no boxes")
    if errs:
        return "FAIL", "; ".join(errs)
    staves = sorted({l["staffIndex"] for l in layout})
    return "PASS", f"noteLayout={len(layout)} == csv={len(expected)} staves={staves} layoutSource=midi-fallback"


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "fixtures"
    fails = passes = 0
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        if not ((d / "expected.tokens.json").exists() and (d / "expected.notes.csv").exists()):
            continue
        status, msg = check_fixture(d)
        print(f"{status:4} {d.name:22} {msg}")
        fails += status == "FAIL"
        passes += status == "PASS"
    print(f"\nLayer C layout check: {passes} pass, {fails} fail")
    return 1 if fails or not passes else 0


if __name__ == "__main__":
    sys.exit(main())
