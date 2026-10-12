class_name AccountService
extends RefCounted
## Player account level (1..max) and the reward handed out at each level.
## Every level pays Credits, every Nth pays Crystals, and some levels open up
## new weapons or cores in the Arsenal - so no level-up is ever empty.

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
	rewards["unlocks"] = _app.arsenal.names_gated_at_level(reached_level)
	return rewards


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
