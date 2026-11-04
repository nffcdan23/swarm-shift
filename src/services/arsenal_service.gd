class_name ArsenalService
extends RefCounted
## Unlockable content: weapons (enter the in-run upgrade pool once unlocked),
## cores (playable characters) and skins (cosmetic tints).
##
## One rule set covers all three, driven by each item's `unlock` block:
##   {"type": "default"}                          always owned
##   {"type": "level", "level": 3, "cost": 700}   needs account level, then Credits
##   {"type": "crystals", "cost": 300}            Crystals
##   {"type": "product", "product": "..."}        granted by a store product
##   {"type": "research", "id": "..."}            owned once that research is done
##   {"type": "feat", "stat": "...", "target": n} earned, from a lifetime stat

signal unlocked(category: String, id: String)
signal loadout_changed

const WEAPONS := "weapons"
const CORES := "cores"
const SKINS := "skins"

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func defs(category: String) -> Dictionary:
	match category:
		WEAPONS: return _app.data.weapon_defs()
		CORES: return _app.data.cores()
		SKINS: return _app.data.skins()
	return {}


func is_owned(category: String, id: String) -> bool:
	var d := GameData.dict(defs(category), id)
	if d.is_empty():
		return false
	var unlock := GameData.dict(d, "unlock")
	match GameData.text(unlock, "type"):
		"default":
			return true
		"research":
			return _app.meta.level(GameData.text(unlock, "id")) > 0
		"feat":
			if _app.stats.value(GameData.text(unlock, "stat")) >= GameData.num(unlock, "target", 1.0):
				return true
	var owned: Array = _app.save.section("unlocks").get(category, [])
	return owned.has(id)


## Everything the UI needs to draw an unlock button.
func unlock_info(category: String, id: String) -> Dictionary:
	var unlock := GameData.dict(GameData.dict(defs(category), id), "unlock")
	var kind := GameData.text(unlock, "type", "default")
	var info := {
		"owned": is_owned(category, id),
		"kind": kind,
		"level": GameData.integer(unlock, "level", 0),
		"cost": GameData.integer(unlock, "cost", 0),
		"currency": Economy.CRYSTALS if kind == "crystals" else Economy.CREDITS,
		"product": GameData.text(unlock, "product"),
		"research": GameData.text(unlock, "id"),
		"feat": GameData.text(unlock, "text"),
		"level_met": true,
		"affordable": false,
	}
	info.level_met = _app.account.level() >= int(info.level)
	# Owned items are never "affordable": the Arsenal badges count this, and an
	# owned weapon whose price the player could pay again kept the WEAPONS
	# badge lit with nothing to buy.
	info.affordable = not bool(info.owned) and kind in ["level", "crystals"] and bool(info.level_met) \
		and _app.economy.can_afford(str(info.currency), int(info.cost))
	return info


func unlock(category: String, id: String) -> bool:
	var info := unlock_info(category, id)
	if bool(info.owned) or not bool(info.affordable):
		return false
	if not _app.economy.spend(str(info.currency), int(info.cost), "unlock:%s:%s" % [category, id]):
		return false
	grant(category, id, "purchase")
	return true


## Adds an item without charging (store products, rewards, debug).
func grant(category: String, id: String, source: String) -> void:
	if is_owned(category, id) or not defs(category).has(id):
		return
	var unlocks := _app.save.section("unlocks")
	var owned: Array = unlocks.get(category, [])
	owned.append(id)
	unlocks[category] = owned
	_app.save.mark_dirty()
	_app.analytics.track(Analytics.ITEM_UNLOCKED, {"category": category, "id": id, "source": source})
	unlocked.emit(category, id)


func unlocked_weapons() -> Array[String]:
	var out: Array[String] = []
	for id: String in _app.data.weapon_defs():
		if is_owned(WEAPONS, id):
			out.append(id)
	return out


## Display names of weapons, cores and skins whose level gate is exactly `at_level`.
func names_gated_at_level(at_level: int) -> Array:
	var out: Array = []
	for category: String in [WEAPONS, CORES, SKINS]:
		var table := defs(category)
		for id: String in table:
			var unlock := GameData.dict(table[id], "unlock")
			if GameData.text(unlock, "type") == "level" and GameData.integer(unlock, "level") == at_level:
				out.append(GameData.text(table[id], "name", id))
	return out


## Weapons the player's level has opened but that are not bought yet, cheapest
## first: [{"id", "name", "cost", "affordable"}]. Reaching a level only puts a
## weapon on sale; it never reaches a run until it is bought.
func weapons_for_sale() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in defs(WEAPONS):
		var info := unlock_info(WEAPONS, id)
		if bool(info.owned) or str(info.kind) != "level" or not bool(info.level_met):
			continue
		out.append({"id": id, "name": GameData.text(defs(WEAPONS)[id], "name", id), "cost": int(info.cost), "affordable": bool(info.affordable)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.cost) < int(b.cost))
	return out


## Of `names_gated_at_level`, the ones sold in the Arsenal (weapons and cores)
## rather than given (research).
func is_for_sale_at_level(name: String, at_level: int) -> bool:
	return names_gated_at_level(at_level).has(name)


func any_affordable_unlock() -> bool:
	for category: String in [WEAPONS, CORES]:
		for id: String in defs(category):
			if bool(unlock_info(category, id).affordable):
				return true
	return false


# ------------------------------------------------------------------ loadout

func selected_core() -> String:
	var id := str(_app.save.section("loadout").get("core", "vanguard"))
	return id if is_owned(CORES, id) else "vanguard"


func select_core(id: String) -> bool:
	if not is_owned(CORES, id):
		return false
	_app.save.section("loadout")["core"] = id
	_app.save.mark_dirty()
	loadout_changed.emit()
	return true


## The weapon a run starts with: the core's own, unless Flex Rack is researched
## and another weapon has been chosen that still qualifies.
func start_weapon() -> String:
	var core_weapon := GameData.text(GameData.dict(_app.data.cores(), selected_core()), "start_weapon", "pulse")
	var chosen := str(_app.save.section("loadout").get("start_weapon", ""))
	return chosen if start_weapon_options().has(chosen) else core_weapon


## Weapons Flex Rack may start with. Empty until it is researched.
func start_weapon_options() -> Array[String]:
	var out: Array[String] = []
	if _app.meta.mod_total("run.flex_rack") <= 0.0:
		return out
	for id: String in unlocked_weapons():
		# A support weapon (the Prism Lance) cannot kill on its own.
		if _app.mastery.rank(id) >= 1 and not GameData.flag(_app.data.weapon(id), "support"):
			out.append(id)
	return out


## Picks a start weapon, or goes back to the core's own with "".
func select_start_weapon(id: String) -> bool:
	if not id.is_empty() and not start_weapon_options().has(id):
		return false
	_app.save.section("loadout")["start_weapon"] = id
	_app.save.mark_dirty()
	loadout_changed.emit()
	return true


func selected_skin() -> String:
	var id := str(_app.save.section("loadout").get("skin", "default"))
	return id if is_owned(SKINS, id) else "default"


func select_skin(id: String) -> bool:
	if not is_owned(SKINS, id):
		return false
	_app.save.section("loadout")["skin"] = id
	_app.save.mark_dirty()
	loadout_changed.emit()
	return true


## Colour the player is drawn in: the skin's tint, or the core's own colour.
func player_color() -> Color:
	var core_color := GameData.color(GameData.dict(_app.data.cores(), selected_core()), "color", Color("2de2ff"))
	return GameData.color(GameData.dict(_app.data.skins(), selected_skin()), "color", core_color)
