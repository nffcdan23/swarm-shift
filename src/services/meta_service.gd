class_name MetaService
extends RefCounted
## Research: everything permanent bought with Credits between runs. Each level
## contributes the entry's `mods` once; the totals are folded into every run's
## build.
##
## Entries are grouped into branches for the Research tab (meta.json ->
## upgrade_categories), may be gated behind a Player Level (`unlock_level`) and
## other research (`requires`), and can be bought several levels at a time.
##
## Four kinds, all stored as a level in the same table:
##   track      a levelled stat (the default)
##   unlock     a one-off that changes how runs play
##   doctrine   a trade-off that only applies while selected, one at a time
##   awakening  gives one core an augment from the start of every run

signal purchased(id: String, level: int)
signal doctrine_changed

const KIND_TRACK := "track"
const KIND_UNLOCK := "unlock"
const KIND_DOCTRINE := "doctrine"
const KIND_AWAKENING := "awakening"

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


func kind(id: String) -> String:
	return GameData.text(def(id), "kind", KIND_TRACK)


# --------------------------------------------------------------- categories

## Category ids in display order.
func categories() -> Array:
	return GameData.dict(_app.data.meta, "upgrade_categories").keys()


func category_def(category: String) -> Dictionary:
	return GameData.dict(GameData.dict(_app.data.meta, "upgrade_categories"), category)


func category(id: String) -> String:
	return GameData.text(def(id), "category", "utility")


func ids_in(wanted: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids():
		if category(id) == wanted:
			out.append(id)
	return out


# ------------------------------------------------------------------ gating

## Player Level needed before this upgrade can be bought (0 = from the start).
func unlock_level(id: String) -> int:
	return GameData.integer(def(id), "unlock_level", 0)


## What has to be owned first: [{"id", "level", "name"}]. An awakening also
## needs its core, reported as {"core": id, "name": display name}.
func requirements(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for token: String in GameData.list(def(id), "requires"):
		var parts := token.split(":")
		var needed := parts[0]
		out.append({"id": needed, "level": int(parts[1]) if parts.size() > 1 else 1, "name": GameData.text(def(needed), "name", needed)})
	var core := GameData.text(def(id), "core")
	if not core.is_empty():
		out.append({"core": core, "name": GameData.text(GameData.dict(_app.data.cores(), core), "name", core)})
	return out


## The requirements not yet met.
func missing_requirements(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for need in requirements(id):
		if need.has("core"):
			if not _app.arsenal.is_owned(ArsenalService.CORES, str(need.core)):
				out.append(need)
		elif level(str(need.id)) < int(need.level):
			out.append(need)
	return out


## Levels already owned are never taken away by a gate added later.
func is_unlocked(id: String) -> bool:
	return level(id) > 0 or (_app.account.level() >= unlock_level(id) and missing_requirements(id).is_empty())


## Display names of upgrades whose gate is exactly `at_level`.
func names_gated_at_level(at_level: int) -> Array:
	var out: Array = []
	for id: String in ids():
		if unlock_level(id) == at_level and at_level > 0:
			out.append(GameData.text(def(id), "name", id))
	return out


# ------------------------------------------------------------------- costs

## Credits for going from `at_level` to the next one.
func cost_at(id: String, at_level: int) -> int:
	var d := def(id)
	var raw := GameData.num(d, "cost_base", 100.0) * pow(GameData.num(d, "cost_growth", 1.5), float(at_level))
	return maxi(Fmt.round_to(raw, 5), 5)


## Credits needed for the next level, or 0 when maxed.
func cost(id: String) -> int:
	if is_maxed(id):
		return 0
	return cost_at(id, level(id))


## Credits for the next `count` levels (clamped to what is left).
func cost_for(id: String, count: int) -> int:
	var from := level(id)
	var upto := mini(from + maxi(count, 0), max_level(id))
	var total := 0
	for step in range(from, upto):
		total += cost_at(id, step)
	return total


## How many of the next `limit` levels the current balance covers.
func affordable_count(id: String, limit: int) -> int:
	if not is_unlocked(id):
		return 0
	var balance := _app.economy.balance(Economy.CREDITS)
	var from := level(id)
	var upto := mini(from + maxi(limit, 0), max_level(id))
	var bought := 0
	for step in range(from, upto):
		var price := cost_at(id, step)
		if price > balance:
			break
		balance -= price
		bought += 1
	return bought


func can_buy(id: String) -> bool:
	return not is_maxed(id) and is_unlocked(id) and _app.economy.can_afford(Economy.CREDITS, cost(id))


func buy(id: String) -> bool:
	return buy_many(id, 1) == 1


## Buys up to `count` levels, stopping at the cap or when Credits run out.
## Returns how many were bought; the Credits and the levels change together.
func buy_many(id: String, count: int) -> int:
	var amount := affordable_count(id, count)
	if amount <= 0:
		return 0
	var price := cost_for(id, amount)
	if not _app.economy.spend(Economy.CREDITS, price, "meta:" + id):
		return 0
	var levels := _app.save.section("meta_upgrades")
	levels[id] = level(id) + amount
	_app.save.mark_dirty()
	_app.stats.add("meta_purchases", float(amount))
	_app.missions.notify_event("meta_purchases", float(amount))
	_app.analytics.track(Analytics.META_UPGRADE_PURCHASED, {"id": id, "level": levels[id], "cost": price, "levels": amount})
	purchased.emit(id, int(levels[id]))
	return amount


# ----------------------------------------------------------------- effects

## The upgrade's single modifier value per level.
func per_level(id: String) -> float:
	var mods := GameData.dict(def(id), "mods")
	for key: String in mods:
		return float(mods[key])
	return 0.0


## Total bonus at `at_level`, as text: "+12%", "+0.6", "+2".
func effect_text(id: String, at_level: int) -> String:
	var total := per_level(id) * float(at_level)
	if GameData.text(def(id), "format", "percent") == "percent":
		return "+%s%%" % Fmt.trim(total * 100.0)
	return "+%s" % Fmt.trim(total)


## Short stat name the effect applies to, e.g. "Damage".
func stat_label(id: String) -> String:
	return GameData.text(def(id), "stat", GameData.text(def(id), "name", id))


## Levels of `id` that count right now: an unselected doctrine counts for nothing.
func _levels_in_force(id: String) -> int:
	if kind(id) == KIND_DOCTRINE and id != active_doctrine():
		return 0
	return level(id)


## Adds every owned upgrade's contribution into `into` (key -> summed value).
func collect_mods(into: Dictionary) -> void:
	for id: String in ids():
		var owned := _levels_in_force(id)
		if owned <= 0:
			continue
		var mods := GameData.dict(def(id), "mods")
		for key: String in mods:
			into[key] = float(into.get(key, 0.0)) + float(mods[key]) * float(owned)


## Sum of one modifier across every owned upgrade.
func mod_total(key: String) -> float:
	var total := 0.0
	for id: String in ids():
		var owned := _levels_in_force(id)
		if owned > 0:
			total += GameData.num(GameData.dict(def(id), "mods"), key, 0.0) * float(owned)
	return total


# --------------------------------------------------------------- doctrines

func active_doctrine() -> String:
	var id := str(_app.save.section("loadout").get("doctrine", ""))
	return id if level(id) > 0 else ""


## Selects a researched doctrine, or clears the choice with "".
func select_doctrine(id: String) -> bool:
	if not id.is_empty() and (kind(id) != KIND_DOCTRINE or level(id) <= 0):
		return false
	_app.save.section("loadout")["doctrine"] = id
	_app.save.mark_dirty()
	doctrine_changed.emit()
	return true


## Augments the core starts every run with, from its researched awakening.
func awakened_augments(core_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids():
		if kind(id) == KIND_AWAKENING and level(id) > 0 and GameData.text(def(id), "core") == core_id:
			out.append(GameData.text(def(id), "augment"))
	return out


func total_levels() -> int:
	var total := 0
	for id: String in ids():
		total += level(id)
	return total


func total_max_levels() -> int:
	var total := 0
	for id: String in ids():
		total += max_level(id)
	return total


func any_affordable() -> bool:
	for id: String in ids():
		if can_buy(id):
			return true
	return false


## The unlocked, unfinished upgrade with the lowest next price: what the lobby
## shows as "next upgrade" so Credits always have a visible purpose. Empty id
## when everything is maxed.
func next_goal() -> Dictionary:
	var best := ""
	var best_cost := 0
	for id: String in ids():
		if is_maxed(id) or not is_unlocked(id):
			continue
		var price := cost(id)
		if best.is_empty() or price < best_cost:
			best = id
			best_cost = price
	if best.is_empty():
		return {"id": "", "cost": 0, "progress": 1.0}
	var balance := _app.economy.balance(Economy.CREDITS)
	return {
		"id": best, "name": GameData.text(def(best), "name", best), "cost": best_cost,
		"progress": clampf(float(balance) / float(maxi(best_cost, 1)), 0.0, 1.0),
		"affordable": balance >= best_cost,
	}
