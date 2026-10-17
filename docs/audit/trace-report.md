# SheetCam / AI Camera – Music Reader — code trace report

- Repo: `yishengjiang99/omr-sheet-cam`, traced at **HEAD `736d0f6`** (`blog: SEO checklist in AGENTS.md; backfill keyword/image_alt front matter`, 2026-10-13). `git fetch` run; tree clean, `main` up to date with `origin/main`; no pull/checkout needed. Code read from `/workspace/omr-sheet-cam` only (read-only; `/workspace/omr-ios-wt` untouched; nothing filed on GitHub).
- Method: static read of `Sources/App/**`, SF2Player package entry points, `OMRSheetCam.xcodeproj` (pbxproj + shared scheme), `OMRSheetCam.storekit`, `Tests/**`, ASC docs and the live privacy page. **No Xcode/simulator on the box, so nothing was run**; runtime-only items are marked RT.
- Duplicate check: `gh issue list -R yishengjiang99/omr-sheet-cam --state all --limit 200 --json number,title,labels,state` returned `[]` (re-run at end of trace) — **no existing issues, so no duplicates**.
- Draft issues: `/workspace/omr-audit/issues/` (27 bug drafts + 6 enhancement drafts). Generators: `/workspace/omr-audit/tools/`.

## 1. P-flow results (P1–P11, traced first)

| Step | Verdict | Evidence (file:line @736d0f6) | Issue draft | Test coverage |
|---|---|---|---|---|
| P1.1 Limit constant | OK | ScanQuota.swift:7 (freeDailyLimit=5); PaywallView.swift:16,107; notes.txt | - | none |
| P1.2 Fresh install state | OK | ScanQuota.swift:24-29,36 | - | none |
| P1.3 What consumes quota | OK | RootFlowView.swift:57-63 (one consume per handlePhoto); sample consumes (DEC) | F4.7 | none |
| P1.4 Quota taken before outcome | BUG | RootFlowView.swift:58; ScanQuota.swift:36 | P1.4 | none |
| P1.5 Boundary: scans 1–5 pass | OK | ScanQuota.swift:30,36 | - | none |
| P1.6 Boundary: 6th scan blocked | OK | ScanQuota.swift:30-35 | - | none |
| P1.7 Every further attempt re-triggers | OK | ScanQuota.swift:31-34 (events per attempt; inflation noted) | - | none |
| P1.8 Day rollover | BUG | ScanQuota.swift:15-19 (no POSIX locale/calendar) | P1.8 | none |
| P1.9 Clock / time-zone manipulation | DEC | ScanQuota.swift:25-28 (client-side counter only) | - | none |
| P1.10 Visibility of remaining scans | GAP | ScanQuota.swift:40-45 scansRemaining never read | P1.10 | none |
| P1.11 Single Pro-check site | OK | rg isPro: ScanQuota.swift:23,41 + StoreKitManager only | - | none |
| P1.12 Duplicate manager | BUG | ScanQuota.swift:11; RootFlowView.swift:15 | P1.12 | none |
| P1.13 Where paywall can be opened | GAP | only presenter ScanQuota.swift:33; SettingsView.swift:57-67 has no Pro row | P1.10 | none |
| P2.1 Presentation | OK | PaywallView.swift:9-62; RootFlowView.swift:50-52 | - | PaywallScreenshotTests.swift (opt-in, skipped by default) |
| P2.2 Funnel event | OK | PaywallView.swift:55 | - | none |
| P2.3 Product request | OK | StoreKitManager.swift:46-60; PaywallView.swift:61 | - | PaywallScreenshotTests.swift (opt-in) |
| P2.4 Loaded UI | OK | PaywallView.swift:21-26,65-101 (R: price shown w/o billing period; verify with App Review - not drafted) | - | PaywallScreenshotTests.swift (asserts $4.99/$29.99; opt-in) |
| P2.5 Load failure / offline | BUG | StoreKitManager.swift:57-59; PaywallView.swift:27-41 | P2.5 | none |
| P2.6 Empty / partial result | OK | PaywallView.swift:21-26 (optionals); no region copy | - | none |
| P2.7 Loading state | BUG | PaywallView.swift:27 (isLoading false on first render; no spinner) | P2.5 | none |
| P2.8 Comparison + legal | OK | PaywallView.swift:103-142 | - | none |
| P2.9 Dismiss | OK | RootFlowView.swift:50; PaywallView.swift:57-59 (no paywall_dismiss event -> P10.2) | P10.2 | none |
| P2.10 Layout / a11y | RT | PaywallView.swift:10-52 ScrollView; Dynamic Type/iPad need device | - | none |
| P2.11 Copy accuracy | OK | PaywallView.swift:103-120 vs AppSettings.swift:12-25 (copy matches: all features free) | - | none |
| P3.1 Tap Subscribe | OK | PaywallView.swift:80-96; StoreKitManager.swift:62-66 | - | none |
| P3.2 Apple sheet | RT | Apple sheet text depends on ASC/localization | - | none |
| P3.3 Verified success | OK | StoreKitManager.swift:68-76; PaywallView.swift:83-84 | - | none |
| P3.4 Unverified success | BUG | StoreKitManager.swift:71,86-90,153-160 | P4.2 | none |
| P3.5 Immediate unlock | OK | ScanQuota.swift:23 reads defaults each call | - | none |
| P3.6 Success feedback | GAP | PaywallView.swift:83-84 silent dismiss; no Pro UI anywhere | P1.10 | none |
| P3.7 Resume interrupted intent | BUG | RootFlowView.swift:57-63 | P3.7 | none |
| P3.8 Concurrent listener | OK | StoreKitManager.swift:105-122 idempotent; double listener via P1.12 | P1.12 | none |
| P3.9 App killed after payment, before `purchase()` returns | RT | needs SKTestSession S17 (Transaction.unfinished/currentEntitlements at launch) | - | none |
| P3.10 Plan change | GAP | no manageSubscriptionsSheet anywhere (rg) | P1.10 | none |
| P3.11 Purchase while not signed into App Store | RT | StoreKit sign-in prompt behavior | - | none |
| P4.1 User cancels Apple sheet | OK | StoreKitManager.swift:77-78 (no event -> P10.2) | P10.2 | none |
| P4.2 Payment error (declined card, network, `notAvailableInStorefront`, `purchaseNotAllowed`, parental restriction) | BUG | StoreKitManager.swift:86-90 raw localizedDescription, reason always "error" | P4.2 | none |
| P4.3 Unknown result | BUG | StoreKitManager.swift:83-84 silent | P4.2 | none |
| P4.4 Double-tap / rapid retry | OK | PaywallView.swift:94 .disabled(isPurchasing) | - | none |
| P4.5 Error state clearing | OK | StoreKitManager.swift:48,64,95 | - | none |
| P4.6 Interrupted purchase (payment method needs attention / 2FA) | RT | needs Xcode Interrupted Purchase (S9) | - | none |
| P4.7 Free tier intact | OK | failure paths do not touch counters/flag | - | none |
| P5.1 `.pending` returned | BUG | StoreKitManager.swift:79-82; PaywallView.swift:35-41 | P5.1 | none |
| P5.2 Approved while app is running | BUG | StoreKitManager.swift:105-118; isPro not @Published (:34-36) | P5.1 | none |
| P5.3 Approved while app is closed | RT | S8; listener+currentEntitlements at launch | - | none |
| P5.4 Declined | GAP | no declined signal / message clearing | P5.1 | none |
| P5.5 Child account can't see scans | OK | ScanQuota.swift:30-35 unchanged while pending | - | none |
| P6.1 Discoverability | BUG | PaywallView.swift:43-47 only Restore; SettingsView.swift:57-67 | P6.1 | none |
| P6.2 In progress | BUG | StoreKitManager.swift:94; PaywallView.swift:43-47 (isLoading not rendered, button enabled) | P6.3 | none |
| P6.3 Restore succeeds | BUG | StoreKitManager.swift:93-103 silent | P6.3 | none |
| P6.4 Nothing to restore | BUG | StoreKitManager.swift:124-141 silent no-op | P6.3 | none |
| P6.5 Sync failure / user cancels Apple ID prompt | BUG | StoreKitManager.swift:100-102 cancel shown as "Restore failed" | P6.3 | none |
| P6.6 Offline restore | RT | offline restore message (S10) | P6.3 | none |
| P6.7 Restore with expired sub | OK | StoreKitManager.swift:131 expired excluded by currentEntitlements; message missing (P6.3) | P6.3 | none |
| P6.8 Telemetry | GAP | no restore events (rg) | P10.2 | none |
| P7.1 Launch-time check | OK | StoreKitManager.swift:23-28,124-141 (stale flag until refresh finishes) | P7.4 | none |
| P7.2 Unverified entitlement | OK | StoreKitManager.swift:129-136 | - | none |
| P7.3 Renewal while running | RT | renewal via Transaction.updates (S13) | - | none |
| P7.4 **Expiry while the app stays alive** | BUG | StoreKitManager.swift:23-28,105-141; ScanQuota.swift:23 | P7.4 | none |
| P7.5 Expiry then relaunch | OK | via P7.1 | - | none |
| P7.6 Refund / revocation | BUG | StoreKitManager.swift:113-115 | P7.6 | none |
| P7.7 Listener grants without checking dates | BUG | StoreKitManager.swift:110-112 (no expirationDate/isUpgraded check) | P7.6 | none |
| P7.8 Auto-renew off (user cancelled) | OK | StoreKit semantics; no in-app notice | - | none |
| P7.9 Billing retry / grace period | RT | grace period (S15) | - | none |
| P7.10 Offline | RT | currentEntitlements offline (S18) | - | none |
| P7.11 Tamper resistance | DEC | plaintext UserDefaults flag (StoreKitManager.swift:34-36,140); documented no server verification | - | none |
| P7.12 Multiple Apple IDs / account switch mid-session | GAP | no account-change handling | P7.4 | none |
| P8.1 Delete + reinstall (same Apple ID, active sub) | RT | S16 reinstall sync | - | none |
| P8.2 Reinstall when auto-sync didn't return entitlement | BUG | Restore only in paywall | P6.1 | none |
| P8.3 Counter after reinstall | DEC | UserDefaults counter (ScanQuota.swift:25-36) | - | none |
| P8.4 New device, same Apple ID | RT | new device | - | none |
| P8.5 iCloud/iTunes backup restore to a device with different Apple ID | OK | StoreKitManager.swift:140 overwrite at launch | P7.4 | none |
| P8.6 Offline reinstall | RT | offline reinstall | - | none |
| P8.7 Library after reinstall | GAP | no export/sync of Library | - | none |
| P9.1 Scope of Pro | OK | rg isPro: ScanQuota + StoreKitManager only | - | none |
| P9.2 Unlock latency | OK | ScanQuota.swift:23 | - | none |
| P9.3 Lock triggers | BUG | lazy lock (StoreKitManager.swift:23-28) | P7.4 | none |
| P9.4 UI differentiation | GAP | no Pro UI (SettingsView.swift:57-67) | P1.10 | none |
| P9.5 Content kept after lapse | OK | gate only in RootFlowView.swift:57-63 | - | none |
| P9.6 Mid-scan lapse | OK | no re-check after gate | - | none |
| P9.7 Counter semantics after lapse | OK | ScanQuota.swift:25-28 | - | none |
| P10.1 Event sequence | OK | ScanQuota.swift:31-32; PaywallView.swift:55,82; StoreKitManager.swift:66,75,81,88 | - | none |
| P10.2 Missing terminal events | BUG | StoreKitManager.swift:77-84,93-103 | P10.2 | none |
| P10.3 Prop filter | BUG | Analytics.swift:53 | P10.3 | none |
| P10.4 No PII | OK | payloads carry product id only | - | none |
| P10.5 Disclosures consistent | RT | ASC App Privacy status external; in-app/manifest/web agree (privacy page fetched 2026-10-17) | - | none |
| P10.6 Subscription disclosure | OK | PaywallView.swift:133-142 | - | none |
| P10.7 Offline telemetry | OK | Analytics.swift:212-230 errors swallowed | - | none |
| P11.1 Reviewer reaches paywall as documented | BUG | LibraryScreen.swift:69-79; notes.txt | P11.1 | none |
| P11.2 Sandbox purchase in review | RT | ASC review state external | - | none |
| P11.3 StoreKit config wiring | BUG | OMRSheetCam.xcscheme:43-63; project.pbxproj | P11.3 | none |
| P11.4 Automated coverage | GAP | no tests for ScanQuota/StoreKitManager; only PaywallScreenshotTests | - | none |
| P11.5 Pricing parity | RT | ASC live prices external; config/doc parity only | - | PaywallScreenshotTests.swift (opt-in) |

Verdict legend: **OK** = code meets the acceptance check; **BUG** = confirmed defect (draft issue); **GAP** = feature/behavior absent in code (no code to trace); **DEC** = by design / product decision; **RT** = cannot be proven statically (needs device/StoreKit session).

## 2. Candidate leads (18 from bug-template.md) — verdicts

| # | Step(s) | Lead | Verdict | One-line evidence | Draft |
|---|---|---|---|---|---|
| 1 | P7.4 | Pro not re-checked on foreground/expiry | CONFIRMED | `refreshEntitlements` only from `StoreKitManager.init` (:23-28); gate reads cached flag (`ScanQuota.swift:23`); listener ignores expiry (:105-122) | P7.4 |
| 2 | P7.6 | `revokePro()` ignores other entitlements | CONFIRMED | listener revokes unconditionally (`StoreKitManager.swift:113-115`); grant has no expiry/isUpgraded check (:110-112) | P7.6 |
| 3 | P6.1–P6.4 | Restore only in paywall; no feedback | CONFIRMED | single call site `PaywallView.swift:43-47`; `restore()` returns Void, `isLoading` unrendered, errors raw (`StoreKitManager.swift:93-103`); Settings has no row (`SettingsView.swift:57-67`) | P6.1, P6.3 |
| 4 | P1.4 | Quota consumed before outcome | CONFIRMED | increment at `ScanQuota.swift:36` via `RootFlowView.swift:58`; ResultScreen has no refund (:245-271) | P1.4 |
| 5 | P3.7 | Photo discarded when paywall shown | CONFIRMED | `handlePhoto` drops `CapturedPhoto` when gate false (`RootFlowView.swift:57-63`); camera shots not saved until ResultScreen | P3.7 |
| 6 | P5.1/P5.2 | Pending shown as error; approval not reflected | CONFIRMED | pending -> `purchaseError` red box + `purchase_fail` (`StoreKitManager.swift:79-82`); `isPro` not @Published (:34-36) | P5.1 |
| 7 | P2.5/P2.7 | Duplicate error text, no retry, flash | CONFIRMED | catch sets purchaseError (:57-59) + empty-state line (`PaywallView.swift:27-41`); `isLoading` false on first render; no retry/spinner | P2.5 |
| 8 | P11.3 | `.storekit` not attached to scheme/project | CONFIRMED | scheme `LaunchAction` (xcscheme:43-63) has no StoreKitConfigurationFileReference; pbxproj has no `.storekit` reference; only `PaywallScreenshotTests` loads it | P11.3 |
| 9 | P1.12 | Two StoreKitManager instances | CONFIRMED | `ScanQuota.swift:11` and `RootFlowView.swift:15`; also `[weak self]` loop retains self (`StoreKitManager.swift:24-26`) | P1.12 |
| 10 | P10.3 | Analytics key filter drops `platform` (`lat`) | CONFIRMED (low impact) | regex at `Analytics.swift:53` matches `platform`; `app_open` props lose it (:44-47); top-level `platform` still sent (:64) | P10.3 |
| 11 | F6.4/F6.8 | Cancel doesn't stop parse; late save/orphan JPEG | CONFIRMED | Cancel = `dismiss()` (`ResultScreen.swift:58`); no `Task.isCancelled` in ResultScreen (rg); cancel only checked while queued (`PageRecognitionService.swift:214`); `saveToPlaylist` at `ResultScreen.swift:269` | F6.8 |
| 12 | F2.7 | Capture JPEG not deleted with scan | CONFIRMED | `PlaylistStore.delete` removes `.mid`+layout only (:158-168); privacy page says deleting removes scans | F2.7 |
| 13 | F2.9 | Corrupt index silently empties Library | CONFIRMED | `loadIndex` returns [] (`PlaylistStore.swift:98-105`), next `saveIndex` overwrites (:115-121); test comment enshrines it (`PlaylistStoreTests.swift:105-121`) | F2.9 |
| 14 | F5.5/F9.5 | "Retake" returns to Library, not Camera | CONFIRMED | camera route removed `RootFlowView.swift:60`; Retake = `dismiss()` (`ResultScreen.swift:66-71,139-142`) | F5.5 |
| 15 | F10.10 | No background audio / Now Playing | CONFIRMED (static; stop-on-lock needs device) | no UIBackgroundModes in pbxproj:678-687 and no plist file; `.playback` session only (`SF2MIDIPlayer.swift:236-241`); rg MPNowPlaying/MPRemoteCommand = none | F10.10 |
| 16 | P11.1 | Review notes' "Try sample ×6" impossible on Library home | CONFIRMED (workaround exists) | button only when `scans.isEmpty` (`LibraryScreen.swift:69-79`); Camera has persistent button (`CameraScreen.swift:48,153-164`); notes hint "or scan/import any photo" | P11.1 |
| 17 | F4.5 | PHAsset fallback without Photos authorization | CONFIRMED statically, runtime unproven (verdict `?`) | fallback `PhotoLibraryImport.swift:36-62`; rg requestAuthorization/PHPhotoLibrary in Sources = none | F4.5 |
| 18 | F8.7 | "Feedback saved" never leaves device | CONFIRMED | `save()` writes `DiagnosticsLog` only (`OMRCompareView.swift:260-274`) | F8.7 |

**Totals: 18 leads — 18 confirmed (1 with `?`/runtime caveat: F4.5), 0 rejected.** Notes that tempered leads: P10.3 impact limited (top-level platform still sent); P11.1 has a workaround path; F2.9's behavior is asserted as intended in an existing test; F10.10 and F4.5 need a device to prove the user-visible effect.

The 10 high-risk leads you named map to: P7.4, P6.1/P6.3, P1.4 + P3.7, F6.8, P11.3, P1.12, F2.7, F2.9, F10.10, P11.1 — all confirmed.

## 3. Confirmed bugs, severity-ordered (P-flow first at equal severity)

| # | Sev | Draft file | Title | One-line |
|---|---|---|---|---|
| 1 | P1 | `issues/P1.4-quota-consumed-before-scan-succeeds.md` | [P1.4] A free scan is charged before recognition runs, so failed/cancelled/reader-not-ready scans burn 1 of 5 | revenue/trust-affecting - users are pushed to the paywall by app-side failures and cancels. |
| 2 | P1 | `issues/P3.7-photo-discarded-after-paywall-purchase.md` | [P3.7] Photo that hit the paywall is discarded after purchase; user must re-shoot | data loss of the user's capture at the exact moment of conversion (rubric: data loss) and a bad first-paid experience; scoped to one photo, so P1 not P0. |
| 3 | P1 | `issues/P6.1-restore-only-reachable-from-paywall.md` | [P6.1] Restore purchases is only reachable from the paywall (no Settings entry) | restore unreachable for most users; App Review risk; support burden. |
| 4 | P1 | `issues/P7.4-pro-not-rechecked-after-expiry.md` | [P7.4] Pro stays unlocked after subscription expires until the app is relaunched | revenue leak - lapsed users keep unlimited scans for as long as the process lives. |
| 5 | P1 | `issues/F2.7-delete-scan-leaves-captured-photo-on-disk.md` | [F2.7] Deleting a scan leaves its captured photo (Documents/captures/*.jpg) on disk, contradicting the privacy policy | privacy statement violated per rubric (P0 definition); downgraded to P1 here because data stays in the app sandbox on the user's own device - raise to P0 if you want to follow the rubric literally. |
| 6 | P2 | `issues/P1.10-no-pro-status-remaining-scans-or-purchase-confirmation-ui.md` | [P1.10] No remaining-scans counter, no Pro status/confirmation, and no way to open the paywall voluntarily | conversion/UX gap with workarounds. |
| 7 | P2 | `issues/P11.1-review-notes-try-sample-button-vanishes.md` | [P11.1] App Review notes say to repeat "Try sample picture" on Library home, but the button disappears after the first scan | App Review friction/possible rejection, but a workaround path exists and is hinted. |
| 8 | P2 | `issues/P11.3-storekit-config-not-attached-to-scheme.md` | [P11.3] OMRSheetCam.storekit is not attached to the Run scheme or project, so Xcode runs cannot load products | blocks local verification of the entire P-flow suite (S-cases) and screenshots; no end-user impact. |
| 9 | P2 | `issues/P2.5-paywall-load-failure-duplicate-errors-no-retry-and-flash.md` | [P2.5] Paywall product-load failure shows two messages, no Retry, and an error flashes before loading starts | misleading on every first paywall presentation; the only recovery is dismissing and re-triggering. |
| 10 | P2 | `issues/P5.1-pending-purchase-shown-as-error-and-approval-not-reflected.md` | [P5.1] Ask-to-Buy "pending" is shown as a red error and later approval does not update the open paywall | misleading messaging on a rare path, with workaround (close paywall, scan). |
| 11 | P2 | `issues/P6.3-restore-has-no-progress-or-result-feedback.md` | [P6.3] Restore purchases gives no progress, success, "nothing to restore" or cancel-safe feedback | misleading/no feedback with workaround (relaunch / look at scan limit); mostly UX but hits review-critical flow. |
| 12 | P2 | `issues/P7.6-revoke-ignores-other-entitlements.md` | [P7.6] Refunding one subscription locks Pro even when another entitlement is still valid | edge case, paying user wrongly locked until relaunch; self-heals on relaunch. |
| 13 | P2 | `issues/F10.10-no-background-audio-or-now-playing.md` | [F10.10] Playback stops when the app is backgrounded or the screen locks (no UIBackgroundModes audio, no Now Playing/remote commands) | core-flow gap for a music app (leave phone on the piano, screen auto-locks); P2 because pieces are short and playback can resume. |
| 14 | P2 | `issues/F2.9-corrupt-or-unreadable-index-silently-empties-library.md` | [F2.9] Unreadable index.json silently empties the Library and the next save overwrites it for good | silent data loss but low trigger probability (atomic writes), so P2. |
| 15 | P2 | `issues/F5.5-retake-button-returns-to-library-not-camera.md` | [F5.5] "Retake" on Result/failure screens returns to Library instead of the Camera | UX friction with obvious workaround. |
| 16 | P2 | `issues/F6.8-cancel-does-not-cancel-recognition-late-save-and-orphan-jpeg.md` | [F6.8] Cancel on the Reading screen does not cancel the parse; zombie parse blocks the next scan and may add a Library entry later | confusing wrong behavior with workaround; also contributes to quota/privacy issues. |
| 17 | P3 | `issues/P1.12-two-storekitmanager-instances.md` | [P1.12] Two StoreKitManager instances (ScanQuota + RootFlowView) run duplicate listeners and entitlement refreshes | no user-visible failure today; complicates fixes for P7.4/P7.6 and doubles StoreKit work. |
| 18 | P3 | `issues/P1.8-quota-date-formatter-uses-device-calendar-locale.md` | [P1.8] Daily quota date string uses the device calendar/locale (no en_US_POSIX), so changing region/calendar can spuriously reset the quota | edge-case quota bypass; the quota is already trivially bypassable via clock (P1.9, product decision). |
| 19 | P3 | `issues/P10.2-funnel-missing-terminal-events.md` | [P10.2] Purchase funnel has no cancel/restore/dismiss/expiry events, and pending is logged as a failure | analytics gap only. |
| 20 | P3 | `issues/P10.3-analytics-filter-drops-platform-prop.md` | [P10.3] Analytics key filter regex matches "lat" in "platform" and silently drops it from event props | analytics gap only; no PII or user impact. |
| 21 | P3 | `issues/P4.2-raw-error-text-and-unverified-purchase-message.md` | [P4.2] Purchase errors show raw localizedDescription; unverified transactions are indistinguishable from other failures | copy/UX on failure paths. |
| 22 | P3 | `issues/F10.3-raw-swift-error-strings-shown-to-users.md` | [F10.3] Raw Swift error descriptions are shown to users (player load, save, delete, playlist) | polish. |
| 23 | P3 | `issues/F11.2-deleting-the-playing-scan-does-not-stop-playback.md` | [F11.2] Deleting the currently playing scan leaves playback/mini-player running on a deleted entry | edge case with workaround. |
| 24 | P3 | `issues/F4.5-photo-asset-fallback-without-photos-authorization.md` | [F4.5] iCloud-only photo fallback uses PHAsset without ever requesting Photos authorization | rare path; error is handled gracefully. |
| 25 | P3 | `issues/F4.7-library-try-sample-failure-is-silent-and-burns-quota.md` | [F4.7] Library "Try sample picture" failure is silent (log only) while Camera shows an error | cosmetic/edge. |
| 26 | P3 | `issues/F7.7-result-share-names-file-after-capture-timestamp.md` | [F7.7] Share MIDI from Result uses the capture timestamp as file name, unlike Library/Player which use the title | polish. |
| 27 | P3 | `issues/F8.7-feedback-saved-toast-but-feedback-never-leaves-device.md` | [F8.7] "Save feedback" / "Feedback saved" implies the report was submitted, but it is only written to the local diagnostics log | misleading copy, no data impact. |

## 4. Counts by severity

| Severity | Confirmed bug drafts | Rejected |
|---|---|---|
| P0 | 0 | 0 |
| P1 | 5 | 0 |
| P2 | 11 | 0 |
| P3 | 11 | 0 |
| **Total** | **27** | **0** |

Of the 27 drafts, 19 cover the 18 candidate leads (P6.1–P6.4 splits into 2 drafts; P2.5/P2.7, F6.4/F6.8, F5.5/F9.5, P5.1/P5.2 each merge into 1) and 8 are extra confirmed findings from the trace (P1.10, P1.8, P10.2, P4.2, F4.7, F11.2, F10.3, F7.7). Enhancement drafts (6) are counted separately in section 8.

Step-level tally (211 steps): OK 124, BUG 45, RT 25, GAP 13, DEC 4.

## 5. Flow steps with no code (feature absent / not implemented)

- **P1.10** Visibility of remaining scans — ScanQuota.swift:40-45 scansRemaining never read
- **P1.13** Where paywall can be opened — only presenter ScanQuota.swift:33; SettingsView.swift:57-67 has no Pro row
- **P3.6** Success feedback — PaywallView.swift:83-84 silent dismiss; no Pro UI anywhere
- **P3.10** Plan change — no manageSubscriptionsSheet anywhere (rg)
- **P5.4** Declined — no declined signal / message clearing
- **P6.8** Telemetry — no restore events (rg)
- **P7.12** Multiple Apple IDs / account switch mid-session — no account-change handling
- **P8.7** Library after reinstall — no export/sync of Library
- **P9.4** UI differentiation — no Pro UI (SettingsView.swift:57-67)
- **P11.4** Automated coverage — no tests for ScanQuota/StoreKitManager; only PaywallScreenshotTests
- **F12.6** Save photo — no Save-to-Photos feature (by design)
- **F13.7** Missing items — no Pro/Restore/Support/telemetry opt-out rows (SettingsView.swift:57-67)
- **F14.7** Localization — English-only strings (no Localizable)

## 6. Flow steps with no test

Test targets: `OMRSheetCamTests` only (14 test files + `PaywallScreenshotTests`); **there is no XCUITest target and no test for `ScanQuota`, `StoreKitManager`, `RootFlowView.handlePhoto`, `ResultScreen`, `LibraryScreen`, `SettingsView` actions, camera, or paywall behavior.** `PaywallScreenshotTests` is opt-in (skipped by default).

**Steps with NO covering test (155 of 211):**

- F1: F1.3
- F2: F2.2, F2.3, F2.5, F2.8
- F3: F3.1, F3.2, F3.3, F3.5, F3.6, F3.7, F3.9, F3.10, F3.11
- F4: F4.1, F4.2, F4.4, F4.5, F4.6
- F5: F5.1, F5.2, F5.3, F5.4, F5.5, F5.6
- F6: F6.3, F6.8, F6.9, F6.10
- F7: F7.3, F7.5, F7.6, F7.8
- F8: F8.1, F8.2, F8.3, F8.4, F8.5, F8.8
- F9: F9.5, F9.6, F9.7, F9.8
- F10: F10.1, F10.3, F10.7, F10.10, F10.12, F10.13
- F11: F11.1, F11.2
- F12: F12.2, F12.4, F12.5, F12.6
- F13: F13.1, F13.2, F13.4, F13.5, F13.7
- F14: F14.1, F14.2, F14.4, F14.5, F14.6, F14.7
- P1: P1.1, P1.2, P1.3, P1.4, P1.5, P1.6, P1.7, P1.8, P1.9, P1.10, P1.11, P1.12, P1.13
- P2: P2.2, P2.5, P2.6, P2.7, P2.8, P2.9, P2.10, P2.11
- P3: P3.1, P3.2, P3.3, P3.4, P3.5, P3.6, P3.7, P3.8, P3.9, P3.10, P3.11
- P4: P4.1, P4.2, P4.3, P4.4, P4.5, P4.6, P4.7
- P5: P5.1, P5.2, P5.3, P5.4, P5.5
- P6: P6.1, P6.2, P6.3, P6.4, P6.5, P6.6, P6.7, P6.8
- P7: P7.1, P7.2, P7.3, P7.4, P7.5, P7.6, P7.7, P7.8, P7.9, P7.10, P7.11, P7.12
- P8: P8.1, P8.2, P8.3, P8.4, P8.5, P8.6, P8.7
- P9: P9.1, P9.2, P9.3, P9.4, P9.5, P9.6, P9.7
- P10: P10.1, P10.2, P10.3, P10.4, P10.5, P10.6, P10.7
- P11: P11.1, P11.2, P11.3, P11.4

**Steps with a covering (or partially covering) test file** are listed in the last column of the per-step tables (sections 1 and 7).

## 7. Core flows F1–F15 — per-step results

| Step | Verdict | Evidence (file:line @736d0f6) | Issue draft | Test coverage |
|---|---|---|---|---|
| F1.1 Launch | OK | LibraryScreen.swift:53-67; RootFlowView.swift:19-24 | - | RedesignTests.swift (HowItWorksArt) |
| F1.2 `OMRSheetCamApp.init` | OK | OMRSheetCamApp.swift:7-14 (platform prop dropped -> P10.3) | P10.3 | Build6PrepTests.swift (legacy key cleared) |
| F1.3 XCTest guard | OK | OMRSheetCamApp.swift:14 | - | none |
| F1.4 Background warmup | OK | ModelWarmup.swift:106-143 | - | ModelWarmupTests.swift (testWarmupReachesReadyOffMainThread) |
| F1.5 Home render | OK | LibraryScreen.swift:68-101; PlaylistStore.swift:21,91-96 | - | PlaylistStoreTests.swift (testBundledSamplesAlwaysPresentAndPlayable); RedesignTests.swift |
| F1.6 Warmup state at first scan | OK | ReadingView.swift; PageRecognitionService.swift:252-262 | - | PageRecognitionServiceTests.swift (testRecognitionProgressForwardsWarmupETA, testReadingViewSubtitleFallback) |
| F1.7 Warmup failure (models missing/bad) | OK | ModelWarmup.swift:88-99,132-139; ScanFailure.swift:31-32,67 (quota burn -> P1.4) | P1.4 | PageRecognitionServiceTests.swift (testSessionFactoryErrorGivesFailedOutcomeAndLogsError); Build16Tests.swift (classify) |
| F1.8 Memory-warning mid-session | OK | PageRecognitionService.swift:130-134; ModelWarmup.swift:158-168 | - | PageRecognitionServiceTests.swift (testMemoryWarningDropsSessionAndNextParseRebuilds) |
| F2.1 Home layout | OK | LibraryScreen.swift:55-67,107-137 | - | RedesignTests.swift (partial) |
| F2.2 Empty state | BUG | LibraryScreen.swift:69-79 (button only when empty) | P11.1 | none |
| F2.3 Row rendering | OK | LibraryScreen.swift:248-282; PlaybackController.swift:77-80 (sync JPEG read per row [RT jank]) | - | none |
| F2.4 Search | OK | PlaylistStore.swift:185-188 | - | PlaylistStoreTests.swift (testRenameAndSearch) |
| F2.5 Row actions | OK | LibraryScreen.swift:83-89 (no confirm/undo; playing row deletable -> F11.2) | F11.2 | none |
| F2.6 Rename | OK | LibraryScreen.swift:228-238; PlaylistStore.swift:174-182 | - | PlaylistStoreTests.swift (testRenameAndSearch) |
| F2.7 Delete | BUG | PlaylistStore.swift:158-168 | F2.7 | PlaylistStoreTests.swift (testDeleteRemovesFileAndIndexEntryButNotSamples - .mid only) |
| F2.8 Open row | OK | RootFlowView.swift:25-28 | - | none |
| F2.9 Index corruption | BUG | PlaylistStore.swift:98-121 | F2.9 | PlaylistStoreTests.swift (testReloadToleratesMissingFilesAndCorruptIndex - enshrines behavior) |
| F3.1 Open camera | OK | RootFlowView.swift:32-39; CameraScreen.swift:27-52 | - | none |
| F3.2 No camera (simulator/iPad w/o back wide) | OK | CameraScreen.swift:64-68; CameraController.swift:14,132-136 | - | none |
| F3.3 First permission prompt | OK | CameraScreen.swift:53; CameraController.swift:90-98 | - | none |
| F3.4 Live preview | RT | CameraController.swift:131-163 (rotation/upright capture needs device) | - | CaptureHelpersTests.swift (normalizedUpright only) |
| F3.5 Permission denied | OK | CameraScreen.swift:55-58,80-90; CameraController.swift:102-108 | - | none |
| F3.6 Restricted (MDM/Screen Time) | OK | CameraScreen.swift:91-95 | - | none |
| F3.7 Focus / torch | RT | CameraController.swift:111-117 (stop() clears torchOn flag but never calls setTorch(false) - hardware torch state needs device) | - | none |
| F3.8 Shutter | OK | CameraScreen.swift:174-182,216-226; CameraController.swift:208-232 | - | CaptureHelpersTests.swift (normalize, save) |
| F3.9 Capture failure | OK | CameraScreen.swift:218-224; CameraController.swift:211-214 | - | none |
| F3.10 Interruptions / app background | OK | CameraController.swift:36-64 (non-reset runtime error leaves message, no retry button - minor, not drafted) | - | none |
| F3.11 Leave camera | OK | CameraScreen.swift:54; RootFlowView.swift:36 | - | none |
| F4.1 Open picker | OK | LibraryScreen.swift:121,171; CameraScreen.swift:168 | - | none |
| F4.2 Pick | OK | LibraryScreen.swift:192-205 | - | none |
| F4.3 Decode | OK | PhotoLibraryImport.swift:25-32 (large-image memory [RT]) | - | Gray8ImageTests.swift (EXIF orientations); CaptureHelpersTests.swift |
| F4.4 Pick cancelled | OK | picker returns nil -> LibraryScreen.swift:153-155 | - | none |
| F4.5 iCloud-only photo | BUG | PhotoLibraryImport.swift:36-62 (no requestAuthorization anywhere; device test needed) | F4.5 | none |
| F4.6 Load errors | OK | LibraryScreen.swift:63-65,201; CameraScreen.swift:253 (Library importError never auto-cleared - minor) | - | none |
| F4.7 Try sample picture | BUG | RootFlowView.swift:66-76 (silent on Library); CameraScreen.swift:228-242 | F4.7 | PageRecognitionServiceTests.swift (testTrySamplePictureIsBundledAndDecodes, testTrySamplePictureRecognizesNotes) |
| F5.1 Receive photo | OK | RootFlowView.swift:23,38,57 | - | none |
| F5.2 Pro bypass | OK | ScanQuota.swift:23 | - | none |
| F5.3 Consume | BUG | ScanQuota.swift:24-37 (pre-charge) | P1.4 | none |
| F5.4 Blocked | BUG | ScanQuota.swift:30-34; photo dropped RootFlowView.swift:57-63 | P3.7 | none |
| F5.5 Navigate to Result | BUG | RootFlowView.swift:60; ResultScreen.swift:66-71 | F5.5 | none |
| F5.6 Midnight / time-zone change | DEC | ScanQuota.swift:15-19,25-28 (clock/timezone bypass; scansRemaining unused -> P1.10) | P1.8 | none |
| F6.1 Reading UI | OK | ReadingView.swift:41-110; RecognitionService.swift:213-219 | - | PageRecognitionServiceTests.swift (testRecognitionProgress*, testMonotonicProgress*) |
| F6.2 Persist capture | OK | ResultScreen.swift:206-243; CaptureStore.swift:38-54 | - | CaptureHelpersTests.swift (testSaveWritesUprightJPEGWithTimestampName) |
| F6.3 Telemetry | OK | ResultScreen.swift:248-256; Analytics.swift:212-230 | - | none |
| F6.4 Serialized parse | BUG | PageRecognitionService.swift:201-219 (queue; cancel only while queued) | F6.8 | PageRecognitionServiceTests.swift (testSessionBuiltOnceReusedAndParsesSerialized, testCancelledQueuedRecognizeSkipsParse) |
| F6.5 Decode | OK | PageRecognitionService.swift:231-243; ScanFailure.swift:28 | - | PageRecognitionServiceTests.swift (testUndecodableImageFailsWithoutBuildingSession); Gray8ImageTests.swift |
| F6.6 Warm-up wait | OK | PageRecognitionService.swift:252-262; RecognitionService.swift:213-219 (UX: bar resets) | - | PageRecognitionServiceTests.swift (testRecognitionProgressPhaseChangeResets) |
| F6.7 Parse | RT | PageRecognitionService.swift:275-285 (memory/jetsam on device; no parse timeout confirmed: no Task timeout anywhere) | - | PageRecognitionServiceTests.swift (testCScalePageFullParseOnWarmedSessions) |
| F6.8 Cancel | BUG | ResultScreen.swift:58,206-216,245-271 | F6.8 | none |
| F6.9 App backgrounded during parse | RT | no beginBackgroundTask (rg: none); effect needs device | - | none |
| F6.10 Rotation | RT | ReadingView.swift:82 | - | none |
| F7.1 Outcome recognized | OK | PageRecognitionService.swift:154-161 | - | PageRecognitionServiceTests.swift (testOutcomeMapping) |
| F7.2 Auto-save | OK | ResultScreen.swift:265-291; PlaylistStore.swift:127-155 | - | PlaylistStoreTests.swift (testAddScanWritesMIDIAndIndexAndAppends); Build16Tests.swift (testScanLayoutSidecarIsSavedLoadedAndDeleted) |
| F7.3 Summary | OK | ResultScreen.swift:46-50 | - | none |
| F7.4 Rename | OK | ResultScreen.swift:95-99,300-307 | - | PlaylistStoreTests.swift (testRenameAndSearch - store level) |
| F7.5 Save to Library | OK | ResultScreen.swift:310-315 (label implies action; no-op - minor, not drafted) | - | none |
| F7.6 Play | OK | ResultScreen.swift:171-190,318-325 | - | none |
| F7.7 Share MIDI | BUG | ResultScreen.swift:72-77 | F7.7 | Build16Tests.swift (MIDIExport names - not the Result path) |
| F7.8 Retake | BUG | ResultScreen.swift:66-71 | F5.5 | none |
| F8.1 Compare header | OK | OMRCompareView.swift:50-98,148 (developer jargon visible - minor) | - | none |
| F8.2 Overlay | RT | OMRCompareView.swift:109-128 alignment needs device | - | none |
| F8.3 Inspect | OK | OMRCompareView.swift:177-190 | - | none |
| F8.4 Mark wrong | OK | OMRCompareView.swift:208-214,243-247 | - | none |
| F8.5 List mode | OK | OMRCompareView.swift:79-87 | - | none |
| F8.6 Verdicts & note | OK | OMRCompareView.swift:228-253 | - | DiagnosticsTests.swift (testFeedbackEventRoundTrip - model only) |
| F8.7 Save feedback | BUG | OMRCompareView.swift:260-274 | F8.7 | DiagnosticsTests.swift (testFeedbackEventRoundTrip) |
| F8.8 Warnings | OK | OMRCompareView.swift:72-74 | - | none |
| F9.1 Failure outcomes | OK | PageRecognitionService.swift:154-161,307-311 | - | PageRecognitionServiceTests.swift (testOutcomeMapping, testParserErrorGivesFailed) |
| F9.2 Classification | OK | ScanFailure.swift:21-35 brittle substring match (model/session/onnx) - minor, not drafted | - | Build16Tests.swift (testScanFailureClassifiesPipelineMessages) |
| F9.3 Photo quality | OK | ScanFailure.swift:113-147; ResultScreen.swift:259-262 | - | Build16Tests.swift (testPhotoQualityMeasuresThumbnail) |
| F9.4 Message | OK | ResultScreen.swift:120-147 | - | Build16Tests.swift (testScanFailureTipsLeadWithPhotoSpecificAdvice) |
| F9.5 Retake photo | BUG | ResultScreen.swift:139-142 | F5.5 | none |
| F9.6 Try again | OK | ResultScreen.swift:87,200-205 (no quota use) | - | none |
| F9.7 Details | OK | ResultScreen.swift:145-147 | - | none |
| F9.8 Play a sample | OK | ResultScreen.swift:157,363-371 | - | none |
| F9.9 `.comingSoon` branch | OK | ResultScreen.swift:148-155 (dead copy) | - | CaptureHelpersTests.swift (testStubRecognitionReturnsComingSoon); Build6PrepTests.swift (testComingSoonGlyphIsNoneOrValidSymbol) |
| F9.10 Edge inputs | RT | needs fixtures/device (no tuplet/key-sig/multi-row fixtures) | - | PageRecognitionServiceTests.swift (oracle pages, partial) |
| F10.1 Open | OK | PlayerView.swift:82,106-108; PlaybackController.swift:253-261 | - | none |
| F10.2 Load | OK | PlayerView.swift:26-32; PlaybackController.swift:262-273 | - | SF2PlayerAppTests.swift (testBundledSoundFontRendersOdeToJoy) |
| F10.3 Load error | BUG | PlaybackController.swift:286-290 | F10.3 | none |
| F10.4 Autoplay | OK | PlaybackController.swift:113-122,285; RootFlowView.swift:78-84 | - | PlaybackAutoAdvanceTests.swift (partial) |
| F10.5 Sheet / Cover | OK | PlayerView.swift:66,70,84-101 (Follow control is a no-op, per code comment) | - | Build16Tests.swift (testSheetFollowFitScaleIsAspectFit) |
| F10.6 Note tap | OK | PlaybackController.swift:176-180,230-233 | - | Build16Tests.swift (testActiveNoteIDsAreHalfOpen); PlaybackSmokeFixtureTests.swift |
| F10.7 Transport | OK | PlaybackController.swift:133-154 | - | none |
| F10.8 Chips | OK | AppSettings.swift; PlaybackController.swift:90-105,199-217 | - | Build16Tests.swift (testTransposeLabels, testHandNamesAndLabels) |
| F10.9 A–B loop | OK | PlaybackController.swift:160-187 | - | Build16Tests.swift (testPlayerLoopAndMuteState) |
| F10.10 Interruptions | BUG | SF2MIDIPlayer.swift:236-241,433-462; project.pbxproj:678-687 (no UIBackgroundModes); rg MPNowPlaying = none | F10.10 | none |
| F10.11 End of track | OK | PlaybackController.swift:42-57 | - | PlaybackAutoAdvanceTests.swift (all four tests) |
| F10.12 Rotation / iPad | RT | PlayerView.swift:80 ScrollView; device | - | none |
| F10.13 Library sheet from Player | OK | PlayerView.swift:131-148 | - | none |
| F11.1 Mini-player | OK | LibraryScreen.swift:139-145; RootFlowView.swift:78-84 | - | none |
| F11.2 Delete playing item | BUG | LibraryScreen.swift:83-89,295-303 | F11.2 | none |
| F11.3 Playlist order | OK | PlaylistStore.swift:65-72 | - | PlaylistStoreTests.swift (testNeighborsFollowScansNewestFirstThenSamples) |
| F11.4 App relaunch | OK | PlaylistStore.swift:90-96 | - | PlaylistStoreTests.swift (testIndexReloadsInANewStore) |
| F12.1 Library share | OK | LibraryScreen.swift:207-214; MIDIExport.swift:17-47 | - | Build16Tests.swift (testLibraryEntriesExportTheirMIDI) |
| F12.2 Player share | OK | PlayerView.swift:123-130 | - | none |
| F12.3 Title → filename | OK | MIDIExport.swift:23-29 | - | Build16Tests.swift (testMIDIExportFileNamesAndBytes) |
| F12.4 Temp files | OK | MIDIExport.swift:39-47 (tmp never explicitly cleaned - low) | - | none |
| F12.5 Result share | BUG | ResultScreen.swift:72-77 | F7.7 | none |
| F12.6 Save photo | GAP | no Save-to-Photos feature (by design) | - | none |
| F13.1 Open/close | OK | SettingsView.swift:57-76 | - | none |
| F13.2 Playback prefs | OK | SettingsView.swift:78-93 | - | none |
| F13.3 Version | OK | SettingsView.swift:99-116; AppSettings.swift:94-105 | - | Build6PrepTests.swift (developer rows only) |
| F13.4 Rate | OK | SettingsView.swift:117-121 (no feedback when throttled) | - | none |
| F13.5 Privacy | BUG | SettingsView.swift:193-202 text OK, but web/in-app claim "Deleting a scan removes them" is false for the photo | F2.7 | none |
| F13.6 Source/licenses | OK | SettingsView.swift:204-276 | - | RedesignTests.swift (testSourceCodeAndLicenseRowExists, testLicenseTextsAreBundled) |
| F13.7 Missing items | GAP | no Pro/Restore/Support/telemetry opt-out rows (SettingsView.swift:57-67) | P6.1 | none |
| F14.1 Offline everything | OK | ReadingView.swift:100; Analytics.swift:212-230 | - | none |
| F14.2 Low disk | BUG | ResultScreen.swift:237,287; raw \(error) strings | F10.3 | none |
| F14.3 Memory pressure | OK | PageRecognitionService.swift:130-134 | - | PageRecognitionServiceTests.swift (testMemoryWarningDropsSessionAndNextParseRebuilds) |
| F14.4 Crash recovery | OK | DiagnosticsLog.installUncaughtExceptionHandler (OMRSheetCamApp.swift:7) | - | none |
| F14.5 Rotation / iPad / Dynamic Type / VoiceOver | RT | a11y/rotation/Dynamic Type need device | - | none |
| F14.6 Dark mode / Reduce Motion | OK | ReadingView.swift:61; ResultScreen.swift:396-399 | - | none |
| F14.7 Localization | GAP | English-only strings (no Localizable) | - | none |
| F15.1 Event log | OK | DiagnosticsLog.swift; LogScreen.swift | - | DiagnosticsTests.swift (testLogPersistsAndReloads, testLogEntryCap, testLogByteCap, testLogClear) |
| F15.2 Copy as prompt | OK | PromptBuilder.swift; PromptCopy.swift | - | DiagnosticsTests.swift (testPromptHasAllSections, testPromptSizeCapTruncatesWithCounts) |
| F15.3 Self-tests | OK | Gate1RootView.swift; SegNetSelfTest.swift | - | Build6PrepTests.swift (testSegNetSelfTestOnBundledPage); Gate1RunnerTests.swift |
| F15.4 Persistence | OK | AppSettings.swift:107-113 | - | Build6PrepTests.swift (testDeveloperRowsIncludeSelfTestNotExperimentalToggle) |

## 8. Product enhancement drafts (not defects; nothing filed)

Labels on each file: `audit, enhancement`. All share the App Review guardrails block (never blocks core use, easy dismiss, frequency cap, respects Pro/restored state, accurate pricing disclosure). Build [P2.1] first.

| # | Draft file | Title | Hook (file:line) | Priority |
|---|---|---|---|---|
| 1 | `issues/P2.1-enh-shared-upgrade-prompt-policy.md` | [P2.1] Enhancement: shared upgrade-prompt policy (reasons, frequency cap, Pro suppression) before adding any new upsell surface | ScanQuota.swift:6-13,30-35; PaywallView.swift:55-59; RootFlowView.swift:50-52 | P2 |
| 2 | `issues/P2.2-enh-soft-upgrade-card-after-successful-scan.md` | [P2.2] Enhancement: soft, dismissible upgrade card on the Result screen after a successful scan | ResultScreen.swift:102-107,252-254,269 | P3 |
| 3 | `issues/P1.6-enh-remaining-scans-nudge-near-quota-limit.md` | [P1.6] Enhancement: "N scans left today" nudge near the quota limit (Library + Camera) with a soft path to Pro | ScanQuota.swift:36,40-45; LibraryScreen.swift:158-190; CameraScreen.swift:116 | P2 |
| 4 | `issues/P9.4-enh-pro-status-and-upgrade-row-in-library-and-settings.md` | [P9.4] Enhancement: Pro status / upgrade row in Settings and a quiet entry point in Library | SettingsView.swift:57-67; LibraryScreen.swift:55-67; PaywallView.swift:83-84 | P2 |
| 5 | `issues/P9.1-enh-contextual-upsell-on-locked-pro-features.md` | [P9.1] Enhancement (product decision): contextual upgrade prompt on locked Pro features | PlaybackController.swift:90,160; PlayerView.swift:308-341; PaywallView.swift:103-122 | P3 |
| 6 | `issues/P2.9-enh-gentle-upgrade-reminder-on-app-return.md` | [P2.9] Enhancement: gentle, capped upgrade reminder when a free user returns to the app | RootFlowView.swift:53 (new scenePhase); LibraryScreen.swift:55-67 | P3 |

Overlaps with bug drafts: [P1.6]-enh counter ⇔ bug `P1.10`; [P9.4]-enh Settings row ⇔ bug `P6.1`/`P1.10`; [P2.9]-enh foreground refresh ⇔ bug `P7.4`; [P2.1]-enh depends on bug `P1.12`. Implement overlapping pairs together.

## 9. Steps I could not fully trace, and why

- **P2.10** Layout / a11y — PaywallView.swift:10-52 ScrollView; Dynamic Type/iPad need device
- **P3.2** Apple sheet — Apple sheet text depends on ASC/localization
- **P3.9** App killed after payment, before `purchase()` returns — needs SKTestSession S17 (Transaction.unfinished/currentEntitlements at launch)
- **P3.11** Purchase while not signed into App Store — StoreKit sign-in prompt behavior
- **P4.6** Interrupted purchase (payment method needs attention / 2FA) — needs Xcode Interrupted Purchase (S9)
- **P5.3** Approved while app is closed — S8; listener+currentEntitlements at launch
- **P6.6** Offline restore — offline restore message (S10)
- **P7.3** Renewal while running — renewal via Transaction.updates (S13)
- **P7.9** Billing retry / grace period — grace period (S15)
- **P7.10** Offline — currentEntitlements offline (S18)
- **P8.1** Delete + reinstall (same Apple ID, active sub) — S16 reinstall sync
- **P8.4** New device, same Apple ID — new device
- **P8.6** Offline reinstall — offline reinstall
- **P10.5** Disclosures consistent — ASC App Privacy status external; in-app/manifest/web agree (privacy page fetched 2026-10-17)
- **P11.2** Sandbox purchase in review — ASC review state external
- **P11.5** Pricing parity — ASC live prices external; config/doc parity only
- **F3.4** Live preview — CameraController.swift:131-163 (rotation/upright capture needs device)
- **F3.7** Focus / torch — CameraController.swift:111-117 (stop() clears torchOn flag but never calls setTorch(false) - hardware torch state needs device)
- **F6.7** Parse — PageRecognitionService.swift:275-285 (memory/jetsam on device; no parse timeout confirmed: no Task timeout anywhere)
- **F6.9** App backgrounded during parse — no beginBackgroundTask (rg: none); effect needs device
- **F6.10** Rotation — ReadingView.swift:82
- **F8.2** Overlay — OMRCompareView.swift:109-128 alignment needs device
- **F9.10** Edge inputs — needs fixtures/device (no tuplet/key-sig/multi-row fixtures)
- **F10.12** Rotation / iPad — PlayerView.swift:80 ScrollView; device
- **F14.5** Rotation / iPad / Dynamic Type / VoiceOver — a11y/rotation/Dynamic Type need device

Other limits: no app run (Linux box, no Xcode/simulator), so every BUG is static-trace evidence (repro rate `always` means the code path is unconditional, not observed); external state not verifiable: App Store Connect subscription review status, ASC App Privacy answers, live ASC prices. Files not read line-by-line (flows.md refs spot-checked only): `ModelWarmup.swift` beyond :85-175, `SheetFollowView`, `DiagnosticsLog`, `PromptBuilder`, `LogScreen`, `Gate1*`/`SegNetSelfTest`, `ScreenshotDemo`, and the `omr-homr-ios` package internals.

## 10. Extra minor findings (confirmed in code, not drafted separately)

- `PlaylistStore.delete` removes the entry from `scans` before `saveIndex()` (`PlaylistStore.swift:161-162`); a write failure leaves UI and disk out of sync until relaunch (touches F2.7).
- `refreshEntitlements` sets `omr.isPro=false` but leaves `omr.proTransactionId` stale (`StoreKitManager.swift:139-140` vs `revokePro` :148-151).
- `CameraController.stop()` clears the published `torchOn` but never sets the hardware torch off (`CameraController.swift:111-117`) — F3.7, needs device.
- `ScanFailure.classify` is substring-based (`model|onnx|session|ort&&runtime` → readerUnavailable, `ScanFailure.swift:31`); `cancelled` maps to `.other` (asserted in `Build16Tests.swift:45`) — F9.2.
- `Save to Library` button is a no-op confirmation (`ResultScreen.swift:310-315`) — F7.5; Settings footer/PrivacyScreen text agree with the policy except the F2.7 deletion claim.
- Paywall shows price without billing period/savings (`PaywallView.swift:78-79`) — P2.4; check against Guideline 3.1.2(a) before submission.
