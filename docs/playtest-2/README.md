# Playtest 2 - pickups that vanish, and "maxed" upgrade cards

Two reports from human playtesting on 22 October 2026, investigated the same day on branch `fix/pickups-and-maxed-upgrades`.

## Bug 1 - energy and Credits stop appearing in big fights

**Report.** During intense combat, defeated enemies sometimes stopped leaving visible pickups; after a while they appeared again.

### Root cause (established)

The field holds at most 340 pickups (`max_pickups`) and 70 Credit piles (`max_credit_pickups`). The game never scrolls back, so crystals and coins the player walks away from stay on the floor, and in a long fight the field fills up. A drop on a full field was folded into a **random** pickup of the same kind anywhere on the field, usually far off screen. So:

- **Not spawned visibly:** kills next to the player left nothing behind.
- **Not lost at that moment, but moved:** the value was added to a distant crystal or pile. It was paid only if the player went back for it, or a magnet or the boss vacuum pulled it in. A run that ended first never paid it.
- **"Then they come back":** once the player collected enough to drop below the cap, new drops got their own slots again.

### Evidence

- `tests/test_pickups.gd` on the unfixed build (checkpoint `66d7314`): with the field full of crystals left 2,200-4,200 units away, 20 kills next to the player produced **0** crystals near the player, with all 20 energy folded into the far crystals. An elite's 30 Credits vanished the same way once 70 piles existed.
- How often the field is full in ordinary play (bot, unfixed build): **32%** of a Sector 3 run and **27%** of a 10-minute Overdrive run (2% in Sector 1).
- The energy ledger (`dropped = collected + on the floor`) held on the unfixed build too: value was relocated, not destroyed.

### Fix

`src/game/pickup_system.gd`. When the field (or the Credit pile count) reaches its cap, pickups **farther than 900 units from the player** are merged into the first pickup of the same kind in the same grid cell (140 units, then 280, 560 and 1,120 if needed) until the field is down to 80% of its cap. The surviving crystal stays where it is, carries the sum and grows a size tier. Then the new drop gets its own slot at the death spot. If everything left is near the player, a new drop joins the **nearest** crystal or pile, so it is still visible where it was earned. Crystals merge only with crystals and coins only with coins; caches and helpers are never merged; pickups already flying to the player are left alone. All settings are under `pickups` in `data/game.json`.

New ledgers prove nothing is created or destroyed: `dropped_xp == collected_energy + field_xp()` and `dropped_credits == collected_credits + field_credits()` at every step, and the run's Credits equal `collected_credits` times the player's Credits multiplier.

After the fix, the same bot runs are full 0% (Sector 3) and 1% (Overdrive) of the time.

**Cost.** An A/B benchmark on the same machine, alternating the unfixed and fixed builds twice: 30 kills next to the player on every step, 300 steps, on a field that starts full. Average step 0.41 ms before, 0.44 ms after; worst step about 3.4 ms in both.

## Bug 2 - maxed weapons and abilities still offered

**Report.** Weapons and abilities that had already reached their maximum level could still appear among the cards.

### What was found

The card rules themselves were already correct, and stayed correct under test:

- A player-like test (`test_reproduce_no_maxed_card_is_ever_dealt`) picks and rerolls at random over six 7-minute runs, checking every hand dealt. It found no maxed, already-owned or wrongly-levelled card, including hands dealt when items were already maxed.
- The phone's own event log holds **483 card picks over 21 real runs** since 13 October. None picked an item above its cap or the same level twice.

**Most likely cause (not proven):** the card that **takes** an item to its last level was tagged **"MAX LEVEL"**, with every level marker filled in. Read quickly, that says "this item is already maxed". Picking it completes the item, which then never appears again. The event log records picks, not the cards shown, so what the tester saw cannot be confirmed.

### Fix

- The completing card now says **FINAL UPGRADE** (the UI font has no arrow character for "4 → MAX").
- The rule is now enforced by the run, not just by which cards are dealt. `UpgradeSystem.apply()` refuses any card that no longer fits the build: a maxed or unknown item, a stale level, a skipped level, a new item with no free slot, or an augment already owned. Before this, an over-cap card would have set a weapon to level 6. `Arena.choose()` then deals a fresh hand for the same level, so a refused card can never strand the screen. Refusals are counted (`RunDiagnostics.upgrades_rejected`, expected to stay 0).
- With everything complete, the hand is still three cards: Field Repair (30% health), Salvage (+40 run Credits, the soft currency) and Purge (a screen-clearing blast). These already existed; they are now tested, including that they never pay Crystals.

## Tests

`godot --headless --path . -- --test=pickups` and `--test=upgrades`, 14 tests:

| Requirement | Test |
| --- | --- |
| Large numbers of simultaneous deaths | 200, 500 and 900 deaths in one step |
| Pickup capacity saturation | Fields filled to 2-3x their caps |
| Energy and Credits preserved | Ledgers checked in every pickup test |
| Merging | Kinds kept apart, specials untouched, sums exact |
| Collection after merging | Everything pulled in; each point paid exactly once |
| Simultaneous explosions | 200 blasts plus chain reactions on a full field |
| Maxed weapons / passives | 300 hands each, caches included; per-item caps (5, 3, 2) |
| Eligibility after every level-up | Six player-like runs, every hand checked |
| Invalid over-cap application | Seven kinds of invalid card refused; a fresh hand dealt in the run |
| Everything maxed | Three fallback cards, 60 s of levels, no softlock, no Crystals |
| Pause/resume during a choice | 20 focus losses on the real HUD; same hand, still on screen |
| Extended heavy play | 5-minute Sector 3 and 10-minute Overdrive bot runs |

Both fixes were checked by breaking them on purpose: with the `apply()` guard switched off, 15 checks fail.

One existing test changed. `test_boss_arrives_on_a_full_field` assumed the boss survives 12 seconds at −95% damage whatever cards the vacuum's level-ups deal. Damage bonuses add up, though: four Amplifiers turn −95% into −47%. The merge change shifts the run's random sequence, the bot drew those Amplifiers, and the boss died about 5 seconds into its fight. The test now gives the boss 50x health instead of relying on which cards come up.

## Not covered

- A human session on the fixed build. Bot runs are not playtests.
- Timings in the stability suite were measured on a heavily loaded Mac (load average 230-560 from other sessions); only the A/B comparison above is a fair measure of cost.
