# App Store listing — AI Camera - Music Reader (version 1.0, en-US)

Source of truth for the ASC listing. `docs/asc/push_listing.py` reads the fenced blocks below
and pushes them to App Store Connect (app `6816476323`, `com.ragnus.vp`). Limits are Apple's.
Never use the word "Grok" anywhere in the listing (Apple rejected it before).

The fenced Subtitle / Promotional text / Keywords / Description blocks are the **upload-ready,
shipped-now** copy and must equal `metadata/en-US/*.txt` (fastlane deliver layout). Post-ship copy
and the lines gated on unshipped features (recognition, highlighting, library, level meter,
instrument): `COPY.md`. Check: `python3 docs/asc/check_copy.py`.

Status: listing prep for build 15 (pulled from review 2026-09-27 with `asc-cancel-review.yml`). Upload + verify with the manual workflow
`.github/workflows/asc-music-reader-upload.yml` (script `scripts/asc/upload_music_reader_listing.py`,
reads `metadata/` in fastlane layout incl. URLs, copyright, categories, App Review contact).
Submitting for review is a separate manual step (`asc-submit-app-store.yml`), run by the owner only;
it re-syncs this listing from the repo files first (input `sync_listing`, default true).

## Name (30)
```
AI Camera - Music Reader
```

## Subtitle (30)
```
Scan sheet music, hear it play
```

## Promotional text (170)
```
Point your camera at printed sheet music and hear it played back. Slow it down to practice, or pick an instrument. Runs on your device: no internet, no account.
```

## Keywords (100, comma-separated)
```
OMR,piano,score,notation,notes,MIDI,sightreading,practice,tempo,choir,teacher,student,scanner,synth
```

## Description (4000)
```
Point your camera at printed sheet music and hear it played. AI Camera - Music Reader reads the notes right on your iPhone or iPad, then plays the page back so you can listen, learn and practice.

HOW IT WORKS
1. Take a photo of a page, or pick one from your photo library.
2. Watch the live progress bar while the app reads the music.
3. Tap Play to hear it.

PRIVATE BY DESIGN
Reading happens entirely on your device, using machine-learning models built into the app. No internet connection is needed, there is no account or sign-in, and the app collects no data. Your photos are never uploaded.

A PLAYER MADE FOR PRACTICE
• Tempo from 0.5x to 2x: slow a tricky passage down or speed it up
• Choose the sound: piano, electric piano, harpsichord, music box, vibraphone, organ, guitar, violin, strings, choir or flute
• Play, pause, seek and skip between pieces
• Playback keeps going while you browse

YOUR LIBRARY
Every page the app reads is saved to your Library on your device, ready to play again anytime, one piece after another.

TRY IT INSTANTLY
No sheet music nearby? Tap "Try sample picture" to read a bundled page of Beethoven's "Ode to Joy" and hear the result.

WHO IT'S FOR
Piano students who want to hear how a new piece should sound, teachers preparing lessons, choir singers getting to know a piece before rehearsal, and hobbyists who read a little and want to hear the rest.

GOOD TO KNOW
It works best with clean, printed sheet music, one page at a time. Keep the whole page in frame, flat and well lit. Handwritten music, very dense scores and worn or crumpled pages may not read correctly, and results can contain mistakes.

OPEN SOURCE
The recognition engine is based on the open-source homr project, and the app is open source under the AGPL-3.0 license.
```

## Support URL
```
https://grepawk.com/music-reader/support.html
```

## Marketing URL
```
```

## Privacy Policy URL
```
https://grepawk.com/music-reader/privacy.html
```

## Terms of Use URL
```
https://grepawk.com/music-reader/terms.html
```

Not an App Store Connect field. The privacy and support pages link to it.
The page says Apple's standard Licensed Application EULA also applies, so the
listing does not upload a custom license agreement.

## Copyright
```
2026 Yisheng Jiang
```

## Categories
- Primary: `MUSIC`
- Secondary: `EDUCATION`

## TestFlight: What to Test
```
Early build. The app opens a diagnostics screen: it loads the bundled recognition models in the background and shows warm-up timings and memory, plus a MIDI playback check. Please report crashes or slow warm-up. Camera capture and the score player are not in this build yet.
```

## URLs: publishing status
Privacy, support, and terms pages are live on grepawk.com (HTTP 200). Marketing URL: blank. Terms of Use is not sent as a custom EULA.

## App Privacy
No network calls, no analytics, no IAP: "Data Not Collected". The public ASC API has no endpoint for
the privacy nutrition label, so set it in the App Store Connect web UI (App Privacy → Get Started →
"No, we do not collect data" → Publish).

## Screenshots
Peach marketing frames built by `screenshots/en-US/make_store_screenshots.py` from `screenshots/en-US/source/`
(hero mockup, real-device player captures, and crops of the scanning screen that exclude the photo preview).
Every frame has a large caption. Uploaded in filename order:
01 "Snap sheet music. Hear it play." (hero mockup) · 02 "Slow it down to practice" (Für Elise player) ·
03 "Reads music right on your iPhone" (progress card + privacy badges; iPad: "on your device") ·
04 "Piano, strings, choir and more" (player controls + the app's instrument list).

| ASC display type | Size | Files |
|---|---|---|
| `APP_IPHONE_67` (6.9" iPhone) | 1320 × 2868 | `screenshots/en-US/iphone-69-0{1..4}-*.png` |
| `APP_IPAD_PRO_3GEN_129` (13" iPad) | 2064 × 2752 | `screenshots/en-US/ipad-13-0{1..4}-*.png` |

The older illustrative frames in `screenshots/*.png` (and `screenshots/simulator/`) are not uploaded.
