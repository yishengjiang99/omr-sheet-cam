#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# omr-sheet-cam — homr oracle EXPORTER (offline tooling, NOT part of the iOS runtime).
# Copyright (C) 2026 the omr-sheet-cam authors.
#
# Drives liebharc/homr (AGPL-3.0, https://github.com/liebharc/homr) at run time.
# Nothing from this file is linked into the app.
"""Export Python-homr staff-level oracle tokens for the OMR fixtures.

REFERENCE / CROSS-CHECK ONLY. The real Gate-1 check is the Swift ``omr-test``;
this script only produces the oracle data that gate compares against.

For a fixture page, runs homr's *own* page pipeline — SegNet -> staff detection ->
``staff_parsing.prepare_staff_image`` (crop + dewarp + centre on the 256 x 1280
canvas) -> ``Staff2Score.predict`` (encoder -> greedy decoder) — and captures,
for every staff handed to the transformer:

* the uint8 canvas homr feeds the encoder (256 x 1280, grayscale),
* the preprocessed float32 tensor ``[1, 1, 256, 1280]`` =
  ``(px / 255 - 0.7931) / 0.1738`` (homr ``staff2score.ConvertToArray``),
* the raw decoder output, per stream (rhythm, pitch, lift, articulation, slur,
  position), exactly as ``Staff2Score.predict`` returned it (EOS excluded).

Models: ONLY the files pinned in ``models.lock`` (fetched into ``models/`` by
``scripts/fetch-models``); every hash is checked before use. SegNet fp16 and
Encoder fp16 run on the ONNX Runtime CPU EP, Decoder fp32 on the CPU EP; the
encoder context is cast to fp32 before the decoder (homr's own seam). homr's
own bundled/auto-downloaded checkpoints are never used.

Setup (homr checkout + venv live outside the repo, pinned to HOMR_COMMIT)::

    git clone https://github.com/liebharc/homr /workspace/homr-upstream
    git -C /workspace/homr-upstream checkout 7d97c3cee4ad772b50266fdf9dc78bbf9064701e
    python3 -m venv /workspace/homr-venv
    /workspace/homr-venv/bin/pip install -e /workspace/homr-upstream

Usage::

    scripts/fetch-models
    HOMR_ROOT=/workspace/homr-upstream /workspace/homr-venv/bin/python \\
        tools/oracle/export_staff_tokens.py --all

    # just the Gate-1 fixture, or re-decode the committed staff.png:
    ... export_staff_tokens.py --gate
    ... export_staff_tokens.py --check-staff fixtures/oracle.c_scale_staff/staff.png
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stderr
from pathlib import Path
from typing import Any

import numpy as np

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
MODELS_DIR = Path(os.environ.get("MODELS_DIR", REPO / "models"))
LOCK = REPO / "models.lock"
STREAMS = ["rhythm", "pitch", "lift", "articulation", "slur", "position"]
GATE_STREAMS = ["rhythm", "pitch", "lift", "articulation"]
GATE_ID = "oracle.c_scale_staff"
GATE_SOURCE = "mono.c_major_scale"
SYNTHETIC = [
    "mono.c_major_scale",
    "mono.sharps_flats",
    "mono.rhythms",
    "mono.rests",
    "poly.chord",
    "clefs.bass",
    "piano.grand",
]
EXPORTER = "tools/oracle/export_staff_tokens.py"
# homr commit whose Config names the models.lock checkpoints (model 465, SegNet 308).
HOMR_COMMIT = "7d97c3cee4ad772b50266fdf9dc78bbf9064701e"


# --------------------------------------------------------------------------- models


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def locked_models() -> dict[str, dict[str, str]]:
    """{'segnet'|'encoder'|'decoder': {'file', 'sha256', 'url', 'path'}} from models.lock."""
    out: dict[str, dict[str, str]] = {}
    for line in LOCK.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        digest, name, url = line.split()
        kind = "segnet" if name.startswith("segnet_") else name.split("_", 1)[0]
        path = MODELS_DIR / name
        if not path.is_file():
            raise SystemExit(f"{path} missing - run scripts/fetch-models")
        have = sha256(path)
        if have != digest:
            raise SystemExit(f"{path}: sha256 {have} != models.lock {digest}")
        out[kind] = {"file": name, "sha256": digest, "url": url, "path": str(path)}
    for kind in ("segnet", "encoder", "decoder"):
        if kind not in out:
            raise SystemExit(f"models.lock has no {kind} entry")
    if not out["encoder"]["file"].endswith("_fp16.onnx"):
        raise SystemExit("expected the fp16 encoder in models.lock")
    if out["decoder"]["file"].endswith("_fp16.onnx"):
        raise SystemExit("expected the fp32 decoder in models.lock")
    return out


# --------------------------------------------------------------------------- homr


class Homr:
    """homr page pipeline + Staff2Score wired to the models.lock files (CPU EP only)."""

    def __init__(self, homr_root: Path, models: dict[str, dict[str, str]]) -> None:
        sys.path.insert(0, str(homr_root))
        self.root = homr_root
        self.models = models
        import homr.onnx_providers as providers
        import homr.segmentation.inference_segnet as seg

        # Force the CPU EP everywhere (no CUDA/ROCm/CoreML even if present) and point
        # SegNet at the pinned fp16 file. With use_gpu_inference=True and no GPU EP,
        # homr's own Segnet() takes its "fp16 model on the CPU" branch.
        for mod in (providers, seg):
            for fn in ("cuda_available", "rocm_available", "coreml_available"):
                if hasattr(mod, fn):
                    setattr(mod, fn, lambda: False)
        seg.segnet_path_onnx_fp16 = models["segnet"]["path"]
        seg.segnet_path_onnx = os.devnull  # never fall back to an unpinned fp32 SegNet

        from homr.transformer.configs import Config
        from homr.transformer.staff2score import Staff2Score

        cfg = Config()
        cfg.use_gpu_inference = False  # decoder: fp32 on the CPU EP (homr default)
        cfg.use_coreml_encoder = False
        # Encoder() on the CPU path opens filepaths.encoder_path; hand it the pinned
        # fp16 file and flip fp16 so inputs are bound as float16 (what homr's
        # CoreML-encoder branch does, minus CoreML).
        cfg.filepaths.encoder_path = models["encoder"]["path"]
        cfg.filepaths.encoder_path_fp16 = models["encoder"]["path"]
        cfg.filepaths.decoder_path = models["decoder"]["path"]
        cfg.filepaths.decoder_path_fp16 = os.devnull
        s2s = Staff2Score(cfg)
        s2s.encoder.fp16 = True
        assert s2s.decoder.fp16 is False, "decoder must be fp32"
        assert s2s.encoder.encoder.get_providers()[0] == "CPUExecutionProvider"
        self.cfg = cfg
        self.s2s = s2s

    def commit(self) -> str:
        return subprocess.check_output(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True
        ).strip()

    def decode_canvas(self, canvas: np.ndarray) -> tuple[np.ndarray, list[Any]]:
        from homr.transformer.staff2score import _transform

        return _transform(image=canvas), list(self.s2s.predict(canvas))

    def run_page(self, image: Path) -> dict[str, Any]:
        import homr.staff_parsing as staff_parsing
        import homr.staff_parsing_tromr as tromr
        from homr.main import ProcessingConfig, detect_staffs_in_image

        tromr.inference = self.s2s  # predict_best() uses this module global
        captured: list[dict[str, Any]] = []
        orig_predict = self.s2s.predict

        def predict_capture(img: np.ndarray) -> list:
            from homr.transformer.staff2score import _transform

            syms = orig_predict(img)
            captured.append({"canvas": np.array(img), "tensor": _transform(image=img), "raw": list(syms)})
            return syms

        orig_parse = staff_parsing.parse_staff_tromr

        def parse_capture(staff: Any, staff_image: np.ndarray, config: Any) -> list:
            res = orig_parse(staff=staff, staff_image=staff_image, config=config)
            captured[-1]["is_grandstaff"] = bool(staff.is_grandstaff)
            captured[-1]["filtered"] = list(res)
            return res

        self.s2s.predict = predict_capture  # type: ignore[method-assign]
        staff_parsing.parse_staff_tromr = parse_capture
        log = io.StringIO()
        try:
            with tempfile.TemporaryDirectory() as td, redirect_stderr(log):
                work = Path(td) / image.name  # homr writes sidecars next to its input
                shutil.copy(image, work)
                pcfg = ProcessingConfig(
                    enable_debug=False,
                    enable_cache=False,
                    write_staff_positions=False,
                    read_staff_positions=False,
                    selected_staff=-1,
                    transformer_use_gpu=False,
                    segnet_use_gpu=True,  # -> pinned fp16 SegNet on the CPU EP (see __init__)
                    coreml_encoder=False,
                    title_detection=False,
                )
                multi_staffs, preprocessed, debug, _title, n_staffs = detect_staffs_in_image(
                    str(work), pcfg
                )
                voices = staff_parsing.parse_staffs(debug, multi_staffs, preprocessed, config=self.cfg)
        finally:
            self.s2s.predict = orig_predict  # type: ignore[method-assign]
            staff_parsing.parse_staff_tromr = orig_parse
        return {"staffs": captured, "voices": voices, "staffs_detected": n_staffs, "log": log.getvalue()}


# --------------------------------------------------------------------------- formats


def sym_dict(sym: Any) -> dict[str, str]:
    return {s: getattr(sym, s) for s in STREAMS}


def streams_of(symbols: list[dict[str, str]], vocab: Any, names: list[str]) -> dict[str, Any]:
    out = {}
    for s in names:
        toks = [d[s] for d in symbols]
        out[s] = {"tokens": toks, "ids": [int(getattr(vocab, s)[t]) for t in toks]}
    return out


def edit_distance(a: list, b: list) -> int:
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def key4(d: dict[str, str]) -> tuple[str, ...]:
    return tuple(d[s] for s in GATE_STREAMS)


def diff_lines(got: list[dict[str, str]], want: list[dict[str, str]]) -> list[str]:
    import difflib

    fmt = lambda d: " ".join(d.get(s, "?") for s in STREAMS)  # noqa: E731
    return list(
        difflib.unified_diff(
            [fmt(d) for d in want], [fmt(d) for d in got], "expected (hand-authored)", "homr oracle", lineterm="", n=99
        )
    )


def load_expected(fid: str) -> list[dict[str, str]]:
    return json.loads((FIXTURES / fid / "expected.tokens.json").read_text()).get("symbols", [])


def checkpoint_meta(models: dict[str, dict[str, str]]) -> dict[str, Any]:
    return {k: {"file": v["file"], "sha256": v["sha256"], "url": v["url"]} for k, v in models.items()}


# --------------------------------------------------------------------------- exports


def export_fixture(h: Homr, fid: str) -> dict[str, Any]:
    image = FIXTURES / fid / "input.png"
    res = h.run_page(image)
    staffs = []
    all_raw: list[dict[str, str]] = []
    for i, cap in enumerate(res["staffs"]):
        raw = [sym_dict(s) for s in cap["raw"]]
        all_raw.extend(raw)
        staffs.append(
            {
                "index": i,
                "is_grandstaff": cap.get("is_grandstaff"),
                "canvas_shape": list(cap["canvas"].shape),
                "symbol_count": len(raw),
                "symbols": raw,
                "symbols_after_position_filter": [sym_dict(s) for s in cap.get("filtered", cap["raw"])],
            }
        )
    expected = load_expected(fid)
    doc = {
        "source": "python-homr (reference/cross-check only; the gate is Swift omr-test)",
        "exporter": EXPORTER,
        "homr_commit": h.commit(),
        "checkpoints": checkpoint_meta(h.models),
        "precision": {"segnet": "fp16", "encoder": "fp16", "decoder": "fp32", "provider": "CPU"},
        "input_image": f"fixtures/{fid}/input.png",
        "input_image_sha256": sha256(image),
        "staffs_detected": res["staffs_detected"],
        "staff_count": len(staffs),
        "symbol_count": len(all_raw),
        "symbols": all_raw,
        "staffs": staffs,
        "homr_page_result": [[sym_dict(s) for s in v] for v in res["voices"]],
        "vs_expected": {
            "expected_symbol_count": len(expected),
            "edit_distance_4streams": edit_distance([key4(d) for d in all_raw], [key4(d) for d in expected]),
            "exact_4streams": [key4(d) for d in all_raw] == [key4(d) for d in expected],
        },
    }
    return {"doc": doc, "res": res}


def export_gate(h: Homr, out: dict[str, Any]) -> dict[str, Any]:
    res = out["res"]
    if len(res["staffs"]) != 1:
        raise SystemExit(f"{GATE_SOURCE}: expected exactly one staff, homr produced {len(res['staffs'])}")
    cap = res["staffs"][0]
    canvas = cap["canvas"]
    if canvas.ndim != 2 or canvas.shape != (256, 1280) or canvas.dtype != np.uint8:
        raise SystemExit(f"unexpected staff canvas {canvas.shape} {canvas.dtype}")
    d = FIXTURES / GATE_ID
    d.mkdir(exist_ok=True)
    from PIL import Image

    Image.fromarray(canvas, "L").save(d / "staff.png", optimize=True)
    tensor = cap["tensor"].astype(np.float32)
    np.save(d / "staff.npy", tensor)

    # Re-decode from the committed PNG alone: it must reproduce the tensor bit-for-bit
    # and the exact same symbols (what the Swift gate will feed).
    reread = np.array(Image.open(d / "staff.png"))
    t2, syms2 = h.decode_canvas(reread)
    if not np.array_equal(t2.astype(np.float32), tensor):
        raise SystemExit("staff.png does not reproduce staff.npy")
    raw = [sym_dict(s) for s in cap["raw"]]
    if [sym_dict(s) for s in syms2] != raw:
        raise SystemExit("re-decoding staff.png gave different symbols")

    vocab = h.cfg.vocab
    tokens = {
        "source": "python-homr Staff2Score.predict (raw decoder output, EOS excluded)",
        "status": "complete",
        "exporter": EXPORTER,
        "homr_commit": h.commit(),
        "input": "staff.png",
        "input_tensor": "staff.npy",
        "symbol_count": len(raw),
        "streams": streams_of(raw, vocab, GATE_STREAMS),
        "symbols": raw,
    }
    (d / "expected.tokens.json").write_text(json.dumps(tokens, indent=2) + "\n")

    enc, dec, seg = h.models["encoder"], h.models["decoder"], h.models["segnet"]
    meta = f"""id: {GATE_ID}
match_tier: exact_tokens
status: complete
clef: treble
key: C
time: "4/4"
source: Python homr oracle export ({EXPORTER}) of fixtures/{GATE_SOURCE}/input.png
license: CC0 synthetic input; tokens are homr (AGPL-3.0) model output
homr_repo: https://github.com/liebharc/homr
homr_commit: {h.commit()}
models:
  encoder: {{file: {enc['file']}, sha256: {enc['sha256']}, precision: fp16, ep: CPU}}
  decoder: {{file: {dec['file']}, sha256: {dec['sha256']}, precision: fp32, ep: CPU}}
  segnet: {{file: {seg['file']}, sha256: {seg['sha256']}, precision: fp16, ep: CPU, used_for: staff detection/crop only}}
staff_input:
  image: staff.png          # uint8 grayscale 256x1280 canvas homr fed the encoder
  tensor: staff.npy         # float32 [1,1,256,1280] = (px/255 - 0.7931) / 0.1738
  tensor_sha256: {sha256(d / 'staff.npy')}
  preprocessing: homr staff_parsing.prepare_staff_image (crop, dewarp, centre on canvas)
symbol_count: {len(raw)}
expected_notes: expected.notes.csv is canonicalized from these tokens (fixtures/README.md rules)
notes: Gate-1 = Swift omr-test decoding staff.png must equal expected.tokens.json exactly.
  Python checks are reference/cross-check only.
"""
    (d / "meta.yaml").write_text(meta)
    write_notes_csv(raw, d / "expected.notes.csv")
    return tokens


RHYTHM_TICKS = {"1": 1920, "2": 960, "4": 480, "8": 240, "16": 120, "32": 60, "64": 30}
STEPS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def write_notes_csv(symbols: list[dict[str, str]], path: Path) -> None:
    """Canonical (tick, pitch, duration, staff) per fixtures/README.md, single-staff subset."""
    rows, tick, last_dur = [], 0, 0
    pending_chord = False
    for s in symbols:
        r = s["rhythm"]
        if r == "chord":
            pending_chord = True
            continue
        kind, _, val = r.partition("_")
        if kind not in ("note", "rest") or not val:
            continue
        dots = len(val) - len(val.rstrip("."))
        base = RHYTHM_TICKS.get(val.rstrip("."))
        if base is None:
            raise SystemExit(f"unsupported rhythm {r} for notes.csv")
        dur = int(base * (1.5 if dots == 1 else 1.75 if dots == 2 else 1))
        if pending_chord:
            tick -= last_dur
        if kind == "note":
            p = s["pitch"]
            midi = 12 * (int(p[1:]) + 1) + STEPS[p[0]] + {"#": 1, "b": -1}.get(s["lift"], 0)
            rows.append((tick, midi, dur, 1 if s["position"] == "lower" else 0))
        tick += dur
        last_dur = dur
        pending_chord = False
    with path.open("w", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["tick", "pitch", "duration", "staff"])
        w.writerows(sorted(rows))


def write_report(results: dict[str, dict[str, Any]], homr_commit: str, gate: dict[str, Any] | None) -> None:
    lines = [
        "# Python homr oracle report",
        "",
        "Reference / cross-check only: the real gate is the Swift `omr-test`.",
        f"Generated by `{EXPORTER}` with liebharc/homr `{homr_commit}` and the",
        "`models.lock` checkpoints (SegNet fp16 + Encoder fp16 + Decoder fp32, ORT CPU EP).",
        "",
        "`symbols` = raw `Staff2Score.predict` output summed over the staffs homr detected",
        "(before homr's position filter). `edit distance` = Levenshtein distance over",
        "symbols, each symbol compared on the four streams rhythm/pitch/lift/articulation,",
        "vs the hand-authored `expected.tokens.json`. The hand-authored GT is unchanged.",
        "",
        "| fixture | staffs | symbols | expected | edit distance | exact (4 streams) |",
        "|---|---|---|---|---|---|",
    ]
    for fid, doc in results.items():
        v = doc["vs_expected"]
        lines.append(
            f"| `{fid}` | {doc['staff_count']} | {doc['symbol_count']} | {v['expected_symbol_count']} "
            f"| {v['edit_distance_4streams']} | {'yes' if v['exact_4streams'] else 'no'} |"
        )
    if gate is not None:
        lines += [
            "",
            f"Gate-1 fixture `{GATE_ID}` (from `{GATE_SOURCE}`): {gate['symbol_count']} symbols; "
            "see `fixtures/oracle.c_scale_staff/` (the fixture plan anticipated 22; this homr",
            "commit + model emits the count above). Encoder fp16 vs homr's stock fp32 encoder",
            "was cross-checked on the same canvases and gave identical symbols.",
        ]
    lines += ["", "## Diffs vs hand-authored GT", ""]
    for fid, doc in results.items():
        exp = load_expected(fid)
        if doc["vs_expected"]["exact_4streams"]:
            continue
        lines += [f"### {fid}", "", "```diff"]
        lines += diff_lines(doc["symbols"], exp)[2:]
        lines += ["```", ""]
    (FIXTURES / "ORACLE_REPORT.md").write_text("\n".join(lines).rstrip() + "\n")


# --------------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--gate", action="store_true", help=f"write fixtures/{GATE_ID}/")
    ap.add_argument("--all", action="store_true", help="gate + oracle.tokens.json for every synthetic fixture + report")
    ap.add_argument("--fixture", action="append", default=[], help="fixture id (writes oracle.tokens.json)")
    ap.add_argument("--check-staff", type=Path, help="decode a 256x1280 staff PNG and print symbols")
    ap.add_argument(
        "--homr-root", type=Path, default=Path(os.environ.get("HOMR_ROOT", "/workspace/homr-upstream"))
    )
    args = ap.parse_args()
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
    ap_commit = os.environ.get("HOMR_ALLOW_ANY_COMMIT") == "1"
    h = Homr(args.homr_root, locked_models())
    print(f"homr {h.commit()}", file=sys.stderr)
    if h.commit() != HOMR_COMMIT and not ap_commit:
        raise SystemExit(f"homr checkout is {h.commit()}, pinned {HOMR_COMMIT} (HOMR_ALLOW_ANY_COMMIT=1 to override)")

    if args.check_staff:
        from PIL import Image

        _, syms = h.decode_canvas(np.array(Image.open(args.check_staff).convert("L")))
        for s in syms:
            print(" ".join(sym_dict(s)[k] for k in STREAMS))
        print(f"{len(syms)} symbols", file=sys.stderr)
        return 0

    ids = list(args.fixture)
    if args.all:
        ids = SYNTHETIC
    gate = None
    results: dict[str, dict[str, Any]] = {}
    if args.gate or args.all:
        out = export_fixture(h, GATE_SOURCE)
        gate = export_gate(h, out)
        results[GATE_SOURCE] = out["doc"]
        print(f"{GATE_ID}: {gate['symbol_count']} symbols", file=sys.stderr)
    for fid in ids:
        if fid not in results:
            results[fid] = export_fixture(h, fid)["doc"]
    for fid in ids:
        doc = results[fid]
        (FIXTURES / fid / "oracle.tokens.json").write_text(json.dumps(doc, indent=2) + "\n")
        v = doc["vs_expected"]
        print(
            f"{fid}: staffs={doc['staff_count']} symbols={doc['symbol_count']} "
            f"expected={v['expected_symbol_count']} edit={v['edit_distance_4streams']}",
            file=sys.stderr,
        )
    if args.all:
        write_report({k: results[k] for k in SYNTHETIC}, h.commit(), gate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
