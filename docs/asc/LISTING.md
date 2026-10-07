# App Store listing — AI Camera - Music Reader (version 1.0, en-US)

Source of truth for the ASC listing. `docs/asc/push_listing.py` reads the fenced blocks below
and pushes them to App Store Connect (app `6816476323`, `com.ragnus.vp`). Limits are Apple's.
Never use the word "Grok" anywhere in the listing (Apple rejected it before).

The fenced Subtitle / Promotional text / Keywords / Description blocks are the **upload-ready**
copy and must equal `metadata/en-US/*.txt` (fastlane deliver layout). History and gates:
`COPY.md`. Check: `python3 docs/asc/check_copy.py`.

**Sync gate:** tip-of-main listing discloses free quota + Pro IAP + anonymous telemetry.
App Review **build 15** (do not cancel) does **not** include IAP/telemetry. Do **not** run
`asc-music-reader-upload` / submit listing sync until the binary under review (or next submit)
matches these claims. User runs submit; agents never dispatch `asc-submit`.

Status: listing optimized 2026-10-06 for tip-of-main. Upload + verify with
`.github/workflows/asc-music-reader-upload.yml` when ready.

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
Point your camera at printed sheet music and hear it play. Free: 5 scans/day; Pro for unlimited. On-device reading — no account.
```

## Keywords (100, comma-separated)
```
OMR,piano,score,notation,notes,MIDI,sightreading,practice,tempo,choir,teacher,student,synth,library
```

## Description (4000)
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
Recognition runs on your device with models built into the app. Your photos and scores are never uploaded. No account or sign-in is required.

USAGE DATA
The app sends anonymous usage events (such as app open, scan success or fail, and purchase funnel steps) to our servers to improve the product. Events include an anonymous device id — never your photos, MIDI, email, or location. Purchases are processed by Apple.

WHO IT'S FOR
Piano students who want to hear how a new piece should sound, teachers preparing lessons, choir singers learning a part before rehearsal, and hobbyists who read a little and want to hear the rest.

GOOD TO KNOW
Works best with clean, printed sheet music, one page at a time. Keep the whole page in frame, flat and well lit. Handwritten music, very dense scores, and worn or crumpled pages may not read correctly; results can contain mistakes.

OPEN SOURCE
The recognition engine is based on the open-source homr project. The app is AGPL-3.0. Sounds use the GeneralUser GS SoundFont.
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
listing does not upload a custom license agreement. Subscriptions also link Apple's
Standard EULA from the paywall and description.

## Copyright
```
2026 Yisheng Jiang
```

## Categories
- Primary: `MUSIC`
- Secondary: `EDUCATION`

## TestFlight: What to Test
```
Tip-of-main (IAP + telemetry + Library home). Please verify:

1. Library is home — how-it-works art, Camera and Photos CTAs, Try sample picture.
2. Capture or import a printed page — progress bar while reading; Play opens the SF2 player.
3. Player: tempo 0.5×–2×, instrument chips, level meter, Sheet highlight, A–B loop, hand mute/solo; playback continues from Library mini-player.
4. Free quota: after 5 scans the same day, paywall appears (Music Reader Pro monthly/yearly). Restore Purchases.
5. Optional: Settings → confirm no account; Developer section still hidden behind version taps.

Report crashes, wrong MIDI, quota/paywall bugs, and slow recognition (device + iOS version).
Photos must never leave the device; only anonymous usage events go to telemetry.
```

## URLs: publishing status
Privacy, support, and terms URLs point at grepawk.com/music-reader/. Redeploy
`docs/asc/web/privacy.html` and `support.html` if the live pages still claim "no analytics"
or "no IAP". Marketing URL: blank. Terms of Use is not sent as a custom EULA.

## App Privacy
**Do not answer "Data Not Collected".** Tip-of-main collects anonymous Product Interaction,
Device ID (anon UUID), and Purchase History (StoreKit). Full manual ASC answers:
`docs/asc/app-privacy.md`. Privacy manifest: `Sources/App/Resources/PrivacyInfo.xcprivacy`.
Agents cannot safely edit the ASC nutrition label via API — owner updates the web UI.

## Screenshots
Peach marketing frames built by **`docs/asc/screenshots/en-US/make_store_screenshots.py`**
(this repo is the source of truth; playbook `configs/` / promotional creatives are reference only —
Header/Search Results assets deferred). From `screenshots/en-US/source/`
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
