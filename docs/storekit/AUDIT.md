# StoreKit audit (5 November 2026)

An audit of the purchase code before the products go live: the Starter Pack's one-time rewards, Restore Purchases, duplicate and replayed transactions, Crystal persistence and refunds, and what the client-side save still leaves open. Every finding below was first reproduced by a test that failed, then fixed; the tests are in `tests/test_storekit.gd` ("audit" section).

## Findings and fixes

| # | Severity | Finding | Fix |
| --- | --- | --- | --- |
| 1 | High | **A purchase made on another device paid out again here.** StoreKit delivers transactions from the player's other devices (same Apple account) through its update stream. They were treated as this device's own: a Starter Pack bought on an iPad paid its 300 Crystals and 5,000 Credits a second time on the iPhone, and a Crystal pack bought elsewhere paid its Crystals here too. | Every purchase now carries an **app account token** unique to this device (Apple's `appAccountToken`, kept in the Keychain as this-device-only). Only a transaction carrying this device's token pays currency. Another device's Starter Pack or Remove Ads brings only what is account-wide (the entitlement, the AURUM skin); another device's Crystal pack brings nothing and is left for that device to finish. |
| 2 | High | **A refunded Starter Pack kept its rewards.** Only the entitlement was removed; the 300 Crystals, 5,000 Credits and the AURUM skin stayed. | Every delivery records exactly what it paid on this device. A refund takes that back (Crystals and Credits as far as the balance still holds them), removes the skin and takes it off the core if worn. |
| 3 | Medium | **A refund could take Crystals that were never paid here.** A refund notice for a pack bought on another device, or the same notice arriving twice, took the pack's Crystals from this balance again. | Currency is taken back only for a transaction this device paid out, and only once (the delivery is marked refunded). |
| 4 | Medium | **A purchase whose save failed was still closed with Apple.** If the save could not be written (a full disk), the transaction was finished anyway, so after a restart the Crystals were gone and StoreKit would not hand the purchase over again. | The transaction is finished only after the save is written. Otherwise it stays open and StoreKit delivers it again next launch; the transaction id stops it being paid twice. |
| 5 | Low | **Restore Purchases could hang the shop.** If the App Store never answered (a stuck sign-in), the shop stayed busy for good. | Restore gives up after two minutes and says so. |
| 6 | Low | **A restore listing a consumable would have recorded it.** StoreKit does not list consumables today (it can be configured to on iOS 18), and none would have paid currency, but it counted as "restored". | Restores only consider non-consumables. |
| 7 | Low | **An interrupted purchase followed by a reinstall** would not have been recognised as this device's (the first version of the token lived in app storage, which a reinstall clears). | The token lives in the Keychain, which survives a reinstall but never moves to another phone. |

## What the tests now guarantee

- **Starter Pack**: its Crystals, Credits and skin are paid once per purchase on the buying device - not again by replaying its transaction, restoring (twice), the launch report, or its transaction arriving from another device. A refund takes all three back; buying it again after a refund pays again, as a new purchase should.
- **Duplicates and replays**: a transaction id that has been paid is never paid again, however often StoreKit hands it over. Finished transactions are never handed over again by StoreKit, and only verified ones (signed by the App Store for this app) reach the game at all.
- **Restore**: brings back Remove Ads and the Starter Pack's entitlement and skin, never currency; a second restore finds nothing; a failed or stuck restore says so and leaves the shop usable.
- **Crystals**: paid and saved before the transaction is closed; a purchase interrupted before saving arrives on the next launch; a failed save leaves it open.
- **Refunds**: take back what that purchase gave on this device, once, never below zero; refunds of purchases paid elsewhere take nothing from this device.

## What the client-side save still leaves open

The profile is a JSON file in the app's private storage, with a checksum. The checksum's salt is inside the app, so it shows tampering by a casual edit but cannot stop someone who reads the app's code. Nothing below can be fixed on the device alone; the remedy for all of them is a small server that owns the Crystal balance and checks each signed transaction (APP_STORE_READINESS.md B-8).

| Risk | Who can do it | Impact | Mitigation available now |
| --- | --- | --- | --- |
| **Editing the save**: Crystals, Credits, Remove Ads, skins and unlocks are all plain values in the file | Someone with a jailbroken phone, or editing an unencrypted Finder/iTunes backup and restoring it | Unlimited Crystals and every paid item, on their own device only | None that does not also hurt honest players. Remove Ads could be checked against StoreKit at launch, but StoreKit can report nothing when the player is signed out or offline, which would put ads back in front of a paying player. Not done. |
| **Rolling the save back**: restoring an older backup returns Crystals that have since been spent | Anyone who restores a device backup | Spent Crystals come back (true of earned Crystals and Credits as well) | None on device |
| **Refund after spending**: Crystals spent before the refund cannot be taken back | Anyone who asks Apple for a refund | The spent value is kept. Apple limits refunds, and repeat refunders are refused by Apple | Could carry the shortfall as a debt against future Crystals; not done (it can surprise a player and needs careful wording) |
| **Hooked StoreKit on a jailbroken device**: tools that fake purchases | Jailbroken devices only | Free purchases | StoreKit 2's signed transactions defeat the common fake-receipt tools; a tool that also patches the verification can only be stopped by checking the signed transaction on a server |
| **Copying the save to another device** | Anyone moving files between devices | Duplicates everything in it (currencies, unlocks) | None on device; a server account would fix it |

None of these let a purchase be paid twice through StoreKit itself; they are the general weakness of a game whose progress lives only on the phone. For a premium currency at this scale that is a common, accepted position; it becomes worth a server if Crystal sales become material, or if cloud saves are added (H-2), which need a server anyway.

## Verifying against App Store Connect

Once the five products exist (docs/storekit/README.md lists the exact ids), with a phone connected:

```
tools/ios_deploy.sh --storekit-check
```

installs a development build and reports, for every product id: found in App Store Connect or not, its localised price, its name and that its type matches the game's (consumable or non-consumable), plus what the account owns. With a sandbox account signed in on the phone (Settings, Developer, Sandbox Account),

```
STOREKIT_BUY=crystals_s tools/ios_deploy.sh --storekit-check
```

also makes one sandbox purchase (nobody is charged), and checks it comes back verified, carries this device's token, and finishes. The check never touches the player's profile. The rest of the sandbox test plan (restore, refund, Ask to Buy, interrupted purchase) is in README.md and needs someone at the phone.
