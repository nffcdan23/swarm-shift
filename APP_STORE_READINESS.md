# SWARM//SHIFT - App Store Readiness Audit

Audit date: 22 October 2026. Audited build: `main` at `5320870` (version 0.2.1, build 3).

This is an internal engineering assessment of what separates the current game from a commercial App Store release under C2 Gaming. **It is not an Apple assessment and the scores are not a prediction or guarantee of approval.** Apple's rules were checked against Apple's own pages on the audit date (sources at the end); they change, so re-check them before submission. Items marked *legal review* need a qualified person, not an engineer.

Nothing was submitted, published, uploaded, signed for distribution or installed on a device during this audit, and no game code was changed.

## Verdict

**Not ready to submit.** The game itself is in good shape: a complete, stable, well-tested core loop with original, reproducible assets. What is missing is almost everything *around* the game that a store release needs: the publishing account is not C2's, both ad and purchase systems are development mocks that would hand out paid content for free, there is no privacy policy, no store metadata, and no release build has ever been produced or validated.

Seven BLOCKERs, ten HIGH. None of them needs the game to be rebuilt.

**Update, 22 October 2026:** C2 has decided that 1.0 launches with both in-app purchases and ads. The AdMob and consent work is now blocker B-7, and the release plan (section 9) puts it in Phase 2, which grows to about 5-6 weeks.

| Area | Score /10 | One line |
| --- | --- | --- |
| Gameplay | 7 | Complete loop, 20 sectors, bosses, meta progression. Balance comes from bot simulations; one human playtest is documented |
| Stability | 7 | 2,427 of 2,428 automated checks pass; the playtest freeze is fixed with evidence. One flaky test; nothing measured on a release build |
| Performance | 6 | 120 fps with ~240 enemies on an iPhone 16 Pro Max (debug). Nothing measured on older or mid-range phones |
| UI/UX | 7 | Polished, safe-area aware, honest shop. iPad untested on hardware; accessibility gaps |
| Copyright | 6 | Every sprite and sound regenerates byte-for-byte from the project's own code. Engine licence notices missing; name not cleared |
| Privacy | 4 | Collects nothing today - but there is no privacy policy, and the decision to ship ads in 1.0 brings consent, ATT and disclosures (B-7) |
| Monetisation | 2 | Policy layer is solid and tested; the ad network and the store are both mocks |
| iOS Compatibility | 6 | Toolchain meets Apple's current minimums; development builds run on a real iPhone. No release build ever made |
| App Store Compliance | 2 | Mocks in the shipping build, no policy, no C2 account, no metadata |
| **Total** | **47 / 90** | Internal judgement only |

---

## 1. What was checked, and how

| Check | Method | Result |
| --- | --- | --- |
| Full automated suite | `godot --headless --path . -- --test` | 111 tests, 2,428 checks, **1 failed** (see M-1), 88 s |
| The failing test, three re-runs | `--test=stability --only=elite_drop` | pass, fail, pass. The "screen never strands" assertions passed every time |
| Asset provenance | Exported the repo to a scratch folder, deleted every sprite, icon and sound, ran `tools/generate_art.gd` and `tools/generate_audio.gd`, compared bytes | **93 of 93** PNG/WAV files identical to the committed ones |
| iPad proportions | Screenshot tour at 768x1024 on the Mac (`--shots`, in-memory profile) | All 33 screens laid out correctly. Desktop emulation, not an iPad |
| Generated Xcode project | Read `build/ios` from the last device export (22 Oct 10:06) | Info.plist, privacy manifest, entitlements, build settings, icons reviewed |
| Engine binary | `strings` over `libgodot.a` for privacy-sensitive APIs | Microphone permission API referenced; no camera, photos, location, IDFA or ATT |
| Network code | Searched `src/` and `data/` for HTTP, sockets, identifiers | None. Nothing leaves the device |
| Toolchain | `xcodebuild -version`, SDK, signing identities | Xcode 27.1, iOS SDK 27.1, Godot 4.7.2 + templates. Two *Development* identities, no *Distribution* identity |
| Engine licences | `Engine.get_copyright_info()`, `ThemeDB.fallback_font` | 70+ third-party components; UI font is the engine's Open Sans SemiBold |
| Apple rules | developer.apple.com: Upcoming Requirements, App Review Guidelines, screenshot specifications | See section 3 |
| Name | Web search for "Swarm Shift" | No identical game or app found. Not a trademark search |

Not done: no release export, no archive, no upload or "Validate App" (needs a distribution certificate and an App Store Connect record, both outside this audit's remit); no device testing (the phones are shared and the brief did not ask for a takeover); no trademark or legal search.

---

## 2. Status at a glance

### Verified ready (evidence in this audit)

- Core loop, 10 weapons, 13 passives, 11 augments, 7 synergies, 9 enemy types plus elites, a three-phase boss, 20 sectors with mutators, Overdrive, Player Level 1-100, 16 permanent upgrade tracks, missions, login calendar, 30 achievements - all exercised by the test suite.
- The playtest-1 freeze: root cause established from the device log, reproduced on the old build, fixed, and guarded by tests that passed on every run in this audit ([docs/playtest-1](docs/playtest-1/README.md)).
- Load: 1,000 enemies, 300 simultaneous explosions with chain kills, a 10-minute Overdrive soak - no hang, flat memory, no HUD recoveries.
- Rewards are paid exactly once per run (run ledger); "double Credits" by ad cannot be claimed twice; an interrupted run is checkpointed and paid at next launch.
- Saves: atomic write with backup, checksum, migration from the pre-0.2 save format (fixture test).
- Every art and audio asset is reproducible from code in this repository (93/93 byte-identical).
- Toolchain meets Apple's current upload minimum (Xcode 26 / iOS 26 SDK since 28 April 2026): Xcode 27.1, iOS SDK 27.1.
- Deployment target iOS 15.0 (Apple's minimum since 9 September 2026 is iOS 13); arm64; requires A12 or newer.
- App icon 1024x1024 with no alpha channel; portrait only; full screen; launch storyboard present.
- `ITSAppUsesNonExemptEncryption = false` is correct for an app with no networking.
- A privacy manifest (`PrivacyInfo.xcprivacy`) with required-reason API declarations is generated by the engine; `NSPrivacyTracking = false`.
- "Restore Purchases" button exists in the shop; ad policy (interstitials only between runs, caps, never after a rewarded ad, off with Remove Ads) is enforced in one service and tested.
- Shop has no timers, fake scarcity or pay-to-win walls; nothing purchasable is needed to progress.

### Implemented but unverified

- Restore Purchases and every purchase path - only ever run against `MockStoreProvider`.
- Ad policy - only ever run against `MockAdProvider`; real SDK timing, failures and no-fill are untested.
- Performance below flagship level: A12 (iPhone XS/XR) to A15 phones, iOS 15-17.
- iPad: layout verified only in desktop emulation.
- Release-build behaviour: every device run so far used a debug export.
- Save survival across a real App Store update (the fixture test covers the format, not the update path).
- Audio interruptions (calls, Siri, alarms), low storage, thermal throttling in long sessions.

### Incomplete

- StoreKit integration, ad network integration, consent flows.
- Privacy policy, support page, in-app links to both.
- Third-party licence notices in the app.
- App Store Connect record, metadata, screenshots, age rating, privacy questionnaire.
- Release export, distribution signing, archive, validation, TestFlight.

### Blocked by external accounts or decisions

- C2-owned Apple Developer Program membership (organisation enrolment, D-U-N-S number).
- Paid Apps Agreement, banking and tax forms (needed before any in-app purchase can be sold).
- EU Digital Services Act trader status (needed to be on the EU storefronts).
- Final name and trademark clearance; final bundle identifier.
- C2 AdMob account and its payments profile (1.0 scope decided 22 Oct 2026: purchases and ads, AdMob); price points.
- Whether to support iPad at launch.
- Whether the generated art and audio are the launch look.
- Hosting for the privacy policy and support URL; a support contact.

---

## 3. Apple requirements: mandatory vs recommended

"Mandatory" means Apple's tooling or written rules require it for this app; "recommended" means good practice or a likely review risk.

| Requirement | Mandatory? | Status | Issue |
| --- | --- | --- | --- |
| Built with Xcode 26+ and iOS 26+ SDK | Mandatory (since 28 Apr 2026) | Met (Xcode 27.1) | - |
| Targets iOS 13 or later | Mandatory (since 9 Sep 2026) | Met (iOS 15.0) | - |
| App complete; no placeholder or test content (2.1(a)) | Mandatory | **Fails**: mock ad and purchase screens, "Development build" text in shop | B-2, B-3 |
| In-app purchases complete, visible and functional for review (2.1(b)) | Mandatory if IAP is offered | Not implemented | B-2 |
| Digital goods sold only through Apple IAP (3.1.1) | Mandatory | Mock would grant goods with no payment | B-2 |
| Restore mechanism for restorable purchases (3.1.1) | Mandatory | Button exists; untested against StoreKit | B-2 |
| Purchased currency may not expire (3.1.1) | Mandatory | Met in design; "Reset all progress" deletes it | M-3 |
| Loot-box odds disclosed (3.1.1) | Mandatory if randomised items are sold | Not applicable: nothing random is sold | - |
| Privacy policy link in App Store Connect **and** in the app (5.1.1(i)) | Mandatory for all apps | **Missing** | B-4 |
| App Privacy ("nutrition label") questionnaire | Mandatory | Not answered | B-6 |
| Privacy manifest with required-reason APIs | Mandatory (since 1 May 2024), including for third-party SDKs | Engine's manifest present; SDK manifests needed when added | B-7 |
| ATT prompt before tracking (5.1.2(i)) | Mandatory only if the app tracks | Required: AdMob in 1.0 scope; not built | B-7 |
| Account deletion (5.1.1(v)) | Only if the app has accounts | Not applicable (no accounts) | - |
| Ads: clearly marked, visible close button, age-appropriate, **a way to report inappropriate ads** (2.5.18) | Mandatory if ads are shown | Required: AdMob in 1.0 scope; no report mechanism yet | B-7 |
| Age rating questions answered honestly (2.3.6), new rating system | Mandatory | Not answered | B-6 |
| Screenshots: at least one iPhone set; **13" iPad set if the app runs on iPad** | Mandatory | None for the store; app declares iPad | B-6, H-9 |
| Metadata accurate; screenshots show the game in use; 30-character name | Mandatory | Not written | B-6 |
| Support URL | Mandatory App Store Connect field | Missing | B-4 |
| EU trader status (DSA) | Mandatory for EU distribution | Not provided | B-1 |
| Paid Apps Agreement, tax, banking | Mandatory to sell IAP | Not in place for C2 | B-1 |
| Export compliance answer | Mandatory | Met in Info.plist | - |
| Purpose strings for any protected API the binary uses | Mandatory when used | Present but **empty** | H-8 |
| Age-range signals (Declared Age Range API) under Texas SB 2420 and similar state laws | Depends on jurisdiction - *legal review* | Not implemented | M-8 |
| Accessibility Nutrition Labels | Voluntary today; Apple says they will become required, no date announced | Not answered | M-4 |
| Game Center | Optional | Not used | - |

---

## 4. Issues

Severity: **BLOCKER** stops submission or would almost certainly be rejected; **HIGH** must be fixed before public release; **MEDIUM** should be fixed before or soon after launch; **LOW** is polish. Complexity: S = under a day, M = days, L = a week or more.

### BLOCKER

#### B-1 The app is set up under STARSCALE LTD, not C2 Gaming
- **Description.** Signing team `8RGSL8W378` (STARSCALE LTD) and bundle id `com.starscale.swarmshift` are in `export_presets.cfg`. Whoever submits the app is the seller of record shown on the App Store, receives the revenue, and must own or license the IP (5.2.1). The Android package placeholder is `com.c2gaming.swarmshift`, so the two platforms also disagree.
- **Evidence.** `export_presets.cfg` lines 30-32; README "Build for iOS". The Mac holds two Development identities (one STARSCALE, one `dcawthorn@c-2.co.uk`) and no Distribution identity.
- **Fix.** Decide the legal publisher. If C2: enrol C2 in the Apple Developer Program as an organisation (needs a D-U-N-S number and someone with legal authority), sign the Paid Apps Agreement, complete tax and banking, provide DSA trader details, then choose the final bundle id (e.g. `com.c2gaming.swarmshift`) and put it and the new team id in `export_presets.cfg`. Do this **before** creating the App Store Connect record: the bundle id cannot be changed afterwards, and changing it later loses every tester's save (the save lives in the app's container). Confirm in writing that C2 owns the code and assets made for this project if STARSCALE staff or accounts were involved - *legal review*.
- **Verify.** App Store Connect shows C2 as the seller; `export_presets.cfg` holds C2's team id; a TestFlight build signs with a C2 Apple Distribution certificate.
- **Complexity.** S engineering; L calendar time (D-U-N-S and enrolment can take one to several weeks).

#### B-2 Purchases are a mock that grants paid content for free
- **Description.** `App.boot()` always installs `MockStoreProvider`. In a shipped build, tapping a price shows "TEST PURCHASE ... No real payment is made" and BUY grants Crystals, Credits and the AURUM skin. That is a 2.1 (test content) and 3.1.1 (unlocking content outside IAP) rejection, and a revenue leak if it ever slipped through.
- **Evidence.** `src/app/app.gd:98`, `src/services/store/mock_store_provider.gd`, `src/services/store/mock_purchase_dialog.gd`, shop footer text in `src/ui/screens/shop_screen.gd:39`. No StoreKit code exists anywhere in the repo.
- **Fix.** Implement a `StoreProvider` on StoreKit 2 behind the existing interface (a small Swift/Objective-C iOS plugin or GDExtension exposing products, purchase, `Transaction.currentEntitlements`, `Transaction.updates`, `AppStore.sync()`). Specifically:
  - load products and show **StoreKit's localised prices** (the JSON prices are only fallbacks);
  - grant only on a `.verified` transaction, then call `finish()` - grant first, finish second, so a crash between them re-delivers rather than loses;
  - listen to `Transaction.updates` from launch, so purchases approved later (Ask to Buy, interrupted, SCA) are delivered;
  - "Restore Purchases" calls `AppStore.sync()` and re-reads `currentEntitlements`;
  - handle revocation (refunds) by removing the entitlement;
  - de-duplicate by transaction id (the purchase history already records it);
  - select the mock only in debug/automated builds, and remove the "Development build" footer from release builds.
  Create the five products in App Store Connect with ids matching `data/monetization.json`. Alternatively ship 1.0 without purchases and hide the PACKS section (see release plan).
- **Verify.** StoreKit configuration-file tests in Xcode; sandbox purchases of every product on TestFlight; kill the app mid-purchase and confirm delivery on relaunch; refund in sandbox and confirm revocation; restore on a second device; Ask to Buy approval; airplane-mode failure shows a clear error and grants nothing. Add unit tests at the provider boundary.
- **Complexity.** L.

#### B-3 Ads are a mock that shows fake full-screen "TEST" ads
- **Description.** `App.boot()` always installs `MockAdProvider`; it reports every ad as ready and shows a "TEST REWARDED AD / Mock ad provider" screen. Placeholder content (2.1(a)), and no revenue.
- **Evidence.** `src/app/app.gd:99`, `src/services/ads/mock_ad_provider.gd`, `src/services/ads/mock_ad_overlay.gd`. Placements: revive (`revive_prompt.gd:53`), reroll (`hud.gd:464`), double run Credits (`results_screen.gd:477`), daily double (`daily_reward_modal.gd:83`), shop Credits; interstitial after results (`main.gd:163,168`).
- **Fix.** Ads are in the 1.0 scope (decided 22 October 2026): implement an `AdMobAdProvider` behind the existing `AdProvider` interface and select it in release builds; keep `MockAdProvider` for debug and automated runs only. Details and the consent work it depends on are in B-7, section 6 and Phase 2.
- **Verify.** TestFlight build shows Google test ads in every placement and no mock overlay; no "TEST"/"mock" strings from the mocks in the release `.pck` (`strings` over it).
- **Complexity.** L.

#### B-4 No privacy policy, no support URL
- **Update 22 Oct 2026.** The in-app rows now exist (Settings: Privacy Policy, Support, Report an ad) and read their URLs from `links` in `data/game.json`. They point at **placeholder pages on example.com**; the policy and support pages themselves still have to be written, hosted and swapped in, so this blocker stands.
- **Description.** Every app must link a privacy policy in App Store Connect and inside the app (5.1.1(i)); a support URL is a required store field. Neither exists, and the game has no link to either.
- **Evidence.** No URL anywhere in `src/` or `data/`; `SettingsModal` has audio, haptics, comfort options, reset, and the version only.
- **Fix.** Write and host a privacy policy that states what the app collects (today: nothing leaves the device; the save and a local event log stay on the phone), what the Google Mobile Ads SDK collects and why (1.0 ships with AdMob), with a link to Google's policy, retention, and how to request deletion; a support page with a contact address. Add "Privacy Policy", "Support", "Licences", "Privacy choices" and "Report an ad" rows (the last two from B-7) to Settings that open the URLs. Put the URLs in `data/game.json` so they are not hard-coded. UK GDPR / EU GDPR wording - *legal review*.
- **Verify.** Links open from the release build; the same URLs are in App Store Connect; the policy matches the App Privacy answers.
- **Complexity.** S engineering, M for the text and review.

#### B-5 No release build has ever been produced, signed for distribution or validated
- **Description.** Every build so far is `--export-debug`, signed with a Development certificate, `export_options.plist` method `development`. There is no Apple Distribution certificate on this Mac and no App Store Connect record, so nobody knows yet whether the archive uploads and passes Apple's automated validation.
- **Evidence.** `tools/ios_deploy.sh:38` (`--export-debug`); `build/ios/SwarmShift/export_options.plist` (`development`); `security find-identity` shows Development identities only.
- **Fix.** Add a release path (a `tools/ios_release.sh` or documented steps): `--export-release`, `export_method_release` = App Store, bump `short_version` to `1.0.0` and `version` monotonically, archive in Xcode, **Validate App**, upload to TestFlight. Keep the debug deploy script for development. Align `project.godot` `config/version` (still `0.1.0`) with the preset (L-1).
- **Verify.** Xcode Organizer "Validate App" passes with no errors; the build appears in TestFlight and installs on a tester's phone; the self-test (`--device-check`) or a manual run passes on the release build.
- **Complexity.** M.

#### B-6 App Store Connect metadata, screenshots, age rating and privacy answers do not exist
- **Description.** Submission needs: name (30 characters max), subtitle, description, keywords, category (Games > Action, say), copyright line, support and privacy URLs, review notes, screenshots, age rating questionnaire under Apple's new rating system, App Privacy questionnaire, pricing and availability, and IAP product metadata with a review screenshot each.
- **Evidence.** None of it is in the repo or (as far as this audit can see) anywhere else. `docs/screenshots` are development shots (540 wide), not store sizes.
- **Fix.** Draft metadata in the repo (e.g. `store/metadata.md`) so it is reviewed like code. Capture store screenshots on device or with the screenshot tour at store resolutions: at least one iPhone set (1320x2868 or 1290x2796 for the large Dynamic Island class, which the 16 Pro Max produces natively) and, if iPad is kept, a 13" set (2064x2752 or 2048x2732). Screenshots must show gameplay, stay 4+ appropriate (2.3.8), and contain no "TEST"/mock UI. Age rating: the game is abstract geometric combat with no blood, gore or people; expect a low rating, but answer each question honestly (2.3.6) - the answers on violence intensity, in-app purchases and ads are a business sign-off. App Privacy: with AdMob in 1.0 the answers must follow Google's data disclosure for the SDK version shipped (B-7); "Data Not Collected" no longer applies.
- **Verify.** App Store Connect shows no missing-field warnings; screenshots validate at upload; a second person checks the age rating answers against the game.
- **Complexity.** M.

#### B-7 Ad consent, ATT and ad compliance are not built (ads are in the 1.0 scope)
- **Description.** C2 decided on 22 October 2026 to launch with both in-app purchases and ads, so this is now a submission blocker rather than follow-up work. With the Google Mobile Ads SDK in the app, the following become mandatory: UK/EEA consent through a certified consent platform (Google's UMP) before any ad request; the ATT prompt before personalised, IDFA-based ads (5.1.2(i)) - declining must not lock any feature, so rewarded ads must still work, non-personalised; the SDK's privacy manifest in the app; App Privacy answers that match Google's own disclosure (device ID, advertising data, product interaction, performance and crash data, coarse location from IP; "used to track you" if ATT is granted); a privacy policy naming Google as an advertising partner; ads appropriate for the age rating (2.5.18); visible close buttons; and **a way for players to report an inappropriate ad** (2.5.18). If children are a likely audience, child-directed ad settings and the UK Age Appropriate Design Code apply - *legal review* (M-8).
- **Evidence.** `privacy/tracking_enabled=false` in the preset; no consent, ATT or ad SDK code; ARCHITECTURE.md "Before real money" item 6.
- **Fix.** The work stream is laid out in section 6 and Phase 2 of the release plan.
- **Verify.** Fresh install with UMP debug geography set to EEA and to UK: consent form before any ad request (Google SDK debug logs, or a proxy showing no ad traffic before consent); refuse consent and decline ATT, and rewarded ads still pay; "Privacy choices" reopens the form; App Privacy answers match Google's data-disclosure page for the SDK version shipped; every placement reviewed on TestFlight with test ads.
- **Complexity.** L.

### HIGH

#### H-1 Purchase validation trusts the client
- **Description.** `StoreService._fulfil()` grants whatever the provider says; the code itself marks where validation belongs. With StoreKit 2, StoreKit's own signature check (`VerificationResult.verified`) is a reasonable baseline for a game of this size; server-side validation (App Store Server API, server notifications for refunds) adds protection against tampered devices and lets the premium balance be restored.
- **Evidence.** `src/services/store/store_service.gd:104`; ARCHITECTURE.md "Before real money" items 1-3.
- **Fix.** Minimum: verified transactions only, transaction-id de-duplication, revocation handling (part of B-2). Recommended if Crystal sales become material: a small backend that verifies `signedTransactionInfo`, receives App Store Server Notifications V2, and owns the Crystal ledger.
- **Verify.** A modified/unsigned transaction is rejected (StoreKit test environment); a sandbox refund revokes the entitlement.
- **Complexity.** M on device; L with a server.

#### H-2 Purchased Crystals live only on the phone
- **Description.** Consumable Crystals are stored only in the local save. Apple does not require consumables to be restorable, but a player who changes phone or reinstalls loses what they paid for, which drives refunds and complaints. `Remove Ads` and `Starter Pack` (non-consumable) come back through Restore; their Credits and Crystals deliberately do not.
- **Evidence.** `StoreService._fulfil()` grants currency only when `source == "purchase"`; no cloud save (`ARCHITECTURE.md` "Cloud save").
- **Fix.** Add iCloud key-value or CloudKit save (a new `SaveBackend` with a merge rule; the profile already has `created_at`, `last_seen`, `play_seconds`), or a server ledger (H-1). State the limitation in the store description and support page until then.
- **Verify.** Buy Crystals on device A, install on device B with the same Apple Account, balance appears.
- **Complexity.** M (iCloud KVS) to L (server).

#### H-4 Third-party licence notices are not shown anywhere
- **Update 22 Oct 2026: fixed, pending a device check.** Settings > Licences lists Godot's MIT notice, every engine component and its copyright holders, the full licence texts (all from the engine binary), and - in builds with the AdMob bridge - godot-cpp and Google's SDK terms (`third_party` in `data/game.json`). UI tests check for the Godot, FreeType, Open Sans and MIT texts.
- **Description.** Godot's MIT licence requires its notice to be included with the game; the engine also bundles third-party code and fonts under their own licences (FreeType, Mbed TLS, HarfBuzz, ICU, libpng, Ogg Vorbis, Open Sans under the SIL OFL, and 60+ more listed by the engine). The game shows none of them.
- **Evidence.** `Engine.get_copyright_info()` lists 70+ components; `ThemeDB.fallback_font` is "Open Sans SemiBold"; no licence screen in `src/ui`. Godot's "Complying with licenses" page: a credits or licences screen satisfies it.
- **Fix.** Add a "Licences" screen in Settings generated from `Engine.get_license_text()`, `get_copyright_info()` and `get_license_info()` (stays correct across engine updates), plus entries for godot-cpp (MIT) and the Google Mobile Ads and UMP SDKs, which the AdMob bridge now links into the app. Add a LICENSE/ownership statement for the project itself.
- **Verify.** Screen opens in the release build and includes the Godot MIT text, FreeType and Open Sans/OFL.
- **Complexity.** S.

#### H-5 Device coverage is one flagship phone on debug builds
- **Description.** The build declares iOS 15+ and any A12-or-newer iPhone and iPad. The only measurements are an iPhone 16 Pro Max (A18 Pro, iOS 27) running debug builds: 120 fps with ~240 enemies. ARCHITECTURE.md itself estimates older phones run GDScript 3-4x slower; the stability suite's worst steps reach 25-37 ms headless on an M1 Pro (1,000-enemy walls, chain explosions), which would be visible hitches on an A12. A second test phone was registered on 22 October; no result from it is recorded.
- **Evidence.** `docs/iphone_16_pro_max_self_test.txt`; this audit's test output (`1000-enemy wall: worst 36.6 ms`, under heavy machine load).
- **Fix.** Run the `--device-check` self-test and a manual session on the oldest supported phone you can borrow (iPhone XS/XR/11 or SE 2nd gen), one mid-range phone, the lowest iOS you keep (or raise the minimum to iOS 16/17 to cut the matrix), and an iPad if iPad stays. Test the **release** export. If needed, tune with the levers already documented (`max_enemies`, blast cap, reduced effects default on older chips).
- **Verify.** Self-test report from each device committed under `docs/`; 60 fps average and slowest second above ~45 fps in late Sector 3 on the oldest device.
- **Complexity.** M (mostly device access).

#### H-6 Balance rests on bot simulations; one human playtest is documented
- **Description.** The design doc is explicit: bot numbers are not a playtest. Documented human play is one session that ended at 2:58 in the freeze. Open questions it lists - Sector 1 boss fairness (40% bot clear rate with no upgrades), readability of Mortar/bombardment telegraphs under a thumb, the Sector 2-3 jump, mid-sector comfort, weak-looking weapons, and an Overdrive payout described as "generous, and due a second look" - are all unanswered.
- **Evidence.** GAME_DESIGN.md "Clear rates" and its question list; docs/playtest-1.
- **Fix.** A TestFlight external beta with 15-30 players for two weeks, the existing local event log (or an opt-in analytics provider, which changes the privacy answers) to measure first-session length, Sector 1 clear rate, day-1/day-7 return, where players quit. Rebalance from that, not from the bot alone.
- **Verify.** Written playtest report with numbers per question; changes re-checked with the simulator.
- **Complexity.** M (calendar time).

#### H-7 Name, branding and IP ownership not cleared
- **Description.** A web search found no game or app called "Swarm Shift", but that is not a trademark search, and "swarm" is common in game titles. The visual and audio assets are original in the narrow sense that the repository generates all of them from its own code (verified, 93/93 files). The code and generators were AI-written; that does not by itself establish freedom from third-party rights, and copyright ownership of AI-generated material is unsettled in some jurisdictions. The survivor-like genre is crowded, so the description and screenshots must not reference other games (4.1, 2.3.7).
- **Evidence.** This audit's provenance check; web search; `data/game.json` title "SWARM//SHIFT", display name "Swarm Shift".
- **Fix.** *Legal review*: trademark searches in the UK (UKIPO), EU (EUIPO) and US (USPTO) in classes 9 and 41, plus an App Store and Google Play name check; register the name if it is kept. Get written confirmation of who owns the code and assets (C2 vs STARSCALE vs contractors). Have a person listen to both music loops for accidental resemblance to existing tunes (they are simple chord progressions and arpeggios, so the risk is low, but nobody has listened critically). Decide whether the generated art/audio is the launch look.
- **Verify.** Written clearance; registration filed; ownership statement on file.
- **Complexity.** S engineering; M legal.

#### H-8 Empty camera, microphone and photo-library purpose strings
- **Description.** The generated Info.plist contains `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription` set to empty strings. The engine library references the microphone permission API. Apple requires a meaningful purpose string for any protected API the app may use, and empty strings are a common cause of upload warnings or 5.1.1 rejections, even when the feature is never used.
- **Evidence.** `build/ios/SwarmShift/SwarmShift-Info.plist`; `strings libgodot.a | grep requestRecordPermission` = 1 hit; no `privacy/*_usage_description` set in `export_presets.cfg`.
- **Fix.** Preferred: remove the keys from the release export (or build a custom export template without the camera/microphone modules, which also shrinks the binary). Otherwise fill them with honest text ("Swarm Shift does not use the microphone."). Confirm with Xcode's "Validate App".
- **Verify.** Validation passes with no purpose-string warnings; the app never shows a permission prompt.
- **Complexity.** S (strings) to M (custom template).

#### H-9 iPad is declared but never tested on an iPad
- **Description.** `TARGETED_DEVICE_FAMILY = "1,2"` means the app is listed for iPad, App Review may test on iPad, and a 13" iPad screenshot set becomes mandatory. The layout behaved correctly at 768x1024 in desktop emulation (this audit), but touch, performance, safe areas and Stage Manager/Split View (blocked by `UIRequiresFullScreen`, correctly) are unverified on hardware.
- **Evidence.** `export_presets.cfg` `targeted_device_family=2`; `build/ios/SwarmShift.xcodeproj/project.pbxproj`; screenshot tour output.
- **Fix.** Decide. Either test on a real iPad and produce 13" screenshots, or set the preset to iPhone-only for 1.0 (the app then still runs on iPads in iPhone compatibility mode, without its own screenshots).
- **Verify.** A run on a physical iPad, or the preset value checked in the release archive.
- **Complexity.** S to M.

#### H-10 No crash reporting outside the device
- **Description.** The only diagnostics are a local event log pulled from a connected phone. Once strangers play, a crash or freeze would be invisible.
- **Evidence.** `LocalLogAnalyticsProvider` ("Nothing leaves the device").
- **Fix.** Use Apple's own crash reports (Xcode Organizer and TestFlight feedback, no SDK and no privacy-label change) and upload dSYMs with each archive. Add a third-party crash/analytics SDK only if needed, and update the privacy policy and labels when you do.
- **Verify.** A deliberate test crash in a TestFlight build appears, symbolicated, in Organizer.
- **Complexity.** S.

#### H-11 An audio interruption that never ends leaves the game frozen
- **Description.** Godot 4.7.2 on iOS treats an audio session interruption as losing focus: it stops drawing and stops its main loop, and starts again only when iOS reports the interruption has ended, or the app becomes active again. If the "ended" notification never arrives while the app stays in front, the game sits on a still frame and ignores touches. Phone calls, Siri, alarms, other apps' audio and full-screen video ads can all interrupt the session.
- **Evidence.** Observed once, cause not proven. On 22 October 2026, during an ordinary session on an iPhone 16 Pro Max, the device log shows `Audio interruption began` at 19:01:36 and no matching `ended`; the game's event log stops at 19:00:31; the player reported the game froze. Godot source: `drivers/apple_embedded/app_delegate_service.mm` (`onAudioInterruption:` calls `on_focus_out()`, which stops rendering). The playtest-1 write-up already listed this as untested. Google's test ads did **not** trigger it: in the verified AdMob run there were no interruptions, and frames kept advancing after every ad.
- **Fix.** Reproduce first: trigger interruptions on purpose (incoming call, Siri, an alarm, music app started over the game) and read the bridge's `[admob]` trace, which logs every interruption with its reason. If confirmed, the smallest fix is native: when the app is active and an interruption has begun but not ended within a short time, reactivate the audio session and restart Godot's loop (for example from the AdMob bridge, which already observes interruptions), or patch the engine's handler. Add the scenario to the device test plan.
- **Verify.** Each interruption type above, during a run and at the menu: the game resumes by itself within a second of the interruption ending, with sound.
- **Complexity.** M.

### MEDIUM

#### M-1 One stability test is timing-sensitive (flaky under machine load)
- **Description.** `test_elite_drop_never_strands_the_upgrade_screen` first checks that its scenario really produces back-to-back choices in at least 3 of 6 seeds. It drives the HUD with real-time waits, so on a loaded machine (load average 30-53 during this audit) it sometimes sees only 2. The assertions that matter - no stranded upgrade screen, no HUD recoveries - passed on every run.
- **Evidence.** Full suite: 1 failed check out of 2,428; three isolated re-runs: pass, fail, pass. `tests/test_stability.gd:197`.
- **Fix.** Make the precondition independent of wall-clock timing (step the arena by simulated time, or count seeds until three produce a double choice), so a red run always means a regression.
- **Verify.** Ten consecutive passes while another heavy process runs.
- **Complexity.** S.

#### M-2 Starter Pack is a non-consumable that bundles consumable currency
- **Description.** Allowed, but its restore behaviour (skin and entitlement return, 300 Crystals and 5,000 Credits do not) must match the product description, or players and reviewers will read it as a broken restore.
- **Evidence.** `data/monetization.json` `starter_pack`; `StoreService._fulfil()`.
- **Fix.** Say "one-time" in the description and review notes; consider making the currency portion part of the skin's value rather than a currency grant. Also rename "Cache of Crystals", which clashes with the in-run "cache" drop.
- **Verify.** Review notes and in-app text agree with behaviour on a restore test.
- **Complexity.** S.

#### M-3 "Reset all progress" silently deletes purchased Crystals
- **Description.** The two-tap reset erases the whole save, including bought Crystals and the purchase history (entitlements return via Restore; consumables do not).
- **Evidence.** `src/ui/screens/settings_modal.gd:_on_reset`, `SaveService.reset()`.
- **Fix.** If any purchase exists, say so in the confirmation ("Purchased Crystals will be lost. Remove Ads and skins can be restored."), or keep the `purchases` section through a reset.
- **Verify.** UI test with a purchased profile.
- **Complexity.** S.

#### M-4 Accessibility gaps
- **Description.** Present: haptics toggle, reduced effects, screen-shake slider, damage-number toggle, separate volume sliders, large tap targets, safe-area layout. Missing: text size options (Dynamic Type is not read), colour-blind support (run energy green vs Credits gold vs red enemies is colour-coded), a photosensitivity notice for flashes and explosions, VoiceOver (not verified for the custom UI; the game is inherently visual). Accessibility Nutrition Labels are voluntary today, but Apple has said they will become mandatory.
- **Evidence.** `SettingsModal._build()`; GAME_DESIGN.md pickup colours.
- **Fix.** Add a text-scale setting, add shape differences or a colour-blind palette for pickups and enemy shots, show a short photosensitivity notice on first launch, default "reduced effects" on when iOS Reduce Motion is on. Answer the nutrition-label questions only for features that actually meet Apple's criteria.
- **Verify.** Run through with iOS colour filters and Reduce Motion on; a tester with a vision impairment if possible.
- **Complexity.** M.

#### M-5 Daily rewards and ad caps trust the device clock
- **Description.** Changing the phone's date unlocks extra daily rewards and resets the shop-ad cap.
- **Evidence.** `GameClock`; ARCHITECTURE.md "Before real money" item 4.
- **Fix.** Acceptable for 1.0 with no server (it only affects soft currency). Rate-limit backwards clock jumps, and move to server time if a backend arrives.
- **Verify.** Unit test with a clock moved back and forward.
- **Complexity.** S.

#### M-6 Overdrive payout looks too generous for the economy
- **Description.** The design doc reports Overdrive at 50% upgrades pays about 6,000 Credits and 7,500 XP per run; full permanent upgrades cost about 130,000 Credits, so a strong player could finish the meta in roughly 20 Overdrive runs.
- **Evidence.** GAME_DESIGN.md "Clear rates", final paragraph.
- **Fix.** Decide the intended time-to-max; cap or curve the Overdrive multiplier; re-run the simulator.
- **Verify.** Simulator output before and after, plus beta data (H-6).
- **Complexity.** S.

#### M-7 No production analytics (product decision)
- **Description.** There is no way to see retention, conversion or where players quit after release. Adding analytics changes the privacy policy and App Privacy answers.
- **Evidence.** Only `LocalLogAnalyticsProvider` is wired.
- **Fix.** Decide whether App Store Connect's own App Analytics (opt-in, no SDK) is enough for 1.0. If an SDK is added, implement it as an `AnalyticsProvider`, gate it on consent, and update the disclosures.
- **Verify.** Disclosures match the SDK's data list.
- **Complexity.** S to M.

#### M-8 Age assurance and children's privacy laws - *legal review*
- **Description.** US state laws (Texas SB 2420 in force since June 2026; Utah and Louisiana scheduled) put duties on app developers around age signals and parental consent, which Apple supports through the Declared Age Range API. In the UK, the ICO's Age Appropriate Design Code applies to online services likely to be accessed by children, which an arcade game with ads may be. Whether and how these apply to a UK publisher with no accounts and no data collection is a legal question, and the answer changes once ads or analytics are added.
- **Evidence.** Apple developer news (Texas, February/June 2026); no age handling in the app.
- **Fix.** Legal opinion before launch; set ad content and child-directed flags to match; adopt the Declared Age Range API if advised.
- **Verify.** Written opinion on file; ad network settings match it.
- **Complexity.** M legal; S-M engineering.

### LOW

| ID | Description | Evidence | Fix | Verify | Size |
| --- | --- | --- | --- | --- | --- |
| L-1 | Version numbers disagree: `project.godot` 0.1.0, preset and `game.json` 0.2.1 | those files | One source of truth, 1.0.0 for launch | Settings footer, Info.plist and App Store Connect agree | S |
| L-2 | Development launch flags (`--autoplay`, `--device-check`, `--profile`, `--snap`) ship in release code | `src/app/app.gd`, `device_check.gd` | Harmless on iOS (no launch arguments in the wild); optionally compile out for release | `strings` on the release pck | S |
| L-3 | The local event log keeps writing in release builds | `LocalLogAnalyticsProvider` | Fine (on-device only, capped at 512 KB, valuable for support); mention it in the privacy policy | Policy text | S |
| L-4 | Sound follows the Ring/Silent switch (ambient session) | README | Product choice; many players expect game audio in silent mode to stay off. Keep, but mention in support FAQ | - | S |
| L-5 | Fallback prices in `monetization.json` are US-dollar strings | `data/monetization.json` | Only shown if StoreKit has not answered; show "-" instead in release | Airplane-mode shop | S |
| L-6 | Engine bundles unused modules (camera, physics engines, visionOS libraries in the Xcode project) | `build/ios` | Custom export template with unused modules disabled: smaller download, fewer purpose strings | Binary size before/after | M |

---

## 5. Stability and quality detail

| Area | State | Evidence | Gap |
| --- | --- | --- | --- |
| Combat freezes | Root cause of the playtest freeze fixed; HUD/run reconciliation repairs any future mismatch and logs it | docs/playtest-1; stability tests pass; `hud recoveries 0` in all load tests | No human session since the fix is documented; M-1 flakiness |
| Chain reactions | Explosion queue capped per step and by field size; 300-explosion chain drained in 63 steps, worst step 6 ms headless | test output | Older-phone timing (H-5) |
| Level-up transitions | Serial-numbered hands, cancellable fades, multi-touch taps, reroll lock; 300-gem vacuum deals one hand per level in order | stability tests | Release build, real thumbs |
| Difficulty balance | Tuned by simulator; numbers documented | GAME_DESIGN.md | H-6, M-6 |
| Sector progression | 20 sectors, rosters and mutators tested | `threats`, `progression` suites | Sectors 4-20 never played by a human |
| Permanent upgrades | 16 tracks, gates, bulk buy tested | `progression` suite | - |
| Save integrity | Atomic write + backup + checksum + migration fixture; run ledger pays once; crash mid-run recovered at next launch | `services`, `progression` suites; device self-test storage checks | Real App Store update path; no cloud copy (H-2). A bad checksum is recorded but the save is still loaded - correct for player goodwill, noted only |
| Heavy load | 1,000 enemies, everything-build 60 s, 10-minute soak with flat memory | test output | Thermal behaviour over 20+ minutes on device |

**Physical-device test gaps:** release build; any phone older than the iPhone 16 Pro Max; iOS 15-17; iPad; incoming call / Siri / alarm during a run and during a level-up choice; backgrounding during an ad or purchase (once real); low storage; low-power mode; 30-minute Overdrive session for thermals; accessibility settings (Reduce Motion, larger text, colour filters); the second registered test phone.

---

## 6. Monetisation: implemented vs mocked

| Item | Implemented | Mocked / missing |
| --- | --- | --- |
| Rewarded ads (revive, reroll, double run Credits, daily double, shop Credits 3/day) | Placements, opt-in UI, policy, caps, pay-once guards, analytics events | Ad network (mock overlay) |
| Interstitials | Only between runs, not before run 3, every 2nd run, 180 s apart, never after a rewarded ad, off with Remove Ads - all tested | Ad network |
| Remove Ads | Non-consumable entitlement suppresses interstitials | StoreKit |
| Premium currency (Crystals) | Earned in play and sold in three packs; exchange to Credits; nothing requires it | StoreKit; no cloud backup (H-2) |
| Starter Pack | Grants Crystals, Credits, AURUM skin, entitlement | StoreKit; see M-2 |
| Restore Purchases | Button, re-grants entitlements without re-paying currency | StoreKit `AppStore.sync()`; never tested for real |
| Transaction validation | None (client trusts provider) | H-1 |
| Reward duplication | Run ledger by run id; doubled flag on run and stored summary; daily claim checked; purchase busy flag; non-consumables cannot be bought twice | Transaction-id de-duplication for real transactions (B-2) |
| Purchase failure handling | `purchase_failed` signal and analytics; busy flag released | User-facing error messages for real StoreKit errors (network, cancelled, pending, not allowed) |
| Consent and privacy | Not built (no data leaves the device today) | UMP consent and ATT, required for 1.0 (B-7) |

**Production integrations for 1.0** (scope decided 22 October 2026: purchases and ads at launch):

- **Purchases:** StoreKit 2 through a thin native iOS plugin for Godot 4.7 behind `StoreProvider`. Keep it small; StoreKit 2 handles signature verification and entitlement queries itself. Check any community plugin for StoreKit 2 support, maintenance and Godot 4.7 compatibility before adopting it - an outdated StoreKit 1 wrapper is not a good base.
- **Ads:** Google AdMob (Google Mobile Ads SDK) with Google's User Messaging Platform (UMP) for consent and the ATT explainer. No mediation at launch: one network keeps the privacy disclosures, SKAdNetwork list and testing small. AppLovin MAX or AdMob mediation can be added later behind the same `AdProvider` if fill or revenue disappoint.
- **Do not enable either** in a build that reaches players without sign-off; the brief requires approval before live payments or advertising. Until then, development and TestFlight builds use Google's **test ad units** only - tapping real ads on your own app is invalid traffic and can get the AdMob account suspended.

### AdMob and consent work stream

**Native layer (iOS plugin).** A small Swift/Objective-C plugin or GDExtension that wraps the Google Mobile Ads SDK and the UMP SDK (Swift Package Manager or CocoaPods), built against Godot 4.7.2's iOS plugin interface. Before choosing, check the current SDK releases' minimum iOS and Xcode versions against this project (iOS 15.0, Xcode 27.1), and that the SDK version ships a privacy manifest (Google says 11.2.0 and later do). Exposes to GDScript: consent status, `canRequestAds`, privacy-options-required, present consent form, present privacy options, load/show rewarded, load/show interstitial, and signals for loaded, failed, shown, dismissed, reward earned.

**Info.plist and project** (through `export_presets.cfg` / the plugin's config, never by hand in `build/ios`):
- `GADApplicationIdentifier` (the AdMob app id - a C2 AdMob account is needed first).
- `SKAdNetworkItems` with Google's published list.
- `NSUserTrackingUsageDescription` - a plain sentence, e.g. "Allows ads to be more relevant to you. Swarm Shift works the same either way." Set `privacy/tracking_enabled` accordingly.
- The SDK's privacy manifest merged into the app's.

**Consent and ATT flow** (UMP is designed for this order):
1. Every launch: `requestConsentInfoUpdate` (Google requires it on every launch; do not rely on a saved consent string).
2. `loadAndPresentIfRequired` shows the GDPR form in the UK/EEA (and Switzerland), the US-state message where configured, and the IDFA explainer followed by Apple's ATT prompt. Configure all of these in AdMob's *Privacy & messaging* tab.
3. Only when `canRequestAds` is true: start the Mobile Ads SDK and preload one rewarded ad. Gate this with a flag so a launch with previous-session consent does not double-initialise.
4. Consider running steps 2-3 after the first completed run rather than at first launch, so the first thing a new player sees is the game. Nothing needs an ad before then: interstitials are already held back until run 3, and rewarded ads are opt-in.
5. Settings gets **Privacy choices** (shown only when UMP reports the entry point is required; calls `presentPrivacyOptionsForm`) and **Report an ad** (opens the support form with the placement and time pre-filled), next to the Privacy Policy and Support rows from B-4.

**`AdMobAdProvider`** (GDScript, behind the existing `AdProvider`; `AdsService` policy is unchanged):
- `is_rewarded_ready()` / `is_interstitial_ready()` reflect a loaded ad, so the existing UI hides offers when there is no fill; preload the next ad after each show; back off after load failures.
- `show_rewarded()` resolves true only on the SDK's reward callback, and only after the ad is dismissed (the interface already requires that). A timeout returns false if the SDK never calls back.
- Pause the game tree and music while a full-screen ad is up and resume on dismissal; test against the game's "ambient" audio session (`mix_with_others`) and an incoming call during an ad.
- Remove Ads keeps suppressing interstitials only (rewarded stays available), as designed.
- Rewards are soft currency, revives and rerolls, so the client callback is acceptable at launch. Server-side verification of rewarded ads is not needed unless rewards become purchasable value.
- Release builds select `AdMobAdProvider`; debug and automated runs keep `MockAdProvider`, so the 111 existing tests still run headless.

**AdMob account settings:** maximum ad content rating to match the App Store age rating (G or PG for a low rating); child-directed and under-age-of-consent tags per the legal advice in M-8; ad units per format (and per placement if reporting by placement is wanted); `app-ads.txt` on C2's website, whose domain must match the developer website in App Store Connect; link the AdMob app to its App Store listing once the app is live.

**Disclosures:** privacy policy names Google as an ad partner and links Google's policy; App Privacy answers from Google's data-disclosure page for the shipped SDK version; age rating questionnaire answered with ads included.

**Tests:** unit tests for `AdMobAdProvider` against a fake native bridge (load failure, no fill, timeout, dismissed without reward, reward then dismiss); on device with UMP debug geography EEA, UK and not-EEA; consent refused; ATT denied; ATT allowed; airplane mode; Remove Ads owned; ad shown while a revive countdown is running; app backgrounded mid-ad.

**Estimate:** about 2-3 weeks on top of the StoreKit work for one developer (plugin and provider about 1-1.5 weeks, consent, ATT and settings about 3-4 days, device testing about 3 days). Interstitials are already built on the policy side; launching with both formats adds little engineering, so ship both and switch interstitials off in `data/monetization.json` if beta retention suffers.

---

## 7. iOS readiness detail

| Item | Found | Needed for the store |
| --- | --- | --- |
| Xcode / SDK | Xcode 27.1 (27A9275), iOS SDK 27.1 | Met (Xcode 26+ required) |
| Godot | 4.7.2 stable, official templates installed | Met; keep templates matched to the editor |
| Export | Debug export, `export_method_debug=1`, project-only | Release export, App Store method (B-5) |
| Signing | Automatic, Apple Development, team STARSCALE `8RGSL8W378` | C2 team, Apple Distribution certificate, App Store profile (B-1, B-5) |
| Bundle id | `com.starscale.swarmshift` | C2's final id, fixed before the App Store Connect record (B-1) |
| Version | 0.2.1 (3) | 1.0.0, build number rising per upload |
| Devices | iPhone + iPad, A12+, iOS 15.0+ | Decide iPad (H-9); test the minimums (H-5) |
| Orientation | Portrait only, full screen | Met |
| Icon | 1024 px, no alpha, full asset catalog | Met; final art is a business decision |
| Privacy manifest | Engine-generated, required-reason APIs declared, no tracking | Merge SDK manifests when added |
| Purpose strings | Camera/microphone/photos present but empty | H-8 |
| Encryption | `ITSAppUsesNonExemptEncryption = false` | Met while there is no non-exempt crypto |
| Entitlements | Empty | Add only what is used (In-App Purchase needs no entitlement; Game Center would) |
| Simulator | Not usable with Godot's stock template on Apple silicon (known) | Real devices / TestFlight |
| TestFlight | Never used | Internal group first, then external beta (needs Beta App Review) |
| App Store Connect | No record | Create under C2 |
| Screenshots | Development only | iPhone set required; 13" iPad set if iPad kept (B-6) |
| App privacy disclosures | Not answered | Answers from Google's AdMob disclosure (B-6, B-7) |
| Age rating | Not answered | New questionnaire (B-6) |
| Support URL / privacy policy | None | B-4 |

---

## 8. Copyright and IP inventory

| Material | Count | Origin | Licence evidence | Risk |
| --- | --- | --- | --- | --- |
| Sprites, enemy art, boss, player, pickups | 35 PNG | `tools/generate_art.gd` (signed-distance shapes in code) | Regenerated byte-identical in this audit | Low |
| App icon, splash | 2 PNG | same generator | Byte-identical | Low; trademark check of the logotype with the name (H-7) |
| Shaders | 6 | Hand-written in the repo, own comments, no third-party headers | Read in this audit | Low |
| Sound effects | 52 WAV | `tools/generate_audio.gd` (oscillators, noise, envelopes) | Byte-identical | Low |
| Music | 2 WAV | same generator: simple chord progressions and arpeggios | Byte-identical | Low; one critical listen recommended (H-7) |
| Fonts | 0 bundled | Engine default **Open Sans SemiBold** | SIL Open Font License 1.1 via Godot | Low; include notice (H-4) |
| Engine | Godot 4.7.2 | godotengine.org official build | MIT + third-party list from `Engine.get_copyright_info()` | Low; notices required (H-4) |
| Bundled frameworks in Xcode project | MoltenVK, Godot libraries | Godot export template | Apache 2.0 / MIT (in the engine's list) | Low; notices (H-4) |
| Code dependencies, plugins, SDKs | None | - | - | None today. Google Mobile Ads SDK and UMP SDK planned for 1.0: add their licence terms to the Licences screen (H-4) |
| Game code and data | ~10,000 lines GDScript, 10 JSON tables | Written for this project with AI assistance | Repository history from 12 Oct 2026 | Ownership statement needed (B-1, H-7) |
| Name and branding | "SWARM//SHIFT", "Swarm Shift", tagline "ONE CORE. ENDLESS SWARM." | Project | No conflict found by web search only | Trademark search needed (H-7) |
| In-game names | Overseer, Prism Lance, Singularity, Bastion, AURUM, etc. | Generic words | - | Low; include in the trademark review if any becomes a brand |
| Development screenshots | `docs/screenshots` | Screenshot tour | Not shipped (`docs/.gdignore`) | None |

Nothing was found whose commercial redistribution rights cannot be established, apart from the open questions on ownership of the work itself (B-1) and name clearance (H-7).

---

## 9. Prioritised release plan

The order is set by what blocks what. Estimates are engineering time for one developer working with AI assistance; external steps run in parallel.

**Phase 0 - Decisions (management, this week).**
Publisher entity and Apple account (B-1); final name and bundle id (H-7); iPad yes/no (H-9); whether the generated art and audio are final; price points.

**Decided 22 October 2026: 1.0 launches with both in-app purchases (StoreKit 2) and ads (AdMob with UMP consent).** This adds the ad work stream to Phase 2 and makes the consent, ATT and disclosure work a blocker (B-7). The App Privacy label will no longer be "Data Not Collected".

**Phase 1 - Accounts and legal (external, start now, 1-4 weeks).**
C2 organisation enrolment and D-U-N-S; Paid Apps Agreement, tax, banking; DSA trader status; **C2 AdMob account** (with its own payments and tax profile) and the app registered in it; C2 website able to host `app-ads.txt`, the privacy policy and the support page; trademark searches; ownership statement; legal advice on children's privacy and age assurance for an ad-supported game (M-8); privacy policy (naming Google as ad partner) and support page drafted, reviewed and hosted.

**Phase 2 - Store-critical engineering (about 5-6 weeks).**
Two work streams for one developer, in this order; the AdMob items can start before the C2 Apple account exists, because they use Google's test ad units and the existing Development signing.

*Purchases and platform (about 3 weeks):*
1. Mocks selected only in debug and automated builds (B-2, B-3).
2. StoreKit 2 provider with verified transactions, updates listener, restore, revocation, error messages (B-2, H-1).
3. Settings rows: Privacy Policy, Support, Licences screen (B-4, H-4).
4. Purpose strings removed or filled (H-8); version 1.0.0 (L-1).
5. Release export and archive script; first "Validate App" (B-5).
6. Reset warning for purchases (M-3); Starter Pack wording (M-2); fix the flaky test (M-1).

*Ads and consent (about 2-3 weeks; details in section 6):*
7. iOS plugin wrapping the Google Mobile Ads SDK and UMP; `GADApplicationIdentifier`, `SKAdNetworkItems`, `NSUserTrackingUsageDescription`, SDK privacy manifest (B-3, B-7). **Done 22 Oct 2026** - [native/admob](native/admob/README.md): consent, tracking prompt, SDK start, test rewarded and interstitial ads verified on an iPhone 16 Pro Max (debug build, test ads only).
8. Consent and ATT flow gating SDK start-up on `canRequestAds`; decide first launch vs after the first run (B-7). **Done 22 Oct 2026** - consent checked at every launch; the form waits for the first quiet moment after the first run (before the next run or on returning to the menu); verified on the iPhone with stored consent wiped.
9. `AdMobAdProvider` behind `AdProvider`: preload, no fill, timeouts, pause and resume, rewards only on the SDK's reward callback; tests against a fake bridge (B-3). **Done 22 Oct 2026** - 11 tests (52 checks) against a fake bridge; a shop rewarded test ad paid +150 Credits on the iPhone. Game audio is silenced during ads rather than the game being paused: every rewarded placement already sits on a paused screen.
10. Settings rows: Privacy choices, Report an ad (B-7, 2.5.18). **Done 22 Oct 2026 (Mac only)** - Settings now has Privacy Policy, Support, Report an ad, Licences, and Privacy choices when Google's consent SDK requires it. Links are **placeholders on example.com** in `data/game.json` (`links`) until C2 hosts real pages (B-4). Report an ad appends the last ad's format, placement, time, network and app version - no personal data. Covered by UI tests and screenshots at the smallest supported screen; not yet checked on a phone.
11. AdMob console: Privacy & messaging (GDPR, US states, IDFA explainer), max ad content rating, child-directed settings per legal advice, ad units (B-7, M-8).

**Phase 3 - Device and beta (2-3 weeks, overlaps Phase 2's end).**
TestFlight internal build; device matrix including the oldest supported iPhone and, if kept, an iPad (H-5, H-9); sandbox purchase test plan (B-2); consent and ATT matrix with UMP debug geographies, test ads only (B-7); audio interruptions during play and during ads (H-11); external beta with 15-30 players (H-6), watching whether interstitials hurt day-1 return; crash reports in Organizer (H-10); rebalance from beta data (H-6, M-6).

**Phase 4 - Store listing (1 week, during the beta).**
Metadata, screenshots at store sizes, age rating with ads declared, App Privacy answers matching Google's disclosure for the shipped SDK, IAP products with review screenshots, review notes explaining the Starter Pack, the consent flow and that nothing is required to progress (B-6, B-7); `app-ads.txt` live on the developer website. Accessibility improvements that are cheap (M-4).

**Phase 5 - Submit.**
Final regression: full test suite, release build on two devices, every purchase in sandbox, restore on a second device, consent and ATT paths, every ad placement with test ads. Switch to live ad units only in the build being submitted, with sign-off. Submit with manual release so C2 chooses the launch day; link the AdMob app to the App Store listing once it is live.

**After launch (1.1).** Cloud save for purchased Crystals (H-2); analytics decision (M-7); mediation if ad fill or revenue is low; age-assurance follow-up (M-8).

---

## Sources

Apple pages read on 22 October 2026:

- [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) - Xcode 26 / iOS 26 SDK uploads since 28 April 2026; iOS 13 minimum since 9 September 2026; new age rating questions by 31 January 2026; DSA trader status; required-reason APIs.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) - 2.1, 2.3, 2.5.18, 3.1.1, 4.1, 4.3, 5.1.1, 5.1.2, 5.2.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) - required iPhone and 13" iPad sets.
- [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels) - voluntary for now, to become required.
- [New requirements for apps available in Texas](https://developer.apple.com/news/?id=btkirlj8) and [Next steps for apps distributed in Texas](https://developer.apple.com/news/?id=2ezb6jhj) - Declared Age Range API.
- Godot: [Complying with licenses](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).
