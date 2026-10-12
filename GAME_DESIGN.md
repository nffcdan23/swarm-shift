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
- **Timeline.** One timeline per run (`stages.json`): swarmer rate climbs from 1.7 to 13 per second over five minutes; Brutes join at 0:45, Dashers at 1:20, Splitters at 2:05, Shooters at 2:35, Tanks at 3:25. Enemy health rises to 6.5x over the same period.
- **Events.** Swarm surges (a closing ring) at 1:00, 2:00, 3:00, 4:00 and 4:36; an elite with an escort at 1:30, 2:45, 3:45 and 4:30.
- **Boss at 5:00.** A shockwave clears the field, everything it drops is pulled to the player, and an energy wall closes the arena.
- **Ending.** Sector mode ends in victory when the boss dies. Endless ("Overdrive", unlocked by clearing Sector 3) starts a harder cycle instead and runs until death.

### Levelling

Energy needed for the next level: `1 + 4L + 0.42L^2`. With the bot at the controls the first level-up arrives 4-8 seconds in and the second by about 15; runs that reach the boss are typically level 25-29.

On level-up the game pauses and offers three cards. Rules: nothing maxed or slotless is offered; the first picks guarantee a new weapon so builds diversify early; owned items are weighted up so builds come together; luck raises the odds of rarer cards. One free reroll per run (more from permanent upgrades), then up to two by rewarded ad. Resuming clears a little space around the player and grants a moment of invulnerability.

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
| Plasma Mines | Dropped behind you; rewards kiting | Level 4 |
| Combat Drone | A wingman that picks its own targets | Level 5 |
| Prism Lance | Sustained piercing beam | Level 7 |
| Singularity | Drags the swarm into a ball, then implodes | Level 10 |

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
| Shooter | Holds range, strafes, fires slow dodgeable shots |
| Splitter | Bursts into three fast Splitlings |
| Tank | Enormous health; cannot be pushed, pushes you |
| Elite | Any type, larger and tougher, with one affix: Swift, Armored, Volatile (a telegraphed death blast) or Broodmother (spawns swarmers). Drops a cache: a bonus pick with boosted rarity |

Occasional drops: a repair cell, a magnet that pulls in every gem, a bomb.

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

- **Account level 1-100.** Every level pays Credits; every fifth pays Crystals; several unlock weapons or cores.
- **Permanent upgrades.** Thirteen tracks bought with Credits: damage, health, speed, crit, energy gain, credit gain, pickup radius, regeneration, luck, armour, extra rerolls, a pre-levelled starting weapon, and a once-per-run revive. Costs rise geometrically.
- **Cores.** Six playable cores, each with its own starting weapon and stat trade-offs (for example Bastion: +40% health, +2 armour, -8% speed, starts with Orbit Blades).
- **Sectors 1-20.** The same timeline, scaled. Clearing one unlocks the next and pays a one-time Crystal bonus. Rewards grow 30% per sector.

## Economy

| Currency | Earned from | Spent on |
| --- | --- | --- |
| **Credits** (soft) | Pickups, time survived, clearing a sector, account levels, missions, login calendar, optional ads | Permanent upgrades, weapon and core unlocks |
| **Crystals** (premium) | Achievements, first clears, every fifth account level, the daily mission bonus, day 3/6/7 of the login calendar, purchase | Core skins, one core, exchange for Credits |

Nothing in the game requires Crystals to progress.

## Retention

- **Daily missions.** Three per day from a pool of twelve, with a bonus for claiming all three.
- **Login calendar.** Seven days, looping. Missing a day never resets it.
- **Achievements.** Thirty, paying Crystals.
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

All numbers are in `data/*.json`. Difficulty per sector is `1 + a*n + b*n^2` on enemy health and damage (n = sector - 1); the squared term is what keeps late sectors ahead of a fully upgraded player.

Current results from the balance simulator (24 bot runs each; "upgrades" is the share of every permanent track bought):

| Sector | Upgrades | Bot skill | Reached boss | Cleared |
| --- | --- | --- | --- | --- |
| 1 | 0% | 0.4 | 75% | 50% |
| 1 | 0% | 0.7 | 75% | 38% |
| 1 | 30% | 0.6 | 96% | 92% |
| 2 | 10% | 0.6 | 92% | 46% |
| 4 | 30% | 0.6 | 92% | 79% |
| 7 | 60% | 0.6 | 96% | 83% |
| 10 | 90% | 0.6 | 92% | 71% |
| 14 | 100% | 0.6 | 75% | 21% |
| 20 | 100% | 0.8 | 33% | 0% |

Read these as a shape, not a prediction: a hard-ish first sector, a comfortable middle once upgrades arrive, and a steep endgame. Twenty-four runs is a small sample (roughly +/-10 points), the bot's skill setting barely moves the result - which upgrades it happens to draw matters far more than how well it dodges - and it never plans a build. **No human has played this build.** The questions that most need a real playtest:

- Is Sector 1 winnable within a new player's first three to five runs?
- Does the first minute feel busy enough?
- Are the weaker-looking weapons (Orbit Blades, Combat Drone, Cryo Nova) weak in human hands, or only in the bot's, which always kites?
- Is five minutes the right length?

## Open questions for the business

- Final name, bundle identifier and Apple Team ID.
- A licensed display typeface (the engine default is used throughout; the swap is one line in `ui_theme.gd`).
- Whether the generated art and audio are the launch look or placeholders for commissioned assets.
- Real price points per region.
