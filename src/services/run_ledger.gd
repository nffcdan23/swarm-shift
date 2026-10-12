class_name RunLedger
extends RefCounted
## Turns a finished run into persistent progress: Credits, account XP,
## Crystals for a first clear, lifetime stats, mission progress and sector
## unlocks. One entry point (`settle`) so a run is always paid out exactly once
## and in the same order.
##
## `result` is the dictionary produced by Arena.build_result():
##   mode, tier, core, time, kills, elites, bosses, level, level_ups, damage,
##   credits_picked, credit_gain, cleared, died, abandoned, synergies, revives


## Preview of what a result is worth. Pure - changes nothing.
static func compute(app: AppRoot, result: Dictionary) -> Dictionary:
	var rewards := GameData.dict(app.data.game, "rewards")
	var tier := maxi(int(result.get("tier", 1)), 1)
	var scale := app.campaign.scaling(float(result.get("effective_tier", tier)))
	var seconds := float(result.get("time", 0.0))
	var cleared := bool(result.get("cleared", false))
	var fraction := GameData.num(rewards, "abandon_reward_fraction", 1.0) if bool(result.get("abandoned", false)) else 1.0

	var time_bonus := seconds / 60.0 * GameData.num(rewards, "credits_per_minute", 10.0)
	var clear_bonus := GameData.num(rewards, "sector_clear_credits", 120.0) if cleared else 0.0
	var bonus := (time_bonus + clear_bonus) * float(scale.reward) * float(result.get("credit_gain", 1.0))
	var credits := int(round((float(result.get("credits_picked", 0)) + bonus) * fraction))

	var xp := seconds * GameData.num(rewards, "xp_per_second", 0.6)
	xp += float(result.get("kills", 0)) * GameData.num(rewards, "xp_per_kill", 0.08)
	xp += float(result.get("level", 1)) * GameData.num(rewards, "xp_per_run_level", 4.0)
	xp += float(result.get("bosses", 0)) * GameData.num(rewards, "xp_per_boss", 120.0)
	if cleared:
		xp += GameData.num(rewards, "xp_sector_clear", 60.0) * float(tier)
	xp *= float(scale.account_xp)

	var first_clear := cleared and str(result.get("mode", "")) == CampaignService.MODE_SECTOR and tier > app.campaign.highest_cleared()
	return {
		"credits": maxi(credits, 0),
		"account_xp": int(round(xp)),
		"crystals": GameData.integer(rewards, "first_clear_crystals", 10) if first_clear else 0,
		"first_clear": first_clear,
	}


## Applies a result to the profile and returns a summary for the results screen.
static func settle(app: AppRoot, result: Dictionary) -> Dictionary:
	var summary := compute(app, result)
	var seconds := float(result.get("time", 0.0))
	var mode := str(result.get("mode", CampaignService.MODE_SECTOR))
	var tier := maxi(int(result.get("tier", 1)), 1)

	summary["level_before"] = app.account.level()
	summary["xp_before"] = app.account.xp()

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

	app.analytics.track(Analytics.GAME_ENDED, {
		"mode": mode, "tier": tier, "core": result.get("core", ""),
		"run_duration": seconds, "kills": result.get("kills", 0), "level": result.get("level", 1),
		"cleared": result.get("cleared", false), "died": result.get("died", false),
		"abandoned": result.get("abandoned", false), "credits": summary.credits,
		"account_xp": summary.account_xp, "weapons": result.get("weapons", {}),
	})
	app.ads.note_run_finished()
	app.save.flush()
	return summary


## Second payout of the run's Credits after a completed rewarded ad.
static func double_credits(app: AppRoot, summary: Dictionary) -> int:
	if bool(summary.get("doubled", false)):
		return 0
	summary["doubled"] = true
	var amount := int(summary.get("credits", 0))
	app.economy.grant(Economy.CREDITS, amount, "run_doubled")
	app.save.flush()
	return amount
