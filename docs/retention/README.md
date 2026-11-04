# Retention: Threat levels and Daily and Weekly Challenges

The problem: an engaged player finishes SWARM//SHIFT in one to three weeks (Sector 20 at about 8 hours of play, everything bought at 20-40 hours), and then only Overdrive is left. More levels on the existing upgrades would only stretch the same numbers. This update adds two reasons to come back that change how runs play:

- **Threat levels:** a ten-step ladder of rule changes for each sector.
- **Daily and Weekly Challenges:** a new fixed run every day and every week.

Nothing about ordinary sector play changes for a player who never touches either.

## 1. What was there

Inspected before building:

- **Save.** Version 2. Defaults are deep-merged under every loaded profile, so new sections need no migration step. Two new sections were added this way (`threat`, `challenges`). Both version 1 fixtures load with their campaign intact and no Threat or challenge history, and a test covers it.
- **Sectors.** Mutators in `stages.json` already change runs with rules, not numbers: elite events, packs, firing lines and bombardments, all telegraphed. The Director stacks them. Threat levels are built as more mutators on the same system, plus a few new effect keys.
- **Economy.** `RunLedger.settle` pays every run exactly once, by run id. Threat and challenge rewards are paid there, so they inherit that guarantee.
- **Clock.** `GameClock` is the one source of time for the login calendar and missions, with an offset hook for tests.
- **TestFlight.** `tools/ios_release.sh` and the export preset are untouched. Nothing was built or uploaded.

## 2. Threat levels

For sectors already cleared. Each level adds one rule on top of everything below it.

| Level | Adds | Kind | Opens at |
| --- | --- | --- | --- |
| 1 | **Elite Patrols**: an extra elite with an escort every 50 s | Elites | Sector 4 |
| 2 | **Quick Shots**: enemy shots 20% faster (shorter-lived, so no longer reach) | Projectiles | Sector 6 |
| 3 | **Scarce Repairs**: all healing and regeneration halved | Healing | Sector 8 |
| 4 | **Crossfire**: a firing line of five Shooters every 45 s | Attack pattern | Sector 10 |
| 5 | **Brood Elites**: every elite also spawns Swarmers, whatever its affix | Elites | Sector 12 |
| 6 | **Boss's Wrath** (was Overseer's Wrath): the boss opens with its second-phase attacks and rests 20% less | Boss | Sector 14 |
| 7 | **Hunter Packs**: six Dashers every 40 s | Attack pattern | Sector 16 |
| 8 | **Scatter Fire**: Shooters fire three-shot spreads with gaps; boss volleys carry 30% more shots | Projectiles | Sector 18 |
| 9 | **No Second Chances**: no free or ad revives; healing halved again (a quarter in all) | Healing | Sector 20 |
| 10 | **Final Protocol**: below 20% health the boss enters a fourth phase with every attack; elites 50% tougher | Boss | Sector 20 |

**The ladder.**
- Each sector has its own ladder: Threat N on a sector needs that sector cleared at N - 1.
- A level also has to be open, which happens as the campaign reaches its sector (table above).
- Threat 1 opens with Sector 4 cleared, so it is there long before Sector 20.
- A complete ladder is 200 sector clears.

**Fair by construction.**
- Every modifier reuses set pieces that are already announced and telegraphed.
- Quick Shots shortens a shot's life by the same factor, so a shot reaches no further than before.
- Scatter Fire's spread leaves gaps wider than the player.
- The fastest enemy shot measured at Threat 10 was 300 units a second. A test fails anything faster than 310.
- No level is a flat health, speed or spawn multiplier on the whole field, and a test enforces that.
- **Enemies a Threat set piece brings drop nothing:** no energy, no Credits, no elite cache. Without this, the first simulations showed Threat 1 *raising* Sector 8's clear rate from 40% to 63%, because the patrol elites handed out caches and levels.

**Rewards.**

| | Amount | How often |
| --- | --- | --- |
| Credits and Player XP | +12% Credits and +8% Player XP per level (Threat 10: x2.2 and x1.8) | Every run |
| First clear of a sector at a level | 50 x level x the sector's reward scale in Credits (Sector 6 at Threat 4: 500) | Once per sector and level |
| First clear of a level anywhere | 5 x level Crystals | Once per level: 275 Crystals in all |
| Achievements | Raising the Stakes (Threat 1), Hazard Pay (5), Apex (10), Under Pressure (10 sectors at Threat 3+) | Once |
| Skins | HAZARD (Threat 5), APEX (Threat 10) | Earned, cannot be bought |

**Premium currency cannot be farmed.**
- The only Crystals Threat pays are the ten one-off milestones and four achievements.
- A test clears three full ladders and checks that the total is exactly the 275-Crystal ceiling, with nothing more on replay.
- Threat runs never count as ordinary clears: they do not move the campaign, change best times or pay the first-clear Crystals of a new sector.

**In the lobby.**
- Once Threat opens, the sector card gains a row: `THREAT < n >`.
- Under it: what the selected level adds, the first-clear reward or the bonus percentage, and the best level cleared on that sector.
- Before that, nothing about the lobby changes.
- A Threat run's results say "THREAT n CLEARED", list the Threat bonus as its own Credit line, and the first-clear reward heads the extras card.

## 3. Daily and Weekly Challenges

Unlocked with Sector 3, beside Overdrive, as a third view in the lobby: SECTORS, OVERDRIVE, CHALLENGES. The arrows switch between the Daily and the Weekly. The card shows:
- the sector and the weapons;
- the rules, as tags plus a one-line description;
- the reward, or that it has been collected;
- the best result this period;
- a live countdown to the next one.

| | Daily | Weekly |
| --- | --- | --- |
| Period | 00:00 UTC to 00:00 UTC | Monday 00:00 UTC, for 7 days |
| Sector | 4-12, capped at one above the player's best | 8-14, same cap |
| Weapons | One or two, set by the challenge (any of 11 loadouts) | Two, from the 7 loadouts with a solid main weapon |
| Rules | One | Two, plus Threat 2 |
| Reward for clearing the boss | 400 Credits x sector scale, 5 Crystals | 1,500 Credits x sector scale, 25 Crystals |
| Seed | Fixed for the period | Fixed for the period |

The 10 rules:
- Glass Cannon (Daily only)
- Elite Hunt
- Iron Body
- Fast Forward
- Bullet Storm
- Swarm Season
- The Hunt
- Big Game
- Chain Reaction
- Shell Shock

Permanent research, the core and its awakening still apply. A challenge can hand the player weapons they have not unlocked, which is a way to try them.

**Rewards are limited.**
- Each pays once per period: at most 60 Crystals a week from challenges, and Credits worth a few ordinary runs.
- A run that crosses midnight still pays for the day it started. One from two or more periods ago does not.
- Achievements: Daily Driver (1), Creature of Habit (10), Every Single Day (30), Week One (1), Gauntlet Runner (6).
- Six Weekly clears earn the GAUNTLET skin.
- Challenge runs never count as sector clears.

**Offline and the clock.**
- Everything is computed on the device, so challenges work offline.
- The profile remembers the latest time it has seen. Moving the clock **forward** only brings the next challenge early.
- Moving it **back** more than two hours behind that mark pauses challenges until real time catches up. The card says "CHECK YOUR DEVICE CLOCK" and PLAY is held.
- So winding the clock forward to collect future rewards and then back costs the player every day they skipped.
- Two hours of slack covers daylight saving and small corrections.

**What is not promised.**
- The schedule is a hash of the period number and a salt. The same build offers the same challenge everywhere for a period, but nothing enforces that.
- A player's sector is capped by their own progress, and research still applies.
- So scores from different players are not comparable, and no ranking is presented.
- `LeaderboardService` is the seam for later. Each result is already submitted there with a board id from the data (`swarmshift.daily`, `swarmshift.weekly`), its period id and a score (a clear, then enemies destroyed). Today the backend only keeps the last few locally.
- A real Game Center leaderboard needs two things this build does not have: an authoritative shared schedule, and server-side validation.

## 4. Balancing

All simulations ran one at a time, at low priority. Clear rates come from 30 runs each (roughly +/-17 points), or 12 runs for challenges.

**Threat, after the no-drops change:**

| Stage | Upgrades | Skill | Threat 0 | Higher levels |
| --- | --- | --- | --- | --- |
| Sector 8 | 40% | 0.6 | 40% | T1 27%, T3 37% |
| Sector 16 | 80% | 0.6 | 97% | T4 90%, T7 77% (before the change, which made high tiers harder) |
| Sector 20 | 100% | 0.6 | 67% | T5 50%, T8 37% (before the change), T10 13% |
| Sector 20 | 100% | 0.85 | - | T10 7-27% (two batches) |

- Low levels are a nudge.
- Each level from about 5 up takes a real bite.
- Threat 10 on Sector 20 is a top-end goal that the strongest bot clears around one run in ten. A human who has learned the boss may do better.
- The first batch (before the no-drops change) showed Threat 1 and Threat 5 *easier* than Threat 0, which is what led to the change.

**Challenges:**
- **Dailies**, at 50% of upgrades: 83-100% across six days. They are meant to be a quick, distinctive win.
- **Weeklies**, at 70% of upgrades: 42-100% across five weeks.
- The first Weeklies swung from 0% to 100% depending on the weapons drawn ("Railgun and Lance" is effectively Railgun alone, and "Arc only" struggled). Single weapons and Glass Cannon are now Daily-only, and the Weekly sector range narrowed from 8-16 to 8-14.

**Economy:** Threat pays more per run, but takes more runs to clear. The Credits it adds are mostly first-clear bonuses, finite at about 212,000 across all 200 sector-levels, earned over hundreds of runs. There was no repeatable Credit sink before this, and there still isn't (see limitations).

**Performance:**
- Threat 10 stacked on top of Sectors 11, 14, 17 and 20 (each with its own two mutators): 0.6 ms per step on average, worst under 7 ms, headless on this Mac.
- Set pieces can push the field past the 420 soft cap, to a peak of 508. They never pass the arena's 530 pool, and a test holds that.

## 5. Tests

- **`threat_levels`, new, 13 tests:**
  - the ladder: hidden until Sector 4, one level at a time, levels opening as the campaign advances, the lobby selection always valid;
  - every modifier doing what it says;
  - Threat's enemies dropping nothing;
  - boss phases, including the fourth phase, without touching the boss data;
  - rewards paying once, and the Crystal ceiling;
  - skins and achievements;
  - the heaviest stacks staying fast, with shots dodgeable and the field bounded;
  - both version 1 saves.
- **`challenges`, new, 10 tests:**
  - a stable, varied schedule;
  - a stable hash;
  - UTC periods, including Monday week starts;
  - the sector never outrunning the campaign;
  - the run a challenge sets up, played by the bot with only its weapons;
  - no sector clears from challenges;
  - one reward per period;
  - runs across midnight;
  - the clock check;
  - old saves.
- **`ui`:**
  - the Threat row appears only once Threat opens;
  - the challenges view, including the countdown and the clock message;
  - PLAY stays clear of the bottom bar;
  - ten weeks of Weekly rules never widen the lobby (the first version did, caught in a screenshot).
- **`data`:** validation of every Threat mutator, challenge rule and loadout. A challenge may not start with a weapon that cannot kill (the Prism Lance).
- **`research`:** no two cores share an awakening.

## 6. Also in this change

Striker's awakening briefly gave Phase Shift, which Phantom already has. It now gives **Explosive Rounds**.

## 7. Limitations

- **No human has played any of this.** Every number is the bot's. These need people:
  - whether Threat 1-3 feel different enough;
  - whether Threat 9-10 feel fair;
  - whether the Weekly feels substantial;
  - whether a quarter of the healing feels right.
- **Challenge difficulty depends on the period.** A Weekly that draws a strong pair of weapons and mild rules is easy for an upgraded player.
- **Challenge difficulty depends on progress.** The sector is capped by progress but not scaled to it, so a new player and a veteran face the same Daily at very different difficulty.
- **Not identical across players.** See "What is not promised". Leaderboards need a server first.
- **Brood Elites' Swarmers still drop.** They are few, but they are the one Threat source that still gives energy.
- **Hard caps reached.** At Threat 10 the field can reach the arena's pool, and set pieces then lose a few enemies silently.
- **No repeatable Credit sink yet.** Threat adds Credits for players who have already bought everything, so this gap matters more now.
- **Not checked on a phone.** The new lobby rows and the three new skins have only been seen in 540x1170 renders.
