#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Render synthetic OMR fixture pages from their LilyPond sources.

For every ``fixtures/<id>/source.ly`` this script:

1. runs LilyPond -> ``fixtures/<id>/input.png`` (one grayscale A4 page, 200 dpi);
2. verifies the LilyPond MIDI output of the *same* source against
   ``fixtures/<id>/expected.notes.csv`` (tick rescaled to 480 TPQ, staff = MIDI
   track order), so page and GT provably share one source;
3. builds ``fixtures/camera.deskew/input.png`` as a *synthetic* camera variant of
   ``mono.c_major_scale/input.png`` (~15 deg rotation + mild perspective + noise).

Requirements: ``lilypond`` (2.24.x) on PATH, Python packages numpy, Pillow, mido.

Usage::

    python tools/fixtures/render_fixtures.py            # render + verify all
    python tools/fixtures/render_fixtures.py --verify-only
"""

from __future__ import annotations

import argparse
import csv
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import mido
import numpy as np
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
DPI = 200
TPQ = 480

# Staff index used in expected.notes.csv for each LilyPond MIDI track (in order).
# Default is [0, 1, ...]. clefs.bass GT uses staff 1 (homr position "lower").
STAFF_MAP: dict[str, list[int]] = {"clefs.bass": [1]}
DESKEW_SEED = 15
DESKEW_ANGLE_DEG = 15.0


def run_lilypond(src: Path, outdir: Path) -> tuple[Path, Path]:
    stem = outdir / "page"
    cmd = [
        "lilypond",
        f"-dresolution={DPI}",
        "-dpixmap-format=pnggray",
        "-dmidi-extension=mid",
        "--png",
        "-o",
        str(stem),
        str(src),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=src.parent)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        raise SystemExit(f"lilypond failed for {src}")
    for line in res.stderr.splitlines():
        if "warning" in line.lower() or "error" in line.lower():
            sys.stderr.write(f"[{src.parent.name}] {line}\n")
    pngs = sorted(outdir.glob("page*.png"))
    if len(pngs) != 1:
        raise SystemExit(f"{src}: expected exactly one page, got {[p.name for p in pngs]}")
    return pngs[0], outdir / "page.mid"


def midi_notes(path: Path, staff_map: list[int] | None = None) -> list[tuple[int, int, int, int]]:
    """(tick@480TPQ, pitch, duration, staff) for every note; staff = track order."""
    mid = mido.MidiFile(str(path))
    scale = TPQ / mid.ticks_per_beat
    out = []
    staff = 0
    for track in mid.tracks:
        t = 0
        on: dict[int, int] = {}
        track_notes = []
        for msg in track:
            t += msg.time
            if msg.type == "note_on" and msg.velocity > 0:
                on[msg.note] = t
            elif msg.type in ("note_off", "note_on") and msg.note in on:
                start = on.pop(msg.note)
                track_notes.append((round(start * scale), msg.note, round((t - start) * scale)))
        if track_notes:
            idx = staff_map[staff] if staff_map else staff
            out.extend((a, b, c, idx) for a, b, c in track_notes)
            staff += 1
    return sorted(out)


def load_csv(path: Path) -> list[tuple[int, int, int, int]]:
    with path.open() as fh:
        rows = list(csv.DictReader(fh))
    return sorted(
        (int(r["tick"]), int(r["pitch"]), int(r["duration"]), int(r["staff"])) for r in rows
    )


def verify(fid: str, midi_path: Path) -> bool:
    expected = load_csv(FIXTURES / fid / "expected.notes.csv")
    actual = midi_notes(midi_path, STAFF_MAP.get(fid))
    # LilyPond articulates notes slightly shorter than notated only with
    # \articulate; plain \midi keeps full values, so compare exactly.
    if actual == expected:
        print(f"  [ok] {fid}: LilyPond MIDI == expected.notes.csv ({len(expected)} notes)")
        return True
    print(f"  [MISMATCH] {fid}\n    lilypond={actual}\n    expected={expected}")
    return False


def make_deskew(src_png: Path, dst_png: Path) -> None:
    """Synthetic 'camera' variant: rotate ~15 deg, mild perspective, noise, blur."""
    rng = np.random.default_rng(DESKEW_SEED)
    img = Image.open(src_png).convert("L")
    w, h = img.size
    # Crop to the engraved region (plus margin) so the page reads like a close-up photo.
    arr = np.asarray(img)
    ys, xs = np.where(arr < 128)
    m = 120
    box = (max(0, xs.min() - m), max(0, ys.min() - m), min(w, xs.max() + m), min(h, ys.max() + m))
    img = img.crop(box)
    # Pad so rotation does not clip content.
    pad = int(0.35 * max(img.size))
    canvas = Image.new("L", (img.width + 2 * pad, img.height + 2 * pad), 255)
    canvas.paste(img, (pad, pad))
    rot = canvas.rotate(DESKEW_ANGLE_DEG, resample=Image.BICUBIC, expand=False, fillcolor=255)
    # Mild perspective: pull the top edge in by ~4% (keystone) via an 8-coef transform.
    cw, ch = rot.size
    k = 0.04 * cw
    src_quad = [(k, 0), (cw - k, 0), (cw, ch), (0, ch)]
    dst_quad = [(0, 0), (cw, 0), (cw, ch), (0, ch)]
    coeffs = _perspective_coeffs(dst_quad, src_quad)
    persp = rot.transform((cw, ch), Image.PERSPECTIVE, coeffs, Image.BICUBIC, fillcolor=255)
    a = np.asarray(persp).astype(np.float32)
    # Uneven illumination (paper under a lamp) + sensor noise.
    yy, xx = np.mgrid[0:ch, 0:cw]
    light = 1.0 - 0.12 * ((xx / cw - 0.3) ** 2 + (yy / ch - 0.2) ** 2)
    a = a * light * 0.93 + 8
    a += rng.normal(0, 6.0, a.shape)
    a = np.clip(a, 0, 255).astype(np.uint8)
    out = Image.fromarray(a, "L")
    out = out.filter(ImageFilter.GaussianBlur(radius=0.8))
    out.save(dst_png, optimize=True, dpi=(DPI, DPI))


def _perspective_coeffs(src, dst):
    # Solve for PIL PERSPECTIVE coefficients mapping output (src) -> input (dst).
    mat = []
    for (x, y), (u, v) in zip(src, dst):
        mat.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        mat.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(mat, dtype=np.float64)
    b = np.array([c for pt in dst for c in pt], dtype=np.float64)
    return np.linalg.solve(a, b).tolist()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify-only", action="store_true")
    args = ap.parse_args()
    if shutil.which("lilypond") is None:
        raise SystemExit("lilypond not found on PATH (apt install lilypond)")
    ok = True
    for src in sorted(FIXTURES.glob("*/source.ly")):
        fid = src.parent.name
        with tempfile.TemporaryDirectory() as td:
            png, mid = run_lilypond(src, Path(td))
            ok &= verify(fid, mid)
            if not args.verify_only:
                Image.open(png).convert("L").save(src.parent / "input.png", optimize=True, dpi=(DPI, DPI))
                print(f"  wrote fixtures/{fid}/input.png")
    if not args.verify_only:
        make_deskew(
            FIXTURES / "mono.c_major_scale" / "input.png",
            FIXTURES / "camera.deskew" / "input.png",
        )
        print("  wrote fixtures/camera.deskew/input.png (synthetic)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
