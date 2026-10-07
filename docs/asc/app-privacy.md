# App Privacy answers — AI Camera - Music Reader (`com.ragnus.vp`)

Manual App Store Connect nutrition-label answers. The public ASC API has no supported
endpoint for App Privacy (iris probes failed previously). Enter these in the ASC **web UI**:
**App Privacy → Edit → answer each type → Publish.**

Sources of truth: `Sources/App/Resources/PrivacyInfo.xcprivacy`, `docs/asc/web/privacy.html`,
and `Sources/App/Services/Analytics.swift` / `StoreKitManager.swift`.

## Status vs live product page

As of 2026-10-06 the listing/docs previously claimed **"Data Not Collected"**. That is
**incorrect** for tip-of-main (first-party telemetry + StoreKit IAP). Update the ASC console
before submitting any binary that includes Analytics/StoreKit (everything after the IAP
commits on main; **not** App Review build 15).

Build **15** (still in review): no telemetry/IAP in that binary — do **not** pull/cancel it
for this doc change. When you next submit a newer build, publish the answers below first.

## Step 1 — Collect data?

**Yes, we collect data from this app.**

## Step 2 — Data types to tick

| Category | Data type | Who / what |
|---|---|---|
| Usage Data | **Product Interaction** | First-party telemetry (`app_open`, `scan_*`, `paywall_*`, `purchase_*`) → `photo.grepawk.com/api/telemetry` |
| Identifiers | **Device ID** | Anonymous UUID (`telemetry.anonId` in UserDefaults), sent with events |
| Purchases | **Purchase History** | StoreKit 2 Pro subscription entitlement; product id on purchase funnel events |

Leave unticked: Contact Info, Health, Location, Sensitive Info, Contacts, User Content
(**Photos or Videos** — processed on-device only, never uploaded), Diagnostics (no third-party
crash SDK beyond optional Apple Opt-In), Advertising Data, etc.

## Step 3 — Per type

| Data type | Purposes | Linked to identity? | Used for Tracking? |
|---|---|---|---|
| Product Interaction | Analytics | **Yes** (anon id) | **No** |
| Device ID | Analytics | **Yes** | **No** |
| Purchase History | App Functionality; Analytics | **Yes** | **No** |

Tracking = No: no third-party advertising SDKs, no ATT, empty `NSPrivacyTrackingDomains`,
`NSPrivacyTracking=false` in the privacy manifest.

## Resulting label (expected)

- **Data Used to Track You:** none
- **Data Linked to You:** Identifiers, Purchases, Usage Data
- **Data Not Linked to You:** none required for the types above

## Also before next submit

- Privacy Policy URL: `https://grepawk.com/music-reader/privacy.html` (redeploy from
  `docs/asc/web/privacy.html` if the live page still says “no analytics / no IAP”).
- Support URL: `https://grepawk.com/music-reader/support.html`
- Confirm ASC subscription products `com.ragnus.vp.pro.monthly` / `com.ragnus.vp.pro.yearly`
