# In-app purchases: Music Reader Pro (auto-renewable subscriptions)

App: **AI Camera - Music Reader**, bundle `com.ragnus.vp`, ASC Apple ID `6816476323`.

The product IDs must match `IAPProductID` in `Sources/App/Services/StoreKitManager.swift` and
`OMRSheetCam.storekit` exactly. They do.

| Item | Value |
|---|---|
| Subscription group (reference name) | `Music Reader Pro` |
| Group en-US display name | `Music Reader Pro` |
| Monthly product ID | `com.ragnus.vp.pro.monthly` |
| Monthly reference / display name | `Music Reader Pro Monthly` |
| Monthly duration / price | `ONE_MONTH`, USD $4.99 |
| Monthly en-US description | `Unlock all Pro features, billed monthly` |
| Yearly product ID | `com.ragnus.vp.pro.yearly` |
| Yearly reference / display name | `Music Reader Pro Yearly` |
| Yearly duration / price | `ONE_YEAR`, USD $29.99 |
| Yearly en-US description | `Unlock all Pro features, billed yearly` |
| Availability | All territories, plus new territories as Apple adds them |
| Other territories' prices | Equalized from the USA base price (Apple's equalization price points) |
| Family Sharing | Off |

## How they are created

`scripts/asc/create_subscriptions.py`, run by the manual workflow
`.github/workflows/asc-create-subscriptions.yml` (Actions > "ASC create subscriptions" > Run workflow).
It's idempotent: it finds existing objects and creates only what's missing. With
`verify_only=true` it only lists the group, subscriptions, states, localizations, availability and
USA prices. It never submits anything for review.

You need an active **Paid Apps Agreement** (ASC > Business). Without it, Apple refuses prices.

## Still manual

- ~~Review screenshot~~ now automated: `docs/asc/review/subscription-paywall.png` (real PaywallView,
  iPhone 6.9" 1320x2868, prices from `OMRSheetCam.storekit`) is captured by `ios-screenshots.yml`
  (input `only_paywall`, test `Tests/PaywallScreenshotTests.swift`) and uploaded to both products by
  `create_subscriptions.py`. Group levels: yearly = 1, monthly = 2.
- **First submission:** new subscriptions have to be submitted together with the **next app version**.
  `asc-submit-app-store.yml` (input `submit_subscriptions`, default on) runs
  `scripts/asc/submit_subscriptions.py` (POST /v1/subscriptionSubmissions) right before it submits the
  version. Manual alternative: on the version page, under "In-App Purchases and Subscriptions", select
  both subscriptions before submitting. App Review notes: `docs/asc/metadata/review_information/notes.txt`.

## Verification

1. Wait about 15 minutes after creation. Products take a while to propagate to the sandbox.
2. Install or open the latest TestFlight build of AI Camera - Music Reader.
3. Trigger the paywall (use up the free scan quota, or open Pro from the app). Both plans should
   show localized prices ($4.99/month and $29.99/year in the US).
4. Buy with a **sandbox Apple ID** (ASC > Users and Access > Sandbox). On TestFlight, purchases are
   free sandbox transactions. Check that Pro unlocks, then test **Restore Purchases**.
5. If products don't load, re-run the workflow with `verify_only=true` and check that both products
   exist, have a USA price, and use the IDs above.
