# OMR IAP Xcode Integration Prompt

## Context

Branch: `agent/omr-iap-xcode` (yishengjiang99/omr-sheet-cam)
The IAP and telemetry Swift code is written and in git, but the 4 new files
are NOT linked in the Xcode project (OMRSheetCam.xcodeproj/project.pbxproj).
Manual pbxproj edits corrupted the project file twice — use Xcode UI instead.

## Files in Git (already committed)

These 4 files exist in the repo but are not in the Xcode project:

1. `Sources/App/Services/Analytics.swift`
   - Telemetry client, POSTs to https://photo.grepawk.com/api/telemetry
   - Sends `app: "omr-sheet-cam"` to distinguish from ProTune
   - Called from `OMRSheetCamApp.init()` via `Analytics.shared.bootstrap()`

2. `Sources/App/Services/StoreKitManager.swift`
   - StoreKit 2 subscription manager
   - Product IDs: `com.ragnus.vp.pro.monthly`, `com.ragnus.vp.pro.yearly`
   - On-device entitlement (UserDefaults), no server verification

3. `Sources/App/Services/ScanQuota.swift`
   - Free tier: 5 scans/day, resets daily
   - Pro users: unlimited
   - Triggers paywall when quota hit

4. `Sources/App/Features/Paywall/PaywallView.swift`
   - SwiftUI paywall with monthly/yearly plan cards
   - Restore purchases button
   - Legal footer (Terms, Privacy)

Also in git:
- `OMRSheetCam.storekit` — StoreKit config for local testing ($4.99/mo, $29.99/yr)
- Modified: `Sources/App/OMRSheetCamApp.swift` (added `Analytics.shared.bootstrap()`)
- Modified: `Sources/App/Capture/ResultScreen.swift` (added scan_start/scan_success/scan_fail events)
- Modified: `Sources/App/RootFlowView.swift` (added quota check, paywall sheet, StoreKitManager environment object)

## Task: Integrate via Xcode UI

### Step 1: Open the project
```
open OMRSheetCam.xcodeproj
```

### Step 2: Add the 4 Swift files
1. In the Project Navigator (left sidebar), right-click the `App` group
2. Select **Add Files to "OMRSheetCam"...**
3. Navigate to and select these 4 files (Cmd+click for multi-select):
   - `Sources/App/Services/Analytics.swift`
   - `Sources/App/Services/StoreKitManager.swift`
   - `Sources/App/Services/ScanQuota.swift`
   - `Sources/App/Features/Paywall/PaywallView.swift`
4. In the dialog:
   - ✅ Check **"Copy items if needed"** (should already be in place, but safe)
   - ✅ Check **"Add to targets: OMRSheetCam"**
   - Select **"Create groups"** (not folder references)
5. Click **Add**

### Step 3: Add the StoreKit config to the scheme
1. Click the scheme dropdown (top bar, next to the Run button) → **Edit Scheme...**
2. Select **Run** → **Options** tab
3. Under **StoreKit Configuration**, click the dropdown and select **OMRSheetCam.storekit`
   - If not listed, click "Add" and navigate to `OMRSheetCam.storekit`
4. Click **Close**

### Step 4: Verify build
1. Select **Any iOS Device** or a simulator
2. Press **Cmd+B** to build
3. Fix any compile errors (see "Known Issues" below)

### Step 5: Commit and push
```bash
git add OMRSheetCam.xcodeproj/project.pbxproj
git commit -m "xcode: integrate IAP/telemetry Swift files via Xcode UI"
git push origin agent/omr-iap-xcode
```

## Known Issues

### Analytics.swift references
- Uses `URLSession.shared.data(for:)` — requires iOS 15+. Check deployment target.
- No dependencies on other app code — should compile standalone.

### StoreKitManager.swift references
- References `Analytics.shared` — ensure Analytics.swift is in the target.
- Uses `@MainActor` and `ObservableObject` — standard SwiftUI.

### ScanQuota.swift references
- Creates its own `StoreKitManager()` instance — this is intentional for simplicity.
  In production, inject the shared instance via `@EnvironmentObject`.
- References `Analytics.shared` — ensure Analytics.swift is in the target.

### PaywallView.swift references
- Uses `@EnvironmentObject private var storeKit: StoreKitManager`
  Must be presented with `.environmentObject(storeKit)` — already done in RootFlowView.
- References `Analytics.shared` — ensure Analytics.swift is in the target.
- Uses `Product` from StoreKit — ensure `import StoreKit` is present.

### RootFlowView.swift changes (already in git)
- Added `@StateObject private var storeKit = StoreKitManager()`
- Added `@StateObject private var quota = ScanQuota.shared`
- Added `.sheet(isPresented: $quota.showPaywall)` for PaywallView
- Added `.environmentObject(storeKit)` at the root

If `ScanQuota.shared` causes issues (it's a singleton with `@MainActor`),
consider changing to `@StateObject private var quota = ScanQuota()` and
updating references.

## Acceptance Criteria

- [ ] Project builds without errors (Cmd+B)
- [ ] All 4 new files appear in Project Navigator under App group
- [ ] StoreKit config is set in the Run scheme
- [ ] App launches, Analytics bootstrap fires (check Console for [Analytics] logs in DEBUG)
- [ ] Scan flow works, quota decrements (check UserDefaults `omr.freeScansUsed`)
- [ ] After 5 scans, paywall appears
- [ ] Paywall shows $4.99/mo and $29.99/yr from StoreKit config
- [ ] Test purchase in sandbox unlocks Pro (unlimited scans)
- [ ] Commit pbxproj changes and push to `agent/omr-iap-xcode`

## After Completion

Once the branch builds and the IAP flow is verified:
1. Merge `agent/omr-iap-xcode` to `main` (merge commit, no squash)
2. Dispatch `ios-testflight.yml` workflow on main
3. TestFlight build will include telemetry + IAP
