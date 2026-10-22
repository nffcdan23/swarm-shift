# AdMob bridge

A small GDExtension that exposes the Google Mobile Ads SDK and Google's User Messaging Platform (UMP, the consent SDK) to GDScript as the engine singleton `AdMob`. It holds no ad policy: what to show and when stays in `AdsService`. Phase 2 item 7 of [APP_STORE_READINESS.md](../../APP_STORE_READINESS.md).

Status: built and verified on an iPhone 16 Pro Max with Google's test ads (22 October 2026). The game itself still uses `MockAdProvider`; wiring the bridge in as an `AdProvider` is item 9.

## Build

```bash
tools/build_admob.sh
```

`tools/ios_deploy.sh` runs it automatically the first time. It downloads pinned, checksum-verified dependencies into `build/deps` (`tools/fetch_ios_deps.sh`), builds, and installs into `addons/admob`:

| Output | What |
| --- | --- |
| `bin/libadmob.ios.template_{debug,release}.xcframework` | Bridge + godot-cpp, static, arm64. Godot's iOS exporter links it and registers the entry symbol itself |
| `bin/libadmob.macos.template_debug.framework` | Desktop stub (`admob_stub.cpp`): same class, `is_supported()` is false, so the editor, tests and Mac runs load cleanly |
| `ios/GoogleMobileAds.xcframework`, `ios/UserMessagingPlatform.xcframework` | Google's SDKs, linked statically into the app. Xcode embeds their privacy manifests |
| `admob.gdextension` | Written last, so Godot only sees the extension once it is complete |

All of it is git-ignored. Without it the game runs exactly as before and iOS exports go ahead without ads (the export plugin says so).

| Dependency | Version | Licence |
| --- | --- | --- |
| Google Mobile Ads SDK | 13.11.0 | Google's SDK terms; ships in the app |
| Google User Messaging Platform | 3.1.0 | Google's SDK terms; ships in the app |
| godot-cpp | branch 4.5, commit `27d9dd23` | MIT; ships in the app (add to the Licences screen, audit H-4) |
| SCons | 4.11.1 | MIT; build tool only |

Extensions built against godot-cpp 4.5 run on Godot 4.5 and later, so the bridge does not need rebuilding for an engine patch release.

## What goes into the iOS export

`addons/admob/admob_export_plugin.gd` (an editor plugin, enabled in `project.godot`, never shipped) adds to every iOS export:

- `GADApplicationIdentifier` from `addons/admob/admob_export.cfg` - **Google's sample app id**, which only ever serves test ads. Putting C2's real app id there switches on live ads and needs sign-off.
- `SKAdNetworkItems` - Google's list of 50 identifiers (same file).
- `NSUserTrackingUsageDescription` - the text on Apple's tracking prompt (same file).
- The `-ObjC` linker flag Google requires.

## API

```gdscript
var ads := Engine.get_singleton("AdMob")  # check Engine.has_singleton("AdMob") first
```

| Call | Notes |
| --- | --- |
| `is_supported()`, `get_sdk_version()` | False / empty on the desktop stub |
| `consent_request_update(debug_geography, test_device_ids, under_age_of_consent)` | Every launch, as Google requires. Emits `consent_info_updated(error)` |
| `consent_load_and_present_if_required()` | Shows Google's form (and, if configured in AdMob, the tracking explainer and Apple's prompt). Emits `consent_form_dismissed(error)` |
| `consent_can_request_ads()`, `consent_get_status()`, `consent_is_privacy_options_required()` | Status codes are the `CONSENT_*` constants |
| `consent_present_privacy_options()` | For the Settings "Privacy choices" row. Emits `privacy_options_dismissed(error)` |
| `consent_reset()` | Testing only |
| `get_tracking_status()` | `TRACKING_*` constants |
| `set_test_device_ids(ids)`, `set_max_ad_content_rating("G"/"PG"/"T"/"MA")`, `set_age_treatment(AGE_*)` | Request configuration; set before loading |
| `start()` | Only once `consent_can_request_ads()` is true. Emits `started` |
| `load_rewarded(unit)`, `is_rewarded_loaded()`, `show_rewarded()` | Signals: `rewarded_loaded`, `rewarded_failed_to_load(error)`, `rewarded_shown`, `rewarded_earned(type, amount)`, `rewarded_dismissed`, `rewarded_failed_to_show(error)` |
| `load_interstitial(unit)`, `is_interstitial_loaded()`, `show_interstitial()` | Same signals with the `interstitial_` prefix, no `earned` |
| `debug_log(text)` | Writes to the device log, which an attached Mac can read; `print()` does not get there |

Every signal is emitted deferred, so handlers run on Godot's main loop, never inside an SDK callback. An `error` argument is empty on success. A shown ad is dropped after it closes; load the next one.

Every SDK event is also written to the device log with the prefix `[admob]`, together with any audio session interruption. After each ad or consent form closes, the bridge checks that Godot is still drawing frames (`frames after ...: running` or `STALLED`). Godot stops its main loop when an audio interruption begins and restarts it only when the interruption ends, so this is the line to look for if the game ever appears frozen after an ad.

## On-device check

```bash
tools/ios_deploy.sh --admob-check
```

Installs the build, launches it with `--admob-check` (`src/app/admob_check.gd`) and prints the bridge's trace and the report. Someone has to be at the phone to answer the consent form and close the two test ads. `ADMOB_ARGS=--admob-reset` forgets stored consent first; `ADMOB_ARGS=--admob-no-show` stops after loading.

Result on 22 October 2026, iPhone 16 Pro Max, iOS 27, debug build, UK: consent required → form answered → consent obtained, tracking authorised → SDK started → test rewarded and interstitial ads loaded, shown and closed, reward reported (`coins x10.0`) → frames kept running after every ad. `RESULT PASS - 12 passed, 0 failed`. Not yet covered: consent refused, tracking denied, no network, a release build, an incoming call during an ad.
