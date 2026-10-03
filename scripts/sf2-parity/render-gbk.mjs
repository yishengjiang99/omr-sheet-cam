#!/usr/bin/env node
// Renders the SF2Player parity references with gbk's own TypeScript synth
// (yishengjiang99/gbk: sf2-parser.ts, src/midi-timer.worker.ts parseMidiBuffer,
// src/sf2-renderer.ts renderOfflineSequenceToAudioBuffer).
//
//   cd scripts/sf2-parity && npm ci
//   node render-gbk.mjs [--gbk /workspace/gbk] [--sf2 path/GeneralUser-GS.sf2] [--out ../../fixtures/sf2]
//
// The render plan mirrors gbk's WAV export (src/midireader.tsx onExportWav) with UI state at
// defaults: per-track preset = first program event (resolvePresetIndex: exact bank, then bank 0,
// then any bank; fallback preset 0), setPreset events for every program event, track CC
// 100/64/127, orchestra pan heuristic, gain 1, maxVoices max(96, 24*tracks), length
// ceil((durationSec + 3) * sr). Master dynamics are NOT applied (post-mix effect, not the synth).
// Metrics written to <out>/<name>.gbk.json are recomputed by the Swift tests with the same code
// (Packages/SF2Player/Tests/SF2PlayerTests/ParityMetrics.swift); keep both in sync.
import { register } from "tsx/esm/api";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

register();

const here = path.dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => (a.startsWith("--") ? [...acc, [a.slice(2), all[i + 1]]] : acc), [])
);
const GBK = path.resolve(args.gbk ?? process.env.GBK_DIR ?? "/workspace/gbk");
const SF2 = path.resolve(args.sf2 ?? path.join(GBK, "public/static/GeneralUser-GS.sf2"));
const OUT = path.resolve(args.out ?? path.join(here, "../../fixtures/sf2"));
const SAMPLE_RATE = 44100;
const TAIL_SEC = 3;
const WINDOW = 2048;   // per-window RMS
const HOP = 256;       // envelope hop for onset/release timing
const EXCERPT = 256;   // PCM excerpt frames per note
const EXCERPT_NOTES = 3;

const { parseSF2 } = await import(path.join(GBK, "sf2-parser.ts"));
const { parseMidiBuffer } = await import(path.join(GBK, "src/midi-timer.worker.ts"));
const { renderOfflineSequenceToAudioBuffer } = await import(path.join(GBK, "src/sf2-renderer.ts"));

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");
const gbkCommit = execSync("git rev-parse HEAD", { cwd: GBK }).toString().trim();

// ---- deterministic C-major scale SMF (format 1, 480 tpq, 120 bpm, C4..C5 quarters, vel 80) ----
function varLen(v) {
  const out = [v & 0x7f];
  while ((v >>= 7)) out.unshift((v & 0x7f) | 0x80);
  return out;
}
function chunk(id, bytes) {
  const n = bytes.length;
  return [...Buffer.from(id, "ascii"), (n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255, ...bytes];
}
function cScaleMidi() {
  const t0 = [
    0, 0xff, 0x03, 5, ...Buffer.from("Tempo"),
    0, 0xff, 0x51, 3, 0x07, 0xa1, 0x20,
    0, 0xff, 0x58, 4, 4, 2, 24, 8,
    0, 0xff, 0x2f, 0,
  ];
  const t1 = [0, 0xff, 0x03, 5, ...Buffer.from("Piano"), 0, 0xc0, 0];
  const notes = [60, 62, 64, 65, 67, 69, 71, 72];
  for (const n of notes) t1.push(0, 0x90, n, 80, ...varLen(480), 0x80, n, 0);
  t1.push(0, 0xff, 0x2f, 0);
  return Buffer.from([...chunk("MThd", [0, 1, 0, 2, 0x01, 0xe0]), ...chunk("MTrk", t0), ...chunk("MTrk", t1)]);
}

// ---- gbk midireader.tsx ORCHESTRA_PAN_RULES / resolveOrchestraPan ----
const ORCHESTRA_PAN_RULES = [
  [/\bviolin\s*(?:ii|2)\b/i, -0.35], [/\bviolin\b/i, -0.75], [/\bviola\b/i, 0.3], [/\bcello\b/i, 0.65],
  [/\b(double\s*bass|contrabass|upright\s*bass)\b/i, 0.8], [/\b(piccolo|flute)\b/i, -0.15], [/\boboe\b/i, -0.05],
  [/\bclarinet\b/i, 0.05], [/\bbassoon\b/i, 0.15], [/\b(french\s*horn|horn)\b/i, -0.5], [/\btrumpet\b/i, 0.25],
  [/\b(trombone|tuba)\b/i, 0.5], [/\btimpani\b/i, -0.1],
];
function resolveOrchestraPan(...labels) {
  const merged = labels.filter(Boolean).join(" | ").toLowerCase();
  if (!merged) return null;
  for (const [re, pan] of ORCHESTRA_PAN_RULES) if (re.test(merged)) return pan;
  return null;
}

function buildPlan(sf2, song) {
  const presets = sf2.pdta.phdr.slice(0, -1);
  const resolvePresetIndex = (program, bank) => {
    const exact = presets.findIndex((p) => p.preset === program && p.bank === bank);
    const bank0 = presets.findIndex((p) => p.preset === program && p.bank === 0);
    const any = presets.findIndex((p) => p.preset === program);
    if (exact >= 0) return exact;
    if (bank0 >= 0) return bank0;
    if (any >= 0) return any;
    return null;
  };
  const fallback = 0;
  const cache = new Map();
  const regionsFor = (i) => {
    if (!cache.has(i)) cache.set(i, sf2.buildRegionsForPreset(i, { decodeToFloat32: true, normalize: true, includeStereoLinks: true }));
    return cache.get(i);
  };
  const tracks = [];
  const events = [];
  for (const track of song.tracks) {
    const programEvent = track.playEvents.find((e) => e.type === "program");
    const defaultPreset = programEvent ? resolvePresetIndex(programEvent.program ?? 0, programEvent.bank ?? 0) : null;
    const presetIndex = defaultPreset ?? fallback;
    const presetName = presets[presetIndex] ? presets[presetIndex].presetName || "(unnamed)" : undefined;
    const pan = resolveOrchestraPan(track.instrumentName, track.name, presetName);
    tracks.push({ trackIndex: track.index, regions: regionsFor(presetIndex), cc7Volume: 100, cc10Pan: 64, cc11Expression: 127, pan: pan ?? 0, gain: 1 });
    for (const ev of track.playEvents) {
      const frame = Math.max(0, Math.round(ev.sec * SAMPLE_RATE));
      if (ev.type === "noteOn") {
        events.push({ frame, seq: ev.seq ?? 0, type: "noteOn", trackIndex: track.index, channel: ev.channel, note: ev.note, velocity: ev.velocity });
      } else if (ev.type === "noteOff") {
        events.push({ frame, seq: ev.seq ?? 0, type: "noteOff", trackIndex: track.index, channel: ev.channel, note: ev.note });
      } else if (ev.type === "program") {
        const p = resolvePresetIndex(ev.program ?? 0, ev.bank ?? 0) ?? fallback;
        events.push({ frame, seq: ev.seq ?? 0, type: "setPreset", trackIndex: track.index, regions: regionsFor(p), presetIndex: p });
      }
    }
  }
  return { tracks, events, maxVoices: Math.max(96, song.tracks.length * 24), length: Math.ceil((song.durationSec + TAIL_SEC) * SAMPLE_RATE) };
}

class TestAudioBuffer {
  constructor(numberOfChannels, length, sampleRate) {
    Object.assign(this, { numberOfChannels, length, sampleRate });
    this.channels = Array.from({ length: numberOfChannels }, () => new Float32Array(length));
  }
  getChannelData(c) { return this.channels[c]; }
}

// ---- metrics (mirrored in ParityMetrics.swift) ----
const sig = (x) => Number(x.toPrecision(7));
function rms(a, s, e) {
  s = Math.max(0, s); e = Math.min(a.length, e);
  let acc = 0;
  for (let i = s; i < e; i++) acc += a[i] * a[i];
  return e > s ? Math.sqrt(acc / (e - s)) : 0;
}
function metrics(L, R, plan) {
  const n = L.length;
  const mono = new Float32Array(n);
  for (let i = 0; i < n; i++) mono[i] = (L[i] + R[i]) * 0.5;
  const windows = Math.ceil(n / WINDOW);
  const rmsL = [], rmsR = [];
  for (let w = 0; w < windows; w++) { rmsL.push(sig(rms(L, w * WINDOW, (w + 1) * WINDOW))); rmsR.push(sig(rms(R, w * WINDOW, (w + 1) * WINDOW))); }
  let peakL = 0, peakR = 0, first = -1, last = -1;
  for (let i = 0; i < n; i++) {
    const a = Math.abs(L[i]), b = Math.abs(R[i]);
    if (a > peakL) peakL = a;
    if (b > peakR) peakR = b;
    if (a > 1e-4 || b > 1e-4) { if (first < 0) first = i; last = i; }
  }
  const hops = Math.ceil(n / HOP);
  const env = new Float64Array(hops);
  for (let h = 0; h < hops; h++) env[h] = rms(mono, h * HOP, (h + 1) * HOP);
  // pair note-ons with their note-offs (same track/channel/note, FIFO like a stack pop per gbk notes)
  const sorted = plan.events.map((e, i) => ({ ...e, _i: i })).sort((a, b) => (a.frame - b.frame) || (a.seq - b.seq) || (a.trackIndex - b.trackIndex) || (a._i - b._i));
  const open = new Map();
  const notes = [];
  for (const e of sorted) {
    const key = `${e.trackIndex}:${e.channel}:${e.note}`;
    if (e.type === "noteOn") { const s = open.get(key) ?? []; const rec = { note: e.note, on: e.frame, off: -1 }; s.push(rec); open.set(key, s); notes.push(rec); }
    else if (e.type === "noteOff") { const s = open.get(key); const rec = s?.pop(); if (rec) rec.off = e.frame; }
  }
  const noteMetrics = notes.map((nr) => {
    const onHop = Math.floor(nr.on / HOP);
    let peak = 0;
    for (let h = onHop; h < Math.min(hops, onHop + 8); h++) peak = Math.max(peak, env[h]);
    let onset = -1;
    for (let h = onHop; h < Math.min(hops, onHop + 8); h++) if (env[h] >= 0.5 * peak && peak > 0) { onset = h - onHop; break; }
    let release = -1;
    if (nr.off >= 0) {
      const offHop = Math.floor(nr.off / HOP);
      const ref = env[Math.min(hops - 1, offHop)];
      const maxH = Math.min(hops, offHop + Math.ceil((2 * SAMPLE_RATE) / HOP));
      for (let h = offHop; h < maxH; h++) if (env[h] <= 0.1 * ref) { release = h - offHop; break; }
    }
    return { note: nr.note, on: nr.on, off: nr.off, rmsOn: sig(rms(mono, nr.on, nr.on + 1024)), rmsOff: nr.off >= 0 ? sig(rms(mono, nr.off, nr.off + 1024)) : 0, onsetHops: onset, releaseHops: release };
  });
  const excerpts = notes.slice(0, EXCERPT_NOTES).map((nr) => ({
    start: nr.on,
    left: Array.from(L.subarray(nr.on, nr.on + EXCERPT), sig),
    right: Array.from(R.subarray(nr.on, nr.on + EXCERPT), sig),
  }));
  return {
    peakL: sig(peakL), peakR: sig(peakR), rmsTotalL: sig(rms(L, 0, n)), rmsTotalR: sig(rms(R, 0, n)),
    firstAudibleFrame: first, lastAudibleFrame: last,
    window: WINDOW, rmsL, rmsR, hop: HOP, notes: noteMetrics, excerpts,
    pcmSha256: sha256(Buffer.concat([Buffer.from(L.buffer), Buffer.from(R.buffer)])),
  };
}

mkdirSync(OUT, { recursive: true });
const cScalePath = path.join(OUT, "c_scale.mid");
writeFileSync(cScalePath, cScaleMidi());
// Public-domain multi-track sample (scripts/samples/make-ode-to-joy-midi.py), the app's "Play a sample".
const SAMPLES = path.resolve(here, "../../fixtures/samples");

const sf2Bytes = readFileSync(SF2);
const sf2 = parseSF2(new Uint8Array(sf2Bytes));
for (const [name, src] of [["c_scale.mid", path.join(OUT, "c_scale.mid")], ["ode-to-joy.mid", path.join(SAMPLES, "ode-to-joy.mid")]]) {
  const midi = readFileSync(src);
  const song = parseMidiBuffer(midi.buffer.slice(midi.byteOffset, midi.byteOffset + midi.byteLength));
  const plan = buildPlan(sf2, song);
  const buf = new TestAudioBuffer(2, plan.length, SAMPLE_RATE);
  const t0 = Date.now();
  renderOfflineSequenceToAudioBuffer({ audioBuffer: buf, tracks: plan.tracks, events: plan.events, maxVoices: plan.maxVoices });
  const ms = Date.now() - t0;
  const m = metrics(buf.getChannelData(0), buf.getChannelData(1), plan);
  const out = {
    generator: "scripts/sf2-parity/render-gbk.mjs",
    gbkCommit, sf2Sha256: sha256(sf2Bytes), midi: name, midiSha256: sha256(midi),
    sampleRate: SAMPLE_RATE, lengthFrames: plan.length, durationSec: song.durationSec, tailSec: TAIL_SEC,
    maxVoices: plan.maxVoices, trackCount: song.tracks.length, eventCount: plan.events.length,
    presets: plan.events.filter((e) => e.type === "setPreset").map((e) => ({ frame: e.frame, trackIndex: e.trackIndex, presetIndex: e.presetIndex })),
    ...m,
  };
  const file = path.join(OUT, name.replace(/\.midi?$/, "") + ".gbk.json");
  writeFileSync(file, JSON.stringify(out) + "\n");
  console.log(`${name}: ${plan.length} frames, ${plan.events.length} events, render ${ms} ms, peak ${out.peakL}/${out.peakR}, sha ${out.pcmSha256.slice(0, 12)} -> ${path.relative(process.cwd(), file)}`);
}
