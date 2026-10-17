---
keyword: sheet music
image_alt: Music Reader share card for the post on recognizing sheet music with on-device AI
title: How Music Reader recognizes sheet music with on-device AI
description: How Music Reader turns a photo of printed sheet music into MIDI on the iPhone: segmentation, staff geometry, a transformer decoder, and no server.
date: 2026-10-12
publish: true
product: music-reader
tags: [optical music recognition, on-device AI, transformer]
properNouns: [SegNet, MIDI]
---

AI Camera - Music Reader turns a photo of printed sheet music into a MIDI file, then plays it back on the phone. Every step runs on the device. No photo is uploaded, and there is no server doing the reading. The recognition engine is a Swift port of the open source [homr](https://github.com/liebharc/homr) project, and this post walks through what it actually does to a page, stage by stage.

## Stage 1: SegNet finds the ink that matters

A phone photo is a hard input: shadows, a curved page, a desk in the background. The first model, SegNet (fp16, about 28.7 MB), is a segmentation network. Instead of boxes, it labels pixels: this pixel belongs to a staff line, this one to a note head, this one to another kind of symbol. That pixel map is what the rest of the pipeline trusts, because it separates the printed music from everything else in the photo.

Classic image code takes it from there. It measures the staff lines from the segmentation, works out how the page is rotated and warped, and straightens (dewarps) it. Then it cuts the page into individual staffs. Each staff becomes a fixed-size grayscale tile of 256 by 1280 pixels, normalized with the same mean (0.7931) and standard deviation (0.1738) the models were trained with. Fixed input size and fixed normalization matter: the networks only ever see staffs presented one way.

## Stage 2: the encoder reads the whole staff at once

Each staff tile goes through a transformer encoder (fp16, about 26.5 MB). The encoder reads the staff as a whole and produces a context: a dense summary of what is printed where, which later steps can look back at. It runs through ONNX Runtime with the Core ML provider, so the Neural Engine and GPU do the work when they can, with a CPU fallback.

One detail here is deliberate. The encoder works in fp16, but its context is converted to fp32 before the next stage sees it. The decoder was published in fp32, and keeping its inputs in fp32 is what keeps its output identical to the reference implementation.

## Stage 3: the decoder writes the staff back, one symbol at a time

The decoder (fp32, about 47 MB) is the stage that does the actual reading. It generates the staff as a sequence of symbols, one step at a time, each new symbol conditioned on the symbols before it and on the encoder context. This is the same pattern language models use, pointed at notation instead of words.

A symbol is not one prediction but several at once, made by separate output heads:

- **Rhythm**: what the symbol is and how long it lasts, such as `clef_G2` (a treble clef), `keySignature_0` (no sharps or flats), `timeSignature/4`, `note_4` (a quarter note), `barline`, `chord`.
- **Pitch**: the note name, such as `C4`, for symbols that have one.
- **Smaller attributes**: articulation, slur, lift and position markers, which cover markings and notes shared between staffs.

Written out in full, the expected score for a C major scale looks like this:

```
clef_G2   keySignature_0   timeSignature/4
note_4 + C4
note_4 + D4
note_4 + E4
note_4 + F4
barline
note_4 + G4
...
```

Decoding is greedy: at each step the app takes the highest-scoring token from each head (an argmax), feeds it back in, and continues until the decoder emits the end token or reaches the vocabulary's 608-step limit. The decoder keeps a key-value cache of the symbols it has already produced so it does not recompute them each step. In this port the cache tensors (32 of them) stay inside ONNX Runtime between steps using I/O binding; only the small per-step outputs cross into Swift. An earlier version copied the whole cache through Swift data on every token, which worked but wasted most of the decode time on copying.

On iPhone, two staffs are decoded in parallel, each with its own encoder and decoder sessions, because a page of piano music may have many staffs and they do not depend on each other.

## Stage 4: symbols become a MIDI file

The token stream is still notation, not yet music you can play. A mapping step walks the symbols in order, tracks the position inside the measure from the rhythm tokens, and turns each note symbol into a pitch, an onset and a duration. The output is a standard MIDI file: format 1, 480 ticks per quarter note, one track per staff, top to bottom, so a piano grand staff becomes a pair of tracks read as one system.

Alongside the MIDI, the same pass builds a layout list with exactly one entry per sounding note, in playback order. The player uses it to highlight each note on the page image at the moment it sounds, so what you hear and what you see stay in step. Playback itself is a SoundFont synthesizer running on the device through AVAudioEngine. Nothing in this stage needs a network either.

## Why on-device is the design, not a fallback

The three model files total about 100 MB and ship with the app. Once installed, recognition works in airplane mode, on a train, in a practice room with bad Wi-Fi. Photos of your music never leave the phone, and there is no per-scan cost. The price is discipline: the models are the published homr checkpoints, the decoder is not re-quantized to something smaller, and the split between Core ML (SegNet and encoder) and CPU (decoder) exists to protect exact output, not to win a benchmark.

## How we check the port tells the truth

A port can look right and still read music wrong, so the engine is tested against the reference Python implementation of homr on fixed pages called oracles. For each oracle staff, the Swift decoder must produce the same symbol stream, token for token. A C major scale staff is the smallest gate: the oracle stream the decoder must match is 12 symbols. The reference decoder emits no key signature token for C major, so the gate stream runs clef, time signature, eight notes and two barlines, one symbol shorter than the written-out score above. If a change to the fastest path (the bound decoder, a new provider setting, a cache change) alters even one token, the gate fails. That is what makes the speed work above safe to ship: the fast path and the slow path have to agree exactly.

## Get it

Music Reader is in App Store review now. The [Music Reader support page](https://grepawk.com/music-reader/support.html) has contact details and the privacy policy, and the full source of the recognition engine is public, since the app is AGPL licensed: [omr-sheet-cam on GitHub](https://github.com/yishengjiang99/omr-sheet-cam).
