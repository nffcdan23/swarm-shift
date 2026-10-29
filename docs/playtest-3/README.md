# Playtest 3 - enemy shots lost in the swarm, Prism Lance and Plasma Mines

Three reports from human playtesting, investigated on 29 October 2026 on branch `feat/readable-projectiles-and-weapons`.

## 1. Enemy shots hidden by the swarm

**Report.** Shooters' small red shots disappear among enemies in a big swarm, so players take hits they never saw coming.

### Root cause (established from the code)

Three things together, all in how the shots were drawn, not in the collision:

1. **Additive blending.** Shots were drawn additively (`ArenaGfx.bullets`), which only brightens what is underneath. A red shot over a red Swarmer, an orange Brute or a bright explosion adds almost nothing visible.
2. **Covered by effects.** The shot layer was above the enemies but **below** particles, beams and flashes, shockwave rings and damage numbers. In exactly the fights where shots matter, explosions and numbers sat on top of them.
3. **Drawn smaller than they hit.** The sprite's solid core had a radius of about 3.6 units; the collision radius is 8. Shots that looked like near misses were hits.

The Shooter's only warning before firing was a brief white flash on its body, invisible in a crowd.

### Changes

- New top layer `ArenaGfx.hostile`, drawn **last**, above every other battlefield layer, with normal alpha blending.
- New sprite `hostile.png` (made by `tools/generate_art.gd`): a near-black outline that no other sprite in the game has, a hot red body, a white-hot centre. Readable on dark floor, bright enemies and explosions alike.
- The red body's edge is the hit radius exactly (`size` 32 = 4 x `radius` 8 in `enemies.json`), so what you see is what hits you. **Collision is unchanged**: same radius, same rule (shot radius + 80% of the player's).
- A short, faint trail behind each shot (two soft glows in the old additive layer) shows its direction without adding anything that looks like a hit area.
- **Firing cue:** for the Shooter's 0.35 s telegraph, the shot gathers at its muzzle in the same look as the shot, growing and brightening. One small sprite per charging Shooter; no screen-wide warnings.

Evidence that gameplay is untouched: in full simulated runs every weapon unaffected by this work gives identical results before and after (table below). Shooters fire throughout those runs.

## 2. Prism Lance

**Report.** "Extremely weak and largely useless."

### What was wrong (measured)

| Measure | Finding |
| --- | --- |
| Single target (a pinned Tank, `--weapon-bench`) | 29 / 59 / **10** damage per second at levels 1 / 3 / 5: it got **worse** with upgrades |
| Moving swarm | 189 / 279 / 747 per second: at levels 1-3 about the starting Pulse Cannon |
| Full runs, only weapon (Sector 2, 15% upgrades) | 74 damage/s, median survival **2:28**, reached the boss 12% of the time, weapon level 2.4 |

Causes: it fired a thin beam (18 wide) at the nearest enemy for 1.6 s every 5.2 s, turning slowly, so it rarely held a line of enemies. With two or more beams (levels 4 and 5) the code switched to a fixed spinning rotor and stopped aiming at all, which is why level 5 hit a single target less than level 1.

### Changes (`src/game/weapons/prism_lance.gd`, `data/weapons.json`)

- **Aims at the most crowded line.** Each cycle it tests the lines towards the 10 nearest enemies and fires down the one that passes through the most. Extra beams take the next-best lines (at least 24 degrees apart); with only one target they fan around it rather than stacking.
- **Charge-up:** 0.45 s, shown by an aim line that brightens along each beam's path and light gathering at the core, with a new rising "lance charge" sound. It re-aims at release.
- **Firing:** a bolder beam (core as wide as the burn, wider glow), a muzzle flash and a new "lance fire" crack-and-hum sound. Each tick pierces everything in line and shoves it slightly along the beam, so the lance also buys room.
- **Numbers:** 10 damage per 0.1 s tick, 1.2 s beams, 1.8 s cooldown, 620 reach, 28 width. Levels: +40% damage; +30% duration and +20% width; +1 beam on the next line; +1 beam, +30% damage and 40% faster charge.
- **Trade-off:** it charges, fires in bursts and then cools down, so against a single target it stays below a fast weapon (a maxed Lance does less to one target than a maxed Pulse Cannon; a test enforces this).

## 3. Plasma Mines

**Report.** "Very little practical value", especially in large swarms.

### What was wrong (measured)

| Measure | Finding |
| --- | --- |
| Single target | **0** at every level: mines were only dropped where the player stood, so a target that held its ground (a boss) never touched one |
| Full runs, only weapon | 265 damage/s, median survival **3:03**, reached the boss **0%** of the time |
| Visibility | Mines were drawn on the floor layer, under the enemies: invisible exactly when they were working |

Other causes: a 44-unit trigger on a 98-unit blast made them slow to go off, and a player who did not constantly kite through their own minefield got little from them.

### Changes (`src/game/weapons/plasma_mines.gd`, `data/weapons.json`)

- **Placement:** each mine is lobbed into the path of the nearest enemy within 300 units (60% of the way, at most 170), or dropped at your feet if nothing is close. Chasers run straight into them; a boss gets them landed at it.
- **Responsive:** trigger radius 70 (was 44), arming 0.25 s (was 0.4), blast 115 (was 98), 44 damage (was 34), a mine every 1.2 s (was 1.5), up to 10 at once (was 8).
- **Visible:** armed mines are drawn above the swarm, blinking, with a soft glow on the floor showing roughly where they will trigger.
- **Levels:** +40% damage; +33% rate and +4 mines; +35% blast radius **and the blasts chill (slow) enemies**; cluster blasts.
- No new camera shake: mine blasts go through the same explosion path, which never shakes on its own (see the screen-shake rules).

## 4. Weapon audit

### Bench (`godot --headless --path . -- --weapon-bench`)

Each weapon alone, no passives, 20 s per scenario, averaged over three seeds, enemies at Sector 8 health. Damage per second that actually came off enemies (overkill excluded):

| Weapon | Single target L1 / L3 / L5 | Swarm, player still | Swarm chasing a moving player |
| --- | --- | --- | --- |
| Pulse Cannon | 24 / 68 / 158 | 23 / 108 / 225 | 24 / 119 / 267 |
| Scatter Shot | 18 / 31 / 58 | 28 / 54 / 179 | 30 / 59 / 188 |
| Orbit Blades | 0 / 0 / 0 | 698 / 1057 / 1127 | 349 / 533 / 725 |
| Cryo Nova | 0 / 9 / 12 | 425 / 768 / 944 | 218 / 374 / 479 |
| Arc Caster | 13 / 19 / 25 | 34 / 63 / 217 | 44 / 81 / 244 |
| Seeker Missiles | 13 / 34 / 101 | 384 / 640 / 1080 | 113 / 367 / 796 |
| **Plasma Mines, before** | 0 / 0 / 0 | 570 / 880 / 1257 | 363 / 522 / 963 |
| **Plasma Mines, after** | 37 / 67 / 100 | 729 / 1048 / 1275 | 550 / 825 / 1107 |
| Combat Drone | 25 / 72 / 147 | 25 / 64 / 242 | 25 / 68 / 258 |
| **Prism Lance, before** | 29 / 59 / 10 | 272 / 515 / 1024 | 189 / 279 / 747 |
| **Prism Lance, after** | 37 / 63 / 83 | 325 / 496 / 1158 | 554 / 746 / 1158 |
| Singularity | 25 / 32 / 53 | 1011 / 1037 / 1298 | 532 / 652 / 976 |

### Full runs (`--weapons=8 --sector=2 --meta=0.15`)

Eight runs per weapon where it is the only weapon the run can have; the bot plays (skill 0.7), passives and augments as usual.

| Weapon | Damage/s | Kills | Survived (median) | Reached boss |
| --- | --- | --- | --- | --- |
| Pulse Cannon | 310 | 1993 | 5:11 | 50% |
| Scatter Shot | 131 | 1748 | 4:30 | 37% |
| Orbit Blades | 57 | 1390 | 5:30 | 75% |
| Cryo Nova | 125 | 1590 | 5:30 | 50% |
| Arc Caster | 203 | 1855 | 4:20 | 37% |
| Seeker Missiles | 383 | 2695 | 5:30 | 75% |
| **Plasma Mines** | 265 -> **564** | 1167 -> 2768 | 3:03 -> **5:30** | 0% -> **75%** |
| Combat Drone | 308 | 2493 | 5:30 | 75% |
| **Prism Lance** | 74 -> **208** | 763 -> 1993 | 2:28 -> **4:39** | 12% -> **37%** |
| Singularity | 124 | 1158 | 2:51 | 0% |

Every other row is identical before and after.

Read these as relative, not absolute: a weapon on its own is not how anyone plays, the bot dodges better than a person, and eight runs is a small sample. What they show: both reworked weapons moved from the bottom of the table into the pack, Mines as a crowd/area weapon that also helps against a boss, the Lance as a formation-breaker that is weaker on a single target. Neither tops every column.

**New finding, not changed:** on its own, **Singularity** now survives least (median 2:51, never reached the boss). It is a level-10 unlock meant to sit alongside other weapons, so this may be fine, but it is worth the same look these two got.

## Tests

`tests/test_combat.gd` (15 tests): enemy fire drawn above every other layer with normal blending; sprite size equals hit size and the hit/miss boundary is unchanged; in a fight with 300+ enemies, four maxed weapons and continuous explosions, every shot in the air is drawn on the top layer every frame (over 1,000 shot-frames checked); the Shooter shows its cue before firing; the Lance charges without damaging, aims down a row of six rather than at a nearer lone enemy, pierces all six and misses the one off the line; level-5 beams take three separate lines; every Lance and Mines level raises both single-target and crowd damage; a maxed Lance stays below a maxed Pulse Cannon on one target; mines deploy while moving and wait to arm, are lobbed at a threat, ignore an enemy just outside the trigger radius and go off the moment it steps in, and slow enemies from level 4; all kills and damage are credited to the weapon; Lance and Mines at level 5 among 400 enemies stay fast; Lance aiming costs well under 2 ms; a pre-update save with both weapons unlocked loads, reloads and plays.

Breaking the Lance's aiming back to "nearest enemy only" makes three of these fail.

Full suite: **2,808 checks pass**.

One existing test changed. `test_new_threats_survive_a_real_sector_three_run` asked for more than 40 blast zones in a bot-played Sector 3 run with every weapon available. That number depends on how fast the bot's build kills Mortars and Bombers: the old code's run saw 78; after this work the bot drew Volatile Cores and exploding rounds (same kills, 2,827 vs 2,820) and saw 35. The test is about what Sector 3 throws at the player, so it now uses only the four starter weapons, which this work did not touch: 30 zones on the old code and the new, and it asks for at least 25.

Tools added for this work (`tests/sim_runner.gd`): `--weapon-bench`, `--weapons=N`, and `--campaign=N` (a free player's campaign; built for the Sector 8 difficulty question, which is still open). Combat now also records damage that landed and kills per source (`Combat.dealt_by_source`, `kills_by_source`); the existing totals, results screen and lifetime stats are unchanged.

## Performance

- Enemy shots: one extra sprite per shot on the top layer and two faint trail sprites; at the 260-shot cap that is about 800 instances in two draw calls.
- Prism Lance aiming: 0.62 ms per aim with 410 enemies on the Mac (was 2.4 ms in the first version of this work, before optimisation), twice per firing cycle of about 3.5 s.
- Level-5 Lance plus level-5 Mines among 400 enemies: about 2.1-2.3 ms per simulation step headless on the Mac.

None of this was measured on a phone.

## Not covered - needs a person and an iPhone

- Whether shots now read clearly at phone size, mid-fight, with a thumb on the screen; whether the trail and the muzzle cue help or distract.
- Whether the Lance feels powerful and the charge-up feels good rather than slow; the two new sounds on the phone's speaker.
- Whether mines feel reliable; whether the lobbing reads as intended.
- Frame rate with these changes on a phone, especially mid-range ones.
