# Playtest 1 - the freeze at 2:58

First real playtest on an iPhone 16 Pro Max (build 0.1.0). The player survived
about 2:58, reached Run Level 16, and reported that the game froze just as an
upgrade screen appeared during a burst of explosions. The app had to be killed,
and the run's rewards were lost with it.

## Root cause

**Established.** The upgrade overlay was hidden by its own fade-out while the
run was waiting for a choice on it.

`LevelUpOverlay.dismiss()` faded the overlay for 0.14 s and then set it
invisible. Nothing cancelled that fade. If a *new* choice began inside those
0.14 s, `present()` showed the new cards and, a few frames later, the old
fade's callback hid them. The run was now in state `CHOOSING` - simulation
stopped, music muffled, joystick disabled - with no cards on screen, and the
pause button only works in state `PLAYING`. Nothing the player could touch led
anywhere. From the outside that is a frozen game with an explosion hanging in
mid-air.

A new choice arriving that quickly is not rare. An elite drops a cache and a
large energy gem on the same spot; both are vacuumed in together and usually
land one simulation step apart. The first opens a choice. The player picks.
One step after play resumes, the second lands and opens another.

## Evidence

1. **The device's own log.** The game keeps a local event log and flushes it
   when the app loses focus. Pulled from the phone, the frozen session
   (`frozen_session_events.jsonl`, 36 events) ends:

   ```
   upgrade_selected  {cache: true, run_level: 15, time: 178.154}
   player_level_up   {level: 16,               time: 178.188}
   ```

   A cache reward picked at 2:58.15; a level-up one step (1/30 s) later; then
   nothing - no pick for level 16, no death, no end of run. The second elite
   of the timeline spawns at 2:45, which is where that cache came from. Time
   and level match the report exactly.

2. **Reproduction on the unfixed build** (`reproduction_before_fix.txt`).
   Replaying that sequence through the real HUD left the run in `CHOOSING`
   with the overlay invisible, pause unavailable and no card tappable. Without
   scripting the order - an elite killed next to a player whose energy bar is
   nearly full - 4 of 6 seeds deadlocked the same way.

3. **Frequency.** Instrumented bot runs of Sector 1 (40 runs, no upgrades):
   10.1% of all upgrade screens opened within 0.14 s of the previous one
   closing, in 28 of the 40 runs. The same run in the log had three earlier
   near-misses, at 0.33 s, 0.82 s and 1.05 s.

4. **It happened again.** The old build stayed on the phone for another day.
   Its log, read before that build was removed on 13 October, holds a second
   run with the same ending: a pick at 301.57 s, a level-up 0.10 s later, then
   nothing - Run Level 19, two seconds after the boss arrived and pulled every
   crystal on the field to the player. Two other runs in that log stop at an
   upgrade screen with no pick, 11 and 16 seconds after the previous one; the
   log cannot say whether those were the unresponsive-card problem below or
   the app simply being closed.

What the log cannot show is the screen itself, and the screenshot mentioned in
the report did not arrive. The conclusion rests on the log proving the
precondition and the code making the outcome deterministic once it holds.

Why it was not caught before: the bot answers choices without the overlay, the
existing UI test covered a single level-up, and earlier human sessions were
short.

## Also found while looking

| Problem | Effect |
| --- | --- |
| Only the first finger on the glass can press a button (the engine turns one touch into the mouse) | With the steering thumb down, taps from the other hand on a card or on PAUSE did nothing. Reads as a freeze; goes away when the thumb lifts |
| Upgrade cards waited for *all* fingers to lift before accepting taps | Same symptom from a second cause |
| A reroll tapped in the 0.3 s after choosing a card dealt a new hand, and the old choice was then applied to it | The player received a card they had not picked, and lost a reroll |
| The joystick dropped the thumb whenever an overlay opened | After every level-up the player stood still until they lifted and re-pressed |
| Rewards existed only in memory until the results screen | Any kill or crash mid-run lost the whole run |
| Credit, cache and helper drops were discarded when the pickup field was full | Silent loss of rewards in long, crowded fights |
| The boss banner and synergy banner had the same untracked-fade pattern | Could hide a banner that had just been shown |
| Unbounded loops reachable from data: energy grants, spawn accumulators, the explosion queue | No hang found in practice, but nothing prevented one |

None of the simulation code could be made to hang, corrupt its arrays or run
away, including at 1,000 enemies (2.4x the shipped cap) with every chain
effect enabled.

## Fixes

**The cause.** `present()` cancels any fade in progress and restores full
opacity. Every delayed step in the overlay (the fade, the 0.3 s pick
confirmation) carries a generation number and does nothing if the overlay has
moved on. Once a card is tapped the reroll buttons are locked.

**The class of bug.** The run and the HUD are two state machines joined by
signals. `Hud._reconcile()` now checks every frame that they agree - an
upgrade screen showing the current hand whenever the run is choosing, a pause
menu whenever it is paused, a revive prompt whenever the player is down - and
repairs any mismatch, logging a `hud_recovered` analytics event. A hand whose
pick never reached the run is dealt again, and after three failed repairs of
the same hand it picks a card, so a run can never wait forever. With the cause
fixed it has nothing to do; the tests assert that.

**Input.** `TouchTaps` turns a quick tap by any finger other than the first
into a click, so buttons work while a thumb steers. Cards arm on time alone.
The joystick keeps tracking the steering thumb through overlays, so movement
resumes without re-touching.

**Rewards.** Each run has an id and is settled exactly once. The run in
progress is checkpointed into the profile every 8 s and whenever the app loses
focus; if it never reaches the results screen it is paid out at next launch.

**Bounds.** Energy grants are validated and capped per grant. The explosion
queue has a cap scaled to the field (it was already limited to 16 per step).
Spawn tracks and scripted events have per-step budgets. Hazard zones refuse a
warning shorter than 0.45 s. A full pickup field merges or relocates drops
instead of discarding them.

## Tests

`tests/test_stability.gd` (20 tests). `godot --headless --path . -- --test=stability`

- the logged sequence, and unscripted elite drops over six seeds;
- sabotage: hide the overlay, lose a pick, or pause with no menu, and the HUD recovers;
- a second finger picks a card and presses PAUSE while a thumb steers;
- a 300-gem vacuum (about 40 levels) deals one hand per level, in order;
- 500 and 1,000 enemies; 300 simultaneous explosions with chain kills; a
  minute of every weapon and augment at once; a full field at boss arrival;
- 60 pause/resume cycles during heavy real-time combat;
- an Overdrive soak (`--soak=<minutes>`, default 10) checking that memory,
  object count and step cost stay flat.

The full output of the final run is in `tests_after_fix.txt`.

Not covered by any of this: a render hang, a thermal throttle, or iOS stopping
the view after an audio interruption that never reports its end. Those need
the device.
