# App Privacy checklist — do the ASC answers need changing? (2026-10-17, main b206c7b + this PR)

Reviewed: `docs/asc/web/privacy.html`, `Sources/App/Services/Analytics.swift`, `StoreKitManager.swift` /
`PurchaseOutcome.swift`, every `Analytics.shared.track` call site (incl. PRs #58 purchase/restore terminal
events and #66 post-scan upgrade card), `Sources/App/Resources/PrivacyInfo.xcprivacy`, and the current
answers in `docs/asc/app-privacy.md`. Analytics are first-party and anonymous per the owner: no account,
no email/name, random per-install UUID.

## Verdict

**Data types: no change.** #58 and #66 only add new *events* (purchase_cancel/pending/fail, restore_*,
paywall_dismiss, upgrade_card_view/dismiss, paywall_trigger/free_quota_hit/paywall_plan_select) inside the
same three data types already in `app-privacy.md` (Product Interaction, Device ID, Purchase History).
The locked-feature Transpose upsell (#69) adds only a `reason=feature_transpose` value. No new network
endpoint: the only outbound call in the app is `POST https://photo.grepawk.com/api/telemetry`
(`grep URLSession` finds only `Analytics.swift`). Photos, camera frames, MIDI and scores never leave the device.

**Two answers need a human decision/confirmation before the next submit** (see "Open items").

## What the app collects (matches the ASC answers)

| ASC data type | What it is in code | Collected? | Purposes | Linked to user? | Tracking? |
|---|---|---|---|---|---|
| Usage Data > Product Interaction | `app_open`, `session_start`, `scan_start/success/fail`, `paywall_*`, `free_quota_hit`, `upgrade_card_*`, `purchase_*`, `restore_*` | Yes | Analytics | see open item 1 | No |
| Identifiers > Device ID | random UUID `telemetry.anonId` (+ `session_id`, 30 min TTL) in UserDefaults, sent with every event | Yes | Analytics | see open item 1 | No |
| Purchases > Purchase History | product id (`com.ragnus.vp.pro.*`) and outcome on purchase/restore events; on-device Pro flag | Yes | Analytics, App Functionality | see open item 1 | No |
| Diagnostics > Performance Data | `scan_success.ms` (scan duration) and `notes` (count) props | Arguably; see open item 2 | Analytics | see open item 1 | No |

Not collected (leave unticked): Contact Info, Health & Fitness, Financial Info, Location, Sensitive Info,
Contacts, User Content (Photos or Videos / Audio / Other: processed on-device only), Search History,
Browsing History, Identifiers > User ID, Advertising Data, Crash Data (only Apple's opt-in reports, not our collection).
Payment details are handled by Apple, not the app.

## Tracking

**No.** No third-party SDKs, no ads, no data broker sharing, no linking with other companies' data,
`NSPrivacyTracking=false`, `NSPrivacyTrackingDomains` empty, no ATT prompt/`NSUserTrackingUsageDescription`.
Keep "Data Used to Track You: none".

## Open items (human)

1. **Linked vs. not linked: docs disagree.** `PrivacyInfo.xcprivacy` declares all three types
   `Linked = true`; `app-privacy.md` says "Linked: No". Apple treats data as *not linked* only if it is
   de-identified before collection (no user id / device id attached). Our events carry a persistent
   per-install UUID, so the conservative, defensible answer is **Linked to You = Yes** for Product
   Interaction, Device ID and Purchase History (still **Tracking = No**), and the label would read
   "Data Linked to You: Identifiers, Purchases, Usage Data". Answering "No" is only safe if the owner is
   comfortable asserting the UUID cannot be tied to a person/device on the server. Whichever is chosen,
   make the ASC console, `PrivacyInfo.xcprivacy` and `app-privacy.md` say the same thing (mismatch is a
   review/audit risk). Not changed in this PR (owner call); `app-privacy.md` carries a pointer to this file.
2. **Performance Data (optional but conservative):** scan duration (`ms`) is an app performance
   measurement. If you want zero ambiguity, also tick Diagnostics > Performance Data (Analytics, same
   linked/tracking answers) and add `NSPrivacyCollectedDataTypePerformanceData` to the manifest.
3. **Server side (cannot verify from this repo):** confirm photo.grepawk.com does not store raw IP
   addresses long-term or join events to anything identifying (email, Apple ID, ad ids); if it does,
   the answers above (and "anonymous" in the policy) need revisiting. Also confirm the retention period.
4. **Publish the answers in ASC web UI before submitting** (App Privacy > Edit > Publish). The API
   can't do it. `app-privacy.md` said the old page claimed "Data Not Collected": verify the live
   state; it must show Data Collected.
5. **Redeploy `docs/asc/web/privacy.html` and `support.html` to grepawk.com/music-reader/** (this PR
   edits both). The live page must be reachable and match the app before review.

## privacy.html review

Accurate: first-party endpoint, anon id + session id, events list (purchase/restore/paywall/upgrade card),
no photos/MIDI/email/location, Apple processes IAP, no ads/tracking, no account, crash reports opt-in.

Edited in this PR (small, no new practices): effective date 2026-10-17; added locked-feature (Pro-only
feature tap), free-scan-limit and plan-selected events; scan duration / note count props; Pro entitlement
now "unlimited scans and Transpose".

Still to consider (owner): the policy says "playback-related funnel steps" but no playback events are
sent (harmless, can be removed); no data retention/deletion contact statement (mailbox is given);
no mention of server IP handling (item 3).
