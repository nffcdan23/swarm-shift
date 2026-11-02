# Game Design

Working title **SWARM//SHIFT**. A portrait, one-thumb roguelite swarm survivor. Sessions of three to six minutes; "one more run" is the goal.

## Pillars

1. **Understood in seconds.** Drag to move. Everything else is automatic.
2. **Power you can feel.** Level-ups come every ten seconds or so, and a good build should become absurd by minute four.
3. **Always something to come back to.** Every run pays out, every account level unlocks or grants something, and there is a daily reason to open the app.
4. **Fair.** Every attack that can hurt is telegraphed. Nothing is sold that is needed to play.

## The loop

```
move -> survive -> kill -> collect energy -> level up -> pick 1 of 3
     -> stronger build -> harder waves -> boss -> rewards
     -> permanent upgrades -> next run
```

## A run

- **Field.** Endless scrolling floor; the camera follows the core. Enemies enter from just off screen, a third of them ahead of the direction of travel so running in a line is never safe.
- **Opening.** Seven swarmers start on screen, so the first shots land within a second or two.
- **Timeline.** One timeline per run (`stages.json`): swarmer rate climbs from 1.7 to 13 per second over five minutes; Brutes join at 0:45, Dashers at 1:20, Splitters at 2:05, Shooters at 2:15, Tanks at 3:25. Enemy health rises to 6.5x over the same period, and from 2:00 enemies also get faster, up to 18% by the boss.
- **Shape of the five minutes.** 0:00-2:00 is the easy part: few enemy types, time to learn the build. 2:00-4:00 adds pressure through behaviour, not only numbers: more Dashers and Shooters, a Dasher pack at 2:30, a pincer at 3:25. 4:00-5:00 cannot be stood through: everything is faster, a firing line arrives at 4:15, and the last surge closes at 4:36.
- **Set pieces.** Swarm surges (a closing ring) at 1:00, 2:00, 3:00, 4:00 and 4:36; an elite with an escort at 1:30, 2:45, 3:45 and 4:30; a pack (one tight group from one side); a pincer (two walls from opposite sides); a firing line (ranged enemies spread along one edge); and, from Sector 3, bombardments (blast circles landing around the player). Each is announced by name, and nothing spawns inside the view.
- **Boss at 5:00.** A shockwave clears the field, everything it drops is pulled to the player, and an energy wall closes the arena.
- **Ending.** Sector mode ends in victory when the boss dies. Endless ("Overdrive", unlocked by clearing Sector 3) starts a harder cycle instead and runs until death.

### Run Level

There are two levels in the game and they are never called just "level". The **Run Level** is this run's: green energy crystals raise it, each level is a choice of three cards, and it resets to 1 at the start of every run. The **Player Level** (see *Between runs*) is permanent.

Energy needed for the next Run Level: `1 + 4L + 0.42L^2`. With the bot at the controls the first level-up arrives 4-8 seconds in and the second by about 15; runs that reach the boss are typically level 25-29.

On level-up the game pauses and offers three cards. Rules: nothing maxed or slotless is offered, and the run refuses any card that no longer fits the build; the card that completes an item is marked FINAL UPGRADE; once everything is complete the hand is Field Repair, Salvage (run Credits) and Purge; the first picks guarantee a new weapon so builds diversify early; owned items are weighted up so builds come together; luck raises the odds of rarer cards. One free reroll per run (more from permanent upgrades), then up to two by rewarded ad. Resuming clears a little space around the player and grants a moment of invulnerability.

Limits: 4 weapons (5 levels each), 5 passives, any number of augments.

### Weapons

| Weapon | Identity | Unlock |
| --- | --- | --- |
| Pulse Cannon | Fast, accurate bolts at the nearest enemy | Start |
| Scatter Shot | Short-range cone; huge up close, strong knockback | Start |
| Orbit Blades | Always-on ring that shreds and repels | Start |
| Cryo Nova | Frost pulse; slows, and freezes at max level | Start |
| Arc Caster | Lightning that chains through packed enemies | Level 2 |
| Seeker Missiles | Homing, explosive, spreads its targets | Level 3 |
| Plasma Mines | Lobbed into the path of whatever is chasing you (or dropped at your feet); big proximity blasts, slowing from level 4, cluster blasts at 5 | Level 4 |
| Combat Drone | A wingman that picks its own targets | Level 5 |
| Prism Lance | Charges, then fires a piercing beam down the most crowded line; extra beams take the next-best lines. Strong against formations, modest against a single target | Level 7 |
| Singularity | Drags the swarm into a ball, then implodes | Level 10 |
| Railgun | Marks the toughest enemy on screen, charges, and fires one instant line through it. Nothing else in the game aims this way | Research |
| Nanite Swarm | Infects enemies: damage over time, part of it a share of their health, spreading when they die. Bosses take a capped share | Research |

Ten of these have two **evolutions** each (see *Evolutions* below).

### Passives and augments

Thirteen passives cover damage, fire rate, crit chance and damage, speed, health, regeneration, armour, pickup radius, energy gain, luck, area and extra projectiles.

Eleven augments change the rules rather than the numbers: enemies explode on death (Volatile Cores), crits throw lightning (Storm Strike), chilled enemies shatter (Shatter), bullets split, seek or explode, a missile barrage every 40 kills, a shockwave when hit, periodic invulnerability, a damage-for-health trade (Glass Reactor), health from kills.

### Synergies

Seven named combinations switch on automatically when their pieces are owned, with a banner and a real bonus - for example **Tesla Storm** (Arc Caster + Storm Strike) or **Cryo-Detonation** (Cryo Nova + Volatile Cores). They are plain data, so more cost nothing to add. Discovering them is tracked and rewarded.

### Enemies

| Enemy | Behaviour |
| --- | --- |
| Swarmer | Weak, numerous, weaves as it closes |
| Brute | Slow and tough |
| Dasher | Stops, shows its lane, then charges along it |
| Shooter | Holds range, strafes, fires slow dodgeable shots. The shot gathers at its muzzle first; every enemy shot is drawn on top of everything, with a dark outline, at its true hit size |
| Splitter | Bursts into three fast Splitlings |
| Tank | Enormous health; cannot be pushed, pushes you |
| Weaver (Sector 2+) | Fast and fragile; circles in and strikes from the flank instead of running straight at you |
| Mortar (Sector 2+) | Stands off and lobs a shell at where you are heading. The landing circle is drawn for the whole flight: turning avoids it |
| Bomber (Sector 3+) | Runs in, plants itself and detonates after a short fuse. Its blast circle shows where not to be; killing it first, or walking away, both work |
| Elite | Any type, larger and tougher, with one affix: Swift, Armored, Volatile (a telegraphed death blast) or Broodmother (spawns swarmers). Drops a cache: a bonus pick with boosted rarity |

**Every blast is telegraphed.** Mortar shells, Bombers, bombardments, volatile elites and the boss's ground blasts all go through one system that draws the full blast circle for the whole fuse. A data test checks that each gives enough time to react and walk out from its centre, and a bombardment is tested against a planner that must always find a safe direction.

Pickups are colour-coded and the two colours are never mixed: **green crystals are run energy** (this run only), **gold coins are Credits** (kept). Enemies drop Credits at a rate set per type - a Swarmer 6% of the time, a Brute 30%, a Tank always; elites and the boss drop larger piles. Occasional helpers: a repair cell, a magnet that pulls in every crystal and coin, a bomb. A first-run hint and the pause menu both carry the green/gold legend.

The floor holds a limited number of pickups. When it fills up, crystals and coins far from the player are merged into larger ones nearby (crystals with crystals, coins with coins, never helpers), so a kill always leaves its reward where it happened and a merged crystal pays exactly what its parts would have.

### Boss - The Overseer

Three phases at 66% and 33% health; each adds attacks, speed and bullet count. A phase change staggers it and clears its bullets.

| Attack | Telegraph |
| --- | --- |
| Radial bursts | Slow, bright, round shots |
| Charge | A lane that tracks, then locks for the last half |
| Summon | A visible wind-up |
| Rotating lasers (phase 2+) | Thin lanes for a second before the beams fire |
| Ground blasts (phase 3) | Circles that fill in; one is always under the player |

## Between runs

- **Player Level 1-100.** Permanent, and always visible in the lobby with its XP numbers, its bar and the next thing it unlocks. Player XP comes from every run - time survived, enemies defeated, Run Level reached, bosses, sectors cleared - and from daily missions and achievements. Every level pays Credits; every fifth pays Crystals; and levels open content: weapons at 2, 3, 4, 5, 7 and 10, cores at 3, 6, 9 and 12, permanent upgrades at 2, 3, 4, 5, 6 and 8.
- **Research.** Everything permanent is bought with Credits in the Research tab, in six branches. **Offence, Defence, Energy, Economy** hold the original sixteen stat tracks (their levels and caps have not changed) plus focused additions such as Siege Protocols (damage to bosses and elites), Last Stand, Kinetic Buffer and Priority Signal (a fourth upgrade card). **Weapon Systems** holds the unlocks that change how runs play: Evolution Lab, Flex Rack (choose your starting weapon), Ballistics Suite, Railgun and Nanite prototypes, Synergy Codex I and II (six extra synergies), Twin Evolution, Auxiliary Bay (sixth passive slot) and Fifth Hardpoint (fifth weapon slot). **Specialisation** holds the doctrines and awakenings.
- **Doctrines.** Trade-offs, one active at a time, changed freely: Glass (+30% damage, -30% health), Bulwark (+40% health and +2 armour, -20% damage), Scavenger (+25% energy and +20% Credits, -15% damage), Specialist (+60% damage, only two weapon slots), Generalist (+1 weapon slot, -2 passive slots). They are depth without inflation: owning them all adds no power, only options.
- **Awakenings.** Each core can research its own ability: an augment it starts every run with (Vanguard: Reactive Shell; Striker: Seeker Rounds; Bastion: Siphon; Frostbite: Shatter; Tempest: Storm Strike; Phantom: Phase Shift).
- **Weapon mastery.** Five ranks per weapon, shown in the Arsenal. A run earns one budget of Mastery XP: 30 per active minute, counting six minutes at most, scaled up slowly by sector, plus bonuses for bosses and a clear. It is shared between the run's weapons by the square root of the damage each landed, so the main weapon earns most and a support weapon or a first try still earns a real share. A longer run earns no more, time spent not moving does not count, and a run with no real fighting earns nothing. Rank 1 makes a weapon a Flex Rack option; 2 and 4 give small weapon-specific perks; 3 and 4 open evolutions; 5 gives a gold finish and counts towards the PARAGON skin.
- **Skins.** Layered, animated cores (see *Skins*). Most are bought with Credits.
- **Cores.** Six playable cores, each with its own starting weapon and stat trade-offs (for example Bastion: +40% health, +2 armour, -8% speed, starts with Orbit Blades).
- **Sectors 1-20.** Clearing one unlocks the next and pays a one-time Crystal bonus. Rewards grow 30% per sector. Sectors are not the same fight with bigger numbers:

| Sector | What is different |
| --- | --- |
| 1 - First Contact | The basics: Swarmers, Brutes, Dashers, Splitters, Shooters, Tanks |
| 2 - Crossfire | Adds Weavers and Mortars, a Weaver pack and a Mortar battery |
| 3 - Meltdown | Adds Bombers, a Bomber wing and three bombardments |
| 4-9 | Everything above, plus one **mutator** from a rotation |
| 10-20 | Two different mutators at once |

Mutators: **Blitz** (everything 12% faster, slightly frailer), **Artillery** (more Mortars, a bombardment every 42 s), **Hunters** (more Dashers and Weavers, a Dasher pack every 38 s), **Elite Guard** (an extra elite every 48 s), **Volatile** (more Bombers; every elite explodes), **Horde** (25% more enemies, each a little weaker). The lobby names the sector's mutators before the run starts, and the run announces them after its opening banner. Overdrive takes one mutator per cycle from its second cycle on. Underneath all of that, enemy health, damage and spawn rate still scale with the sector.

### Evolutions

At its final level a weapon can evolve, if the path has been unlocked (Evolution Lab, the Mastery rank, and Credits). A card appears on the next level-up with both owned paths side by side, plus one ordinary card. One weapon can evolve per run; Twin Evolution makes it two. Choosing mid-run is the point: the right path depends on the run in front of you.

| Weapon | Evolution | Job |
| --- | --- | --- |
| Pulse Cannon | Storm Repeater / Breach Cannon | One tight stream for single targets / slow shells that burst on everything they pass |
| Scatter Shot | Flak Burster / Slug Thrower | Shells that burst at range / a tight cone of heavy slugs up close |
| Orbit Blades | Ripper Discs / Aegis Halo | Blades fling out for reach / a wider ring that destroys enemy shots |
| Cryo Nova | Permafrost / Glacial Spikes | Lingering frozen fields / ice spikes at the toughest enemies |
| Arc Caster | Storm Conductor / Overload Coil | No fade and far more jumps / fewer, harder strikes that burst |
| Seeker Missiles | Hive Pods / Bunker Buster | A cloud of small missiles / one heavy warhead at the toughest enemy |
| Plasma Mines | Shaped Charges / Stasis Field | Tight, heavy blasts / blasts that leave a slowing, burning field |
| Combat Drone | Hunter Pack / Siege Platform | An extra drone with curving rounds / heavy rounds at the toughest enemy |
| Prism Lance | Rail Lance / Sweeping Lance | One narrow instant shot at the toughest enemy / wide beams that swing across the screen |
| Singularity | Collapsar / Supernova | A longer hole that pins the swarm / a quick collapse into one colossal blast |

A test holds this to account: on the weapon bench, neither path of any weapon may beat the other at everything.

### Skins

Each skin is a stack of animated layers: a body with its own silhouette, orbiting armour plates, a ring, an aura, a pulsing reactor and motes, plus its own movement trail, kill-burst colour and a tint over every weapon. Same footprint as the factory core.

| Rarity | Skins | How |
| --- | --- | --- |
| Common | Factory | Default |
| Rare | Ember, Venom, Amethyst, Rose | Crystals (unchanged) |
| Epic | Ghost | Crystals (unchanged) |
| Epic | Glacier, Inferno, Solar, Quantum, Void | Player Level and 12,000 to 50,000 Credits |
| Legendary | Aurum | Starter Pack (unchanged) |
| Legendary | Paragon, Overseer | Earned: master 3 weapons; clear Sector 20 |

Skins are looks only. Tests prove it: the same seed plays out identically in every skin. No skin's tints may come near the red of enemy fire, because a red ring with a white centre is what an enemy shot looks like.

## Economy

| Currency | Earned from | Spent on |
| --- | --- | --- |
| **Credits** (soft) | Gold pickups in a run, a survival bonus (10 per minute), clearing a sector, Player Levels, missions, login calendar, optional ads | Research, weapon and core unlocks, evolutions, skins |
| **Crystals** (premium) | Achievements, first clears, every fifth Player Level, the daily mission bonus, day 3/6/7 of the login calendar, purchase | Core skins, one core, exchange for Credits |

Nothing in the game requires Crystals to progress.

**Overdrive pays by depth, up to what the player has earned.** Its reward tier is capped at the highest sector cleared plus one, so it cannot out-earn the campaign early on.

**Nothing earned in a run is ever lost.** Credits and Player XP are banked when the run ends, however it ends: death, victory, or leaving from the pause menu (which first shows exactly what will be banked and asks). Leaving early pays the same as dying at that moment. Each run can be paid out once only. And a run that never reaches its end - the app is closed or killed mid-fight - is checkpointed every few seconds and paid out at the next launch.

The results screen shows time survived, enemies defeated, Run Level reached and bosses defeated, then collects the rewards in sequence: Credits line by line (picked up, survival bonus, sector clear), then Player XP line by line into the Player Level bar, with any level-ups and what they unlock. A tap skips the sequence; it never changes what was earned.

Rough income for a player with no upgrades: about 200 Credits for a three-minute run, 600-800 for a cleared Sector 1. The first upgrade levels cost 100-250, so the first runs each buy one or two.

## Retention

- **Daily missions.** Three per day from a pool of twelve, with a bonus for claiming all three.
- **Login calendar.** Seven days, looping. Missing a day never resets it.
- **Achievements.** Thirty, paying Crystals and Player XP.
- **Statistics.** Lifetime totals on the profile screen.

## Monetisation

| | |
| --- | --- |
| Rewarded ads (always optional) | Revive once per run, double a run's Credits, an extra reroll, double the daily reward, a few free Credits per day |
| Interstitial ads | Between runs only. Never before the third run, never more often than every second run or every three minutes, never straight after a rewarded ad |
| Remove Ads | One-time purchase; removes interstitials, keeps the optional rewarded ads |
| Starter Pack | One-time: Crystals, Credits and an exclusive skin |
| Crystal packs | Three sizes |

Deliberately absent: countdown timers on offers, fake scarcity, pay-to-skip difficulty walls, punishing streak resets, ads during play.

## Tuning

All numbers are in `data/*.json`. Difficulty per sector is `1 + a*n + b*n^2` on enemy health and damage (n = sector - 1); the squared term is what keeps late sectors ahead of a fully upgraded player. On top of that sit the sector's roster and mutators (see *Between runs*).

### How hard each minute pushes

From the balance simulator (`--pressure`, 30 bot runs, averages over the runs still alive at the start of each minute). "Health lost" is damage taken as a share of maximum health; "blast zones" are telegraphed ground blasts from Mortars, Bombers, bombardments, volatile elites and the boss.

| Minute | Sector 1, no upgrades | Sector 2, 15% upgrades | Sector 3, 25% upgrades |
| --- | --- | --- | --- |
| 0-1 | 0% health lost, 16 enemies | 0%, 16 enemies | 0%, 16 enemies |
| 1-2 | 2%, 46 enemies, 5 charges | 3%, 47 enemies | 3%, 43 enemies |
| 2-3 | 13%, 94 enemies, 28 charges, 12 shots | 18%, 7 blast zones | 12%, 11 blast zones |
| 3-4 | 22%, 149 enemies, 30 shots | 46%, 18 blast zones | 36%, 21 blast zones |
| 4-5 | 28%, 177 enemies, 14% faster, 46 shots | 59%, 19 blast zones | 58%, 26 blast zones |
| Boss | 70% | 46% | 55% |

That is the intended shape: two minutes with almost no damage, a middle that starts to cost health, a last minute before the boss that cannot be stood through, and the boss as the real test of a first, un-upgraded run.

### Clear rates

24-30 bot runs each at skill 0.7; "upgrades" is the share of every permanent track bought. Sectors 4 and up are shown at roughly the upgrade level a player might have by then, which is a guess.

| Sector | Upgrades | Reached boss | Cleared |
| --- | --- | --- | --- |
| 1 | 0% | 87% | 40% |
| 1 | 15% | 90% | 80% |
| 2 | 5% | 60% | 33% |
| 2 | 15% | 70% | 67% |
| 3 | 15% | 60% | 37% |
| 3 | 25% | 80% | 57% |
| 4 (Blitz) | 35% | 83% | 67% |
| 5 (Artillery) | 45% | 75% | 58% |
| 6 (Hunters) | 50% | 88% | 79% |
| 7 (Elite Guard) | 60% | 75% | 71% |
| 8 (Volatile) | 65% | 79% | 67% |
| 9 (Horde) | 75% | 96% | 88% |
| 10 (two mutators) | 85% | 96% | 88% |
| 14 | 100% | 29% | 12% |
| 20 | 100% | 8% | 0% |

These figures predate the November 2026 progression overhaul, which made early sectors easier and Sector 8 less of a spike; see `docs/progression/README.md`.

For the same player (15% of upgrades), Sectors 1, 2 and 3 clear at 80%, 67% and 37%: beginner, moderate, challenging. Each sector is roughly ten points of upgrades ahead of the one before.

Average payout with no economy upgrades: a three-minute Sector 1 run pays about 130 Credits and 240 Player XP; Sector 1 averages 540 Credits and 570 XP a run, 750 Credits when cleared; Sector 3 at 25% upgrades averages about 900 Credits. Overdrive at 50% upgrades lasts a median of 21 minutes and pays about 6,000 Credits and 7,500 Player XP, because its reward multiplier is taken from the last cycle reached - generous, and due a second look.

Read all of this as a shape, not a prediction. Thirty runs is a small sample (roughly +/-9 points), the bot never plans a build, and it dodges blast zones with perfect attention and no thumbs. **Bot numbers are not a playtest.** One human session exists so far: on the previous build a player reached Run Level 16 at 2:58 in Sector 1 with no upgrades, comfortably, before the freeze described in [docs/playtest-1](docs/playtest-1/README.md) ended it - which is in line with the bot at that point and says nothing about minutes 3 to 5 or anything in Sector 2 or beyond. The questions that most need real play:

- Is Sector 1's boss fair for a first-time player, or is 40% too low for a beginner sector?
- Do Mortar shells and bombardments read clearly on a phone, with a thumb over part of the screen?
- Are Weavers noticed as a different kind of enemy, or just as faster Swarmers?
- Is the jump from Sector 2 to Sector 3 too steep?
- Do the mid sectors (6, 7, 9, 10) feel too comfortable once upgrades arrive?
- Are the weaker-looking weapons (Orbit Blades, Combat Drone, Cryo Nova) weak in human hands, or only in the bot's, which always kites?

## Open questions for the business

- Final name, bundle identifier and Apple Team ID.
- A licensed display typeface (the engine default is used throughout; the swap is one line in `ui_theme.gd`).
- Whether the generated art and audio are the launch look or placeholders for commissioned assets.
- Real price points per region.
