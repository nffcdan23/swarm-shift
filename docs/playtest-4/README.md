# Playtest 4 - Prism Lance rebuilt, Scatter Shot strengthened

Feedback (November 2026): the Prism Lance "does literally nothing", and a run that starts with only Scatter Shot is very hard to play. The player suggested a Lance that spins around the player instead of aiming. It should not kill full-health enemies outright. It should cut them down so far that any weapon then finishes them in one hit.

## 1. Prism Lance

### What it does now (`src/game/weapons/prism_lance.gd`, `Combat.cut()`)

- **Spokes, not shots.** Beams come out of the core and spin continuously: two at level 1, four at level 5, at 2.2 radians a second (about one full turn every three seconds), sped up by fire-rate bonuses. There is no aiming, charging or cooldown. A fading trail behind each spoke shows the spin.
- **Each pass cuts a share of the enemy, not a number.** When a spoke sweeps over an enemy, the enemy loses 30% of its maximum health (35% at level 2, 40% at level 5), plus a little flat damage. A cut can never take an enemy below **12%** of its maximum. The Lance **never kills**: a full-health enemy is at its floor after about three passes, and then one hit from anything finishes it. One level-1 Scatter Shot volley finishes a Tank at its floor; a test checks this.
- **It scales with the enemy.** Because it works in shares, it stays useful at Sector 20 just as at Sector 1.
- **Elites take half a cut. Bosses take one hundredth of it** (0.3-0.4% a pass) and never go below half health, so the Lance cannot melt a boss.
- **Each pass is counted once, however wide the beam.** It is detected by the spoke's direction crossing the enemy's bearing, so a fast spin cannot skip anyone and a slow one cannot hit twice.
- **It cannot be a Flex Rack starting weapon** (`"support": true` in `data/weapons.json`). A run with only a weapon that cannot kill could not be won.
- Small outward push on each pass. A bigger push (90) threw enemies around so much that partners missed, so it is 30.

### Evolutions

Ids kept (`rail`, `sweep`), so saves that own them carry over.

| Path | Role | What it does |
| --- | --- | --- |
| Sundering Lance | Boss killer | Two long spokes (+40% reach), triple flat damage; elites take full cuts; bosses lose 2.2% of their health a pass (five times the unevolved rate), down to a quarter of their health |
| Prism Wheel | Swarm clearer | Six spokes, spinning 30% faster |

Also changed: Gravity Lens (the Lance + Singularity synergy) gave 40% wider beams, which no longer matters, so it now gives 30% more reach. Mastery Rank 2 is +10% reach; Rank 4 is a 15% faster spin (was "charges faster").

### Measurements

The ordinary bench measures one weapon alone, and the Lance alone kills nothing by design. So the bench gained `--partner=pulse`: the weapon fights beside a level 5 Pulse Cannon, and the kill columns count both weapons. It is twenty seconds a scenario, three seeds, Sector 8 health. Damage includes the health the Lance cuts.

| Beside Pulse Cannon 5 | Single dps | Swarm dps | Swarm kills | Kite dps | Kite kills |
| --- | --- | --- | --- | --- | --- |
| Pulse Cannon 5 alone | 158 | 225 | 125 | 267 | 63 |
| + Prism Lance 1 | 112 | 931 | 388 | 726 | 102 |
| + Prism Lance 3 | 192 | 1264 | 263 | 834 | 282 |
| + Prism Lance 5 | 360 | 1356 | 282 | 1017 | 297 |
| + Sundering Lance | 948 | 1345 | 489 | 1204 | 182 |
| + Prism Wheel | 664 | 1283 | 452 | 1194 | 270 |

With the Lance beside it, a Pulse Cannon kills two to four times as many enemies. The single-target column is against a boss stand-in: the bench dummy is now flagged as a boss and carries a Sector 8 boss's maximum health, so share-based damage reads as it would on a real boss. It still overstates the Lance a little, because the dummy is topped up and never reaches the half-health floor. That change only affects weapons that read maximum health. Nanite Swarm's share is capped at 30 a tick either way, so no other weapon's numbers moved.

## 2. Scatter Shot

| | Before | Now |
| --- | --- | --- |
| Damage per pellet | 9 | 12 |
| Range | 320 | 420 |
| Pellet speed | 640 | 760 |
| Cone | 46 degrees | 38 degrees (more pellets land at range) |
| Level 2 | +2 pellets | +2 pellets, +15% range |

Bench (single / swarm / kite dps, Sector 8 health): level 1 29 / 45 / 46 -> 40 / 58 / 60; level 5 89 / 408 / 364 -> 143 / 537 / 494.

## 3. What it does to difficulty

Same seeded sims, previous build against this one, one at a time:

| Run | Before | Now |
| --- | --- | --- |
| Striker (starts with Scatter Shot), Sector 1, 5% of upgrades, weapons to Level 3, 60 runs | 75% | 83% |
| Striker, Sector 2, same | 43% | 58% |
| Default core, Sector 1, no upgrades, starters only, 60 runs | 68% | 70% |
| Sector 8, 40% of upgrades, skill 0.45, 30 runs (90 for "now") | 27% | 41% |
| Same, Lance change only (Scatter as before), 30 runs | 27% | 33% |

Thirty runs is roughly plus or minus 17 points, sixty plus or minus 12, ninety plus or minus 10. A Striker start is clearly kinder, which was the point. Sector 8 is easier too: it went from about a quarter of runs to about two in five at that stage. Both changes contribute. If Sector 8 now feels too soft, the levers are Scatter's damage (12) and the Lance's cut (0.3) and floor (0.12) in `data/weapons.json`.

## 4. Tests

`tests/test_combat.gd`:
- the spokes turn, and one pass cuts every enemy in a ring without killing any;
- a cut stops exactly at the floor;
- after the Lance, one starter volley finishes a Tank;
- bosses stay above half health after twenty seconds of a maxed Lance, and elites keep more health than ordinary enemies;
- spokes are evenly spaced (four at level 5, six on the Prism Wheel);
- the Lance alone kills nothing and leaves nothing below 12%;
- the Lance's crowd damage rises at levels 3 and 5;
- load among 400 enemies.

`tests/test_mastery.gd`: Flex Rack refuses the Lance. The evolution-dominance test covers the new paths.

## 5. Not yet checked

- On a phone: how the spin looks and reads in a dense fight, and whether the cut numbers clutter the screen.
- Whether players notice what the Lance is doing. The damage numbers show the cut, but nothing yet marks an enemy as "at its floor".
- No new sound: each pass that cuts something plays the existing charge sound, higher, at most every 0.45 s.

## 6. After build 6

**Seeker Rounds removed.** The augment bent every projectile towards the nearest enemy. On Scatter Shot that pulled the cone onto one target, which defeats the point of a scatter. Pulse Cannon and Combat Drone shots are aimed and already land, so excluding Scatter would have left it doing nothing. It is gone from the augment pool, along with its projectile flag and turn-rate code. **Striker Awakening** started every Striker run with Seeker Rounds. It briefly gave Phase Shift instead, but Phantom's awakening is already Phase Shift, so it now gives **Explosive Rounds**: Scatter's pellets burst on impact, which suits a close-range core. Anyone who already researched it keeps it and gets the new augment. A test now checks that no two cores share an awakening.

**WEAPONS badge fixed.** The Arsenal's badges count items that can be bought. `ArsenalService.unlock_info()` worked "affordable" out from Player Level and Credits alone, without checking ownership. Once a player's Credits were above the price of a weapon they already owned (Arc Caster costs 400), the WEAPONS tab and the ARSENAL button showed "1" with nothing to buy. Cores had the same fault. An owned item is now never affordable. A test buys a weapon and checks that the badge goes out; it fails without the fix.

## 7. Before build 7

Feedback on the always-on Lance: it should fire for a few seconds, as before, but spin instead of aim. It also did not seem to hurt big enemies.

**Bursts.** A cycle is now: wait until an enemy is within reach; charge for 0.35 s, with faint lines where the spokes will appear, light gathering at the core and the old charge sound; fire for 1.6 s, with the spokes turning at 4 radians a second, about one full turn, and the old fire sound; switch off for 2.2 s, shortened by fire-rate bonuses. The spokes fade out at the end of a burst. Level 4 now adds 30% beam duration instead of spin speed, and Mastery Rank 4 makes beams last 15% longer. Player duration bonuses lengthen the burst.

**Big enemies.** Measured in a real run, big enemies were being cut; it just did not show:
- **Elites took only half a cut**, so an elite needed about six passes to reach its floor and usually got to the player first. Elites now take the full cut.
- **Bosses took 1% of a cut**, which nobody could notice. They now take 2.5% of it (0.75-1% of their health a pass), still never below half. Sundering Lance raises that eightfold, down to a quarter.
- **Nothing showed the cut.** Enemies have no health bars, and damage numbers are capped in a crowd. A cut on anything big (Brutes, Tanks, Splitters, elites, bosses) now pops up as a pink percentage, such as "-30%", which always gets through the cap.

Bench beside a level 5 Pulse Cannon (single / swarm / kills / kite / kills): Lance 1 200 / 975 / 333 / 641 / 88; Lance 5 610 / 1127 / 322 / 1036 / 146; Sundering 2504 / 1375 / 282 / 1007 / 210; Prism Wheel 1173 / 1196 / 323 / 1075 / 279. Pulse alone kills 125 and 63. Sector 8 at 40% of upgrades, skill 0.45, 60 runs: **33%**, against 41% for the always-on Lance and 27% before any of this.

**Double Credits button.** The results screen showed it only if a rewarded ad was already loaded at the moment the screen opened, and never checked again. On a phone that is often not the case: just after another ad (a revive or a reroll), while AdMob is still loading, or while a failed load waits on its retry timer (10 s up to 5 minutes). It is now always there when there are Credits to double. It reads LOADING AD... and cannot be pressed until an ad is ready, then becomes DOUBLE CREDITS. It is hidden only when no ad can come: the placement is switched off, or consent does not allow ads. A UI test covers the waiting state.

**Clear bonus.** A clear paid 120 Credits on top of the run (scaled 30% per sector: about 370 at Sector 8), so dying at the boss paid almost as much as winning. It is now 300: about 930 at Sector 8, and a cleared Sector 8 run averages about 2,700 Credits against about 1,100 for one that dies. Overdrive has no clears, so its income is unchanged.

Campaign, free player, sectors only, skill 0.6 (`--campaign=20 --skill=0.6`), against the same sim in the [progression report](../progression/README.md). The new clear bonus and the Lance and Scatter changes are measured together:

| Milestone, hours of play | Before | Now |
| --- | --- | --- |
| First evolution | 3.0 | 1.3 |
| Sector 12 cleared | 3.2 | 2.6 |
| Sector 16 cleared | 5.0 | 3.8 |
| Sector 20 cleared | 8.7 | 7.7 |
| 25% of research, by Credits | 8.6 | 7.8 |

Progress is roughly 10-25% faster. Sector 17 is still the slowest wall (21 attempts).

## 8. After build 8: level-up cards repeating

Feedback from a tester: the two cards passed on at one level-up came straight back at the next, level after level, and late in a run the same few weak cards filled every hand.

**Cause.** `UpgradeSystem.roll()` had no memory. Each hand was a fresh weighted draw from every card still valid, and owned weapons and passives are weighted up. Late in a run, with every weapon and passive slot full, only a handful of cards remain, so the cards just refused were the likeliest ones again. A reroll did not exclude the hand it replaced either. Measured over six seeded runs, playing like a person who picks at random:

| Run level | Cards still possible | Passed cards back in the next hand | Hands with both passed cards back |
| --- | --- | --- | --- |
| 0-9 | 29 | 0.22 | 0% |
| 20-29 | 16 | 0.43 | 5% |
| 30-39 | 11 | 0.81 | 13% |
| 40+ | 5 | 1.49 | 55% |

**Fix** (`src/game/upgrade_system.gd`, `Arena.choose()` and `Arena._reroll_offers()`):
- A weapon, passive or augment card that was shown and not taken **sits out the next hand**, whether that hand is a level-up, an elite cache or a reroll.
- Each pass in a row makes the card **rarer** (weight x0.55 per pass, down to x0.15), until it is taken. A card the player keeps refusing stops crowding the hand, but is never removed.
- A **reroll counts as passing on the whole hand**, so it always deals different cards when any exist.
- When the only upgrades left are the ones just passed on, the hand is made of the fallback cards (Field Repair, Salvage, Purge), and the passed cards return a hand later.
- **Evolutions are exempt**: a weapon ready to evolve is still always offered.

After the fix, the same measurement shows no passed or rerolled-away weapon, passive or augment in the very next hand at any level. The only repeats left at level 40+ are the fallback cards.

Still true: late in a run the pool is small (a complete build has only a few cards left to give), so cards return every other hand rather than never. More variety there needs more content (more augments, or a choice that spends levels on something other than the build), not dealing.

Difficulty is unchanged within noise (30 runs, about plus or minus 17 points): Sector 8 at 40% of upgrades, skill 0.6, 40% -> 33%; Sector 20 with every upgrade, 67% -> 73%.

**Tests** (`tests/test_upgrades.gd`):
- six seeded ten-minute runs, with rerolls, never deal a passed card in the next hand;
- twenty rerolls in a row never share a card with the hand they replace;
- with only two upgrades left, passing them gives a fallback hand, and they return a hand later;
- three passes make a card turn up less than half as often, and taking it resets the count;
- evolutions are never held back.

## 9. Before build 10: challenge results off screen, new weapons not seen

**Challenge results shifted right.** A tester's cleared Daily Challenge showed the whole results screen pushed to the right and partly off screen. The headline "CHALLENGE COMPLETE" at the results screen's 52-point title size is 702 pixels wide; with the side padding that forced the column to 758 on the 720-wide canvas, and the screen centred on the wider column. Every challenge clear, Daily or Weekly, did it; "THREAT 10 CLEARED" (618) and the others fit. The headline now shrinks to fit 640 pixels (`UiKit.fitted_title_size`, the same approach the in-run banners already used), down to 34 points at the least. A new UI test lays out the results screen of a Daily, a Weekly, a Threat 10 and a Sector 19 clear on a 720 x 1560 phone canvas and checks nothing crosses either edge; it failed at 758 before the fix. The old screen tests ran in the 1280-wide headless window, which is why they never caught it.

**New weapons not turning up.** Reaching a Player Level does not give a weapon: Arc Caster (Level 2), Seeker Missiles (3), Plasma Mines (4), Combat Drone (5), Prism Lance (7) and Singularity (10) go on sale in the Arsenal and only reach runs once bought; Railgun and Nanite Swarm come from Research. The game said otherwise: the level-up note read "NOW AVAILABLE: Arc Caster" and the lobby "NEXT UNLOCK - LV 2: Arc Caster". Once bought, a weapon does reach runs: Arc Caster was offered in 30 of 30 seeded runs, usually by Run Level 2-4.
- The level-up note now says "NEW IN THE ARSENAL: Arc Caster - buy it to use it" (research unlocks still say NOW AVAILABLE).
- While a weapon the player has reached is unbought, the lobby's progress line says "NEW WEAPON IN THE ARSENAL: ARC CASTER - 400 CREDITS", in gold when it is affordable, instead of the next level's unlock.
- Tests: a weapon on sale is not in the run's pool; bought, it is offered in at least 9 of 10 runs; the lobby and the level-up note point at the Arsenal.

Not changed: the weapons still cost Credits. Granting them for free on reaching the level is a one-line data change per weapon if wanted, but it removes 9,200 Credits of early spending.

**A test that leaked.** One of the level-up card tests added for build 9 left an arena running; later results-screen tests then failed on taps (10 checks) when the whole suite ran together. It is fixed; the game itself was never affected.

**Bought weapons not turning up (follow-up).** The real report was that a weapon already bought did not always appear in the run. Measured over 30 seeded runs with random picks, a bought weapon was offered at all in only 24-27 runs when three were owned, and 22-25 when eight were: in about one run in four it never showed. Bought weapons had the same small chance as the four starters, and new-weapon cards are only guaranteed until the build's second weapon (slots fill around Run Level 9).
- **The newest purchase not yet used is the run's first weapon card**, every run, until it has been used in a run (it has Mastery XP). Then the previous unused purchase takes over (`ArsenalService.featured_weapon`, `RunConfig.featured_weapon`).
- **Unused weapons are likelier**: never used in a run x3, below Mastery Rank 1 x1.5 (`untried_weapon_weight`, `new_weapon_weight` in `data/game.json`).
- With six weapons bought and the starters well used, the newest purchase was offered in 30 of 30 runs, the other purchases in 20-28, the starters in 13-18.
- Tried and dropped: offering a new weapon in every hand until the slots are full. Builds filled faster and Sector 20 went from 60% to 83% cleared in the sims, undoing the harder bosses. With the guarantee kept to the first weapon, the sims are unchanged (Sector 8 10/30, Sector 20 18/30).
- Tests: the newest purchase is in the first hand that offers a weapon in 10 of 10 runs; using it moves the feature on, and with everything used nothing is featured; over 600 hands an unused Arc Caster comes up more than twice as often as a well-used Scatter Shot; early hands always carry a weapon, a full build never gets one.

## 10. After build 10: Arsenal SKINS tab off screen

The SKINS tab of the Arsenal laid out wider than the screen (743 on the 720-wide canvas), so the list sat shifted right and cut off; CORES and WEAPONS were fine. The three skins added for build 8 (HAZARD, APEX, GAUNTLET) show their unlock goal in a tag on the right of the card, and a tag never wraps: "COMPLETE 6 WEEKLY CHALLENGES" made its card row 703 wide before the card's own padding. The older goals ("CLEAR SECTOR 20") were short enough to fit. Goal tags now wrap at 150 pixels (`UiKit.wrapped_tag`), about the width of a price button.

Tests: every Arsenal tab, and every main screen (Research, Arsenal, Play, Missions, Shop) on a profile far into the game, is laid out on a 720 x 1560 phone canvas and checked for anything past the right edge; the SKINS check failed at 743 before the fix. The screenshot tour gains the bottom of the SKINS list.
