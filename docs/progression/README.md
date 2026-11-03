# Progression, weapons and cosmetics overhaul

Started 2 November 2026 on branch `feat/deep-progression`, from `main` at d961235 (build 5).

## 1. Audit of the game as it stood

All numbers are from the shipped game, played by the bot on one persistent free profile through the real `RunLedger` (`--campaign`), or from fixed runs (`--sim`, `--track-value`). A bot is not a person: treat these as relative, not as a promise of what a human will feel.

### How fast everything runs out

Free player, no purchases, no ads, no daily rewards or missions, always playing the highest sector available, never touching Overdrive:

| Skill | 25% of upgrades | 50% | 75% | 100% | Runs to 100% | Credits unspent after 115-120 runs |
| --- | --- | --- | --- | --- | --- | --- |
| 0.35 | 41 min | 93 min | 3 h 19 | **6 h 32** | 104 | 26,137 |
| 0.60 | 36 min | 70 min | 3 h 03 | **5 h 56** | 90 | 33,612 |
| 0.85 | 42 min | 101 min | 3 h 11 | **7 h 00** | 103 | 20,338 |

- **Every upgrade is bought in 6-7 hours, usually before Sector 18**, and Credits then accumulate with nothing to spend them on. Everything costs about 160,000 Credits in total (130,732 for upgrades, about 30,000 for weapon and core unlocks).
- **Skill barely changes that.** Income comes from showing up, not from playing well.
- **Overdrive makes it much shorter.** Per run at 25% / 50% / 100% of upgrades: 3,741 / 8,556 / 10,417 Credits and 5,077 / 11,004 / 10,504 Player XP, against about 1,000-2,000 Credits for a Sector clear. Per minute that is about the same as clearing sectors, but it needs no clear, it unlocks after Sector 3, and it pays more the longer you can stretch the run. At that rate the whole tree is about 15-20 runs.
- **Player Level goes quiet.** Nothing new unlocks after Level 12. Levels 13-100 pay Credits and nothing else.

### What the spending looks like

- **There are no choices.** Sixteen tracks, nothing mutually exclusive, and eventually you own all of it. The only decision is the order.
- **Nearly every upgrade is imperceptible on its own.** `--track-value` (the same 16 runs with one track maxed, Sector 8 at 30% of everything): most tracks gain 0-2 seconds of survival per 1,000 Credits, which is inside the noise. Emergency Reboot is the stand-out at +7.6 s per 1,000. Nothing is broken, but nothing is exciting either: a player buys forty small numbers.
- **Nothing changes how the game plays.** Every purchase is a stat, apart from Pre-Charged Arsenal, Reboot and rerolls.
- **Skins are a colour swap.** Six tints of the same hexagon, on Crystals only, so they never absorb Credits either.
- **Credits have no use at the end, and neither do Crystals** beyond the exchange and the skins.

### Weapons

`--weapon-bench` and `--weapons=8` (see `docs/playtest-3`):

- **Arc Caster** and **Scatter Shot** are weak in single-target and early swarm damage (Arc: 13 / 19 / 25 single target by level).
- **Singularity** is the weakest alone: median survival 2:51, never reached a boss. It fires every 5.6 s and does nothing in between.
- **Combat Drone** does little to a swarm early (25 damage/s at level 1, it hits one thing at a time).
- **Orbit Blades** and **Cryo Nova** do nothing to a target that stays away from you.
- Every weapon aims at the nearest enemy or the densest area. **Nothing hunts the most dangerous enemy on screen, and nothing deals damage over time**, which is why high-health enemies in late sectors simply take longer.

### Sector 8 (Alex's report)

Thirty runs per sector at 40% of upgrades, skill 0.45:

| Sector | 6 | 7 | **8** | 9 | 10 | 11 | 12 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Clear rate | 37% | 50% | **7%** | 23% | 7% | 0% | 7% |
| Reached the boss | 57% | 63% | 37% | 27% | 17% | 0% | 17% |

**Sector 8 is harder than Sector 9.** Below about a third of all upgrades it is effectively closed (0% at 20%, 8-17% at 35%). The sectors the bot gets stuck on across whole campaigns are 8, 11, 14 and 17, and all four carry the **Volatile** mutator (double Bomber wings, every elite explodes). So this is a specific spike, not the general curve, and it can be fixed without flattening the game.

### The most important weaknesses, in order

1. The economy has no endgame: 6-7 hours and it is over, and Overdrive shortens that to a fraction.
2. Permanent progress is forty invisible stat bumps with no choices in it.
3. Nothing a player does with a weapon carries over, so nothing pulls them towards trying a different one.
4. Three weapons are weak and two roles do not exist.
5. Skins are not worth wanting.
6. Sector 8 (Volatile) is a wall in the wrong place.

## 2. The design

Five connected ideas, using existing systems wherever possible. The modifier language, the run ledger, the unlock rules, the upgrade cards and the Credits economy all stay; nothing here adds a currency.

- **Research** replaces the Upgrades tab. The sixteen existing tracks stay as they are, with their levels and caps. Around them, six branches (Offence, Defence, Energy, Weapon Systems, Economy, Specialisation) add one-off unlocks that change how a run plays: evolutions, a choice of starting weapon, new synergies, a fourth upgrade card, a fifth weapon slot, each core's own ability, and doctrines, which are mutually exclusive trade-offs rather than more power.
- **Weapon mastery** is five ranks per weapon, earned from damage actually dealt. A run has a fixed budget of mastery, shared between the weapons that did the work, so a longer run earns nothing extra and a weapon you try for the first time still earns its share.
- **Evolutions** are two paths per weapon. Mastery and Credits unlock them; the choice is made during the run, on a card, once the weapon reaches its final level, so the right path depends on the run in front of you.
- **Two new weapons** fill the two roles the audit found missing: a Railgun that hunts the toughest enemy on screen, and a Nanite Swarm that deals spreading damage over time.
- **Skins** become layered, animated cores with their own silhouette, armour, reactor, trail and kill effect, and most of them are bought with Credits.

## 3. What was built

### Research (`data/meta.json`, `MetaService`, `UpgradesScreen`)

The Upgrades tab is now Research: 45 entries in six branches, 132 levels, 556,000 Credits in total. The original sixteen tracks are untouched, so no existing level or cap moved. Everything new is a one-off, a doctrine or an awakening; no stat cap was raised.

| Branch | Added |
| --- | --- |
| Offence | Siege Protocols (+10% to bosses and elites, 3 levels), Executioner (ordinary enemies under 10% die to any hit) |
| Defence | Last Stand, Kinetic Buffer |
| Energy | Priority Signal (a fourth upgrade card) |
| Weapon Systems | Flex Rack, Evolution Lab, Synergy Codex I and II, Ballistics Suite, Railgun Prototype, Nanite Foundry, Twin Evolution, Auxiliary Bay, Fifth Hardpoint |
| Economy | Bounty Network (+25% clear bonus, 3 levels), Field Analyst (+10% Mastery XP, 3 levels), Mission Uplink (a fourth daily mission) |
| Specialisation | Five doctrines (one at a time) and six awakenings (one per core) |

Player Level gates now run to Level 36, so levels 13-40 open things again.

### Mastery and evolutions (`data/weapons.json`, `MasteryService`, `WeaponModal`)

Five ranks per weapon at 100 / 300 / 800 / 2,000 / 5,000 XP. The rules against farming:

| Exploit | Why it does not work |
| --- | --- |
| Leaving the game running | The level-up screen stops the run anyway; time not moving stops counting after 6 seconds |
| Stretching a run | The budget counts six active minutes at most, and two bosses at most |
| Farming Overdrive for depth | Same budget as a sector of the same length |
| Starting and quitting runs | XP is per minute and per kill rate: eight seconds is worth under 6 XP before it is shared |
| Hiding in a corner | A run below 60 kills a minute earns proportionally less, and no kills earns nothing |

Evolutions: ten weapons, two paths each, twenty in total, 182,000 Credits. Railgun and Nanite Swarm have Mastery but no evolutions yet.

### Weapons

| Weapon | Change |
| --- | --- |
| Arc Caster | 24 damage (was 16), 1.0 s (1.25), more reach, less falloff, +60% at level 3 |
| Scatter Shot | 9 damage (7), 0.92 s (1.05), slightly more range, pellets pierce from level 3 |
| Combat Drone | 10 damage (9), pierces one from level 1 |
| Singularity | 11 tick and 130 implosion (8 and 90), 3.8 s (5.6), larger and stronger pull |
| Railgun (new) | Targets the toughest enemy on screen; instant piercing line |
| Nanite Swarm (new) | Damage over time, part of it a share of max health, spreads on death; bosses capped |

GRAVITY WELL was not added because Singularity is that weapon. PLASMA STORM and VOID PULSE were not added because they overlap Mines and Cryo Nova. RAILGUN and NANITE SWARM were added because nothing else aimed at the toughest enemy or dealt damage over time.

### Cosmetics

`CoreVisual` draws a skin as animated layers, in the run, the lobby and the Arsenal alike. There are 14 skins: the six old ids are kept, so every purchase stands, and each now has real art; five themed cores (Glacier, Inferno, Solar, Quantum, Void) cost 142,000 Credits between them; Paragon and Overseer are earned, not bought. A weapon at Master rank wears a gold finish.

### Economy

- **Overdrive's reward tier** is capped at the highest sector cleared plus one.
- **Volatile's Bomber wings** go from x2.0 to x1.3.
- Total Credit sinks: **about 880,000** (research 556,000, evolutions 182,000, Credit skins 142,000), up from about 160,000.
- No new currency. Six new achievements add a little free Crystal income, the same way achievements always have.

## 4. Balance results

The same tools as the audit, on the final numbers.

### Free player, sectors only (`--campaign`)

No purchases, ads, daily rewards or missions, and no Overdrive. Hours of play:

| Milestone | Skill 0.35 | Skill 0.60 | Skill 0.85 |
| --- | --- | --- | --- |
| Evolution Lab | 0.9 | 0.8 | 1.5 |
| Sector 8 cleared | 1.7 | 1.0 | 1.2 |
| First evolution | 2.3 | 3.0 | 2.9 |
| Sector 12 cleared | 3.3 | 3.2 | 2.2 |
| First Master rank | 4.9 | 4.8 | 4.5 |
| Sector 16 cleared | 5.2 | 5.0 | 3.5 |
| Sector 20 cleared | 10.0 | 8.7 | 6.1 |
| 25% of research, by Credits | 9.2 | 8.6 | 8.5 |
| Every evolution | not reached in 16.5 h | 16.4 | 17.4 |
| 50% of research, by Credits | not reached in 16.5 h | 17.9 | 18.3 |

Income was 15,000-22,000 Credits an hour. At that rate the 880,000 Credits of sinks is **about 40-55 hours**, against 6-7 hours before. Reaching Sector 20 takes about as long as it did (5.6 hours before at skill 0.6, 6.8 now), so the extra depth did not come from slowing the campaign down much. Sector 20 still clears only about 6-16% of the time, on a profile with most research done.

Skill now matters more: a Sector 20 clear comes 4 hours sooner at skill 0.85 than at 0.35. Before, skill barely changed the pace, and the 0.35 and 0.85 bots never reached Sector 20 in 120 runs even with every upgrade bought.

### With Overdrive mixed in (`--campaign --overdrive=3`)

One run in three in Overdrive, skill 0.6, stopped at run 194:

| By | Play time | Earned from runs | State |
| --- | --- | --- | --- |
| Run 30 | 4.9 h | 84,000 Credits | Player Level 34 |
| Run 60 | 10.4 h | 233,000 | Player Level 51 |
| Run 90 | 15.9 h | 385,000 | Player Level 63 |
| Run 120 | 21.4 h | 547,000 | Everything the bot was set to buy is bought |

Overdrive now pays about what sectors do: around 26,000 Credits an hour against 28,000 at that stage, and an early run (Sector 3 cleared, 15:38) pays 3,000. Before, it was the best income in the game from Sector 3 onwards. So an engaged player finishes everything in **about 25-30 hours**. This bot never buys cores, so it also skips their awakenings and any skins, which is why Credits start piling up after that: 438,000 banked by run 194, and a reminder that the sinks do end.


### Sector 8

Thirty runs per sector, 40% of every stat track, skill 0.45:

| Sector | 6 | 7 | **8** | 9 | 10 | 11 | 12 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Before | 37% | 50% | **7%** | 23% | 7% | 0% | 7% |
| After | 47% | 70% | **27%** | 27% | 20% | 13% | 7% |

Sector 8 no longer sits above Sector 9, and it took the Volatile change, not a general reduction, to do it. Campaigns: Sector 8 fell on the first attempt at all three skill levels; before it took 8, 1 and 7.

Early sectors, build 5 against this build in the same seeded sim: 60 runs each at skill 0.6, using only the weapons a player could own by that Player Level (`--level-pool`), because a new player does not have every weapon:

| Sector, upgrades, weapons owned | Build 5 | Now |
| --- | --- | --- |
| 1, 0%, starters only | 48% | 68% |
| 1, 5%, up to Level 3 | 62% | 63% |
| 2, 5%, up to Level 4 | 35% | 45% |
| 2, 10%, up to Level 5 | 58% | 65% |
| 3, 10%, up to Level 7 | 38% | 52% |
| 3, 15%, up to Level 8 | 63% | 65% |

**The first attempts at each early sector got easier. Once a player has bought a little, the curve is back where it was.** Sixty runs is roughly plus or minus 12 points, so only the first row has clearly moved. The cause is mostly Scatter Shot, a starting weapon, which is now about 50% stronger. A first Sector 1 clear about two times in three seems right for a beginner sector (the design notes already asked whether 40% was too hard), and Sectors 2 and 3 still fall about half the time at those stages, so nothing was changed. If playtesters find the first runs too easy, trim Scatter's damage first.

With every weapon available from the start, the same sim shows bigger rises (Sector 1 at 0%: 58% to 80%; Sector 3 at 25%: 70% to 95%), but no real player has that.

### Weapons alone

Sector 2, 15% of upgrades, eight runs where it is the only weapon. Survival and damage per second:

| Weapon | Before | After |
| --- | --- | --- |
| Scatter Shot | 4:30, 131 | 5:23, 207 |
| Arc Caster | 4:20, 203 | 5:30, 404 |
| Combat Drone | 5:30, 308 | 5:26, 341 |
| Singularity | 2:51, 124 | 4:04, 275 |
| Railgun | new | 2:23, 289 |
| Nanite Swarm | new | 5:30, 387 |

### Evolutions (`--weapon-bench --evolved`)

Damage per second, Sector 8 health. Single target / swarm around a still player / swarm chasing a moving one. The swarm columns top out around 1,300 because the bench runs out of enemies.

| Weapon | Level 5 | Path A | Path B |
| --- | --- | --- | --- |
| Pulse Cannon | 158 / 225 / 267 | Storm Repeater 284 / 507 / 538 | Breach Cannon 135 / 1192 / 1080 |
| Scatter Shot | 89 / 408 / 364 | Flak Burster 91 / 913 / 659 | Slug Thrower 289 / 499 / 584 |
| Orbit Blades | 0 / 1127 / 725 | Ripper Discs 71 / 1169 / 821 | Aegis Halo 0 / 1241 / 813, plus destroys shots |
| Cryo Nova | 12 / 944 / 479 | Permafrost 12 / 1277 / 1021 | Glacial Spikes 217 / 999 / 612 |
| Arc Caster | 52 / 489 / 473 | Storm Conductor 52 / 1232 / 1175 | Overload Coil 132 / 1123 / 987 |
| Seeker Missiles | 101 / 1080 / 796 | Hive Pods 191 / 1116 / 923 | Bunker Buster 270 / 981 / 630 |
| Plasma Mines | 105 / 1275 / 1107 | Shaped Charges 234 / 838 / 965 | Stasis Field 137 / 1319 / 1176 |
| Combat Drone | 163 / 380 / 368 | Hunter Pack 217 / 784 / 529 | Siege Platform 315 / 354 / 400 |
| Prism Lance | 83 / 1169 / 1237 | Rail Lance 231 / 731 / 645 | Sweeping Lance 55 / 1280 / 1148 |
| Singularity | 90 / 1009 / 1052 | Collapsar 88 / 1341 / 1143 | Supernova 172 / 1263 / 1230 |

The first pass failed this: Overload Coil beat Storm Conductor, Stasis Field beat Shaped Charges and Siege Platform beat Hunter Pack, on nearly every column. They were retuned, and a test now fails if any path beats its sibling at everything.

### Performance

`--weapon-load`: each weapon at level 5 among 400 enemies. The most expensive evolution, Aegis Halo, adds 0.9 ms per step; most add under 0.3 ms. Headless on a loaded Mac, not a phone. Six level-5 weapons, four of them evolved, cost under 8 ms a step in the same conditions, and a test holds it there.

## 5. Tests

Three new suites: `research` (26 tests, including both version 1 fixtures), `mastery` (29), `skins` (11), plus 10 new UI tests. Full suite: **3,595 checks, 0 failed**. Also: same seed in five skins plays out identically; every evolution runs and does damage; rendered screens reviewed for Research, Arsenal, the weapon view, the lobby, every skin, eleven evolved weapons in combat, the evolution card, and four cards on a 450x800 window. The iOS resource pack exports locally (3.7 MB) with the new assets in and tests out; nothing was built for or installed on a phone.

Rendered review found two things tests had not: the long loadout caption pushed the whole lobby off the right edge, and the Overseer skin's red kill bursts looked like enemy shots. Both are fixed and both now have tests.

## 6. Known limitations

- **None of this has been played by a person.** Every balance number above is the bot, and bots are not players. Whether evolutions feel earned, whether the first weeks feel too fast or too slow, whether Mastery is noticed at all, needs people.
- **The first attempts at Sectors 1-3 got easier** (Sector 1 with no upgrades: 48% to 68% in the bot's hands), mostly from the Scatter Shot buff. Probably right for a beginner sector, but it needs a person's view. If it is too much, trim Scatter's damage first: `hp_per_tier` does nothing at Sector 1.
- **Sector 17 is the next wall** for a weaker bot (77 attempts at skill 0.35, 21 at the others). It carries Volatile and Artillery together. It may be right for that stage of the game; it may need the same look Sector 8 got.
- **Railgun is poor on its own by design** (2:23 alone, never reaches a boss) and **Singularity is still the weakest of the original ten alone** (4:04), though far better.
- **Railgun and Nanite Swarm have no evolutions**, so those two have no reason to reach Rank 3 or 4 beyond their perk.
- **The economy never has a repeatable sink.** It is about 880,000 Credits long, which is 40-55 hours for a free player, but it ends. Past that, Credits have no use again. A player that far in has finished the game, so this seems fine; flagging it because it was the original complaint.
- **Doctrines, awakenings and Flex Rack were not used by the simulated player,** so the campaigns understate what a player who uses them gets, and their strength has been checked by tests of what they do, not by how they balance.
- **New sounds were not added.** Railgun and evolutions reuse existing effects at other pitches.
- **Skins and the trail were reviewed on Mac renders only,** not on a phone at phone brightness.

## 7. How to try it

Mac, with a throwaway profile so the real save is untouched:

```bash
godot --path . -- --profile=overhaul
```

A new profile starts at the beginning. To see the late game quickly, use the screenshot tour, which builds a rich in-memory profile and writes a picture of every new screen:

```bash
godot --path . --resolution 540x1170 -- --shots=/tmp/swarm-shots --only=progress
```

On an iPhone, once installed: check that an existing save keeps everything; open Research and try each branch; buy Evolution Lab; play until a weapon reaches Rank 3 and open it in the Arsenal; take a weapon to its final level and look for the two cards; try a Credit skin in a run. Sector 8 is the one to send Alex back to.

## 8. Before the next TestFlight build

1. Raise the build number (`export_presets.cfg`, `application/version`; 5 is taken).
2. Run `tools/ios_release.sh` for a local archive, then install on a phone with an existing save and confirm the migration.
3. Play it: Alex on Sector 8, plus someone on a new profile for the first hour.
4. Check frame rate with an evolved build on a phone, and how the new skins read at phone size.
5. Upload only when you ask for it. Nothing here was uploaded.
