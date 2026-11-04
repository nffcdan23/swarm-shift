# Bosses: one per sector

Feedback (November 2026): every sector ended with the same boss, the Overseer, which looked and fought the same each time and seemed to have the same health. Clearing a sector and killing its boss should also pay more.

The Overseer's health did scale (16,000 at Sector 1, about 48,000 at Sector 8, about 157,000 at Sector 20), but nothing showed it, and the player's weapons scale too, so every fight felt the same length. Its attacks, phases, look and colour never changed.

## What changed

**Twenty bosses**, one per sector, in five families that match the five arena colours. The arena colour repeats every five sectors, and so does the family, so each family returns three times, each time as a different and harder boss. The Overseer is now the last of them (Sector 20); the OVERSEER skin is still the reward for clearing it.

- **Each has its own look.** A shell, a core and a ring from a library of six shells, five cores and four rings (`assets/sprites/bosses`, drawn by `tools/generate_art.gd` in grey), tinted in the boss's colour by `assets/shaders/boss_tint.gdshader`. No two bosses share a combination of parts and colour (tested).
- **Each has its own attacks.** Three new patterns join the original five:
  - **Spiral**: a pulsing wind-up, then a turning stream of slow shots for three seconds.
  - **Aimed fan**: a lane towards the player, then volleys of a five-to-seven-shot spread aimed at them.
  - **Blink**: the landing spot fills in on the ground while the boss fades out; it lands there with a blast, some bosses with a ring of shots.

  One boss can carry two versions of a pattern (the Lattice and the Architect have a fixed cross of four lasers and a sweeping one) through an attack's `"type"`.
- **Later bosses are harder.** More phases (two for Sectors 1-4, three for 5-14, four for 15-20), more attacks, shorter rests, and more base health on top of the existing sector scaling. Every boss has more health than the one before it (tested).
- **The health bar shows the boss's own phase breaks**, and its name is shown in its colour. The lobby's sector card names the boss waiting at the end ("BOSS: THE RIFT WEAVER").
- **Overdrive** meets them in sector order, one per cycle, instead of the Overseer every time.
- **Threat**: Overseer's Wrath is now **Boss's Wrath**. Final Protocol's extra phase now uses every attack the boss has, rather than a fixed list of the Overseer's.

## Roster

Health is at Sector 1 scaling. The sector multiplies it by 1 + 0.18n + 0.015n² (n = sector - 1), as before. Bounty is in Credits before sector scaling.

| Sector | Boss | Title | Arena | Phases | Attacks | Shell / core / ring | Health | Bounty | First-clear Crystals |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | The Sentinel | Keeper of the first grid | Cyan Grid | 2 | burst, charge, summon | spikes / eye / segmented | 12,000 | 250 | 15 |
| 2 | The Furnace | It burns the ground you stand on | Ember Field | 2 | charge, zones, summon | fortress / reactor / segmented | 12,500 | 250 | 15 |
| 3 | The Phase Wraith | Never where you are looking | Violet Rift | 2 | blink, burst, summon | petals / rift / double | 13,000 | 250 | 15 |
| 4 | The Broodmother | Mother of the swarm | Toxic Bloom | 2 | summon, zones, fan | petals / hive / orbs | 13,500 | 250 | 15 |
| 5 | The Enforcer | First of the Overseer's line | Crimson Void | 3 | burst, charge, fan, summon | claw / reactor / double | 15,000 | 400 | 25 |
| 6 | The Lattice | Every line is a wall | Cyan Grid | 3 | spiral, cross (laser), burst, summon | fortress / prism / double | 15,000 | 250 | 15 |
| 7 | The Magma Ram | It does not stop | Ember Field | 3 | charge, zones, fan, summon | horns / reactor / gear | 15,500 | 250 | 15 |
| 8 | The Rift Weaver | It folds the arena around you | Violet Rift | 3 | blink, laser, fan, summon | blades / rift / orbs | 15,500 | 250 | 15 |
| 9 | The Plague Engine | The ground is never safe | Toxic Bloom | 3 | zones, summon, burst, fan | fortress / hive / gear | 16,000 | 250 | 15 |
| 10 | The Executor | Sentence is carried out | Crimson Void | 3 | charge, laser, zones, fan | blades / eye / gear | 16,500 | 400 | 25 |
| 11 | The Prism Warden | Light, bent into a cage | Cyan Grid | 3 | spiral, laser, fan, summon | spikes / prism / orbs | 16,500 | 250 | 15 |
| 12 | The Cinder King | Where it lands, it burns | Ember Field | 3 | blink, charge, zones, burst | spikes / eye / gear | 17,000 | 250 | 15 |
| 13 | The Void Herald | It speaks in silence | Violet Rift | 3 | blink, laser, spiral, zones | horns / rift / double | 17,000 | 250 | 15 |
| 14 | The Hive Queen | The swarm answers to her | Toxic Bloom | 3 | summon, zones, spiral, charge | petals / hive / double | 17,500 | 250 | 15 |
| 15 | The Tyrant | The Overseer's right hand | Crimson Void | 4 | burst, charge, laser, zones, fan, summon | horns / eye / orbs | 18,000 | 400 | 25 |
| 16 | The Architect | It built the grid. It can unbuild you | Cyan Grid | 4 | spiral, cross (laser), sweep (laser), zones, blink | fortress / reactor / gear | 18,500 | 250 | 15 |
| 17 | The Sunbreaker | A star with a grudge | Ember Field | 4 | charge, zones, spiral, laser, blink | blades / reactor / orbs | 19,000 | 250 | 15 |
| 18 | The Singularity | Everything falls towards it | Violet Rift | 4 | blink, laser, spiral, zones, summon | blades / rift / segmented | 19,000 | 250 | 15 |
| 19 | The Blight Titan | The last of the hive | Toxic Bloom | 4 | summon, zones, spiral, fan, laser | horns / hive / segmented | 19,500 | 250 | 15 |
| 20 | The Overseer | The mind behind the swarm | Crimson Void | 4 | burst, charge, summon, laser, zones, spiral, fan, blink | claw / eye / segmented | 20,000 | 600 | 40 |

## Rewards

| | Before | Now |
| --- | --- | --- |
| Credits the boss drops | 150 | 200 |
| Boss bounty, paid on the results screen for a clear | none | 250; 400 for Sectors 5, 10 and 15; 600 for the Overseer |
| Player XP per boss | 120 | 200 |
| First-clear Crystals | 10 per sector (200 in all) | 15; 25 for Sectors 5, 10 and 15; 40 for the Overseer (355 in all) |
| Clear bonus | 300 | 300 (unchanged) |

All Credit amounts scale 30% per sector, like the clear bonus, and the Threat bonus applies on top. Crystals are paid once per sector, on its first clear, so they cannot be farmed (tested). The bounty is paid every time a sector is cleared, and the double-Credits ad doubles it like everything else.

## Balance

Same seeded sims (`--sim=30 --skill=0.6`) on the previous build and this one, run side by side. Thirty runs is roughly plus or minus 17 points.

| Sector, share of upgrades | Previous build: beat the boss / reached it | New bosses: beat the boss / reached it |
| --- | --- | --- |
| 1, none | 24 / 30 | 30 / 30 |
| 4, 15% | 18 / 28 | 23 / 28 |
| 8, 40% | 10 / 18 | 10 / 18 |
| 12, 60% | 30 / 30 | 30 / 30 |
| 16, 80% | 30 / 30 | 24 / 30 |
| 20, all | 22 / 28 | 18 / 28 |

The two-phase bosses of Sectors 1-4 are a little gentler than the Overseer was there, which suits a first boss. The middle is unchanged. The four-phase bosses of Sectors 15-20 are the hardest fights in the game, and the Overseer is the hardest of all. Overdrive (10 runs, 80% of upgrades, skill 0.7, 25 minutes) ran every run to the time limit through five different bosses.

If a boss feels unfair, its levers are all in `data/stages.json`: `hp`, each phase's `idle` (rest between attacks) and `speed_mult`, and each attack's numbers.

## Tests

`tests/test_bosses.gd`:
- every sector has a boss, no two sectors share one, and no two look alike;
- each boss has more health than the one before and at least as many phases; the first is two-phase and the Overseer knows every attack;
- every attack pattern is used by some boss;
- all twenty fights, played through every phase, use every attack the boss has, never fill the bullet pool, never leave the arena, and warn every ground blast at least 0.5 s ahead;
- a blink is marked on the ground before the boss lands there; a fan is aimed at the player; a spiral keeps firing and turns;
- each sector spawns its own boss, with its name, colour and health-bar phase breaks, and Overdrive meets them in order;
- a clear pays the boss's bounty, every fifth boss is worth more and none more than the Overseer; first-clear Crystals come from the boss and are paid once; the results screen shows the bounty.

`tests/test_threat_levels.gd` and `tests/test_gameplay.gd` read phase counts from the data instead of assuming the Overseer's three. Data validation (`GameData._check_bosses`) checks every boss's phases, attack types, summons and sprites, and that there is one boss per sector.

## Not yet checked

- On a phone: whether the new attacks read clearly in a dense fight, especially the spiral among the swarm's own bullets, and whether the bright gold and cyan bosses stand out from the arena behind them.
- Whether the titles should be shown somewhere (they are in the data, unused on screen).
- No new sounds: the new attacks reuse existing ones.
