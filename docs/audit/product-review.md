# Product & design review — "AI Camera – Music Reader" (SheetCam) iOS

Repo `yishengjiang99/omr-sheet-cam` @ `736d0f6` · Review date: Sat 2026-10-17 (America/Los_Angeles) · Author: product-research pass for Yisheng
Companion doc: `/workspace/omr-audit/flows.md` (bug/flow audit, IDs like **F5.5**, **P1.4**). This review does **not** repeat those bugs; it cites them by ID only where a recommendation depends on one.

**Constraint honoured:** nothing here changes OMR, recognition, or the playback engine. Every backlog row has a **Touches core?** column: `No` (copy/layout/analytics/store), `Around` (new UI wrapped around an existing core step, no change to the step itself), or `Additive` (new capability that needs Yisheng's explicit OK; parked in §11).

## 0. How to read this / evidence rules

- Tags: **[CODE path]** = I read it in the repo. **[S#]** = external source in §12 (URL there). **[INFERENCE]** = my reasoning, not a measured fact. **[UNVERIFIED]** = could not confirm.
- I read code and docs statically. I did **not** run the app, so on-device feel (timings, haptics, VoiceOver behaviour) is [INFERENCE] unless a test or doc says otherwise.
- The app is **not live yet**: an iTunes lookup for bundle `com.ragnus.vp` returned `resultCount:0` on 2026-10-17, consistent with `TODO.md` ("v1.0 build 30 + subscriptions WAITING_FOR_REVIEW since 2026-10-09") [CODE TODO.md:14]. So there are **no real ratings, reviews, or funnel data** for this app. All "what users do" claims come from comparable apps and industry data.
- No benchmark is invented. Every number is either quoted from a cited source, read from the repo, or computed from those (marked "computed").
- Prices/limits of competitors were read on 2026-10-17 from the pages listed; they change often.

---

## 1. Executive summary

### 1.1 What the app is today (evidence snapshot)

| Area | Fact | Source |
|---|---|---|
| Promise | Photo of printed sheet music → on-device read → play; tempo 0.5–2×, A–B loop, hands mute/solo, 11 sounds, library, Share MIDI | [CODE docs/asc/metadata/en-US/description.txt], PlayerView |
| Free / Pro | Free: **5 page scans/day** (resets at local calendar day). Pro: **unlimited scans** only. Yearly **$29.99**, monthly **$4.99**, **no intro offer / trial** | [CODE ScanQuota.swift:7], [CODE OMRSheetCam.storekit:38,66,42] |
| Computed | $29.99/12 = **$2.50/mo**; vs 12×$4.99 = $59.88 → yearly saves **49.9% (~50%)** | computed |
| Onboarding | **None.** No first-run screen. Library shows a static "Photo → music → play" card, Camera/Photos buttons, and (only while Library has zero scans) a small "Try sample picture" text button | [CODE LibraryScreen.swift:55-70, 307-336] |
| Samples | Two bundled **MIDI-only** rows ("Ode to Joy (sample)", "C major scale (sample)") — no image/layout, so they cannot show the sheet-following highlight that is the app's signature moment | [CODE PlaylistStore.swift sample defs; SamplePicture in CaptureStore.swift:60-105] |
| Paywall | Only shown when the 6th scan of the day is attempted (modal). Plan cards + Free/Pro table + Restore + legal links | [CODE ScanQuota.swift:30-34, PaywallView.swift] |
| Analytics | 11 events total: `session_start, app_open, scan_start, scan_success, scan_fail, free_quota_hit, paywall_trigger, paywall_view, paywall_plan_select, purchase_start/success/fail`. **No playback, capture, library, settings, or retention events.** Random install UUID, first-party endpoint, **no opt-out** | [CODE Services/Analytics.swift + 5 call sites], flows F13.7 |
| Accessibility | 20 `accessibilityLabel`s in Sources; 6 fixed-size `.font(.system(size:))` (Camera ×2, Player, Settings, Theme, a debug view); Reduce Motion honoured in ReadingView/ResultScreen only | [CODE grep] |
| Store | Name "AI Camera - Music Reader", subtitle "Scan sheet music, hear it play" (30 chars), keywords 100-char field, hero screenshot documented as **"hero mockup"** | [CODE docs/asc/metadata, LISTING.md:146-148] |
| Brand | Home-screen name is **"SheetCam"** (`CFBundleDisplayName`) but App Store name is **"AI Camera - Music Reader"** | [CODE project.pbxproj:679,715] vs metadata |

### 1.2 The three strategic findings

1. **The free tier is so generous that most people will never see the paywall — and the paywall explains nothing when they do.** 5 scans/day ≈ 150/month [computed], versus Soundslice Free **2 pages/month** [S5], Newzik Free **10 converted pages total** [S11], PlayScore Free **one page at a time** (a new photo replaces the last) [S8]. The app's only Pro benefit is volume. Freemium apps convert slowly: RevenueCat's 2026 median download-to-paid at day 35 is **2.1%** for freemium (**2.8% North America**), and for freemium **23% of conversions arrive 6+ weeks after download** [S4]. [INFERENCE] A casual learner scanning one piece a week hits the wall ~never; the people who do hit it (teachers, choir directors, someone digitising a songbook) are exactly the high-intent segment — so the paywall must speak to *them* ("scanning a whole piece/book?") and the app needs more than one reason to pay (see §4.7 and §11).
2. **Time-to-"aha" is longer than it needs to be and the best demo is hidden.** The aha is *seeing the highlight follow the music you photographed*. Today that requires: find the small "Try sample picture" link under an empty-state, wait for a first-run warm-up (flows F6/P-series note a progress reset), land on a developer-ish result screen, then press Play. The two always-visible sample rows play sound but **cannot show the highlight** [CODE PlaylistStore]. RevenueCat: ~**half of all paid conversions happen on Day 0** (overall 50.6%; freemium roughly one-third) and "the battle for the subscriber is won or lost in the first session" [S4]. Apple also recommends presenting value at first launch [S1].
3. **Discoverability and trust are the cheapest wins and the real launch risks.** The store name has none of the words people search ("sheet", "scan", "scanner") in the *name*; the installed name differs from the store name; the hero screenshot is a mockup (2.3.3 risk); usage analytics have no consent/opt-out (5.1.1 risk). All are low-effort to fix before launch.

### 1.3 Top 5 recommendations (ranked by impact ÷ effort)

| # | Recommendation | Why (one line) | Effort | Impact | Backlog |
|---|---|---|---|---|---|
| **1** | **Scan meter + metered-paywall choreography**: a "3 of 5 scans left today" chip on Library/Camera from scan 3, a soft card after scan 5 succeeds ("That was your 5th free scan. Resets at midnight."), then the paywall at the block with the reset time and a first-class "Not now" | Apple itself recommends a metered paywall with prompts "when they near their monthly limit" [S1]; today the user is blocked with zero warning and the photo is lost to the flow (P1.4, P1.10 in flows.md) | S | High | B1–B4 |
| **2** | **Rebuild the paywall's information design** (billed amount dominant, per-month + savings subordinate, "what you get" in plain words, honest Free-vs-Pro table that shows free is not crippled, "Not now", Restore + Manage) | Apple *requires* the billed amount be the most prominent price and per-month/savings be subordinate [S1]; Duolingo's paywall learning: clarity beats persuasion [S4]; conversion is a design-quality problem more than a model problem [S4: hard-paywall spread 4.2–38.7%] | S–M | High | B5–B9 |
| **3** | **First 60 seconds**: make "See it work" the primary first-run action (sample picture, quota-free), give the sample rows a pre-baked sheet layout so the highlight appears with no scan, and add a one-time 3-card intro that ends on that action (not a permission prompt) | Day-0 is where conversion and retention are decided [S4]; competitor reviewers praise "no instructions needed" flows (Sheet Music Scanner review, 2023) [S9] | M | High | B10–B14 |
| **4** | **Capture coaching** (page-frame guide, live light/blur/tilt hint, torch suggestion, a quality verdict *before* a scan is consumed, one-tap "Retake → camera") | In the closest comparable's reviews, **photo quality is the main accuracy lever** ([INFERENCE] generalised): "(easy, but the least reliable transcription method)" [S9]; a 2018 VoiceOver reviewer asked for camera guidance on whether the page fills the frame [S9]; the app already has the words (`ScanFailure.Tip`) but shows them only **after** failure [CODE ScanFailure.swift:74-82] | M | High | B15–B20 |
| **5** | **Fix store presence**: unify name (SheetCam vs "AI Camera"), put "Sheet Music"/"Scan" into the name, rewrite subtitle/keywords, replace the hero mockup with a real capture, rewrite promo text to benefits not "GPU acceleration" | Search ranking is driven by name, subtitle, keywords, category + behaviour [S3]; I searched 5 head terms on 2026-10-17 — competitors owning them have "Sheet Music" in the name (§9.2) | S | High | B40–B47 |

### 1.4 Launch-risk callouts (not growth — App Review / trust)

| Risk | Why | Fix | Effort |
|---|---|---|---|
| Telemetry without consent or withdrawal | Guideline 5.1.1: "Apps that collect user or usage data must secure user consent for the collection, even if such data is considered to be anonymous… Apps must also provide the customer with an easily accessible and understandable way to withdraw consent." [S2]. App sends events at launch with no prompt and no toggle [CODE Analytics.swift bootstrap; flows F13.7] | Settings toggle + one-time consent card (§7.2) | S |
| Hero screenshot is an illustrative mockup | 2.3.3: "Screenshots should show the app in use" [S2]; repo calls it "hero mockup" [CODE LISTING.md:146] | Replace with a real device capture of the Sheet view mid-playback | S |
| Paywall price hierarchy | Apple: "the amount that will be billed must be the most prominent pricing element… breakdown… subordinate" [S1] | §4.3 spec | S |
| "Ongoing value" for a volume-only subscription | 3.1.2(a): "you must provide ongoing value to the customer" [S2]. "Unlimited scans" is consumption-based and defensible, but thin; add review-notes explanation and ideally a second Pro benefit | B30, §11 | S (notes) / M+ |

---

## 2. Market & competitor read

### 2.1 Pricing, free tier, paywall pattern (all read 2026-10-17)

| App | Free tier | Paid | Paywall / pattern | Source |
|---|---|---|---|---|
| **Soundslice** (web) | 2 trial scans/month, 1 page & first 32 bars each | Plus **$5/mo or $50/yr** (100 pages/mo, ≤25 pages/upload); Teacher $20/mo or $200/yr | Hard feature+volume gate; "Save 16%" annual badge; "no obligation / cancel from account settings" FAQ | [S5][S6] |
| **PlayScore 2** | Plays any PlayScore doc; creates single-page docs (new photo replaces previous) | Productivity **$5.99/mo or $34.99/yr** (multi-page, share/export docs). Site headline: "No monthly limits – scan as much music as you like". Exports MusicXML/MIDI, PDFs, 23 instruments/staff, count-in | Capability gate (multi-page), not a count gate | [S7][S8] (US prices via search-synthesised App Store listing — **[UNVERIFIED]** directly) |
| **Sheet Music Scanner** (App Sub 1 LLC) | Free download, IAP; no free-scan limit stated on listing | 10 IAP/sub price points listed $4.99–$34.99 | Subscription ladder; multi-page, cloud sync, export MIDI/MusicXML/audio/PDF; listing documents *limitations* explicitly (no handwriting, no dynamics/grace notes…) | [S9] |
| **Newzik** | 3 scores; **10 LiveScore (OMR) pages total**; 7-day Premium trial | Essentials €29.99 lifetime; Premium €9.99 (period not shown in fetched text); Premium Lifetime €199 | Lifetime tiers alongside subscription; trial | [S11] |
| **forScore** | $24.99 paid app | forScore Pro **$14.99/yr**; **"forScore Pro 30-Day Pass" $2.99**; Family Sharing tier | Short non-recurring pass for seasonal users | [S10] |
| **This app** | 5 scans/day | $29.99/yr, $4.99/mo | Hard modal at 6th scan only | [CODE] |

**Read-across ([INFERENCE]):**
- $29.99/yr sits between forScore Pro ($14.99) and PlayScore ($34.99)/Soundslice ($50). RevenueCat's overall yearly median is **$34.80** (Education **$44.99**, the most common yearly price point **$30**) [S4]. So the price is credible; the problem is *what the buyer receives*, not the number. Do not change price pre-launch.
- Every serious competitor's paid tier unlocks **capability** (multi-page, export, editing, cloud) as well as volume. This app's Pro unlocks volume only.
- forScore's $2.99 30-day pass is the one pattern aimed at seasonal use (exam piece, choir season) — a good fit for an app whose usage is episodic.

### 2.2 What users complain about / want (from real reviews of the closest comparable)

Source: Sheet Music Scanner App Store page, ~6.5K ratings, 4.5★ [S9]. Quotes verbatim; dates as shown.

| Theme | Evidence | Implication here |
|---|---|---|
| **Photo input is the least reliable path** | "input music either by taking photos of it (easy, but the least reliable transcription method), using your own scanner (better), or downloading a PDF (best)" — 08/30/2025 | Capture coaching is worth more than anything else in the funnel; also offer **Photos/Files import** as a first-class "better quality" path (app has Photos import already). |
| **Show what could not be read** | "If you notice a lot of grayed-out notes (meaning the app couldn't read them), ask your choir director if they have a clean PDF" — 08/30/2025 | Users value a visible "unsure" state. Soundslice: "For music we're not 100% sure about, we'll ask you for clarification instead of just making a (possibly incorrect) automatic decision" [S6]. |
| **Wrong-but-silent playback erodes trust** | "Timing was god-awful, notes were completely passed on… Guess that's 5 dollars down the drain" — 09/24/2022 (1★-style review) | A refund-shaped complaint. Set expectations *before* playback (see §7.3) and make "retake" cheap. |
| **Retry cost** | "I've fixed it by taking a new picture and reimporting, but that does waste a couple minutes." — 11/05/2023 (positive review) | Retake→camera in one tap (F5.5 is the bug; design in §5.5) and don't charge a scan for a failed read (P1.4). |
| **Manual correction requested** | "If there was away to manually input these factors I think that would be very useful" — Aug 7; "it has an actual editing software you can use if it gets it wrong" — 02/25/2021 | Editing is a recurring ask; Soundslice makes it core ("built-in notation editor… original image inline") [S6]. Parked as **Additive** (§11). |
| **Multi-page + export** | "add all 5 pages into one document"; MusicXML to Guitar Pro "came in perfectly" — 08/30/2023 | Multi-page "piece" and MusicXML are what paid users value. Parked (§11). |
| **Accessibility needs** | VoiceOver user, 2018: wants camera guidance "whether or not the page is filling the screen" (paraphrased; the review is garbled dictation) | The camera screen is an accessibility gap *and* the accuracy lever (§5.2, §8). |
| **Competitor accessibility disclosure is blank** | Both the Sheet Music Scanner and forScore listings say "The developer has not yet indicated which accessibility features this app supports" [S9][S10] | A free differentiator: publish Accessibility Nutrition Label answers honestly once the work in §8 is done. |
| **Privacy as a selling point** | forScore listing: "The developer does not collect any data from this app" [S10]; Sheet Music Scanner lists Usage Data as "used to track you" [S9] | This app can credibly claim *on-device, no account, no ad tracking* — but only if telemetry is consented/opt-out (§7). |

---

## 3. First-run & activation

### 3.1 Current journey (code-verified) and friction

1. Launch → Library (large title, **no welcome**). Static "Photo → music → play" card, then **Camera / Photos** buttons [CODE LibraryScreen.swift:55-70, 162].
2. "Your scans" empty: "No scans yet. Take a photo or import one — it shows up here." + small coral text button **"Try sample picture"** [CODE :73-82]. It vanishes forever after the first scan (flows P11.1).
3. Tap → ReadingView ("Read on your iPhone. No internet needed." lock label [CODE ReadingView.swift:100]) → ResultScreen ("Ready to play") → Play.
4. Camera permission is requested only when Camera opens; the "Hold steady over one page" hint is the only coaching [CODE CameraScreen.swift:35].

**Frictions:** (a) the highest-value demo is the smallest control on screen; (b) the "Samples" section rows play audio only; (c) no statement of *what good input looks like* before the first photo; (d) first-run model warm-up exists (ModelWarmup) but there is no designed "first read takes longer" message [CODE Inference/ModelWarmup.swift; flows F6.6] ([INFERENCE]: first-run latency is the largest drop-off risk because the user has no sunk cost yet).

### 3.2 Recommendations

**A1 — Sample-first first-run (B10).** On first launch (flag in `UserDefaults`), replace `HowItWorksArt` with a hero card:
- Title: **"Hear any page of sheet music"**
- Body: **"Point your camera at printed music. We read it on your iPhone and play it back — no account, nothing uploaded."**
- Primary button (full width, coral): **"See it work · 10 seconds"** → sample picture flow (must not consume a scan; P11.1/P1.x).
- Secondary: **Scan my music** (camera) · tertiary: **Choose a photo**.
After the first successful *anything*, collapse the card to today's compact `HowItWorksArt`. Keep "Try sample picture" permanently reachable (Library "⋯" menu or Settings → "Try the sample again") — that also fixes the App Reviewer path (P11.1).

**A2 — Make the sample rows show the magic (B11).** Pre-compute the layout sidecar for the bundled Ode to Joy image once (offline, at build time) so the "Ode to Joy (sample)" row opens in **Sheet** view with highlight, no OMR run, no quota. [CODE PlayerView.swift:85-93 only shows Sheet when `layout` and `sheetImage` exist.] This is content, not engine, work (**Touches core: No**) — but needs an engineer to export the layout the same way a scan does.

**A3 — One-time 3-card intro, ending on the action (B12).** Cards: (1) *Photo → Play* animation; (2) **"Get a clean read"** with the three tips that matter most (flat page, bright even light, one page at a time — reuse `ScanFailure.Tip` strings so copy is consistent) and an honest "Printed music works best; handwritten may not read"; (3) **"Private by design"** (reads on your iPhone, no account) with a *consent switch for anonymous usage stats* (§7.2). Last card CTA = "See it work". Skippable. RevenueCat: onboarding "needs to build trust… and show value quickly" [S4 contributor quote]; Apple: keep onboarding "brief, engaging" [S1].

**A4 — Designed "first read" waiting state (B13).** If the model warm-up is in progress, show **"Getting ready — the first read takes a little longer (one time only)"** instead of a bar that appears to restart (F6.6 is the bug; this is the copy/design wrapper). Add **"Keep this screen open"** only if background cancellation is real (check P-series).

**A5 — Time-to-first-success target (B14).** Define **TTFS = `app_open` (first ever) → first `play_start`**. Instrument it (§10). No benchmark exists in my sources; set the target from your own first 200 installs. [INFERENCE] The sample path should be the fastest, camera path the highest-quality.

**A6 — Permission priming (B14b).** Don't add a pre-permission screen for the camera (the system prompt text "Take photos of sheet music to read and play them" is already specific [CODE Info.plist usage string per project]). Do add the denied-state UI you already have ("Open Settings" [CODE CameraScreen.swift:86]) plus a **Choose a photo instead** button there so denial isn't a dead end.

**Capture guidance details (first-run specific)** → §5.2.

---

## 4. Free-to-Pro funnel & paywall

### 4.1 Current funnel (as built)

`Scan #1–5 (silent)` → `Scan #6 attempt` → **modal paywall** ("Music Reader Pro"; "Free: 5 page scans a day. Music Reader Pro unlocks unlimited scans.") → plan cards (Yearly "Best value", Monthly) → Subscribe / Restore / Close [CODE PaywallView.swift:12-135].
Events: `free_quota_hit → paywall_trigger(reason=quota) → paywall_view → paywall_plan_select → purchase_start → purchase_success|fail` [CODE]. There is no `paywall_dismiss`, no entry from Settings/Library (flows F13/P-series), no remaining-count surface (P1.10).

### 4.2 Trigger timing and value moments

Apple's own guidance for a metered model: "include contextually relevant prompts to encourage people to subscribe — for example, when they near their monthly limit… consider making it easy to subscribe at any time by including a prompt throughout the app interface. Test and measure" [S1].

| Moment | Surface | Copy (draft) | Blocking? | Event |
|---|---|---|---|---|
| Scan 3 of 5 completes | Library + Camera chip (neutral grey) | **"3 of 5 scans used today"** | No | `quota_meter_view {used:3}` |
| Scan 4 completes (1 left) | Chip turns coral; toast on Result | **"1 free scan left today"** | No | `quota_meter_view {used:4}` |
| Scan 5 *succeeds* | Inline card on ResultScreen under Play | **"That was your 5th free scan. Free scans reset at midnight. Scanning a whole piece or songbook? Pro removes the daily limit."** + `See Pro` (secondary) | No | `paywall_soft_view` → `paywall_soft_tap` |
| Scan 6 attempted | Paywall modal | See §4.3 | Yes (but dismissible) | `paywall_view {source:"quota"}` |
| User taps Pro entry in Settings / Library footer | Paywall | same paywall, header changes to "Music Reader Pro" w/o "you've used" line | No | `paywall_view {source:"settings"}` |
| 3rd successful scan *week* (i.e. returning user) | Same soft card, once | **"You've scanned N pages this week."** | No | `paywall_soft_view {source:"habit"}` |

Why this ordering ([INFERENCE] + [S4]): freemium conversions are long-tail (23% at 6+ weeks) and most trial starts/conversions happen on Day 0 for apps that gate on Day 0; this app *cannot* gate on Day 0 (5 free scans), so its job is to (a) make Pro permanently visible and legible, and (b) catch the heavy-use moment honestly. Mojo (RevenueCat contributor): "Triggering a paywall on app open once per week for free users drove 15% of new revenue with no backlash. The more generous your free tier, the more users tolerate the ask." [S4] — a weekly, dismissible soft prompt is a testable idea for this generous tier (B4); **frequency cap and an off-switch are mandatory** for trust.

**Do not** use countdown timers, fake scarcity, or "you've been selected" language. RevenueCat reports countdown timers appear on ≤1.4% of paywalls anyway [S4], and they erode the trust story (§7).

### 4.3 Paywall redesign spec (App-Review-safe)

Apple's required elements for a subscription sign-up screen [S1]: subscription name & duration & what's provided; **full renewal price, clear and prominent, localized**; a way to restore purchases; Terms + Privacy links. Billed amount must be the most prominent pricing element; per-month breakdown and savings must be "subordinate in position and size" [S1].

Wireframe (portrait):

```
[×]                                   Upgrade
Scan as much as you like
You've used 5 of 5 free scans today.        ← only when source=quota
They reset at midnight.                      ← local midnight (ScanQuota uses calendar day)

┌ Yearly ──────────────────────  Best value ┐
│  $29.99 / year          ← 22pt bold        │
│  $2.50/month · about 50% less than monthly │ ← 12pt secondary, computed from StoreKit price
└────────────────────────────────────────────┘
┌ Monthly ───────────────────────────────────┐
│  $4.99 / month                             │
└────────────────────────────────────────────┘

What you get
• Unlimited page scans, every day
(Everything else stays free: playback, tempo, loop, 11 sounds, library, MIDI share)

[ Subscribe — $29.99/year ]                  ← CTA names price+period (dynamic)
Renews automatically until canceled. Cancel anytime in Settings → Apple ID → Subscriptions.
[ Not now — I'll wait until tomorrow ]       ← equal-size text button, no dark patterns
Restore purchases · Manage subscription · Terms · Privacy
```

Specifics tied to the existing code:
- **B5** `planCard`: show `product.displayPrice` + period as the largest text; compute monthly equivalent as `product.price / 12` formatted with `product.priceFormatStyle` (localised; never hard-code `$2.50`). Today each card shows the title ("Yearly"/"Monthly"), a `largeTitle` `displayPrice` with no "/ year" unit, a per-card "Subscribe" button, and no per-month equivalent or savings figure [CODE PaywallView.swift:64-95]. (The price *is* already the most prominent element — keep that — but add the unit and keep any extras smaller than it.) Savings line is computed from the *actual* monthly product so it can't go stale: `1 − yearly/(12×monthly)` = 49.9% at current prices (computed) → say "about 50% less than monthly".
- **B6** Add `paywall_dismiss {via:"close"|"not_now"}` and rename "Close" → keep `X` and add **"Not now"**.
- **B7** Keep the Free-vs-Pro table but make it *honest and reassuring*: rows "Page scans per day — 5 / Unlimited"; "Playback, tempo, A–B loop, 11 sounds — ✓ / ✓"; "Library & Share MIDI — ✓ / ✓"; "Works offline, no account — ✓ / ✓". Showing what remains free reduces buyer's-remorse reviews like "5 dollars down the drain" [S9] and aligns with "describe what the user will get for the price" (3.1.2(c)) [S2].
- **B8** Restore + **Manage subscription** (StoreKit `manageSubscriptionsSheet` / `AppStore.showManageSubscriptions`) in Settings → "Music Reader Pro" section, visible to everyone (F13/P-series flag the missing Settings entry; this is the design). Apple: "Consider allowing a way for subscribers to see the status of their subscription within your app… and a way to easily manage or turn off" [S1].
- **B9** Show the user's last scan thumbnail (from `captures/`) at the top for `source=quota` — personal context, no new data.
- Consider `SubscriptionStoreView` (StoreKit 2 SwiftUI) as a fallback implementation: it renders compliant price hierarchy, legal links and restore by default. Trade-off: less control over copy/layout ([INFERENCE] fine for v1.0 if time-boxed).

### 4.4 Trial / intro offer — recommendation: **don't add a free trial yet**

- A free tier already is the trial; a 3-day trial on top mostly adds cancel-anxiety. RevenueCat: for 3-day trials "55.4% cancel on Day 0"; 7-day 39.8%; 30-day 31.1% [S4].
- If you do want an acquisition lever, the data point to **longer** trials converting better (17–32 days median trial-to-paid **42.5%** vs **25.5%** for ≤4 days) [S4] — but a long trial on a volume-only product gives the user nothing to "feel" (they never hit the cap). [INFERENCE]
- Better fit: a **non-renewing "30-Day Pass"** (forScore ships exactly this at $2.99 [S10]). It matches seasonal use (recital, exam, choir term), removes auto-renew anxiety, and is a clean upsell to yearly after the pass. **Additive** (new IAP product + entitlement logic) → B31, needs Yisheng's OK and review-notes update.
- Win-back offers are native: Apple shows them on the product page, in-app sheet, and Subscription settings with no extra work [S1] — configure one for lapsed yearly subscribers after launch (B32, S).

### 4.5 Reverse-trial idea (test later)

An RevenueCat contributor (App Masters) reports a "reverse trial" — give temporary premium access after the user dismisses the paywall — lifting freemium conversion from "0.4% to 4.5%" (single-contributor claim, not a benchmark) [S4]. For this app, "premium" = more scans for 24h, i.e. *raising the cap temporarily*. That is a policy change, so **hold until you have baseline data**; listed as B33 (experiment, needs Yisheng's call).

### 4.6 Pricing presentation checklist

- Localise everything via StoreKit; never string-format dollars.
- Keep exactly **two plans** (RevenueCat: two-plan paywalls are 41–60% of paywalls across categories) [S4]; keep yearly pre-selected (already `primary: true`).
- CTA text: "Subscribe — $29.99/year" (dynamic). "Continue" is the most common CTA in the data but is ambiguous for a first-time buyer; price-in-CTA is the safer review posture. [INFERENCE]
- Restore must be reachable *without* triggering a purchase (it is, on the paywall) and from Settings (add).

### 4.7 What Pro should include to justify "ongoing value" (honest assessment)

Pro = unlimited scans only. For App Review 3.1.2(a) that's arguably "access to… continually updated" service-like value, but it is thin, and competitors' Pro is capability-led (§2.1). Options, in order of risk/effort:
1. **Copy-only:** describe Pro as "no daily limit" and put the reasoning in App Review notes (B30, S).
2. **Additive, no new engine:** per-piece memory of tempo/instrument/loop (also a retention hook) as a *free* feature; lock-screen playback as free; **Pro-only: iCloud library backup/sync** (M–L). Competitors treat cloud sync as a Pro feature (Newzik cloud, Sheet Music Scanner cloud sync) [S9][S11].
3. **Additive, new capability:** multi-page "piece" grouping and **MusicXML export** (PlayScore, Sheet Music Scanner and Newzik Premium all sell this) [S7][S9][S11]. Parked: needs engine/output work.

---

## 5. Core experience polish

### 5.1 Home/Library
- **Information scent:** the first row after the big title should be the *job*, not an explainer. Move `scanActions` above `HowItWorksArt` after first success (B21).
- **Row design:** show a **thumbnail** (the `captures/<name>.jpg`) at 44 pt, title, "n notes · mm:ss · date", NEW pill (exists). Thumbnails are the strongest recognition cue for a *photo* library; but flows F2.3 flags artwork-loading jank → use `ThumbnailCache` + downsampled `CGImageSource` (B22).
- **Meter chip** (§4.2) in the nav bar trailing area next to the camera button; 44×44 pt target; label "3 of 5 scans used today".
- **Samples section:** rename header "Samples" → **"Try these first"** for users with 0 scans; when ≥1 scan, collapse by default.
- **Search** exists ("Search your music") ✔.

### 5.2 Capture quality feedback (the biggest accuracy lever)
Existing assets: `PhotoQuality` verdicts (dark / washed out / small) and the `Tip` set [CODE ScanFailure.swift:74-82]. They fire after a failed read. Move them *before* the shutter:
1. **Page-frame guide (B15):** portrait rounded-rect brackets at ~US Letter/A4 aspect with the label **"Fit the page"**; turns coral→green when edges are inside the frame (Vision `VNDetectDocumentSegmentationRequest` on preview frames at ~2 Hz [INFERENCE: API available iOS 15+; verify perf]). 
2. **Live hint line** replacing the static "Hold steady over one page": priority-ordered, one at a time — *"Too dark — try the torch"* · *"Tilt: hold the phone flat above the page"* (CoreMotion gravity) · *"Move closer"* · *"Looks good — tap to focus"* (B16).
3. **Torch**: a torch button already exists in the camera chrome when the device has one [CODE CameraScreen.swift:130-131]; just make the "too dark" hint tappable to turn it on (B17).
4. **Pre-flight verdict (B18):** after shutter, only if `PhotoQuality` flags a problem, show a half-sheet **"This photo may be hard to read — Retake / Use anyway"**; otherwise go straight to reading (zero added friction for good photos). Pairs with *not consuming quota until the read starts or succeeds* (P1.4).
5. **VisionKit alternative (B19, L):** `VNDocumentCameraViewController` provides auto-capture, edge detection and perspective flattening out of the box; trade-off: loses custom chrome and possibly the exact image pipeline expected by the model — treat as an *experiment*, not a swap. **Touches core: Around** (changes the input image).
6. **Accessibility of the camera:** announce hints via `UIAccessibility.post(.announcement)` and expose the frame state as an accessibility value (§8) (B20).

### 5.3 Progress states (ReadingView)
Today: determinate bar + Cancel + lock-label [CODE ReadingView.swift:38-100]. Add: named stages ("Finding staves → Reading notes → Building playback") only if the pipeline emits them (check); otherwise keep one calm bar. Show **elapsed-time expectation**: Soundslice states "Takes about a minute per page" openly [S6] — an honest ETA reduces abandonment ([INFERENCE]). Measure p50/p90 `ms` from `scan_success` first, then publish "usually N seconds" (the repo notes parse time is unmeasured per TODO — do not claim a number until measured; listing already avoids it ✔).

### 5.4 Error messaging
`ScanFailure` copy is already specific and kind ("No printed notes found", "No music staff found"…) ✔ [CODE ScanFailure.swift:39-62]. Improvements:
- Lead with the **fix**, not the diagnosis: title "Couldn't read this page" + first line = the single most-likely tip (by `FailureKind`), diagnosis in "Details".
- Replace "ort/onnx/session" jargon paths with the existing `.readerUnavailable` copy only ✔; ensure "Details" is collapsed by default.
- Add **"Try the sample instead"** (exists as "Play a sample" [CODE ResultScreen.swift:157]) *and* **"Choose a cleaner source"** nudge: Photos/Files import, because photos are the least reliable path [S9].

### 5.5 Reader & playback UX
- **Retake** should reopen the **Camera** (F5.5 bug) — design: Retake button label = "Retake" with camera glyph; secondary "Library".
- **Follow toggle** does nothing today (F10.5) — either wire it or *remove it from the UI* until it works; a dead toggle in a practice tool costs trust.
- **Sheet/Cover picker** is a clear segmented control ✔; default to **Sheet** when layout exists ✔ (`showSheet = true`).
- **Practice affordances users expect** (from competitor feature lists): count-in (PlayScore "Accompaniment Count-in feature" [S7]), metronome (forScore "integrated utilities like our metronome" [S10]), per-staff mute (exists: "Hands"), transposition (Sheet Music Scanner: semitone shift [S9]; app has Transpose ✔ [CODE PlayerView.swift:318]). **Count-in/metronome click = B36 (Additive, M)**.
- **Haptics:** none in Sources (grep) → add light impact on shutter, success haptic on Result, selection feedback on loop A/B set (B23, S).
- **Reduce Motion** is honoured in two places ✔; verify the highlight auto-scroll (SheetFollowView) also respects it (B24).

### 5.6 Editing corrections
Recurring ask in reviews [S9]; Soundslice builds the product around it [S6]. Out of scope by constraint → §11 (B50). *Cheap proxy that stays inside the constraint:* a **"Report a wrong note"** button that attaches (with consent) the cropped image region + staff/measure index to a feedback email — gives you an accuracy dataset and gives users agency. (Local-only feedback today: F8.7.) → B25 (M; requires consent flow §7.2).

---

## 6. Retention hooks

Reality check [INFERENCE]: this is an **episodic utility** (new piece → scan → practice for days). Retention levers should extend *per-piece* engagement and make coming back for the next piece frictionless — not streak gimmicks. I found no verified music-app D1/D7 retention benchmark in reachable sources (Business of Apps was behind a Cloudflare challenge; I did not bypass it) — **measure your own via App Store Connect cohorts** [S1: "Cohorts page… retention"].

| Hook | Design | Effort | Core? | Evidence |
|---|---|---|---|---|
| **Resume where I left off** | Library row shows a thin progress bar + "Resume 0:42 · 0.75×"; per-piece persisted tempo/instrument/loop | S–M | Around | Soundslice lists "Auto-saved player settings" among practice features [S5]; B26 |
| **Lock-screen / background playback** | `AVAudioSession` playback + `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` | M | Additive | flows F10.10 shows it's missing; playing while holding an instrument is the use-case. Needs your OK (touches audio session) — B37 |
| **Piece = multiple pages** | Group consecutive scans into one library item with page chips | M–L | Additive | Reviewers praise "add all 5 pages into one document" [S9]; PlayScore Pro sells multi-page [S8] — B51 |
| **Share to a student/teacher** | `ShareLink` already exports MIDI [CODE PlayerView.swift:125, LibraryScreen.swift:211, ResultScreen.swift:74]. Make it a **bundle**: scan photo + MIDI + one-line message "Hear this page: …" + App Store link (after launch) | S | No | Teachers/students are the stated audience [CODE description.txt "WHO IT'S FOR"]; PlayScore pitches teachers directly [S7]; B27 |
| **Control Center "Scan" control + "Resume" widget** | WidgetKit; Controls require iOS 18 (deployment target is **17.0** [CODE project.pbxproj:640]) → availability-gate | M | No | forScore 14.3.1 shipped control-center widgets + a Goals widget [S10]; B38 |
| **App Shortcuts / Siri "Scan sheet music"** | `AppIntent` opening Camera | S–M | No | forScore added dozens of Shortcuts actions (14.4.1) [S10]; B39 |
| **Opt-in practice reminder** | After 2nd session on a piece, ask once: "Remind me to practice *Ode to Joy* tomorrow at ___?" local notification | S–M | No | Apple: notifications must be "timely, serve a clear purpose"; marketing pushes need explicit opt-in [S1]; low priority — B28 |
| **Ratings prompt at success** | `requestReview` after the **3rd successful scan *and* ≥30 s of playback**, never after an error, max once per version. Apple disallows custom review prompts ("Use the provided API") [S2 5.6.1] so **no "Do you like the app?" pre-screen**; give "Send feedback" as a separate Settings row | S | No | Today only a Settings button calls `requestReview` [CODE SettingsView.swift:54,118]; B29 |

---

## 7. Trust

### 7.1 Privacy story (strong, make it visible)
Repo facts: on-device recognition, models bundled, photos never uploaded, no account; privacy policy live (HTTP 200) and in-app About text consistent [CODE SettingsView.swift:136,196-197; privacy.html fetched 2026-10-17]. Surface it at moments of doubt, not only in Settings: the Reading screen lock label ✔ already; add the same line to the Camera permission-denied state and the intro card (§3.2 A3).
Small mismatch to tidy: policy lists scan events "with a non-sensitive error type" but code also sends `notes` count and `ms` on `scan_success` [CODE ResultScreen.swift:253] — harmless, but update the policy sentence (B41, S).
`grepawk.com/music-reader/` root returned **403** to curl on 2026-10-17 while privacy/support/terms returned 200 — confirm there is no public 403 on any URL you advertise (e.g. marketing URL) [UNVERIFIED if bot-block].

### 7.2 Analytics consent and opt-out (launch risk)
Apple 5.1.1(ii): consent required "even if such data is considered to be anonymous" and an "easily accessible… way to withdraw consent"; paid features must not depend on granting it [S2]. Today: events fire at launch via `Analytics.bootstrap()`; no toggle (F13.7).
Design options:
- **A (safest):** intro card #3 has a switch "Share anonymous usage stats" (default **off** until user flips; or default on with a clear 'You can turn this off in Settings' — consent semantics are Yisheng/counsel's call). Settings → Privacy → same switch. Gate `Analytics.track` on it.
- **B (lighter):** Settings toggle only, default on.
- Either way: add **Device ID** or **Usage Data** to the App Privacy label if the install UUID counts as a device-level identifier (check Apple's definitions) [UNVERIFIED — verify in ASC]. Keep using **App Store Connect analytics + subscription dashboards** for consent-free aggregate funnel basics [S1].
[INFERENCE] opt-in lowers event volume; ASC aggregates cover installs/conversion/retention regardless. Not legal advice.

### 7.3 Setting accuracy expectations (without touching OMR)
- **On Result ("Ready to play"):** one line under the title: **"Check the highlighted notes against your page — reads can contain mistakes."** The listing already says this ("results can contain mistakes") [CODE description.txt GOOD TO KNOW]; echo it in-app where decisions happen.
- **Reading summary chip:** "3 staves · 124 notes read" (data already known to the pipeline per `ScanFailure` staff/note counts [CODE ScanFailure.swift:25-26,55]). If the pipeline can expose measures it skipped or low-confidence notes, show them greyed — the exact pattern reviewers describe ("grayed-out notes") [S9] and Soundslice's "ask for clarification" [S6]. **Engineering check needed**; otherwise ship the count-only chip.
- **Say what it can't do** in a "What reads well" sheet (printed, one page, standard notation). Sheet Music Scanner's listing enumerates unsupported symbols in plain text (codas, dynamics, double sharps, grace notes) [S9] — transparency lowers refund-shaped reviews. Fill in your own list from `docs/SPEC.md` rather than guessing.

### 7.4 Subscription honesty
No dark patterns: equal-weight "Not now", reset time shown, per-month math derived from real prices, renewal terms visible near the CTA (already in footer text) and Terms/Privacy links present [CODE PaywallView.swift:135-]. Duolingo's reported paywall learning: "Prioritize clarity over persuasion… removing uncertainty about the purchase process drives more conversions than trying to sell harder" [S4].

---

## 8. Accessibility

Code posture [CODE grep]: 20 `accessibilityLabel`; icon-only buttons labelled in Library (Settings/Import photo/Camera), Player (Previous/Next/Hands/Transpose), Camera shutter; Reduce Motion handled in ReadingView and ResultScreen; **fixed-size fonts** at CameraScreen:143,197, PlayerView:215 (34 pt transport glyph), SettingsView:184, Theme:55; no `dynamicTypeSize`/`ScaledMetric` usage. Competitors disclose nothing on accessibility [S9][S10] — an opportunity.

| # | Issue → Fix | Effort | Backlog |
|---|---|---|---|
| 1 | Fixed-size fonts → `@ScaledMetric` or semantic styles; cap with `.dynamicTypeSize(...accessibility3)` on dense rows (Player transport) | S | B60 |
| 2 | **Sheet-following highlight** is purely visual → add VoiceOver value on the player ("Measure 5 of 16, 0:12 of 0:48") and a "Read current measure notes" accessibility action (pitch names exist in the data per OMRCompareView) | M | B61 |
| 3 | Camera: no non-visual framing feedback. VoiceOver user asked for exactly this in 2018 [S9]. Announce "Page fills the frame" / "Move phone up" | M | B20 |
| 4 | Scan-meter chip and coral/green frame state must not rely on colour alone; add text/glyph | S | B62 |
| 5 | Tap targets ≥ 44×44 pt for loop A/B handles, "⋯" row button, hand mute pills | S | B63 |
| 6 | Contrast: coral text on `coralSoft` card and white-on-cream title in the 2nd store screenshot appear low-contrast on visual inspection — run Accessibility Inspector, target 4.5:1 | S | B64 |
| 7 | Reduce Motion: confirm SheetFollowView auto-scroll/cross-fades honour it; today only 2 files read the setting | S | B24 |
| 8 | Haptics as a non-visual success/fail cue | S | B23 |
| 9 | Publish **Accessibility Nutrition Label** answers in App Store Connect only for features you have verified (VoiceOver, Larger Text, Reduced Motion, Sufficient Contrast) — don't over-claim | S | B65 |
| 10 | UI tests: add XCUITest `performAccessibilityAudit()` to CI for Library, Camera, Result, Player, Paywall ([INFERENCE]: available iOS 17+) | S | B66 |

---

## 9. App Store listing, ASO, screenshots

### 9.1 What Apple says drives search
"Search results are based on… text relevance (matches for your app's title, subtitle, keywords, and primary category), as well as user behavior (downloads, ratings and reviews, and more)." Keywords: 100 chars, comma-separated, **don't repeat words in name/subtitle/category**, avoid plurals/generic words; **promotional text does not affect search ranking**; third-party trademarks and competitor names in keywords are a rejection reason; App Store search can also generate **app tags with LLMs from your metadata** [S3]. Guideline 2.3.7: names ≤30 chars, subtitles must not "make unverifiable product claims" [S2].

### 9.2 Competitive search snapshot (iTunes Search API, US, 2026-10-17; ratings counts are as returned that day)

| Query | Top results (rank, name, ratings count) |
|---|---|
| "scan sheet music" | 1 Sheet Music Scanner (6,475) · 2 PlayScore 2 (4,741) · 3 Newzik: Sheet Music Reader (1,547) · 4 Sheet Music Reader Halbestunde (1,477) · 5 Musicnotes: Sheet Music Reader (43,214) |
| "sheet music scanner" | 1 Sheet Music Scanner · 2 PlayScore 2 · 3 Musicnotes · 4 Sheets Music Scanner & Reader (14) · 5 Halbestunde |
| "music reader" | 1 PlayScore 2 · 2 Sheet Music Scanner · 3 Musicnotes · 4 Shazam · 5 Halbestunde |
| "sheet music to midi" | 1 MuseScore (79,071) · 2 Sheet Music Scanner · 3 Ivory (36) · 4 MIDI Score (151) · 5 Notation Pad (5,286) |
| "play sheet music from photo" | 1 Flat (6,953) · 2 Sheet Music Direct · 3 Tomplay · 4 forScore (43,350) · 5 Suno … |
| "sheetcam" | no sheet-music result in top 8 (iVCam, LookCam, …) |

**Read:** the head terms are owned by apps with ≥1.4K ratings, and tiny apps (14 ratings, "Sheets Music Scanner & Reader") still appear because **their names contain the query**. [INFERENCE] The current name "AI Camera - Music Reader" matches only "music reader"; "sheet", "scan", "scanner" rely on the subtitle alone. And the installed name "SheetCam" can't be found by anyone who remembers it.

### 9.3 Name / subtitle / keywords — proposals (≤ limits verified by `len()`)

| Field | Current | Proposal | Notes |
|---|---|---|---|
| Name (≤30) | `AI Camera - Music Reader` (24) | **`SheetCam: Sheet Music Scanner`** (29) — or `SheetCam - Scan Sheet Music` (27) | Unifies with the installed name. *Risk:* "Sheet Music Scanner" is also the name of an incumbent app (App Sub 1 LLC) — as a descriptive phrase after your brand it's common, but confirm trademark/confusion risk (2.3.7 "popular app names") [S2]. Safer fallback: `SheetCam – Scan & Play Music`. "SheetCam" has no sheet-music collision in the search above. |
| Subtitle (≤30) | `Scan sheet music, hear it play` (30) | If name takes "Sheet Music Scanner": **`Photo to playback, offline`** or **`Hear any page. No account.`** | Don't repeat words already in name (Apple: don't repeat) [S3]. "Offline/No account" are verifiable (code). Avoid "best/most accurate" (2.3.7) [S2]. |
| Keywords (100) | `OMR,piano,score,notation,notes,MIDI,sightreading,practice,tempo,choir,teacher,student,synth,library` | Drop jargon/low-intent (`OMR`, `synth`, `library`, `student`); add intent phrases: `photo to midi,piano,sight reading,choir,score reader,music notes,learn piano,practice,tempo,teacher` | Never add competitor names. Validate with Apple Ads search-popularity or ASC "Search Terms" after launch — I have **no** keyword-volume data (S3 says popular terms are competitive for newer apps). |
| Promo text (170, not indexed) | "…On-device OMR with iPhone GPU acceleration…" | Benefit-first: **"Point your camera at printed sheet music and hear it play — slow it down, loop a bar, pick an instrument. Private: reads on your iPhone, no account."** | GPU/Neural Engine is an engineering detail; keep in the description's "ON-DEVICE READING" paragraph if you like. Promo text is changeable without review [S3]. |
| Description opening | "Point your camera at printed sheet music and hear it played. AI Camera - Music Reader reads…" | Lead with the user job and *one* proof line; move "FREE AND PRO" higher than "A PLAYER MADE FOR PRACTICE" — 2.3.2 wants IAP clarity [S2] | Keep "GOOD TO KNOW" (honest limitations) ✔ |

### 9.4 Screenshots
Repo: 4 iPhone 6.9" + 4 iPad frames, captions: "Snap sheet music. Hear it play." (hero mockup), "Slow it down to practice" (Für Elise player), "Reads on your device", "Pick a sound" [CODE LISTING.md:146-148, docs/asc/screenshots/en-US].
- **Replace the hero mockup with a real capture** (2.3.3) [S2]; keep the caption.
- Search results show **up to three screenshots/previews** [S3] → frames 1–3 must carry the whole story: (1) Camera with the page-frame guide (after B15) or Sheet view mid-highlight, (2) tempo/loop, (3) privacy/offline.
- Show a **recognisable, public-domain** piece. Für Elise/Ode to Joy are fine; **verify the rights status of any other title that appears in the hero** (I could not verify the piece shown) [UNVERIFIED].
- Add a **15–30 s app preview** (screen capture only per 2.3.4) of "photo → highlight follows"; the Library empty state is not a good thumbnail.
- **Custom Product Pages** (Apple supports keyword-assigned CPPs [S3]) for later: "teachers", "choir", "piano students" — each reusing real captures with different captions.
- Don't show prices or "Pro" in screenshot art beyond what 2.3.2 requires (the subscription review screenshot lives in `docs/asc/review/` already) [S2].

### 9.5 Ratings
Rating volume and sentiment feed ranking [S3]. Prompt at §6 moment; respond to every review (Apple lets developers respond; replies must be on-topic, no marketing [S2 5.6.1]).

---

## 10. Metrics to instrument

### 10.1 Rules
Keep the payload privacy rules already in `Analytics.track` (no photos/email/location; value ≤200 chars). Gate on consent (§7.2). Add a **`consent` prop? No** — if user opts out, send nothing. Use ASC App Analytics / Subscriptions / Cohorts for installs, conversion, retention that need no SDK [S1].

### 10.2 New events (names `snake_case`, consistent with existing)

| Event | Props | Fires when | Answers |
|---|---|---|---|
| `first_launch` | `app_version, os` | first ever `app_open` | cohort anchor |
| `intro_view` / `intro_complete` / `intro_skip` | `card` | each intro card | onboarding drop-off |
| `sample_start` | `source: "hero"\|"library"\|"result_fail"` | sample picture or sample row tapped | sample usage |
| `camera_open` | `perm: "granted"\|"denied"\|"prompt"` | CameraScreen appears | permission funnel |
| `camera_hint_shown` | `hint: "dark"\|"tilt"\|"closer"\|"ok"` | live hint changes (≤1/2s, dedupe) | does coaching fire? |
| `capture_taken` | `source:"camera"\|"photos"\|"sample", quality:"ok"\|"dark"\|"washed"\|"small"` | shutter/import | input mix & quality |
| `preflight_shown` / `preflight_choice` | `choice:"retake"\|"use"` | quality half-sheet | friction vs benefit |
| `scan_start` ✔ / `scan_success` ✔ / `scan_fail` ✔ | add `source`, `quality`, **`fail_kind`** (`noMusicFound`…), `staves`, `ms`, `first_run:Bool` | existing | scan success rate by cause |
| `scan_retake` | `after:"fail"\|"success"` | Retake tapped | retry loops |
| `play_start` | `entry_source:"scan"\|"sample"\|"library"`, `mode:"sheet"\|"cover"` | first playback of a session item | **activation** |
| `play_complete` | `pct_listened` bucket (25/50/75/100) | stop/end | engagement depth |
| `practice_action` | `type:"tempo"\|"loop"\|"hands"\|"instrument"\|"transpose"` | each first-use per play session | which practice tools matter |
| `share_tap` | `kind:"midi"\|"bundle"`, `surface` | ShareLink | virality |
| `quota_meter_view` | `used` | meter chip first shown at each count | meter exposure |
| `paywall_soft_view` / `paywall_soft_tap` | `source` | inline card | soft-prompt CTR |
| `paywall_view` ✔ | add `source:"quota"\|"settings"\|"soft"\|"library"`, `scans_used_total`, `days_since_install` | existing | funnel head |
| `paywall_dismiss` | `via:"x"\|"not_now"`, `ms_visible` | close | intent signal |
| `paywall_plan_select` ✔ / `purchase_start` ✔ / `purchase_success` ✔ / `purchase_fail` ✔ | add `plan`, `price_tier`; `purchase_fail.reason` = `cancelled\|pending\|error` | existing (P3.6 silent-success bug aside) | take rate by plan |
| `restore_tap` / `restore_result` | `result:"found"\|"none"\|"error"` | Settings/paywall | restore friction |
| `review_prompt_requested` | `trigger` | `requestReview` called | rating rate |
| `consent_set` | `value:"on"\|"off"`, `surface` (only the *change to on* can be sent) | toggle | opt-in rate |
| `feedback_wrong_note` | none | report button | accuracy signal |

### 10.3 Funnels & definitions

| Metric | Definition | Notes |
|---|---|---|
| **Activation (A1)** | % of new installs with `play_start` within 24 h | Primary north-star for onboarding work |
| **TTFS** | median time `first_launch` → first `play_start` | Report by entry source (sample vs camera) |
| **Camera funnel** | `camera_open` → `capture_taken` → `scan_success` → `play_start` | Find the biggest leak |
| **Scan success rate** | `scan_success / scan_start`, **cut by** `source, quality, fail_kind, first_run` | The single best read on whether coaching works; compare before/after B15–B18 |
| **Quota exposure** | % of active users reaching `quota_meter_view{used≥4}` and `free_quota_hit` | Tells you if the cap bites at all (my §1.2 prediction) |
| **Paywall view→purchase** | `purchase_success / paywall_view`, by `source` | Compare to nothing external: RevenueCat gives only download→paid (D35 freemium median **2.1%**, NA **2.8%**) and trial→paid [S4]; compute **install→paid D35** from ASC to compare |
| **Plan mix** | yearly vs monthly share of `purchase_success` | RevenueCat: yearly-dominant apps show higher RPI [S4] |
| **D1 / D7 retention** | from **ASC Cohorts / App Analytics** (no SDK) and from `app_open` by `first_launch` cohort if consent on | No music-category retention benchmark verified |
| **Refund/cancel** | ASC Subscriptions dashboard (cancellation reasons) [S1] | Watch after any paywall copy change (Yousician: check refunds/renewals before celebrating conversion wins) [S4] |

### 10.4 Experiment hygiene
Read results by **geography and cohort** (Mojo: winners differ by region; aggregate results hide it) and re-check winners at 3 and 6 months (Yousician) [S4]. With a small user base, run **sequential before/after** with a stable control week rather than A/B you can't power; ASC Product Page Optimization handles listing tests (screenshots/icon/promo text) [S3].

---

## 11. Parked — useful but beyond "don't change core functionality"
These change what the product does; Yisheng decides.

| ID | Idea | Why it matters | Effort | Evidence |
|---|---|---|---|---|
| B50 | In-app note editing / correction view with original image inline | #1 recurring review ask; Soundslice core | L | [S6][S9] |
| B51 | Multi-page "piece" + whole-PDF import | paid driver at PlayScore/Sheet Music Scanner/Soundslice | L | [S5][S7][S9] |
| B52 | MusicXML export | export is a paid feature across comps; reviewers use it with Guitar Pro/Dorico | L | [S7][S9][S11] |
| B53 | iCloud sync as Pro value | capability-led Pro | M–L | [S9][S11] |
| B54 | Staff/part selection beyond "Hands" (choir SATB mute) | choir & ensemble users asked for it | M–L | [S7][S9] |
| B36 | Count-in / metronome click | practice staple | M | [S7][S10] |
| B37 | Background / lock-screen playback | missing today (F10.10) | M | flows |
| B31 | 30-Day Pass (non-renewing IAP) | seasonal use, trust | M | [S10] |
| B33 | Reverse trial / temporary cap lift | experiment only after baseline | M | [S4] |

---

## 12. Prioritised backlog

Scoring: **Impact** H/M/L on activation, conversion, discoverability or trust. **Effort** S ≤ ~2 dev-days, M ≤ ~1–2 weeks, L > 2 weeks ([INFERENCE] estimates, not measured). **Risk** = regression/review/brand risk. **Core?** No / Around / Additive. Evidence column cites §/sources.

### P0 — before or at launch (S, high leverage or review-critical)

| ID | Idea | Rationale | Eff | Impact | Risk | Core? | Evidence |
|---|---|---|---|---|---|---|---|
| B1 | Scan-meter chip (Library + Camera) "3 of 5 scans used today" | metered paywalls work when users see the limit coming; `scansRemaining` exists but unused (P1.10) | S | H | Low | No | [S1]; flows P1.10 |
| B2 | Soft card after 5th successful scan with reset time | honest, converts the intent moment without a block | S | H | Low | No | [S1] |
| B3 | Paywall copy shows local reset time + "Not now" equal weight | trust; App Review-safe | S | M | Low | No | [S1][S4 Duolingo] |
| B5 | Plan card: billed price dominant; per-month + % savings computed from StoreKit, subordinate | Apple requirement | S | H | Low | No | [S1] |
| B6 | `paywall_dismiss`, `paywall_view.source` events | funnel blind spots | S | H | Low | No | §10 |
| B7 | Honest Free-vs-Pro table rows (show what stays free) | reduces regret reviews; 3.1.2(c) | S | M | Low | No | [S2][S9] |
| B8 | Settings → Pro section: status, Restore, Manage subscription | Apple recommends in-app manage; hidden restore (flows) | S | H | Low | No | [S1]; flows F13 |
| B30 | App Review notes: explain Pro value + how to reach paywall + sample re-trigger | 3.1.2(a) "ongoing value" | S | M | Low | No | [S2] |
| B40 | Replace hero mockup with real capture | 2.3.3 | S | H | Low | No | [S2]; LISTING.md |
| B41 | Telemetry consent switch + Settings toggle; gate `track` | 5.1.1(ii) | S | H | Low | No | [S2]; F13.7 |
| B42 | Unify brand: store name ↔ `CFBundleDisplayName` | findability, trust | S | H | Med (trademark check) | No | §9.3 |
| B43 | Name/subtitle/keywords rewrite (§9.3) | text relevance drives search | S | H | Low | No | [S3] |
| B44 | Promo text benefit-first | conversion; free to change | S | M | Low | No | [S3] |
| B45 | Move "FREE AND PRO" ahead of feature list in description | 2.3.2 clarity | S | L | Low | No | [S2] |
| B46 | Update privacy policy sentence for `notes`,`ms` props | accuracy of claims | S | L | Low | No | §7.1 |
| B47 | Verify rights for any non-PD piece in screenshots | 5.2 IP risk | S | M | Low | No | §9.4 [UNVERIFIED] |

### P1 — first 2–4 weeks post-launch (activation & quality)

| ID | Idea | Rationale | Eff | Impact | Risk | Core? | Evidence |
|---|---|---|---|---|---|---|---|
| B10 | Sample-first hero on first run, quota-free | Day-0 matters; hides best demo today | M | H | Low | No | [S4][S1] |
| B11 | Pre-baked sheet layout for "Ode to Joy (sample)" row | show highlight w/o scan | M | H | Low | No | PlaylistStore |
| B12 | 3-card intro ending on "See it work" (+consent switch) | trust + activation | M | M | Low | No | [S1][S4] |
| B13 | Designed first-read waiting copy | avoid perceived hang | S | M | Low | No | F6.6 |
| B14 | Instrument `first_launch`, `play_start`, TTFS | measure activation | S | H | Low | No | §10 |
| B14b | Camera denied state → "Choose a photo instead" | no dead end | S | M | Low | No | CameraScreen.swift:86 |
| B4 | Weekly soft Pro prompt for returning free users (cap + off-switch) | generous free tier tolerates it; test | S | M | Med (annoyance) | No | [S4 Mojo] |
| B9 | Last-scan thumbnail atop quota paywall | personal context | S | M | Low | No | — |
| B15 | Page-frame guide on camera | #1 accuracy lever | M | H | Med (perf) | Around | [S9] |
| B16 | Live hint line (dark/tilt/closer) | uses existing tips pre-shutter | M | H | Low | Around | ScanFailure.Tip |
| B17 | Make the "too dark" hint tap-to-torch (torch button already exists) | low-light fix | S | M | Low | Around | CameraScreen.swift:130; ScanFailure.dark tip |
| B18 | Pre-flight "may be hard to read" sheet (only when flagged) | prevents wasted scans | M | H | Low | Around | P1.4 |
| B20 | Camera VoiceOver announcements | a11y + accuracy | M | M | Low | Around | [S9] 2018 review |
| B21 | Library: actions above explainer after first success | information scent | S | M | Low | No | §5.1 |
| B22 | Thumbnails on scan rows (downsampled cache) | recognition | M | M | Med (F2.3 jank) | No | F2.3 |
| B29 | `requestReview` after 3rd success + ≥30 s play, once/version | ratings → ranking | S | M | Low | No | [S2][S3] |
| B27 | Share bundle (photo + MIDI + message) | teacher/student loop | S | M | Low | No | [S7] |
| B26 | Per-piece resume/tempo/instrument memory | practice continuity | M | M | Low | Around | [S5] |
| B60–B66 | Accessibility set (§8) | broad | S–M | M | Low | No | §8 |
| B23 / B24 | Haptics; Reduce-Motion in SheetFollow | polish | S | L–M | Low | No | §5.5 |
| B28 | Opt-in practice reminder | retention (low priority) | S–M | L | Med (annoyance) | No | [S1] |
| B25 | "Report a wrong note" (with consent) | accuracy data + agency | M | M | Low | No | F8.7; [S9] |
| B32 | Configure win-back offer in ASC | re-acquire | S | L–M | Low | No | [S1] |
| B38 | Control Center scan control + Resume widget (iOS 18 gated) | re-entry | M | M | Low | No | [S10] |
| B39 | App Shortcuts "Scan sheet music" | re-entry | S–M | L–M | Low | No | [S10] |
| — | Screenshot set v2 + 15–30 s app preview + Custom Product Pages (teachers/choir/piano) | CVR + long-tail ASO | M | M | Low | No | [S3] |
| — | Accuracy expectation line + staves/notes chip; greyed "unsure" notes if pipeline can expose | trust | S–M | H | Low | No | [S6][S9] |

### P2/P3 — parked / strategic: see §11 (B31, B33, B36, B37, B50–B54).

---

## 13. Suggested sequencing

- **Week 0 (before/at launch):** B1–B3, B5–B8, B30, B40–B47, B41. Mostly copy and small SwiftUI changes; removes the three review risks.
- **Weeks 1–2:** B10–B14, B14b, B21, B29; confirm event pipeline (§10) works and read first-week funnel from real data.
- **Weeks 2–5:** B15–B18, B20 (capture coaching) with before/after on `scan_success` by `quality`; accessibility pass; screenshots v2.
- **Then decide with data:** B4 weekly prompt; B31 30-Day Pass; whether Pro needs a capability (B51/B52/B53) — look at `free_quota_hit` rate first. If <~few % of active users ever hit the cap, the problem is value packaging, not paywall design. (Threshold intentionally unspecified — set from your own baseline.)

## 14. Open questions for Yisheng
1. Is the telemetry default opt-in or opt-out acceptable to you (and counsel) — §7.2?
2. May the store name change to include "Sheet Music" / "SheetCam" (trademark check on "Sheet Music Scanner" as a suffix)?
3. Is a second Pro benefit (cloud backup, multi-page, MusicXML) on the roadmap, or is Pro intentionally volume-only?
4. Is an additive 30-Day Pass acceptable?
5. Can the pipeline expose per-note/per-measure confidence or "skipped" markers?

---

## 15. Sources (all fetched 2026-10-17 unless noted)

- **[S1]** Apple — Auto-renewable subscriptions (metered paywall, contextual prompts, billed-amount prominence, restore, manage, win-back, retention/cohorts): https://developer.apple.com/app-store/subscriptions/
- **[S2]** Apple — App Review Guidelines (2.3.1, 2.3.2, 2.3.3, 2.3.7, 3.1.1 restore, 3.1.2(a)/(c), 5.1.1, 5.6.1): https://developer.apple.com/app-store/review/guidelines/
- **[S3]** Apple — App Store search (ranking factors, keyword rules, promo text not indexed, custom product pages, up to three screenshots in results): https://developer.apple.com/app-store/search/
- **[S4]** RevenueCat — State of Subscription Apps 2026 (freemium vs hard paywall D35 2.1% vs 10.7%; NA freemium/overall D35; trial lengths; day-0 behaviour; price medians; paywall UI stats; contributor essays by Mojo, Duolingo, App Masters, Yousician): https://www.revenuecat.com/state-of-subscription-apps/
- **[S5]** Soundslice — Plans & pricing: https://www.soundslice.com/plans/
- **[S6]** Soundslice — Scan sheet music (limits, "asks you for help", editor, ~1 min/page): https://www.soundslice.com/sheet-music-scanner/
- **[S7]** PlayScore 2 — site (no monthly limits, MusicXML/MIDI export, count-in, 23 instruments): https://playscore.co/
- **[S8]** PlayScore 2 — Productivity subscription FAQ (1- and 12-month auto-renewing): https://www.playscore.co/blog/faq-items/playscore-2-productivity-subscription/ ; US price ($5.99/mo, $34.99/yr) and free-tier behaviour via App Store listing https://apps.apple.com/us/app/playscore-2/id1449591118 (**read through a search-engine synthesis, not opened directly — [UNVERIFIED]**)
- **[S9]** Sheet Music Scanner — App Store listing and reviews (price points, features, limitations, review quotes): https://apps.apple.com/us/app/sheet-music-scanner/id884984324 and https://apps.apple.com/us/app/sheet-music-scanner/id884984324?see-all=reviews
- **[S10]** forScore — App Store listing (Pro $14.99, 30-Day Pass $2.99, release notes: control-center widgets, Shortcuts, family tier; data not collected): https://apps.apple.com/us/app/forscore/id363738376
- **[S11]** Newzik — pricing/FAQ (free tier, 10 LiveScore pages, 7-day trial, lifetime tiers): https://newzik.com/pricing
- **[S12]** iTunes Search API (US) queries run 2026-10-17: `https://itunes.apple.com/search?term=<query>&entity=software&country=us` and bundle lookup `com.ragnus.vp` (0 results).
- Repo: `/workspace/omr-sheet-cam` @ `736d0f6` (files cited inline); `/workspace/omr-audit/flows.md`; live policy page https://grepawk.com/music-reader/privacy.html (HTTP 200).

**Not verified / not obtained:** Business of Apps music-app benchmarks (Cloudflare challenge — not bypassed); any music-category D1/D7 retention figure; keyword search volumes; real on-device behaviour; PlayScore US price directly from the App Store page; rights status of non-sample score images in screenshots.
