# ASO copy — AI Camera - Music Reader (`com.ragnus.vp`, ASC version 1.0, en-US)

Rule: the listing only claims what tip-of-main ships. Anything that needs a binary newer than
the build currently in App Review is called out under **Binary gates** (do not cancel that review).

- Upload-ready: `metadata/en-US/*.txt` (fastlane deliver layout), mirrored in `LISTING.md`
  (read by `push_listing.py`).
- Check: `python3 docs/asc/check_copy.py`
- Never use "Grok". No competitor or brand names in keywords.
- Privacy nutrition label: `docs/asc/app-privacy.md` (ASC console is manual).

## Shipped on tip-of-main (2026-10-06) — what upload-ready may claim

- Camera capture (focus/expose, torch) + PhotosPicker import; pages saved on device
- Full-page on-device recognition (`PageRecognitionService` / homr); encoder+SegNet CoreML EP (GPU/ANE), decoder ORT CPU; live progress / warmup UI
- Library home (how-it-works art, Camera/Photos CTAs, Your scans + Samples, search, rename/delete)
- SF2 player (GeneralUser GS): play/pause/seek, tempo 0.5×–2×, instrument picker (Original + 11 GM programs), level meter, mini-player
- Sheet mode note highlighting, Follow toggle, A–B loop, per-hand mute/solo, Share MIDI, transpose
- Bundled sample: public-domain Ode to Joy (photo + MIDI)
- Free quota: 5 scans/day (`ScanQuota`); Music Reader Pro IAP `com.ragnus.vp.pro.monthly` / `.yearly`
- First-party anonymous telemetry → `https://photo.grepawk.com/api/telemetry` (`Analytics`)
- No account / sign-in; photos never uploaded

Honest Pro scope in listing: **unlimited scans**. Instruments and recognition are not Pro-gated
in code (paywall UI matches that). Do not claim "priority processing".

## Binary gates (vs App Review build 15; submit tip with build 24)

| Claim | In build 15? | In tip-of-main? |
|---|---|---|
| Full-page recognition + progress + Play | Yes | Yes |
| Library + instruments + tempo | Yes (Camera was home) | Yes (Library home) |
| Note highlighting / A–B / hand mute | No (post–build 15) | Yes |
| Free 5/day + Pro IAP + telemetry | No | Yes |
| PrivacyInfo.xcprivacy | No | Yes (this change) |

**Do not** sync this listing to ASC while build 15 is the binary under review if the sync would
advertise IAP/telemetry/highlighting that build 15 lacks. Prefer sync when submitting a newer build.

## Upload-ready (mirrors metadata/en-US)

- Name: `AI Camera - Music Reader`
- Subtitle: `Scan sheet music, hear it play`
- Keywords: `OMR,piano,score,notation,notes,MIDI,sightreading,practice,tempo,choir,teacher,student,synth,library`
- Promotional text: `Point your camera at printed sheet music and hear it play. Free: 5 scans/day; Pro for unlimited. On-device with iPhone GPU acceleration — no account.`
- What's New: `On-device OMR with iPhone GPU acceleration. Free: 5 pages/day; Pro unlocks unlimited scans. Tempo, 11 instruments, library, and practice tools.`
- Description: `metadata/en-US/description.txt`

Keyword notes: name/subtitle words (ai, camera, music, reader, scan, sheet, hear, it, play) are not
repeated; single tokens so Apple can combine them; no brand names (SoundFont kept out).

## PENDING (keep out of upload-ready)

| Item | Why |
|---|---|
| "reads clefs, key and time signatures" as a marketing guarantee | Pipeline is best-effort; avoid overclaim |
| "coming soon" | Must never appear in listing |
| "collects no data" / "Data Not Collected" | False once telemetry/IAP ship |
| "priority processing" / Pro-only instruments | Not enforced in binary |
| Header / Search Results creatives | Deferred (playbook gap); peach `make_store_screenshots.py` remains SoT |

## Post-ship blocks (same as upload-ready while tip matches)

### Post-ship name
```
AI Camera - Music Reader
```

### Post-ship subtitle
```
Scan sheet music, hear it play
```

### Post-ship keywords
```
OMR,piano,score,notation,notes,MIDI,sightreading,practice,tempo,choir,teacher,student,synth,library
```

### Post-ship promotional text
```
Point your camera at printed sheet music and hear it play. Free: 5 scans/day; Pro for unlimited. On-device with iPhone GPU acceleration — no account.
```

### Post-ship description
```
Point your camera at printed sheet music and hear it played. AI Camera - Music Reader reads the notes on your iPhone or iPad, then plays the page back so you can listen, learn, and practice.

HOW IT WORKS
1. Take a photo of a page, or pick one from your photo library.
2. Watch the live progress bar while the app reads the music on your device.
3. Tap Play to hear it — follow highlighted notes on the scan, change tempo, or pick an instrument.

FREE AND PRO
• Free: 5 page scans per day
• Music Reader Pro (auto-renewable): unlimited scans via monthly or yearly subscription (prices shown in the app)
• Payment charged to your Apple ID; renews unless canceled at least 24 hours before period end
• Manage or cancel in Settings → Apple ID → Subscriptions
• Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
• Privacy Policy: https://grepawk.com/music-reader/privacy.html

A PLAYER MADE FOR PRACTICE
• Tempo from 0.5x to 2x: slow a tricky passage down or speed it up
• Choose the sound: piano, electric piano, harpsichord, music box, vibraphone, organ, guitar, violin, strings, choir, or flute
• Play, pause, seek, A–B loop, and mute or solo hands
• Live level meter; playback keeps going while you browse
• Share MIDI from your library

YOUR LIBRARY
Every page the app reads is saved to your Library on your device, ready to play again anytime.

TRY IT INSTANTLY
No sheet music nearby? Tap "Try sample picture" to read a bundled page of Beethoven's "Ode to Joy" and hear the result.

ON-DEVICE READING
Recognition runs on your device with iPhone GPU acceleration for optical music recognition (Core ML on the GPU and Neural Engine for the heavy vision steps). Models are built into the app — your photos and scores are never uploaded. No account or sign-in is required.

USAGE DATA
The app sends anonymous usage events (such as app open, scan success or fail, and purchase funnel steps) to our servers to improve the product. Events include an anonymous device id — never your photos, MIDI, email, or location. Purchases are processed by Apple.

WHO IT'S FOR
Piano students who want to hear how a new piece should sound, teachers preparing lessons, choir singers learning a part before rehearsal, and hobbyists who read a little and want to hear the rest.

GOOD TO KNOW
Works best with clean, printed sheet music, one page at a time. Keep the whole page in frame, flat and well lit. Handwritten music, very dense scores, and worn or crumpled pages may not read correctly; results can contain mistakes.

OPEN SOURCE
The recognition engine is based on the open-source homr project. The app is AGPL-3.0. Sounds use the GeneralUser GS SoundFont.
```

## Screenshot caption plan (peach store frames)

Format: `# | caption | screen | status`. Upload via workflow only; never submit from CI.
Source of truth: `docs/asc/screenshots/en-US/make_store_screenshots.py` (not playbook configs).

### Screenshot captions
```
1 | Snap and hear it | Hero mockup | shipped (on-image: "Snap sheet music. Hear it play.")
2 | Slow it to practice | Player tempo | shipped
3 | GPU on your iPhone | Reading progress | shipped (on-image: "GPU-accelerated on your iPhone")
4 | Piano strings and choir | Instrument chips | shipped
5 | Private on your device | Privacy framing | shipped (photos on-device; telemetry in privacy policy)
```

## Character counts (`python3 docs/asc/check_copy.py`)
```
upload-ready (metadata/en-US)
  field              chars  limit  ok
  Name                  24     30  yes
  Subtitle              30     30  yes
  Keywords              99    100  yes
  Promotional text     149    170  yes
  Description         2679   4000  yes

post-ship (COPY.md)
  field              chars  limit  ok
  Name                  24     30  yes
  Subtitle              30     30  yes
  Keywords              99    100  yes
  Promotional text     149    170  yes
  Description         2679   4000  yes

screenshot captions (<= 5 words)
  4 words  1 | Snap and hear it | Hero mockup | shipped (on-image: "Snap sheet music. Hear it play.")
  4 words  2 | Slow it to practice | Player tempo | shipped
  4 words  3 | GPU on your iPhone | Reading progress | shipped (on-image: "GPU-accelerated on your iPhone")
  4 words  4 | Piano strings and choir | Instrument chips | shipped
  4 words  5 | Private on your device | Privacy framing | shipped (photos on-device; telemetry in privacy policy)

OK
```
