# ASO copy — AI Camera - Music Reader (`com.ragnus.vp`, ASC version 1.0, en-US)

Rule: the listing only claims what a shipped build does. Anything that needs an unshipped feature
lives in **PENDING until shipped** below and stays out of the upload-ready files.

- Upload-ready (shipped now, TestFlight build 5): `metadata/en-US/*.txt` (fastlane deliver layout),
  mirrored into the fenced blocks of `LISTING.md` (read by `push_listing.py`).
- Post-ship final version: the `Post-ship …` blocks below. Swap them in field by field as each gate
  ships; move lines out of PENDING in the same commit.
- Check: `python3 docs/asc/check_copy.py` (limits, keyword hygiene, LISTING.md == metadata,
  no pending phrases in upload-ready files, caption word counts). Output pasted at the bottom.
- Never use "Grok". No competitor or brand names in keywords.

## Shipped in build 5 (what the copy may claim)
- Camera capture (tap to focus/expose, torch) + photo import (PhotosPicker); page saved on device
- SF2 player (`Sources/App/Player/PlayerView.swift`, `f38272a`): bundled sample MIDI (public-domain `ode-to-joy.mid` since build 16) via
  GeneralUser GS; play / pause / stop, seek slider, tempo 0.5×–2×; reached from Result → "Play sample"
- On-device homr model self-test of one staff (Diagnostics → Run Gate-1)
- No network code, no account

Not shipped: full-page recognition of the user's photo (Result shows "Recognition coming soon"),
note highlighting, library / playlists, more sample songs, live level meter, instrument choice.

## Upload-ready (shipped now)
Source of truth: `metadata/en-US/`. Values:
- Name: `AI Camera - Music Reader`
- Subtitle: `Sheet music capture & playback`
- Keywords: `scanner,scan,OMR,MIDI,piano,notes,score,notation,sight,reading,practice,tempo,synth,choir,band,learn`
- Promotional text: `Capture sheet music with your camera or import a photo, then play the included sample song on a built-in synthesizer. Private and offline. No account needed.`
- Description: `metadata/en-US/description.txt`

Keyword notes: name/subtitle words (ai, camera, music, reader, sheet, capture, playback) are not
repeated; single words so Apple can combine them ("sight reading", "sheet music scanner",
"piano notes"); no plurals of included singulars; no brand names ("SoundFont" is a Creative
trademark, kept out of keywords).

## PENDING until shipped
Each line names its gate. None of these are in `metadata/en-US/` or `LISTING.md`.

| Field | Pending copy | Gate |
|---|---|---|
| Subtitle | `Scan sheet music, hear it play` | full-page recognition → playback of the user's photo |
| Keywords | swap `scan,band` → `playback` (subtitle takes "scan") | ships with the subtitle swap |
| Promo | post-ship promo (reads notes on device, hear it played) | full-page recognition |
| Description | lead: "Photograph a page of sheet music and hear it played. … reads the notes right on your device … highlighting each note as it sounds." | recognition + note highlighting |
| Description | "The app reads clefs, key and time signatures, notes and rests" | recognition |
| Description | "Tap Play and follow the highlighted notes" | recognition + highlighting |
| Description | "Choose an instrument: piano and other General MIDI sounds" | instrument picker |
| Description | "Live level meter while it plays" | level meter |
| Description | LIBRARY section (library, playlists, "Sample songs included" plural) | library/playlist + more bundled samples |
| Description | "Recognition runs entirely on your device …" (PRIVATE) | recognition (shipped copy says model self-test instead) |
| Description | GOOD FOR bullets 1–2, WORKS BEST WITH | recognition |
| Captions | #2 Result, #4 Library; #3 as worded (your scan playing) | recognition; library |

## Post-ship final version (all gates shipped)

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
scanner,OMR,MIDI,piano,notes,score,notation,sight,reading,practice,tempo,synth,choir,learn,playback
```

### Post-ship promotional text
```
Photograph sheet music and hear it played. Notes are read right on your device by an open-source recognition model, so your scores stay private. No account needed.
```

### Post-ship description
```
Photograph a page of sheet music and hear it played. AI Camera - Music Reader reads the notes right on your device and plays them back on a built-in synthesizer, highlighting each note as it sounds.

Point your camera at a printed score, or import a photo, and hear how a passage goes before you play it.

HOW IT WORKS
• Capture a page with the camera, or import a photo
• The app reads clefs, key and time signatures, notes and rests
• Tap Play and follow the highlighted notes

PLAYER
• Play, pause and seek
• Change tempo from half speed to double speed
• Choose an instrument: piano and other General MIDI sounds
• Live level meter while it plays

LIBRARY
• Every scan is saved to your library
• Build playlists of the pieces you are practicing
• Sample songs included to try right away

PRIVATE BY DESIGN
Recognition runs entirely on your device with a model that ships inside the app. Your photos are never uploaded. No account, no sign-in, and no internet connection needed.

GOOD FOR
• Hearing a new piece before you practice it
• Checking pitches and rhythms while sight-reading
• Students, teachers, choir and band members

WORKS BEST WITH
Clean, printed sheet music photographed straight on in good light. Handwritten music is not supported.

BUILT ON OPEN SOURCE
Music recognition is based on homr, an open-source optical music recognition project, licensed under AGPL-3.0. Sounds use the GeneralUser GS SoundFont.
Open source (AGPL-3.0).
```

## Screenshot caption plan (build 6 consumer UI, 6.9" 1320×2868)
Format: `# | caption | screen | status`. Upload via workflow only; never submit.

### Screenshot captions
```
1 | Snap your sheet music | Scan (camera) | shipped
2 | See every note, then play | Result (notes highlighted + Play) | PENDING: recognition + highlighting
3 | Hear it played back | Player (scan playing) | PENDING: recognition; shipped-now alt "Play, pause, change tempo" with sample song
4 | Your scans, one library | Library | PENDING: library/playlist
5 | Private, on your device | Privacy (on-device, no account) | shipped
```

Until the gates ship, upload only #1, #3 (alt caption, sample song) and #5.

## Character counts (`python3 docs/asc/check_copy.py`)
```
upload-ready (metadata/en-US)
  field              chars  limit  ok
  Name                  24     30  yes
  Subtitle              30     30  yes
  Keywords             100    100  yes
  Promotional text     157    170  yes
  Description         1099   4000  yes

post-ship (COPY.md)
  field              chars  limit  ok
  Name                  24     30  yes
  Subtitle              30     30  yes
  Keywords              99    100  yes
  Promotional text     163    170  yes
  Description         1450   4000  yes

screenshot captions (<= 5 words)
  4 words  1 | Snap your sheet music | Scan (camera) | shipped
  5 words  2 | See every note, then play | Result (notes highlighted + Play) | PENDING: recognition + highlighting
  4 words  3 | Hear it played back | Player (scan playing) | PENDING: recognition; shipped-now alt "Play, pause, change tempo" with sample song
  4 words  4 | Your scans, one library | Library | PENDING: library/playlist
  4 words  5 | Private, on your device | Privacy (on-device, no account) | shipped

OK
```
