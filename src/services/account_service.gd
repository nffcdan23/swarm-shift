class_name AccountService
extends RefCounted
## The permanent PLAYER LEVEL (1..max) and the reward handed out at each level.
## Every level pays Credits, every Nth pays Crystals, and some levels open up
## new weapons, cores or permanent upgrades - so no level-up is ever empty.
##
## Not to be confused with the Run Level, which lives in the Arena, is fed by
## the green energy crystals and resets at the start of every run. Player XP
## comes from finished runs (time survived, enemies destroyed, Run Level
## reached, bosses, sectors cleared - see RunLedger), from daily missions and
## from achievements, and is never lost.

signal xp_changed(level: int, xp: int, needed: int)
signal leveled_up(level: int, rewards: Dictionary)

var _app: AppRoot
var _cfg: Dictionary


func _init(app: AppRoot) -> void:
	_app = app
	_cfg = GameData.dict(app.data.meta, "account")


func level() -> int:
	return int(_app.save.section("account").get("level", 1))


func xp() -> int:
	return int(_app.save.section("account").get("xp", 0))


func max_level() -> int:
	return GameData.integer(_cfg, "max_level", 100)


func is_max() -> bool:
	return level() >= max_level()


## XP required to go from `for_level` to the next one.
func xp_needed(for_level: int) -> int:
	var l := float(for_level)
	return int(GameData.num(_cfg, "xp_base", 80.0) + GameData.num(_cfg, "xp_linear", 40.0) * l + GameData.num(_cfg, "xp_quad", 6.0) * l * l)


func progress() -> float:
	if is_max():
		return 1.0
	return clampf(float(xp()) / float(xp_needed(level())), 0.0, 1.0)


## What reaching `reached_level` pays out.
func level_rewards(reached_level: int) -> Dictionary:
	var credits := mini(
		GameData.integer(_cfg, "credits_base", 100) + GameData.integer(_cfg, "credits_per_level", 40) * reached_level,
		GameData.integer(_cfg, "credits_cap", 3000))
	var rewards := {"credits": credits, "crystals": 0, "unlocks": []}
	var interval := GameData.integer(_cfg, "crystal_interval", 5)
	if interval > 0 and reached_level % interval == 0:
		rewards["crystals"] = GameData.integer(_cfg, "crystal_amount", 25)
	rewards["unlocks"] = unlocks_at(reached_level)
	return rewards


## Display names of everything whose gate is exactly `at_level`: weapons and
## cores (which then cost Credits in the Arsenal) and permanent upgrades.
func unlocks_at(at_level: int) -> Array:
	var names: Array = _app.arsenal.names_gated_at_level(at_level)
	names.append_array(_app.meta.names_gated_at_level(at_level))
	return names


## The next level above the current one that opens something new:
## {"level": int, "names": Array}. Level 0 when nothing is left to unlock.
func next_unlock() -> Dictionary:
	for candidate in range(level() + 1, max_level() + 1):
		var names := unlocks_at(candidate)
		if not names.is_empty():
			return {"level": candidate, "names": names}
	return {"level": 0, "names": []}


## Upcoming unlocks, nearest first: [{"level", "names", "reached"}].
func roadmap(limit: int = 6) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var current := level()
	for candidate in range(2, max_level() + 1):
		var names := unlocks_at(candidate)
		if names.is_empty():
			continue
		out.append({"level": candidate, "names": names, "reached": candidate <= current})
	# Keep the last thing already earned for context, then what is ahead.
	var first_ahead := 0
	while first_ahead < out.size() and bool(out[first_ahead].reached):
		first_ahead += 1
	var start := maxi(first_ahead - 1, 0)
	return out.slice(start, start + limit)


## XP still needed to reach the next level (0 at the cap).
func xp_to_next() -> int:
	if is_max():
		return 0
	return maxi(xp_needed(level()) - xp(), 0)


## Adds account XP and returns one entry per level gained (may be empty).
func add_xp(amount: int, source: String) -> Array[Dictionary]:
	var gained: Array[Dictionary] = []
	if amount <= 0 or is_max():
		return gained
	var account := _app.save.section("account")
	var current_level := level()
	var current_xp := xp() + amount
	while current_level < max_level() and current_xp >= xp_needed(current_level):
		current_xp -= xp_needed(current_level)
		current_level += 1
		var rewards := level_rewards(current_level)
		gained.append({"level": current_level, "rewards": rewards})
	if current_level >= max_level():
		current_xp = 0
	account["level"] = current_level
	account["xp"] = current_xp
	_app.save.mark_dirty()
	for entry in gained:
		var rewards: Dictionary = entry.rewards
		_app.economy.grant(Economy.CREDITS, int(rewards.credits), "account_level")
		_app.economy.grant(Economy.CRYSTALS, int(rewards.crystals), "account_level")
		_app.analytics.track(Analytics.ACCOUNT_LEVEL_UP, {"level": entry.level, "source": source})
		leveled_up.emit(int(entry.level), rewards)
	xp_changed.emit(current_level, current_xp, xp_needed(current_level))
	return gained
