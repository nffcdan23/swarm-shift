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
