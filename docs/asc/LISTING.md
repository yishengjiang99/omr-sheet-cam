# App Store listing — AI Camera - Music Reader (version 1.0, en-US)

Source of truth for the ASC listing. `docs/asc/push_listing.py` reads the fenced blocks below
and pushes them to App Store Connect (app `6816476323`, `com.ragnus.vp`). Limits are Apple's.
Never use the word "Grok" anywhere in the listing (Apple rejected it before).

The fenced Subtitle / Promotional text / Keywords / Description blocks are the **upload-ready,
shipped-now** copy and must equal `metadata/en-US/*.txt` (fastlane deliver layout). Post-ship copy
and the lines gated on unshipped features (recognition, highlighting, library, level meter,
instrument): `COPY.md`. Check: `python3 docs/asc/check_copy.py`.

Status: listing prep for build 10. Upload + verify with the manual workflow
`.github/workflows/asc-music-reader-upload.yml` (script `scripts/asc/upload_music_reader_listing.py`,
reads `metadata/` in fastlane layout incl. URLs, copyright, categories, App Review contact).
Submitting for review is a separate manual step (`asc-submit-app-store.yml`), run by the owner only.

## Name (30)
```
AI Camera - Music Reader
```

## Subtitle (30)
```
Sheet music capture & playback
```

## Promotional text (170)
```
Capture sheet music with your camera or import a photo, then play the included sample song on a built-in synthesizer. Private and offline. No account needed.
```

## Keywords (100, comma-separated)
```
scanner,scan,OMR,MIDI,piano,notes,score,notation,sight,reading,practice,tempo,synth,choir,band,learn
```

## Description (4000)
```
Photograph pages of sheet music with your camera, and play the included sample song on a built-in synthesizer, all on your device.

AI Camera - Music Reader is a private, offline camera and music player for musicians. Capture a page or import one from your photo library. Open the player to hear the sample song performed with the GeneralUser GS SoundFont, and slow it down or speed it up while you listen.

WHAT YOU CAN DO
• Capture sheet music with the camera: tap to focus, torch for dim rooms
• Import a page from your photo library
• Play the bundled sample song on a General MIDI synthesizer
• Play, pause, stop and seek
• Change tempo from half speed to double speed

PRIVATE BY DESIGN
Everything runs on your device. No account, no sign-in, and no internet connection needed. Your photos are never uploaded.

BUILT ON OPEN SOURCE
The app bundles an optical music recognition model based on homr, an open-source project, and runs it entirely on your device. A built-in self-test reads a sample staff of music with it. The recognition engine is licensed under AGPL-3.0.
Open source (AGPL-3.0).
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
Both pages are live on grepawk.com (HTTP 200, mention "Music Reader"). Marketing URL: blank.

## App Privacy
No network calls, no analytics, no IAP: "Data Not Collected". The public ASC API has no endpoint for
the privacy nutrition label, so set it in the App Store Connect web UI (App Privacy → Get Started →
"No, we do not collect data" → Publish).

## Screenshots
Real-device player captures (`screenshots/en-US/source/*.jpg`), turned into store sizes by
`screenshots/en-US/make_store_screenshots.py` (Lanczos to width/height, padded with the capture's
own edge colour, no captions). Order: 01 Die Letzte Kompanie, 02 Für Elise.

| ASC display type | Size | Files |
|---|---|---|
| `APP_IPHONE_67` (6.9" iPhone) | 1320 × 2868 | `screenshots/en-US/iphone-69-0{1,2}-*.png` |
| `APP_IPAD_PRO_3GEN_129` (13" iPad) | 2064 × 2752 | `screenshots/en-US/ipad-13-0{1,2}-*.png` |

The older illustrative frames in `screenshots/*.png` (and `screenshots/simulator/`) are not uploaded.
