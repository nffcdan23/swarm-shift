class_name GoalService
extends RefCounted
## What the player is working towards, at three distances, for the lobby. Reads
## other services; stores nothing.
##   short    the next research to buy (hours of Credits at most)
##   medium   the weapon closest to its next Mastery rank
##   long     the next big unlock: an evolution, a new weapon, a skin
## Each is a dictionary the lobby can draw without knowing where it came from:
## {"icon", "color", "title", "detail", "progress", "tab", "branch"}, or empty
## when there is nothing left at that distance.

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func short_term() -> Dictionary:
	var goal := _app.meta.next_goal()
	if str(goal.id).is_empty():
		return {}
	var balance := _app.economy.balance(Economy.CREDITS)
	var ready := bool(goal.affordable)
	return {
		"icon": "credit", "color": Palette.CREDITS,
		"title": ("READY: %s" if ready else "NEXT RESEARCH: %s") % str(goal.name),
		"detail": "%s / %s" % [Fmt.compact(float(mini(balance, int(goal.cost)))), Fmt.compact(float(goal.cost))],
		"progress": float(goal.progress), "ready": ready, "tab": "upgrades", "branch": _app.meta.category(str(goal.id)),
	}


## Prefers the weapon furthest through its current rank, so the bar in the lobby
## is the one most likely to fill soon.
func medium_term() -> Dictionary:
	var best := ""
	var best_fraction := -1.0
	var mastery := _app.mastery
	var candidates: Array[String] = _app.arsenal.unlocked_weapons()
	for id in candidates:
		if mastery.is_maxed(id):
			continue
		var fraction := float(mastery.progress(id).fraction)
		# A weapon that has actually been used beats one that has not.
		if mastery.xp(id) > 0:
			fraction += 1.0
		if id == _app.arsenal.start_weapon():
			fraction += 0.001
		if fraction > best_fraction:
			best_fraction = fraction
			best = id
	if best.is_empty():
		return {}
	var state := mastery.progress(best)
	var weapon := _app.data.weapon(best)
	return {
		"icon": GameData.text(weapon, "icon", "star"), "color": GameData.color(weapon, "color", Palette.CYAN),
		"title": "%s: %s" % [GameData.text(weapon, "name", best).to_upper(), mastery.rank_name(int(state.rank) + 1)],
		"detail": "%s / %s" % [Fmt.compact(float(state.into)), Fmt.compact(float(state.needed))],
		"progress": float(state.fraction), "ready": false, "tab": "arsenal", "branch": "",
	}


func long_term() -> Dictionary:
	var evolution := _next_evolution()
	if not evolution.is_empty():
		return evolution
	for id: String in _app.meta.ids():
		if _app.meta.kind(id) == MetaService.KIND_UNLOCK and not _app.meta.is_maxed(id):
			var gate := _app.meta.unlock_level(id)
			var def := _app.meta.def(id)
			var waiting := "LV %d" % gate if _app.account.level() < gate else Fmt.compact(float(_app.meta.cost(id)))
			return {"icon": GameData.text(def, "icon", "star"), "color": Palette.VIOLET,
				"title": "MILESTONE: %s" % GameData.text(def, "name", id), "detail": waiting,
				"progress": clampf(float(_app.economy.balance(Economy.CREDITS)) / float(maxi(_app.meta.cost(id), 1)), 0.0, 1.0),
				"ready": false, "tab": "upgrades", "branch": _app.meta.category(id)}
	return _next_skin()


## The cheapest evolution not yet owned on a weapon that has the rank for it,
## else the one its owner is closest to.
func _next_evolution() -> Dictionary:
	if not _app.mastery.lab_ready():
		return {}
	var best := {}
	var best_cost := 0
	for weapon_id: String in _app.arsenal.unlocked_weapons():
		for path: String in _app.mastery.evolution_table(weapon_id):
			var info := _app.mastery.evolution_info(weapon_id, path)
			if bool(info.owned) or not bool(info.rank_met):
				continue
			if best.is_empty() or int(info.cost) < best_cost:
				best_cost = int(info.cost)
				var entry := _app.mastery.evolution_def(weapon_id, path)
				best = {"icon": GameData.text(_app.data.weapon(weapon_id), "icon", "star"), "color": GameData.color(entry, "color", Palette.GOLD),
					"title": "EVOLVE: %s" % GameData.text(entry, "name", path), "detail": Fmt.compact(float(best_cost)),
					"progress": clampf(float(_app.economy.balance(Economy.CREDITS)) / float(maxi(best_cost, 1)), 0.0, 1.0),
					"ready": bool(info.affordable), "tab": "arsenal", "branch": ""}
	return best


func _next_skin() -> Dictionary:
	for id: String in _app.data.skins():
		var info := _app.arsenal.unlock_info(ArsenalService.SKINS, id)
		if bool(info.owned) or str(info.kind) != "level":
			continue
		var def := GameData.dict(_app.data.skins(), id)
		return {"icon": "star", "color": GameData.color(def, "color", Palette.GOLD),
			"title": "SKIN: %s" % GameData.text(def, "name", id), "detail": Fmt.compact(float(info.cost)),
			"progress": clampf(float(_app.economy.balance(Economy.CREDITS)) / float(maxi(int(info.cost), 1)), 0.0, 1.0),
			"ready": bool(info.affordable), "tab": "arsenal", "branch": ""}
	return {}
