class_name StatsService
extends RefCounted
## Lifetime player statistics. Achievements read from here, the profile screen
## displays it, and it is the natural payload for future leaderboards.

signal changed(key: String, value: float)

## Shown on the profile screen, in this order.
const DISPLAY: Array[Dictionary] = [
	{"key": "runs", "label": "Runs played"},
	{"key": "kills", "label": "Enemies destroyed"},
	{"key": "bosses_defeated", "label": "Bosses defeated"},
	{"key": "elites_killed", "label": "Elites destroyed"},
	{"key": "highest_sector_cleared", "label": "Highest sector cleared"},
	{"key": "highest_run_level", "label": "Highest run level"},
	{"key": "longest_survival", "label": "Longest survival", "format": "time"},
	{"key": "total_damage", "label": "Total damage dealt"},
	{"key": "credits_earned", "label": "Credits earned"},
	{"key": "synergies_found", "label": "Synergies discovered"},
	{"key": "time_played", "label": "Time in combat", "format": "time"},
]

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func add(key: String, amount: float) -> void:
	if amount == 0.0:
		return
	var table := _app.save.section("stats")
	table[key] = float(table.get(key, 0.0)) + amount
	_app.save.mark_dirty()
	changed.emit(key, float(table[key]))


func set_max(key: String, candidate: float) -> bool:
	var table := _app.save.section("stats")
	if candidate <= float(table.get(key, 0.0)):
		return false
	table[key] = candidate
	_app.save.mark_dirty()
	changed.emit(key, candidate)
	return true


## Stored stats plus a few derived from other services.
func value(key: String) -> float:
	match key:
		"account_level":
			return float(_app.account.level())
		"weapons_unlocked":
			return float(_app.arsenal.unlocked_weapons().size())
		"highest_sector_cleared":
			return float(_app.campaign.highest_cleared())
		"synergies_found":
			var found: Array = _app.save.state.get("synergies", [])
			return float(found.size())
	return float(_app.save.section("stats").get(key, 0.0))


func display_value(entry: Dictionary) -> String:
	var v := value(str(entry.get("key", "")))
	if str(entry.get("format", "")) == "time":
		return Fmt.time_mmss(v)
	return Fmt.compact(v)
