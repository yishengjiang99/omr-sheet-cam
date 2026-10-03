#!/usr/bin/env python3
"""Writes fixtures/samples/ode-to-joy.mid deterministically (no randomness, no timestamps).

Ode to Joy (L. v. Beethoven, Symphony No. 9; public domain). Right hand = the melody of
fixtures/samples/ode-to-joy.ly note for note (the "Try sample picture" page); left hand = a plain
tonic/dominant bass written for this sample (whole / half notes). SMF format 1, 480 TPQ like the
app's SMFWriter: track 0 conductor (name, 4/4, 100 bpm), track 1 right hand (ch 1), track 2 left
hand (ch 2), both GM program 0.

    python3 scripts/samples/make-ode-to-joy-midi.py [out.mid]
"""
import sys
from pathlib import Path

TPQ = 480
TEMPO_US = 600_000  # 100 bpm
Q, H, W, DQ, E = TPQ, 2 * TPQ, 4 * TPQ, 3 * TPQ // 2, TPQ // 2

# MIDI numbers: c' = 60. One tuple per note: (pitch, ticks). Copied from ode-to-joy.ly `melody`.
c, d, e, f, g = 60, 62, 64, 65, 67
MELODY = [
    (e, Q), (e, Q), (f, Q), (g, Q), (g, Q), (f, Q), (e, Q), (d, Q),
    (c, Q), (c, Q), (d, Q), (e, Q), (e, DQ), (d, E), (d, H),
    (e, Q), (e, Q), (f, Q), (g, Q), (g, Q), (f, Q), (e, Q), (d, Q),
    (c, Q), (c, Q), (d, Q), (e, Q), (d, DQ), (c, E), (c, H),
    (d, Q), (d, Q), (e, Q), (c, Q), (d, Q), (e, Q), (c, H),
    (d, Q), (e, Q), (d, Q), (c, Q), (c, Q), (d, Q), (d, H),
    (e, Q), (e, Q), (f, Q), (g, Q), (g, Q), (f, Q), (e, Q), (d, Q),
    (c, Q), (c, Q), (d, Q), (e, Q), (d, DQ), (c, E), (c, H),
]
C3, G2 = 48, 43
BASS = (
    [(C3, W), (G2, W), (C3, W), (G2, W)]
    + [(C3, W), (G2, W), (C3, W), (G2, H), (C3, H)]
    + [(G2, H), (C3, H), (G2, H), (C3, H), (G2, H), (C3, H), (C3, H), (G2, H)]
    + [(C3, W), (G2, W), (C3, W), (G2, H), (C3, H)]
)
assert sum(t for _, t in MELODY) == 16 * W and sum(t for _, t in BASS) == 16 * W


def vlq(v: int) -> bytes:
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.insert(0, (v & 0x7F) | 0x80)
        v >>= 7
    return bytes(out)


def meta(kind: int, data: bytes) -> bytes:
    return bytes([0xFF, kind]) + vlq(len(data)) + data


def track(events: list[tuple[int, int, bytes]]) -> bytes:
    """events: (tick, order, bytes); sorted by tick, then order (note-offs before note-ons)."""
    body, last = b"", 0
    for tick, _, ev in sorted(events, key=lambda x: (x[0], x[1])):
        body += vlq(tick - last) + ev
        last = tick
    body += vlq(0) + meta(0x2F, b"")
    return b"MTrk" + len(body).to_bytes(4, "big") + body


def notes_track(name: str, ch: int, notes: list[tuple[int, int]], vel: int) -> bytes:
    ev = [(0, 0, meta(0x03, name.encode())), (0, 1, bytes([0xC0 | ch, 0]))]
    t = 0
    for pitch, dur in notes:
        ev.append((t, 3, bytes([0x90 | ch, pitch, vel])))
        ev.append((t + dur, 2, bytes([0x80 | ch, pitch, 0])))
        t += dur
    return track(ev)


def build() -> bytes:
    conductor = track([
        (0, 0, meta(0x03, b"Ode to Joy (L. v. Beethoven)")),
        (0, 1, meta(0x58, bytes([4, 2, 24, 8]))),
        (0, 2, meta(0x51, TEMPO_US.to_bytes(3, "big"))),
    ])
    header = b"MThd" + (6).to_bytes(4, "big") + (1).to_bytes(2, "big") + (3).to_bytes(2, "big") + TPQ.to_bytes(2, "big")
    return header + conductor + notes_track("Right hand", 0, MELODY, 90) + notes_track("Left hand", 1, BASS, 64)


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "fixtures/samples/ode-to-joy.mid"
    out.write_bytes(build())
    print(f"{out}: {out.stat().st_size} bytes, {len(MELODY)} + {len(BASS)} notes, {16 * 4 * 60 / 100:.1f} s")
