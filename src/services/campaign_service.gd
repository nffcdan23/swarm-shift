class_name CampaignService
extends RefCounted
## Sector progression. Every sector reuses the same timeline, scaled by tier,
## so new "content" is a number until bespoke timelines are worth authoring.
## Clearing sector N unlocks N+1; clearing the configured sector opens Endless.

signal changed

const MODE_SECTOR := "sector"
const MODE_ENDLESS := "endless"

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func sector_count() -> int:
	return GameData.integer(_app.data.stages, "sector_count", 20)


func highest_cleared() -> int:
	return int(_app.save.section("sectors").get("highest_cleared", 0))


func max_selectable() -> int:
	return mini(highest_cleared() + 1, sector_count())


func selected() -> int:
	return clampi(int(_app.save.section("sectors").get("selected", 1)), 1, max_selectable())


func select(tier: int) -> void:
	_app.save.section("sectors")["selected"] = clampi(tier, 1, max_selectable())
	_app.save.mark_dirty()
	changed.emit()


func endless_unlocked() -> bool:
	return highest_cleared() >= GameData.integer(_app.data.stages, "endless_unlock_sector", 3)


func best_time(tier: int) -> float:
	var times: Dictionary = _app.save.section("sectors").get("best_times", {})
	return float(times.get(str(tier), 0.0))


func endless_best() -> float:
	return float(_app.save.section("sectors").get("endless_best", 0.0))


func theme(tier: int) -> Dictionary:
	var themes := GameData.list(_app.data.stages, "themes")
	if themes.is_empty():
		return {}
	return themes[posmod(tier - 1, themes.size())]


## Multipliers applied to a run at the given (possibly fractional) tier.
func scaling(tier: float) -> Dictionary:
	var s := GameData.dict(_app.data.stages, "scaling")
	var steps := maxf(tier - 1.0, 0.0)
	var squared := steps * steps
	return {
		"hp": 1.0 + GameData.num(s, "hp_per_tier") * steps + GameData.num(s, "hp_per_tier_sq") * squared,
		"damage": 1.0 + GameData.num(s, "damage_per_tier") * steps + GameData.num(s, "damage_per_tier_sq") * squared,
		"speed": minf(1.0 + GameData.num(s, "speed_per_tier") * steps, GameData.num(s, "speed_cap", 1.3)),
		"spawn": minf(1.0 + GameData.num(s, "spawn_per_tier") * steps, GameData.num(s, "spawn_cap", 1.6)),
		"boss_hp": 1.0 + GameData.num(s, "boss_hp_per_tier") * steps + GameData.num(s, "boss_hp_per_tier_sq") * squared,
		"reward": 1.0 + GameData.num(s, "reward_per_tier") * steps,
		"account_xp": 1.0 + GameData.num(s, "account_xp_per_tier") * steps,
	}


## Records a finished run. Returns {"first_clear": bool, "new_best": bool}.
func record_run(mode: String, tier: int, cleared: bool, seconds: float) -> Dictionary:
	var sectors := _app.save.section("sectors")
	var out := {"first_clear": false, "new_best": false}
	if mode == MODE_ENDLESS:
		if seconds > endless_best():
			sectors["endless_best"] = seconds
			out.new_best = true
	elif cleared:
		var times: Dictionary = sectors.get("best_times", {})
		var key := str(tier)
		if not times.has(key) or seconds < float(times[key]):
			times[key] = seconds
			sectors["best_times"] = times
			out.new_best = true
		if tier > highest_cleared():
			sectors["highest_cleared"] = tier
			out.first_clear = true
			# Move the selector forward so the next press of PLAY is fresh content.
			sectors["selected"] = mini(tier + 1, sector_count())
	_app.save.mark_dirty()
	changed.emit()
	return out
