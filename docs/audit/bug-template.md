# Bug report template (code-tracer → GitHub issue)

One issue per root cause. Use the step ID from `flows.md`. **Do not** file from this audit without the user's approval; the audit itself filed nothing.

## Title

`[<StepID>] <short, user-visible symptom>` — e.g. `[P3.7] Photo that hit the paywall is discarded after purchase`

Labels: `bug`, flow label (`flow:F3`, `flow:P6`), severity (`sev:P0`…`sev:P3`), `area:{capture|recognition|player|library|settings|iap|telemetry|docs}`.

## Body

```markdown
**Step ID:** F3.4            <!-- from flows.md; add "also P1.4" if it spans flows -->
**Flow:** F3 Camera capture & camera permission
**Static verdict from audit:** GAP | ? | confirmed-by-run     <!-- change to confirmed-by-run once reproduced -->
**Build / env:** version (build) · iOS version · device · Simulator|Device · StoreKit env (Xcode config | Sandbox | Prod) · Apple ID type

### Expected
<what flows.md "Expected"/"Acceptance" says should happen>

### Actual
<what the code / device does — quote log lines (Settings → Version ×5 → Event log → Copy as prompt) when relevant>

### Location
`Sources/App/Path/File.swift:LINE` (+ any secondary refs, `Packages/...:LINE`)
Root cause (1–2 lines): <why the code behaves this way>

### Repro
1. Preconditions (fresh install? `defaults write com.ragnus.vp omr.freeScansUsed -int 5`? airplane mode? StoreKit config attached?)
2. Steps…
3. Observed result

Repro rate: always | intermittent (n/m) | needs device only
Evidence: screenshot / screen recording / diagnostics prompt / telemetry events observed

### Severity
P0 | P1 | P2 | P3   — one-line justification
- **P0** data loss, crash/hang on core path, purchase charged but Pro not granted, App-Review blocker, privacy statement violated
- **P1** core flow broken or revenue-affecting (wrong lock/unlock, restore unreachable), frequent confusing failure
- **P2** wrong/misleading behavior with a workaround, edge-case failures, analytics gaps
- **P3** polish, copy, minor a11y, docs drift

### Suggested fix
<minimal change, named function(s); mention alternatives and any product decision needed>

### Acceptance test
- [ ] Manual: <exact steps + expected observable result, copied/adapted from the flows.md acceptance check>
- [ ] Automated: <XCTest / SKTestSession (see flows.md case Sx) / XCUITest name and assertion>
- [ ] Regression: <neighbouring step IDs re-verified, e.g. F5.3, P1.5>
```

## Worked example (from this audit)

**Title:** `[P7.4] Pro stays unlocked after subscription expires until the app is relaunched`
**Step ID:** P7.4 (also P9.3) · **Static verdict:** GAP (confirm with S12)
**Expected:** After the subscription's `expirationDate`, the next scan attempt shows the paywall without relaunching.
**Actual:** `omr.isPro` is only recomputed in `StoreKitManager.init` (→ `refreshEntitlements`) and on restore; `Transaction.updates` listener handles only grants/revocations.
**Location:** `Sources/App/Services/StoreKitManager.swift:23-28,105-141`; gate read in `Sources/App/Services/ScanQuota.swift:23`.
**Repro:** E1 StoreKit config; buy Monthly; Debug ▸ StoreKit ▸ Manage Transactions ▸ Expire; background/foreground (don't kill); take a 6th scan the same day → scan proceeds.
**Severity:** P1 — revenue leak; lapsed users keep unlimited scans for as long as the process lives.
**Suggested fix:** Call `refreshEntitlements()` on `scenePhase == .active` and at the start of `checkAndConsume()`; derive Pro from `Transaction.currentEntitlements` (and `expirationDate`) instead of a cached flag; inject a single `StoreKitManager` into `ScanQuota`.
**Acceptance test:** SKTestSession test (S12): buy → `expireSubscription` → `await manager.refreshEntitlements()` → `ScanQuota.checkAndConsume()` returns false on 6th scan and sets `showPaywall`. Manual S12 per flows.md. Regression: P3.5, P7.5.

## Pre-filled candidate list for the tracer (highest value first; verify, don't assume)

| Step | Suspected issue | Primary file:line |
|---|---|---|
| P7.4 | Pro not re-checked on foreground/expiry | `StoreKitManager.swift:23-28,124-141` |
| P7.6 | `revokePro()` ignores other valid entitlements | `StoreKitManager.swift:113-115` |
| P6.1–P6.4 | Restore only in paywall; no progress/result feedback | `PaywallView.swift:43-46`; `StoreKitManager.swift:93-103` |
| P1.4 | Quota consumed before recognition outcome | `RootFlowView.swift:57-62`; `ScanQuota.swift:22-38` |
| P3.7 | Photo discarded when paywall shown | `RootFlowView.swift:57-62` |
| P5.1/P5.2 | Pending shown as error; approval not reflected in UI | `StoreKitManager.swift:79-82,105-118` |
| P2.5/P2.7 | Duplicate error text, no retry, flash of error pre-load | `PaywallView.swift:27-41`; `StoreKitManager.swift:46-60` |
| P11.3 | `.storekit` not attached to scheme / project | `OMRSheetCam.xcodeproj` (scheme + pbxproj) |
| P1.12 | Two `StoreKitManager` instances | `ScanQuota.swift:11`; `RootFlowView.swift:15` |
| P10.3 | Analytics key filter drops `platform` (`lat`) | `Analytics.swift:53` |
| F6.4/F6.8 | Cancel doesn't stop parse; late save/orphan JPEG | `ResultScreen.swift:58,206-216`; `PageRecognitionService.swift:210-219` |
| F2.7 | Capture JPEG not deleted with scan | `PlaylistStore.swift:158-168` |
| F2.9 | Corrupt index silently empties Library | `PlaylistStore.swift:98-113` |
| F5.5/F9.5 | "Retake" returns to Library, not Camera | `RootFlowView.swift:59-61`; `ResultScreen.swift:66-71,139-142` |
| F10.10 | No background audio / Now Playing | project settings; `SF2MIDIPlayer.swift:433-462` |
| P11.1 | Review notes' "Try sample ×6" impossible on Library home | `LibraryScreen.swift:69-73` |
| F4.5 | PHAsset fallback without Photos authorization | `PhotoLibraryImport.swift:36-61` |
| F8.7 | "Feedback saved" never leaves device | `OMRCompareView.swift:260-274` |
