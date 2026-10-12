class_name MetaService
extends RefCounted
## Permanent upgrades bought with Credits between runs. Each level contributes
## the upgrade's `mods` once; the totals are folded into every run's build.

signal purchased(id: String, level: int)

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func ids() -> Array:
	return _app.data.meta_upgrades().keys()


func def(id: String) -> Dictionary:
	return GameData.dict(_app.data.meta_upgrades(), id)


func level(id: String) -> int:
	return int(_app.save.section("meta_upgrades").get(id, 0))


func max_level(id: String) -> int:
	return GameData.integer(def(id), "max_level", 1)


func is_maxed(id: String) -> bool:
	return level(id) >= max_level(id)


## Credits needed for the next level, or 0 when maxed.
func cost(id: String) -> int:
	if is_maxed(id):
		return 0
	var d := def(id)
	var raw := GameData.num(d, "cost_base", 100.0) * pow(GameData.num(d, "cost_growth", 1.5), float(level(id)))
	return maxi(Fmt.round_to(raw, 5), 5)


func can_buy(id: String) -> bool:
	return not is_maxed(id) and _app.economy.can_afford(Economy.CREDITS, cost(id))


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var price := cost(id)
	if not _app.economy.spend(Economy.CREDITS, price, "meta:" + id):
		return false
	var levels := _app.save.section("meta_upgrades")
	levels[id] = level(id) + 1
	_app.save.mark_dirty()
	_app.stats.add("meta_purchases", 1.0)
	_app.missions.notify_event("meta_purchases", 1.0)
	_app.analytics.track(Analytics.META_UPGRADE_PURCHASED, {"id": id, "level": levels[id], "cost": price})
	purchased.emit(id, int(levels[id]))
	return true


## Adds every owned upgrade's contribution into `into` (key -> summed value).
func collect_mods(into: Dictionary) -> void:
	for id: String in ids():
		var owned := level(id)
		if owned <= 0:
			continue
		var mods := GameData.dict(def(id), "mods")
		for key: String in mods:
			into[key] = float(into.get(key, 0.0)) + float(mods[key]) * float(owned)


func total_levels() -> int:
	var total := 0
	for id: String in ids():
		total += level(id)
	return total


func any_affordable() -> bool:
	for id: String in ids():
		if can_buy(id):
			return true
	return false
