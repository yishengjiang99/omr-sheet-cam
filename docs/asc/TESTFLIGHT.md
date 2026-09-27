# TestFlight: AI Camera - Music Reader (`com.ragnus.vp`)

- ASC app: Apple ID `6816476323`, SKU `Ai-cam-omr`, team `83D36RPMUM` (GrepAwk LLC). Bundle ID resource `PNNDP4FZLJ`.
- Signing (CI only, the project stays on Automatic for local builds): Apple Distribution cert `YXDKHJC7J9`
  (shared with FinalCap), App Store profile **"AI Camera Music Reader App Store"** (`8A593928L5`, expires 2027-09-23).
- Repo secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`,
  `IOS_DISTRIBUTION_P12_BASE64`, `IOS_DISTRIBUTION_P12_PASSWORD`, `IOS_APPSTORE_PROFILE_BASE64`.
- Internal group **Internal Testers** (`68652e1c-7527-454e-b86f-29bf70e6c7a1`, access to all builds) with yisheng.jiang@gmail.com.

## Cut a build
1. Actions → **iOS TestFlight** → Run workflow (build number = run number, version 1.0).
   It fetches the pinned models (`scripts/fetch-models`, cached on `models.lock`), archives with
   `OMR_REQUIRE_MODELS=1`, fixes the embedded `onnxruntime.framework` MinimumOSVersion (ITMS-90208),
   runs `altool --validate-app`, uploads, then waits until ASC reports the build **VALID**; any
   failure fails the job.
2. New builds reach the internal group automatically. `ITSAppUsesNonExemptEncryption=NO` is in
   Info.plist, so there is no export-compliance prompt (fallback: **ASC clear export compliance**).
3. Status: **ASC status (read-only)**.

## History
| Build | Commit | Result |
|---|---|---|
| 1 | `10953c5` | Rejected after upload: ITMS-90208 (onnxruntime.framework MinimumOSVersion 15.1 vs binary minos 17.0) |
| 2 | `8452060` | Same ITMS-90208 (wrong fix: the framework is dynamic, not static) |
| 3 | `a4c2e06` | **VALID**, in internal testing (includes model bundling + ModelWarmup `1f2aa91`) |
| 4 | `c2950ae` | **VALID** (ios-testflight run 36265488038; the workflow fails unless ASC reports VALID) |
| 5 | `42bb4e8` | **VALID** (run 36269862370) |
| 6 | `83c335d` | **VALID** (run 36279588528; SegNet CoreML NeuralNetwork fix) |

Listing copy and screenshots: `LISTING.md`, `push_listing.py`, `screenshots/`. Never submit for App Store review from CI.

## Internal testing assignment
The **Internal Testers** group has access to all builds, so new VALID builds reach it automatically. The manual **ASC assign Internal Testing** workflow exists as a fallback; its only run (36270215129, 2026-09-26) failed — re-run it with the build number if a build ever does not appear in TestFlight.
