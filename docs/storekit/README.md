# Real purchases: StoreKit 2

The shop now sells through the App Store on an iPhone. The test store (the "TEST PURCHASE" dialog that hands goods out for free) is only used in the editor, on the desktop and in automated tests. A release build on a phone can never fall back to it: if the StoreKit bridge were missing, the shop would show every product as UNAVAILABLE.

## How it fits together

| Piece | What it does |
| --- | --- |
| `native/storekit/src/StoreKitBridge.swift` | All StoreKit 2 calls (StoreKit 2 is Swift-only): loads products, buys, listens for transactions, restores. Only reports transactions StoreKit has **verified** (signed by the App Store for this app). Keeps each purchase **unfinished** until the game says it has saved the goods. |
| `native/storekit/src/storekit_ios.mm`, `storekit_bridge.*` | The Godot side: the `StoreKit` engine singleton, one signal `event(name, payload)`. `storekit_stub.cpp` is the desktop stand-in (`is_supported()` is false). |
| `tools/build_storekit.sh` | Compiles the Swift layer and the bridge into `addons/storekit` (git-ignored output). `tools/ios_release.sh` and `tools/ios_deploy.sh` run it if it is missing. |
| `addons/storekit/storekit_export_plugin.gd` | Adds the Swift runtime library paths to the exported Xcode project, which has no Swift of its own. |
| `src/services/store/storekit_store_provider.gd` | Maps game products to App Store products, shows StoreKit's localised prices, turns events into purchases. |
| `src/services/store/store_service.gd` | Pays out a purchase **once** (by transaction id), saves, then finishes the transaction. Handles purchases that arrive on their own, refunds and restores. |

### What happens when

- **Buy.** The App Store sheet appears. Paid and verified: the goods are granted, saved, then the transaction is finished. Cancelled: nothing happens. Any failure: nothing is granted and the shop says why ("Can't reach the App Store", "Purchases are turned off on this device", "you were not charged").
- **Closed mid-purchase.** If the app dies after payment but before saving, StoreKit hands the purchase back the next time the app starts, and it is granted then. A transaction id already paid is never paid twice.
- **Ask to Buy.** A child's purchase waiting for a parent shows "Waiting for approval". If approved, it arrives later on its own and is granted.
- **Refund.** Apple tells the app: Remove Ads or the Starter Pack entitlement is removed; a Crystal pack's Crystals are taken back, as far as the balance goes.
- **Restore Purchases.** Syncs with the App Store (may ask the player to sign in) and brings back Remove Ads and the Starter Pack, without paying the Starter Pack's Crystals again.
- **New phone or reinstall.** At launch the app quietly asks StoreKit what the account owns and restores it, without a sign-in.
- **Prices.** StoreKit's own, in the player's currency (£ in the UK). Until they arrive, or if the App Store cannot be reached, products show UNAVAILABLE rather than a guessed dollar price.

Validation: StoreKit's on-device verification is the baseline. A server that checks each signed transaction and receives Apple's refund notifications is optional for a game of this size (APP_STORE_READINESS.md B-8); the place it would go is marked in `StoreService._deliver()`.

## What you need to set up in App Store Connect

1. **Agreements, Tax and Banking**: sign the Paid Apps Agreement, add the bank account and tax forms. Nothing can be sold, even in the sandbox for some features, until this is active.
2. **Small Business Program** (optional): 15% commission instead of 30% under $1M a year.
3. **In-app purchases** for the app, with exactly these product ids (they come from `data/monetization.json`: `store.ios_prefix` + the product key):

| Product id | Type | Name | Price (US tier) |
| --- | --- | --- | --- |
| `com.starscale.swarmshift.remove_ads` | Non-Consumable | Remove Ads | $3.99 |
| `com.starscale.swarmshift.starter_pack` | Non-Consumable | Starter Pack | $1.99 |
| `com.starscale.swarmshift.crystals_s` | Consumable | Handful of Crystals (120) | $0.99 |
| `com.starscale.swarmshift.crystals_m` | Consumable | Cache of Crystals (650) | $4.99 |
| `com.starscale.swarmshift.crystals_l` | Consumable | Vault of Crystals (1,500) | $9.99 |

   Each needs a display name, a description and a review screenshot (the shop screen). A product id can never be reused once created, even if deleted. To use different ids, set `ios_prefix`, or an `ios_id` on a single product, in `data/monetization.json`.
4. **Sandbox tester**: Users and Access, Sandbox, add a tester with an email address that is not an existing Apple ID. On the phone: Settings, Developer (or App Store), Sandbox Account.

TestFlight builds always buy in the sandbox: nobody is charged. Until the products exist in App Store Connect, the shop in TestFlight shows them as UNAVAILABLE.

## Sandbox test plan (on a phone, from TestFlight)

1. Shop shows £ prices for all five products.
2. Buy each Crystal pack: Crystals arrive; buy one twice.
3. Buy Remove Ads: interstitials stop; the card says OWNED.
4. Buy the Starter Pack: Crystals, Credits and the AURUM skin arrive.
5. Cancel a purchase: nothing changes, no message.
6. Airplane mode, then buy: "Can't reach the App Store", nothing granted.
7. Start a purchase, pay, and force-quit the app before it says "Purchase complete": relaunch, and the purchase arrives once.
8. Delete and reinstall: Remove Ads and the Starter Pack come back at launch; RESTORE PURCHASES also restores them, Crystals are not paid again.
9. Ask to Buy (a sandbox child account, or the sandbox setting that requires approval): "Waiting for approval", then approve and it arrives.
10. Refund (sandbox "Request a refund" or App Store Connect's sandbox refund): Remove Ads goes away.

## Tests

`tests/test_storekit.gd` drives the real provider and store service through a fake bridge that answers like the native one: product ids and prices, a product missing from App Store Connect, no connection, a purchase delivered once then finished, the same transaction handed over again, a purchase paid but never saved arriving next launch, every failure (cancelled, pending, network, not allowed, unverified) granting nothing and saying why, Ask to Buy, refunds of a non-consumable and of Crystals (never below zero), Restore, a failed restore, a reinstall restoring at launch without a sign-in, and the closed store a release build would get without the bridge. The native code itself is only exercised on a phone against the sandbox (plan above). A full release export links it: the archived app loads StoreKit and the Swift runtime.
