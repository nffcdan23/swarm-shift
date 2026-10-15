class_name RunDiagnostics
extends RefCounted
## Cheap counters describing how hard a run has been pushed and whether any of
## its safety valves opened. Nothing reads these to make gameplay decisions:
## they exist for the stress tests, the balance simulator (`--sim`) and the
## on-screen `--perf` read-out, so a bad run can be explained afterwards.

## Upgrade screens that open this soon after the previous one closed arrive
## while the HUD is still fading the old one out (see docs/playtest-1).
const QUICK_WINDOW := 0.14

## Upgrade screens opened (level-ups and elite caches; rerolls not counted).
var choices := 0
## ...of which opened within QUICK_WINDOW seconds of the previous one closing.
var quick_choices := 0
var shortest_choice_gap := INF
## Most level-ups banked by a single simulation step.
var levels_in_one_step := 0
## Longest the queue of pending explosions has been.
var blast_queue_peak := 0
## Explosions discarded because the queue was full.
var blasts_dropped := 0
## Energy grants refused for not being a finite, positive number.
var xp_rejected := 0
## Times the HUD found itself out of step with the run and repaired it.
var hud_recoveries := 0
## Drops that had to be merged or banked because the field was full.
var pickups_merged := 0


func summary() -> String:
	return "choices %d (quick %d, shortest gap %s)  levels/step %d  blast queue peak %d (dropped %d)  merged drops %d  hud recoveries %d" % [
		choices, quick_choices, ("%.3fs" % shortest_choice_gap) if shortest_choice_gap < INF else "-",
		levels_in_one_step, blast_queue_peak, blasts_dropped, pickups_merged, hud_recoveries]
