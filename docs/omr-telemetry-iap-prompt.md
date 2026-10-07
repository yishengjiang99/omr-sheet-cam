# OMR App: Telemetry + IAP Implementation Prompt

## Context

Port ProTune's telemetry and in-app purchase model to the OMR iOS app
(AI Camera - Music Reader, bundle ID `com.ragnus.vp`).

ProTune reference implementation:
- iOS telemetry client: `~/workspace/photo-recipes/ios/PhotoRecipes/Services/Analytics.swift`
- Telemetry server: `~/workspace/photo-recipes/server/telemetry.ts`
  (POST /api/telemetry → MySQL `telemetry_events` table)
- Admin panel: `~/workspace/photo-recipes/server/admin.ts` + `src/pages/Admin.tsx`
  (photo.grepawk.com/admin)
- IAP: `~/workspace/photo-recipes/ios/PhotoRecipes/Services/StoreKitManager.swift`
- Paywall: `~/workspace/photo-recipes/ios/PhotoRecipes/Features/Paywall/PaywallView.swift`
- ProTune product IDs: `com.ragnus.mvp.pro.monthly`, `com.ragnus.mvp.pro.yearly`

OMR app repo: `~/workspace/omr-sheet-cam` (yishengjiang99/omr-sheet-cam)
OMR app structure: SwiftUI, Sources/App/, no server component.

## TestFlight Copy (prefer LISTING.md; kept here for the IAP prompt)

Canonical "What to Test" lives in `docs/asc/LISTING.md`. Verbatim snapshot:

```
Tip-of-main (IAP + telemetry + Library home). Please verify:

1. Library is home — how-it-works art, Camera and Photos CTAs, Try sample picture.
2. Capture or import a printed page — progress bar while reading; Play opens the SF2 player.
3. Player: tempo 0.5×–2×, instrument chips, level meter, Sheet highlight, A–B loop, hand mute/solo.
4. Free quota: after 5 scans the same day, paywall appears (Music Reader Pro monthly/yearly). Restore Purchases.
5. Optional: Settings → confirm no account; Developer section still hidden behind version taps.

Report crashes, wrong MIDI, quota/paywall bugs, and slow recognition.
Photos must never leave the device; only anonymous usage events go to telemetry.
```

Pro unlocks **unlimited scans** only (instruments are not Pro-gated in code).

## Task 1: Telemetry Client (iOS)

### 1a. Port Analytics.swift

Copy `~/workspace/photo-recipes/ios/PhotoRecipes/Services/Analytics.swift`
to `~/workspace/omr-sheet-cam/Sources/App/Services/Analytics.swift`.

Changes required:
- The `APIClient` dependency: OMR app has no APIClient. Replace with
  direct URLSession POST to `https://photo.grepawk.com/api/telemetry`.
- Set `app: "omr-sheet-cam"` in every event payload (the server uses
  the `app` field to distinguish; defaults to `photo-recipes`).
- Keep the same anon_id/session_id logic (UserDefaults keys can stay
  the same — different app sandbox, no collision).
- Keep the same sanitization: never send photos, base64, email, GPS.

### 1b. Wire bootstrap

Call `Analytics.shared.bootstrap()` from the app's entry point
(find the `@main` App struct in Sources/App/).

### 1c. Add OMR-specific events

Track these events at the appropriate call sites:
- `app_open` (already in bootstrap)
- `scan_start` — user taps scan/capture
- `scan_success` — reading completes, MIDI generated
- `scan_fail` — reading fails (include error type in props)
- `playback_start` — user taps play
- `paywall_view` — paywall shown
- `purchase_start`, `purchase_success`, `purchase_fail`

### 1d. Admin panel: add app filter

The ProTune admin panel (`server/admin.ts` `telemetrySummary()`) currently
aggregates all apps. Add an `app` breakdown:

In `telemetrySummary()`, add:
```sql
SELECT app, COUNT(*) AS c FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
GROUP BY app ORDER BY c DESC
```
Expose as `appSplit` in the returned object.

In `src/pages/Admin.tsx`, add an app filter dropdown above the
telemetry section. When an app is selected, append `?app=<name>` to
the telemetry API calls and filter all queries by `app`.

This is a ProTune repo change (`~/workspace/photo-recipes`), not OMR.
Push to photo-recipes main after verifying.

## Task 2: In-App Purchase (StoreKit 2)

### 2a. Product IDs

OMR app product IDs (must be created in App Store Connect):
- `com.ragnus.vp.pro.monthly`
- `com.ragnus.vp.pro.yearly`

Note: These do NOT exist yet. The user must create them in
App Store Connect → AI Camera - Music Reader → Subscriptions.
Do NOT proceed with IAP testing until confirmed.

### 2b. Port StoreKitManager.swift

Copy `~/workspace/photo-recipes/ios/PhotoRecipes/Services/StoreKitManager.swift`
to `~/workspace/omr-sheet-cam/Sources/App/Services/StoreKitManager.swift`.

Changes required:
- Update `IAPProductID`:
  ```swift
  static let monthly = "com.ragnus.vp.pro.monthly"
  static let yearly = "com.ragnus.vp.pro.yearly"
  ```
- Remove the `APIClient` and `EntitlementsStore` dependencies if OMR
  doesn't have them. Replace server-side entitlement sync with
  on-device UserDefaults persistence (simple `isPro` boolean + 
  transaction ID for restore).
- Keep `loadProducts()`, `purchase()`, `listenForTransactions()`,
  restore purchases.

### 2c. Port PaywallView.swift

Copy `~/workspace/photo-recipes/ios/PhotoRecipes/Features/Paywall/PaywallView.swift`
to `~/workspace/omr-sheet-cam/Sources/App/Features/Paywall/PaywallView.swift`.

Changes required:
- Update copy for OMR context:
  - Free: 5 scans/day
  - Pro: unlimited scans, premium voices, priority processing
- Update pricing display to use the OMR product IDs
- Keep the same layout pattern (ProTune's paywall is the reference)

### 2d. Free tier enforcement

Add a scan counter:
- UserDefaults key: `omr.freeScansUsed`
- UserDefaults key: `omr.freeScansDate` (reset daily)
- Limit: 5 scans per day for free users
- When limit hit and not Pro: show PaywallView
- Pro users: no limit

Add `paywall_trigger` event when paywall is shown due to quota,
and `free_quota_hit` event when the free limit is reached.

### 2e. StoreKit configuration file

Create `~/workspace/omr-sheet-cam/OMRSheetCam.storekit` for local testing:
```json
{
  "products": [
    {
      "id": "com.ragnus.vp.pro.monthly",
      "type": "autoRenewableSubscription",
      "price": 4.99,
      "locale": "en_US"
    },
    {
      "id": "com.ragnus.vp.pro.yearly",
      "type": "autoRenewableSubscription",
      "price": 29.99,
      "locale": "en_US"
    }
  ]
}
```
Reference it in the Xcode scheme for debug builds.

## Task 3: Build & TestFlight

After Task 1 and 2 are complete and CI is green:

1. Bump build number (currently 17, next is 18)
2. Dispatch `ios-testflight.yml` workflow on main with:
   - `marketing_version: "1.0"`
   - Build will auto-increment
3. Use the TestFlight copy above for the "What to Test" field
4. Verify the build uploads successfully

## Acceptance Criteria

- [ ] Analytics events from OMR app appear in photo.grepawk.com/admin
      with app="omr-sheet-cam"
- [ ] Admin panel has working app filter dropdown
- [ ] Paywall shows correct monthly/yearly prices from StoreKit
- [ ] Sandbox purchase unlocks Pro (unlimited scans)
- [ ] Free tier correctly limits to 5 scans/day
- [ ] Pro status persists across app restarts
- [ ] `paywall_trigger` and `free_quota_hit` events fire correctly
- [ ] CI green on omr-sheet-cam main
- [ ] TestFlight build 18+ uploaded successfully

## Notes

- The OMR app currently has NO server. Telemetry POSTs to the
  ProTune server (photo.grepawk.com). This is intentional — one
  admin panel for all apps.
- IAP products must be created in ASC before testing. This is a
  manual user step.
- Do NOT modify the ProTune app's telemetry or IAP code.
- Follow the repo's AGENTS.md: token efficiency, no redundant explanations.
