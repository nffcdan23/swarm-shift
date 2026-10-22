# Architecture

Godot 4.7.2, GDScript, Mobile renderer (Metal on iOS, Vulkan on Android with automatic OpenGL fallback). Portrait, 720-wide design space that scales to the device.

## The shape of it

```
App (autoload: src/app/app.gd)          app-lifetime services, built in dependency order
 └─ Main (scenes/main.tscn)             the shell: menus <-> run <-> results
     ├─ MenuShell                       top bar, five tab screens, dialogs, toasts
     └─ Arena + Hud                     one run; created on PLAY, freed afterwards
```

Three rules hold the structure together:

1. **One autoload.** `App` is the composition root. It constructs every service and hands each a reference to itself. Swapping an implementation (real ads, real store, cloud save, another analytics SDK) is a change in `App.boot()` and nowhere else.
2. **Run state lives in the Arena, not in globals.** Enemies, weapons, the build - everything that belongs to one run is owned by the `Arena` node and disappears with it. The Arena reads a `RunConfig` and never touches the profile.
3. **The Arena does not know about UI.** It emits signals (`choice_started`, `run_ended`, `announced`...) and exposes state. The HUD listens. That is why the same class runs headless for tests at hundreds of times real speed.

## Services (`src/services`)

| Service | Responsibility |
| --- | --- |
| `GameData` | Loads `data/*.json`; `apply_overrides()` deep-merges remote config on top |
| `SaveService` | The profile dictionary; debounced, atomic, checksummed writes via a `SaveBackend` |
| `SaveMigrations` | Schema version, defaults, forward migrations |
| `Economy` | The only place balances change; every grant/spend names its source |
| `AccountService` | The permanent Player Level: XP, per-level rewards, what each level unlocks |
| `MetaService` | Permanent upgrades: categories, Player Level gates, single and bulk purchase, effect text |
| `ArsenalService` | Weapon / core / skin unlocks and the loadout |
| `CampaignService` | Sectors, tier scaling, sector briefs and mutators, Endless unlock |
| `MissionService` | Daily missions (seeded per day and install) |
| `AchievementService` | Thresholds over lifetime stats |
| `DailyRewardService` | Seven-day login calendar |
| `StatsService` | Lifetime statistics |
| `RunLedger` | Turns a run into rewards, exactly once (by run id); checkpoints the run in progress and recovers it if the app never finishes it |
| `AdsService` + `AdProvider` | Ad policy (caps, rules) + the network adapter |
| `StoreService` + `StoreProvider` | Purchases and entitlements + the platform adapter |
| `Analytics` + `AnalyticsProvider` | Event front door + sinks |
| `AudioService`, `HapticsService`, `SettingsService`, `GameClock` | As named |

Services are plain `RefCounted` objects (only `AudioService` is a node, because it owns players). Tests rebuild the whole set against an in-memory save with `App.boot(MemorySaveBackend.new())`.

## A run (`src/game`)

A swarm game lives or dies on entity count, so the simulation is **data-oriented**: there is no node per enemy, bullet or pickup. Each system keeps parallel packed arrays (one array per field, one index per entity) and one loop does everything for that entity type.

`Arena.step(dt)` is the entire simulation, in a fixed order:

```
player -> director (spawning) -> boss -> enemies -> weapons -> projectiles
       -> combat.flush (queued area damage) -> enemy bullets -> hazards -> pickups
       -> enemies.sweep (remove the dead) -> effects -> commit draw buffers
```

| System | Notes |
| --- | --- |
| `EnemySystem` | AI (seek, dasher, shooter, mortar, weaver, bomber), movement, crowd separation, player contact and the draw instance in one loop. Spatial hash grid for queries. |
| `ProjectileSystem` | All player projectiles in one pool; behaviour is flags (homing, seeking, exploding, splitting) |
| `BulletSystem`, `HazardSystem`, `PickupSystem` | Enemy fire, telegraphed ground blasts, energy / credits / drops |
| `Combat` | The only path to enemy health. Crits, bonus rules, stats, and every on-hit / on-kill augment |
| `Director` | Reads the timeline: spawn tracks, set pieces (surge, elite, pack, pincer, line, bombard), boss, tier scaling, and which of those a sector has unlocked or mutated |
| `RunDiagnostics` | Counters for tests, the simulator and `--perf`: back-to-back choices, queue peaks, anything a safety valve dropped |
| `Boss` | State machine driving one slot in the `EnemySystem`, so every weapon can hit it with no special cases |
| `RunBuild`, `UpgradeSystem` | What the player has assembled; rolling and applying the three-card choice |
| `Weapon` + `weapons/*.gd` | One small script per weapon |
| `Autopilot` | The bot used by tests, simulations and the screenshot tour |

Rules that keep this safe:

- **Indices are only valid for the current step.** Enemies are stored densely and compacted when they die. Keep `id[i]` and re-validate with `is_valid()` to refer to one later.
- **Kills are deferred.** `hurt()` marks an enemy dead; `sweep()` compacts once at the end of the step.
- **Area damage is queued.** `Combat.blast()` adds to a queue resolved in `flush()`. An explosion whose kills cause more explosions just grows the queue, and a per-step cap turns a huge chain into a visible rolling wave instead of a one-frame spike.
- **`on_enemy_killed` must not start an overlap query** - the caller may be iterating the shared result buffer.
- **Gameplay randomness uses `arena.rng`.** A seed reproduces a run exactly (there is a test for it). Visual-only effects may use the global generator.
- **Nothing loops on a value from data without a bound.** Energy grants are validated and capped per grant, spawn tracks and scripted events have a per-step budget, the explosion queue has a cap scaled to the field, and every pool (`EnemySystem`, `ProjectileSystem`, `PickupSystem`, `HazardSystem`, effects) refuses or merges when full. `RunDiagnostics` counts each time one of these opens.
- **Nothing hurts without a telegraph.** Blasts go through `HazardSystem`, which draws the full blast circle for the whole fuse and refuses a fuse shorter than `MIN_DELAY`. A data test checks every blast in the tables can be walked out of from its centre.

### The run and the HUD

`Arena` owns the run's state machine (`PLAYING`, `CHOOSING`, `PAUSED`, `DOWNED`, `ENDING`, `ENDED`) and knows nothing about UI: it emits signals and the `Hud` listens. Two separate state machines joined by signals can disagree, and the first device playtest froze because they did ([docs/playtest-1](docs/playtest-1/README.md)). The rules since:

- **Transitions happen between steps.** Level-ups and caches are counted during a step and opened one at a time in `_after_step`; `choose()` deals the next pending hand directly.
- **Every hand has a serial** (`Arena.choice_serial`). The overlay records the serial it is showing, and a pick is only accepted for the hand still on the table.
- **Overlays are safe to re-present at any moment.** `LevelUpOverlay.present()` cancels a fade in progress; anything delayed (a fade, the pick confirmation) checks a generation number before it acts. Track and kill any tween whose callback hides something.
- **`Hud._reconcile()` runs every frame** and proves the two machines agree: choosing means the current hand is on screen, paused means a pause menu exists, downed means a revive is pending. A mismatch is repaired and reported as a `hud_recovered` event. It should never fire; the stability tests assert that it does not.

Input: Godot turns only the first finger on the glass into mouse events, and buttons listen to the mouse. `TouchTaps` (a child of `App`) mirrors that rule and converts a quick tap by any other finger into a click, so buttons work while a thumb is steering. The joystick keeps tracking its finger while disabled, so steering resumes after an overlay without re-touching.

### Rendering

Everything on the battlefield is drawn by a handful of `SpriteBatch` nodes (`MultiMeshInstance2D`), one draw call each regardless of count, all sampling one atlas that is packed at startup from the individual PNGs in `assets/sprites/atlas/`. Systems write 16 floats per instance straight into a buffer.

Particles are **stateless on the GPU** (`particle.gdshader`): a particle is written once when born and the shader derives its position from the clock, so thousands cost the CPU nothing per frame.

Two sprite conventions: *mix* sprites are full colour with normal blending (enemies, pickups); *energy* sprites are white with intensity in alpha, drawn additively and tinted at runtime (projectiles, beams, glows).

### Performance

Measured headless on an M1 Pro (`--bench`): about 0.8 ms per step with 490 enemies alive, including draw-buffer writes; the enemy loop is roughly 90% of that. The worst single step seen is 5-6 ms, during large kill chains. A mid-range phone runs GDScript roughly 3-4x slower, which still fits a 16.6 ms frame on average but makes those chain-reaction steps the first place to look for dropped frames. The levers, in order: `max_enemies` in `game.json`, `MAX_BLASTS_PER_STEP` in `combat.gd`, the "reduced effects" setting (halves particle bursts, simplifies the floor shader), then the per-system numbers from `--bench`. On an iPhone 16 Pro Max (debug build) the game holds 120 fps with 250 enemies on screen, at about 1.4 ms of simulation per frame. That is a flagship; an older or mid-range phone has **not been measured yet**, and that is where these levers will matter.

## Data (`data/*.json`)

| File | Contents |
| --- | --- |
| `game.json` | Title, player base stats, run rules, XP curve, rarities, drops, rewards, haptics, feel |
| `enemies.json` | Enemy types, elite modifiers and affixes, behaviour constants |
| `weapons.json` | Weapons: base stats and five levels each |
| `upgrades.json` | Passives, augments, synergies |
| `stages.json` | Timeline (tracks, events, curves), tier scaling, themes, boss |
| `meta.json` | Account curve, permanent upgrades, cores, skins |
| `retention.json` | Daily missions, login calendar, achievements |
| `monetization.json` | Products, shop layout, exchange rates, ad rules |
| `audio.json`, `sprites.json` | Sound table, atlas manifest |

`GameData.validate()` cross-checks every reference between these files and is run by the test suite.

### The modifier language

Every source of power - permanent upgrades, the chosen core, in-run passives, augments, synergies - is a dictionary of `key -> amount`, summed into one table in `RunBuild`:

| Key | Meaning |
| --- | --- |
| `damage_pct: 0.12` | +12% to the `damage` player stat |
| `max_hp: 20` | +20 flat |
| `w.pulse.projectiles: 1` | +1 projectile on the Pulse Cannon only |
| `fx.volatile: 1` | Switches a special effect on (parameters are also `fx.*` keys) |
| `run.rerolls: 1` | Run set-up values |

A stat resolves as `(base + flat) * (1 + percent)`. New content in an existing shape is therefore **data only**.

## Adding content

| To add | Do this |
| --- | --- |
| A passive, an augment using existing effects, a synergy | Add an entry to `upgrades.json` |
| A permanent upgrade, core or skin | Add an entry to `meta.json` |
| An enemy using existing AI | Add to `enemies.json`, add its sprite to `sprites.json` and the art tool, reference it in `stages.json` |
| A weapon | Add its block to `weapons.json`; add `src/game/weapons/<script>.gd` extending `Weapon` and overriding `update()` |
| A new special effect | Add `fx.*` keys in data, read them in `Combat.refresh()`, implement the trigger in `Combat` |
| A sector with its own pacing | Today every sector shares one timeline scaled by tier; give `Director` a per-tier timeline lookup |
| A mission or achievement | Add to `retention.json` (any stat in `StatsService` works) |
| A store product | Add to `monetization.json` and to `shop_layout` |

## Saves

`SaveService` holds the profile as one dictionary and writes it as JSON inside an envelope `{v, sum, body}`. Writes are debounced (2 s), forced on app pause/quit and after purchases, and atomic (temp file, keep previous as `.bak`, swap). A corrupt file falls back to the backup, then to a new profile.

The `runs` section is `RunLedger`'s: the ids of the last 24 runs paid out (with their summaries, so a repeated claim returns the same numbers and pays nothing) and a snapshot of the run in progress, refreshed every 8 seconds and flushed when the app loses focus. A snapshot still there at launch is a run that never reached its results screen; it is settled then and the player is told.

Adding a field needs no migration: `SaveMigrations.defaults()` is merged underneath every loaded profile. `tests/fixtures/profile_v1_before_playtest_update.save` is a profile written by the build before Player Level gates, upgrade categories and the run ledger existed, and a test loads it to prove nothing in it is lost. For a breaking change, bump `CURRENT_VERSION` and add a `_from_vN` step; steps run in sequence. Unknown keys are preserved, so an older build will not destroy a newer save.

**Cloud save** is a new `SaveBackend` (iCloud / Play Games / own server) plus a conflict rule; `created_at`, `last_seen` and `play_seconds` are already in the profile for that purpose.

## Monetisation and analytics

Both ads and purchases are split into a *policy* service and a *provider* adapter. The policy is tested; the providers are mocks.

- **Ads** - `AdMobAdProvider` (iPhone builds with the bridge in `native/admob`; Google test ads only so far) runs Google's consent flow - a check at every launch, the form at a quiet moment between runs once the first run is over (`AdsService.between_runs()`, called before a run starts and on returning to the menu) - and starts the SDK only when consent allows ad requests. It keeps one rewarded and one interstitial ad loaded, retries failed loads with a growing delay, pays a rewarded ad only on the SDK's reward callback, and gives up on an ad that never reports closing. Game audio is silenced while any ad is up. Tests drive it against `tests/fakes/fake_admob_bridge.gd`. `AdsService` enforces: rewarded ads are opt-in and always pay what was promised; interstitials appear only between runs, never during one, are frequency capped (`monetization.json`), never follow a rewarded ad in the same results flow, and stop once Remove Ads is owned. `MockAdProvider` shows an obviously fake ad on the desktop and in tests.
- **Store** - `StoreService.purchase()` -> provider -> `_fulfil()` grants the product's `grants` block. `MockStoreProvider` shows a clearly labelled confirmation and takes no payment.
- **Analytics** - `Analytics.track(event, props)` with event-name constants. Every event is stamped with session, days since install, account level, app version and A/B group. `LocalLogAnalyticsProvider` writes JSON lines to `user://analytics.jsonl`.

Events emitted today: `session_start`, `session_end`, `game_started`, `game_ended` (includes `run_duration`), `player_death`, `player_revived`, `player_level_up`, `upgrade_selected`, `upgrade_rerolled`, `synergy_found`, `boss_started`, `boss_defeated`, `ad_requested`, `ad_viewed`, `rewarded_ad_completed`, `purchase_started`, `purchase_completed`, `purchase_failed`, `currency_earned`, `currency_spent`, `mission_completed`, `achievement_claimed`, `daily_reward_claimed`, `account_level_up`, `meta_upgrade_purchased`, `item_unlocked`, `tutorial_step`, `screen_view`, `hud_recovered`. Retention falls out of `session_start` + `days_since_install`.

The local log is also a flight recorder: it is flushed whenever the app loses focus, so after a crash or freeze on a device `Documents/analytics.jsonl` in the app container holds the session's last events. That is how the playtest-1 freeze was diagnosed.

## Before real money

Everything below is **not done** and must be before a real store or ad provider is switched on. The client is not a trustworthy place for anything of value.

1. **Validate receipts on a server.** Send every purchase receipt to a backend that verifies it with Apple (App Store Server API) or Google (Play Developer API) and only then grants. The call belongs at the marked line in `StoreService._fulfil()`. Handle refunds and revocations from the stores' server notifications.
2. **Make the premium balance server-authoritative.** Once Crystals can be bought, the server owns the ledger; the local balance becomes a cache. The local save checksum is tamper *evidence*, not protection.
3. **Use server-side verification for rewarded ads** that pay out anything of real value.
4. **Stop trusting the device clock.** Daily missions, the login calendar and ad caps read `GameClock`; point it at server time.
5. **Deliver remote config over an authenticated channel.** `App._apply_remote_config()` currently reads a local file.
6. **Compliance.** App Tracking Transparency prompt and consent flow (GDPR/UMP) before any ad SDK initialises; complete the iOS privacy manifest for the SDKs added; age rating and child-directed settings; a data deletion path; a real privacy policy and terms.
7. **Restore purchases** is implemented against the provider interface and must be re-tested against the real store.

## Designed for, not built

| Feature | Where it plugs in |
| --- | --- |
| Remote balancing | `GameData.apply_overrides()` - already merges a JSON blob over the bundled tables |
| A/B testing | `ab.group` is assigned per install and stamped on every event; branch on it or key overrides by it |
| Leaderboards | `StatsService` and the run result hold the payload; runs are seed-deterministic, so a server can re-simulate to verify |
| Events and seasons, battle pass | New services alongside `MissionService`, reading the same run results through `RunLedger` |
| Push notifications | `GameClock.seconds_until_next_day()` and the daily services provide the triggers |

## Testing

`tests/` is excluded from exported builds and loaded by path, never by class name, so shipping code cannot depend on it.

- `test_runner.gd` runs any `test_*` method on the suites.
- Gameplay tests run the real `Arena` with the `Autopilot`, calling `step()` directly at 30 simulated steps per second: full runs, each weapon in isolation, the boss through all phases, Endless cycling, revive, abandon, the entity caps, seed determinism.
- UI tests build every screen from a new and a maxed profile, and push synthetic touches through the engine's input pipeline. Every list is swiped from a row and from a button: it must scroll, and the swipe must not buy, claim or select anything.
- Progression tests cover the Player Level, Credits, banking exactly once, recovery of an interrupted run, permanent upgrades, and loading a save from before those features existed.
- Threat tests cover what each sector contains, the mutators, and that every new danger can be avoided - a bombardment is run against a planner that looks for any safe direction, and must always find one.
- Stability tests replay the playtest freeze, sabotage the HUD to exercise its recovery, and push the simulation to 1,000 enemies, hundreds of simultaneous explosions and a long Overdrive soak.
- `sim_runner.gd` is the balance tool; `shot_tour.gd` captures every screen for visual review.
- `src/app/device_check.gd` ships in the build and stays dormant unless the app is launched with `--device-check`. It is the only way to test what a Mac cannot: real safe-area insets, the device renderer, audio output, storage and frame rate under load. See the README for how to run it.

## Conventions

- Strictly typed GDScript. This engine version treats inference from an untyped value as an error, so read from dictionaries through `GameData.num/text/dict/...` or with an explicit type.
- Use `set_anchors_and_offsets_preset()` to make a control fill its parent; the anchors-only variant keeps the current (zero) size.
- Put scrolling content in `UiKit.scroll()`, never in a bare `ScrollContainer`. On a touch screen a list scrolls only if the drag reaches it, and every button and every `PanelContainer` (what rows are made of) has a mouse filter of STOP and keeps the touch. A mouse wheel is exempt, so a bare list scrolls on a Mac and barely moves on a phone - build 0.2.0 shipped that way. `ScrollList` sets everything inside it to PASS, including rows added later, and has a deadzone so a tap with a little wobble is still a tap. Buttons outside a list must stay STOP, or the touch falls through to the joystick.
- After adding a file with `class_name`, run `godot --headless --path . --import` once so the class is registered.
