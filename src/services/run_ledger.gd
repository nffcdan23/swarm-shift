class_name RunLedger
extends RefCounted
## Turns a finished run into persistent progress: Credits, Player XP, Crystals
## for a first clear, lifetime stats, mission progress and sector unlocks. One
## entry point (`settle`) so a run is always paid out in the same order - and,
## because every run carries a `run_id` that is remembered once paid, exactly
## once however many times it is asked.
##
## A run that never reaches `settle` (the app was closed or killed mid-fight)
## is not lost either: `checkpoint` keeps the latest snapshot of the run in the
## profile and `recover_pending` pays it out at the next launch.
##
## `result` is the dictionary produced by Arena.build_result():
##   run_id, mode, tier, core, time, kills, elites, bosses, level, level_ups,
##   damage, credits_picked, credit_gain, cleared, died, abandoned, synergies,
##   revives

## Settled run ids remembered, newest last.
const SETTLED_KEPT := 24


## Preview of what a result is worth. Pure - changes nothing.
##
## Credits = what was picked up in the run + a survival bonus + a clear bonus.
## Player XP = time survived + enemies destroyed + Run Level reached + bosses
## + a sector-clear bonus. Both are returned with their parts so the results
## screen can show where every point came from.
static func compute(app: AppRoot, result: Dictionary) -> Dictionary:
	var rewards := GameData.dict(app.data.game, "rewards")
	var tier := maxi(int(result.get("tier", 1)), 1)
	var scale := app.campaign.scaling(float(result.get("effective_tier", tier)))
	var seconds := float(result.get("time", 0.0))
	var cleared := bool(result.get("cleared", false))
	var fraction := GameData.num(rewards, "abandon_reward_fraction", 1.0) if bool(result.get("abandoned", false)) else 1.0

	var bonus_scale := float(scale.reward) * float(result.get("credit_gain", 1.0)) * fraction
	var collected := maxi(int(round(float(result.get("credits_picked", 0)) * fraction)), 0)
	var survival := maxi(int(round(seconds / 60.0 * GameData.num(rewards, "credits_per_minute", 10.0) * bonus_scale)), 0)
	var clear_bonus := maxi(int(round(GameData.num(rewards, "sector_clear_credits", 120.0) * bonus_scale)), 0) if cleared else 0

	var xp_bonus := app.meta.mod_total("account_xp_pct")
	var xp_scale := float(scale.account_xp) * (1.0 + xp_bonus)
	var xp_parts := {
		"time": int(round(seconds * GameData.num(rewards, "xp_per_second", 0.6) * xp_scale)),
		"kills": int(round(float(result.get("kills", 0)) * GameData.num(rewards, "xp_per_kill", 0.08) * xp_scale)),
		"level": int(round(float(result.get("level", 1)) * GameData.num(rewards, "xp_per_run_level", 4.0) * xp_scale)),
		"bosses": int(round(float(result.get("bosses", 0)) * GameData.num(rewards, "xp_per_boss", 120.0) * xp_scale)),
		"clear": int(round(GameData.num(rewards, "xp_sector_clear", 60.0) * float(tier) * xp_scale)) if cleared else 0,
	}
	var xp := 0
	for part: String in xp_parts:
		xp += int(xp_parts[part])

	var first_clear := cleared and str(result.get("mode", "")) == CampaignService.MODE_SECTOR and tier > app.campaign.highest_cleared()
	return {
		"credits": collected + survival + clear_bonus,
		"credits_collected": collected,
		"credits_survival": survival,
		"credits_clear": clear_bonus,
		"account_xp": xp,
		"xp_parts": xp_parts,
		"xp_bonus_pct": xp_bonus,
		"crystals": GameData.integer(rewards, "first_clear_crystals", 10) if first_clear else 0,
		"first_clear": first_clear,
	}


## True once this run has been paid out.
static func is_settled(app: AppRoot, run_id: String) -> bool:
	if run_id.is_empty():
		return false
	var settled: Dictionary = app.save.section("runs").get("settled", {})
	return settled.has(run_id)


## Applies a result to the profile and returns a summary for the results
## screen. Asking again for the same run returns the same summary, flagged
## `duplicate`, and changes nothing.
static func settle(app: AppRoot, result: Dictionary) -> Dictionary:
	var run_id := str(result.get("run_id", ""))
	var runs := app.save.section("runs")
	if is_settled(app, run_id):
		var settled: Dictionary = runs.get("settled", {})
		var again: Dictionary = (settled[run_id] as Dictionary).duplicate(true)
		again["duplicate"] = true
		return again

	var summary := compute(app, result)
	var seconds := float(result.get("time", 0.0))
	var mode := str(result.get("mode", CampaignService.MODE_SECTOR))
	var tier := maxi(int(result.get("tier", 1)), 1)

	summary["run_id"] = run_id
	summary["duplicate"] = false
	summary["level_before"] = app.account.level()
	summary["xp_before"] = app.account.xp()
	summary["credits_before"] = app.economy.balance(Economy.CREDITS)

	# Lifetime stats first, so achievements and missions see the new totals.
	app.stats.add("runs", 1.0)
	app.stats.add("kills", float(result.get("kills", 0)))
	app.stats.add("elites_killed", float(result.get("elites", 0)))
	app.stats.add("bosses_defeated", float(result.get("bosses", 0)))
	app.stats.add("total_damage", float(result.get("damage", 0.0)))
	app.stats.add("level_ups", float(result.get("level_ups", 0)))
	app.stats.add("time_played", seconds)
	app.stats.add("revives_used", float(result.get("revives", 0)))
	if bool(result.get("died", false)):
		app.stats.add("deaths", 1.0)
	app.stats.set_max("highest_run_level", float(result.get("level", 1)))
	app.stats.set_max("longest_survival", seconds)

	var found: Array = app.save.state.get("synergies", [])
	var new_synergies: Array = []
	for id: String in result.get("synergies", []):
		if not found.has(id):
			found.append(id)
			new_synergies.append(id)
	app.save.state["synergies"] = found
	summary["new_synergies"] = new_synergies

	var record := app.campaign.record_run(mode, tier, bool(result.get("cleared", false)), seconds)
	summary["new_best"] = bool(record.new_best)

	app.economy.grant(Economy.CREDITS, int(summary.credits), "run")
	app.economy.grant(Economy.CRYSTALS, int(summary.crystals), "first_clear")

	var mission_input := {
		"kills": result.get("kills", 0), "time": seconds, "bosses": result.get("bosses", 0),
		"level_ups": result.get("level_ups", 0), "level": result.get("level", 1),
		"damage": result.get("damage", 0.0), "credits": summary.credits,
		"elites": result.get("elites", 0), "runs": 1,
	}
	app.missions.refresh()
	summary["missions_completed"] = app.missions.apply_run(mission_input)

	summary["level_ups"] = app.account.add_xp(int(summary.account_xp), "run")
	summary["level_after"] = app.account.level()
	summary["xp_after"] = app.account.xp()
	summary["credits_after"] = app.economy.balance(Economy.CREDITS)

	app.analytics.track(Analytics.GAME_ENDED, {
		"mode": mode, "tier": tier, "core": result.get("core", ""),
		"run_duration": seconds, "kills": result.get("kills", 0), "level": result.get("level", 1),
		"cleared": result.get("cleared", false), "died": result.get("died", false),
		"abandoned": result.get("abandoned", false), "interrupted": result.get("interrupted", false),
		"credits": summary.credits, "account_xp": summary.account_xp, "weapons": result.get("weapons", {}),
	})
	app.ads.note_run_finished()
	_remember(runs, run_id, summary)
	runs["pending"] = {}
	app.save.flush()
	return summary


static func _remember(runs: Dictionary, run_id: String, summary: Dictionary) -> void:
	if run_id.is_empty():
		return
	var settled: Dictionary = runs.get("settled", {})
	var order: Array = runs.get("order", [])
	settled[run_id] = summary.duplicate(true)
	order.append(run_id)
	while order.size() > SETTLED_KEPT:
		settled.erase(str(order.pop_front()))
	runs["settled"] = settled
	runs["order"] = order


## Second payout of the run's Credits after a completed rewarded ad. Once per run.
static func double_credits(app: AppRoot, summary: Dictionary) -> int:
	var run_id := str(summary.get("run_id", ""))
	var settled: Dictionary = app.save.section("runs").get("settled", {})
	var stored: Dictionary = settled.get(run_id, {}) if not run_id.is_empty() else {}
	if bool(summary.get("doubled", false)) or bool(stored.get("doubled", false)):
		return 0
	summary["doubled"] = true
	if not stored.is_empty():
		stored["doubled"] = true
	var amount := int(summary.get("credits", 0))
	app.economy.grant(Economy.CREDITS, amount, "run_doubled")
	app.save.flush()
	return amount


# ------------------------------------------------------------- interruption

## Stores the run so far, so that it can still be paid out if the app never
## gets to finish it. Overwrites the previous snapshot. Cheap enough to call
## every few seconds; pass `flush` when the app is about to lose focus.
static func checkpoint(app: AppRoot, result: Dictionary, flush: bool = false) -> void:
	var run_id := str(result.get("run_id", ""))
	if run_id.is_empty() or is_settled(app, run_id):
		return
	var snapshot := result.duplicate(true)
	snapshot["abandoned"] = true
	snapshot["died"] = false
	snapshot["cleared"] = false
	snapshot["interrupted"] = true
	app.save.section("runs")["pending"] = {"result": snapshot, "saved_at": app.clock.now()}
	app.save.mark_dirty()
	if flush:
		app.save.flush()


## The snapshot waiting to be recovered, or an empty dictionary.
static func pending(app: AppRoot) -> Dictionary:
	var entry: Variant = app.save.section("runs").get("pending", {})
	if entry is Dictionary and (entry as Dictionary).get("result") is Dictionary:
		return (entry as Dictionary).result
	return {}


## Pays out a run that was cut short last session. Returns its summary (with
## `recovered` set) or an empty dictionary when there was nothing to recover.
static func recover_pending(app: AppRoot) -> Dictionary:
	var result := pending(app)
	if result.is_empty():
		return {}
	var runs := app.save.section("runs")
	if is_settled(app, str(result.get("run_id", ""))):
		runs["pending"] = {}
		app.save.mark_dirty()
		return {}
	var summary := settle(app, result)
	summary["recovered"] = true
	summary["time"] = float(result.get("time", 0.0))
	summary["kills"] = int(result.get("kills", 0))
	summary["run_level"] = int(result.get("level", 1))
	return summary
