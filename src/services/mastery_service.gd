class_name MasteryService
extends RefCounted
## Weapon mastery and evolutions.
##
## Every weapon has five ranks. A run earns one budget of Mastery XP, shared
## between the weapons by the damage each actually landed, so:
##   - it comes from use in combat: a weapon that landed nothing gets nothing,
##     and a run with no kills earns nothing;
##   - a longer run earns no more than a normal one. The budget counts the
##     first few minutes only, so stretching a run is pointless, and time the
##     player spends not moving does not count at all;
##   - the share is softened (square root of damage), so a support weapon or
##     one being tried for the first time still earns a real part of it.
## Ranks pay out as small weapon-specific perks and open up evolutions.
##
## An evolution is a second form of a weapon at its final level. Each weapon has
## two, for different jobs. Unlocking one (rank, Credits, Evolution Lab) only
## puts it on the table: which to take is decided on a card during the run.
##
## Awarded from RunLedger.settle, so it is paid exactly once per run like
## everything else a run earns.

signal changed
signal ranked_up(weapon_id: String, rank: int)

var _app: AppRoot
var _cfg: Dictionary


func _init(app: AppRoot) -> void:
	_app = app
	_cfg = GameData.dict(app.data.weapons, "mastery")


func _ranks() -> Array:
	return GameData.list(_cfg, "ranks")


func max_rank() -> int:
	return _ranks().size()


## Display name of a rank; "UNRANKED" below rank 1.
func rank_name(rank_number: int) -> String:
	if rank_number < 1 or rank_number > max_rank():
		return "UNRANKED"
	return GameData.text(_ranks()[rank_number - 1], "name")


## Total XP a weapon needs to hold `rank_number`.
func rank_xp(rank_number: int) -> int:
	if rank_number < 1:
		return 0
	return GameData.integer(_ranks()[mini(rank_number, max_rank()) - 1], "xp")


func _entry(weapon_id: String) -> Dictionary:
	var entry: Variant = _app.save.section("mastery").get(weapon_id, {})
	return entry if entry is Dictionary else {}


func xp(weapon_id: String) -> int:
	return int(_entry(weapon_id).get("xp", 0))


func _rank_for(amount: int) -> int:
	var reached := 0
	for i in max_rank():
		if amount >= rank_xp(i + 1):
			reached = i + 1
	return reached


func rank(weapon_id: String) -> int:
	return _rank_for(xp(weapon_id))


func is_maxed(weapon_id: String) -> bool:
	return rank(weapon_id) >= max_rank()


## Lifetime numbers for the Arsenal: {"kills", "damage", "runs"}.
func record(weapon_id: String) -> Dictionary:
	var entry := _entry(weapon_id)
	return {"kills": int(entry.get("kills", 0)), "damage": float(entry.get("damage", 0.0)), "runs": int(entry.get("runs", 0))}


## Everything a progress bar needs. `fraction` is progress within the rank.
func progress(weapon_id: String) -> Dictionary:
	var have := xp(weapon_id)
	var current := _rank_for(have)
	if current >= max_rank():
		return {"rank": current, "xp": have, "into": 0, "needed": 0, "fraction": 1.0, "maxed": true}
	var floor_xp := rank_xp(current)
	var span := rank_xp(current + 1) - floor_xp
	return {"rank": current, "xp": have, "into": have - floor_xp, "needed": span,
		"fraction": clampf(float(have - floor_xp) / float(maxi(span, 1)), 0.0, 1.0), "maxed": false}


func mastered_weapons() -> Array[String]:
	var out: Array[String] = []
	for id: String in _app.data.weapon_defs():
		if is_maxed(id):
			out.append(id)
	return out


func weapons_at_rank(wanted: int) -> int:
	var total := 0
	for id: String in _app.data.weapon_defs():
		if rank(id) >= wanted:
			total += 1
	return total


# ---------------------------------------------------------------- earning XP

## The Mastery XP a finished run is worth before it is shared out. Pure.
func run_budget(result: Dictionary) -> float:
	var earn := GameData.dict(_cfg, "run_xp")
	var seconds := float(result.get("active_time", result.get("time", 0.0)))
	var minutes := minf(seconds / 60.0, GameData.num(earn, "minutes_cap", 6.0))
	# Real combat, not a run spent hiding: full credit from a low kill rate.
	var fighting := clampf(float(result.get("kills", 0)) / maxf(minutes * GameData.num(earn, "kills_per_minute", 60.0), 1.0), 0.0, 1.0)
	var tier := float(maxi(int(result.get("tier", 1)), 1))
	var tier_scale := minf(1.0 + GameData.num(earn, "per_tier", 0.05) * (tier - 1.0), GameData.num(earn, "tier_cap", 2.0))
	var budget := GameData.num(earn, "per_minute", 30.0) * minutes * fighting * tier_scale
	budget += GameData.num(earn, "boss", 40.0) * minf(float(result.get("bosses", 0)), GameData.num(earn, "bosses_cap", 2.0))
	if bool(result.get("cleared", false)):
		budget += GameData.num(earn, "clear", 60.0)
	var fraction := GameData.num(GameData.dict(_app.data.game, "rewards"), "abandon_reward_fraction", 1.0) if bool(result.get("abandoned", false)) else 1.0
	return budget * fraction * (1.0 + _app.meta.mod_total("mastery_xp_pct"))


## What each weapon in `result` would earn: {weapon_id: xp}. Pure.
func preview(result: Dictionary) -> Dictionary:
	var dealt: Dictionary = result.get("dealt_by_source", result.get("damage_by_source", {}))
	var weights: Dictionary = {}
	var total := 0.0
	for weapon_id: String in result.get("weapons", {}):
		var landed := float(dealt.get(weapon_id, 0.0))
		if landed > 0.0 and _app.data.weapon_defs().has(weapon_id):
			weights[weapon_id] = sqrt(landed)
			total += float(weights[weapon_id])
	var out: Dictionary = {}
	if total <= 0.0:
		return out
	var budget := run_budget(result)
	for weapon_id: String in weights:
		out[weapon_id] = maxi(int(round(budget * float(weights[weapon_id]) / total)), 1)
	return out


## Adds a run's Mastery XP and returns a row per weapon, biggest gain first:
## {"id", "gained", "rank_before", "rank_after", "fraction_after", "maxed"}.
func award(result: Dictionary) -> Array[Dictionary]:
	var gains := preview(result)
	var kills: Dictionary = result.get("kills_by_source", {})
	var dealt: Dictionary = result.get("dealt_by_source", result.get("damage_by_source", {}))
	var table := _app.save.section("mastery")
	var rows: Array[Dictionary] = []
	for weapon_id: String in gains:
		var entry: Dictionary = _entry(weapon_id).duplicate()
		var before := int(entry.get("xp", 0))
		var cap := rank_xp(max_rank())
		var after := mini(before + int(gains[weapon_id]), cap)
		entry["xp"] = after
		entry["kills"] = int(entry.get("kills", 0)) + int(kills.get(weapon_id, 0))
		entry["damage"] = float(entry.get("damage", 0.0)) + float(dealt.get(weapon_id, 0.0))
		entry["runs"] = int(entry.get("runs", 0)) + 1
		table[weapon_id] = entry
		rows.append({"id": weapon_id, "gained": after - before, "rank_before": _rank_for(before), "rank_after": _rank_for(after)})
	rows.sort_custom(func(l: Dictionary, r: Dictionary) -> bool: return int(l.gained) > int(r.gained))
	_app.save.mark_dirty()
	for row in rows:
		var state := progress(str(row.id))
		row["fraction_after"] = state.fraction
		row["maxed"] = state.maxed
		if int(row.rank_after) > int(row.rank_before):
			_app.analytics.track(Analytics.MASTERY_RANK_UP, {"weapon": row.id, "rank": row.rank_after})
			ranked_up.emit(str(row.id), int(row.rank_after))
	if not rows.is_empty():
		changed.emit()
	return rows


# --------------------------------------------------------------------- perks

## [{"rank", "desc", "mods", "earned"}] for a weapon, lowest rank first.
func perks(weapon_id: String) -> Array[Dictionary]:
	var have := rank(weapon_id)
	var out: Array[Dictionary] = []
	for perk: Dictionary in GameData.list(_app.data.weapon(weapon_id), "mastery"):
		out.append({"rank": GameData.integer(perk, "rank"), "desc": GameData.text(perk, "desc"),
			"mods": GameData.dict(perk, "mods"), "earned": have >= GameData.integer(perk, "rank")})
	return out


## Adds every earned perk to a run's modifiers, addressed to its weapon.
func collect_mods(into: Dictionary) -> void:
	for weapon_id: String in _app.data.weapon_defs():
		for perk in perks(weapon_id):
			if not bool(perk.earned):
				continue
			var mods: Dictionary = perk.mods
			for key: String in mods:
				var address := "w.%s.%s" % [weapon_id, key]
				into[address] = float(into.get(address, 0.0)) + float(mods[key])


# ---------------------------------------------------------------- evolutions

func evolution_table(weapon_id: String) -> Dictionary:
	return GameData.dict(_app.data.weapon(weapon_id), "evolutions")


func evolution_def(weapon_id: String, path: String) -> Dictionary:
	return GameData.dict(evolution_table(weapon_id), path)


## True once the Evolution Lab has been researched.
func lab_ready() -> bool:
	return _app.meta.mod_total("run.evolutions") > 0.0


func owned_paths(weapon_id: String) -> Array[String]:
	var out: Array[String] = []
	var owned: Array = _app.save.section("evolutions").get("unlocked", [])
	for path: String in evolution_table(weapon_id):
		if owned.has("%s.%s" % [weapon_id, path]):
			out.append(path)
	return out


func owned_count() -> int:
	var owned: Array = _app.save.section("evolutions").get("unlocked", [])
	return owned.size()


## Everything the UI needs to draw an evolution.
func evolution_info(weapon_id: String, path: String) -> Dictionary:
	var d := evolution_def(weapon_id, path)
	var needed := GameData.integer(d, "rank", 3)
	var cost := GameData.integer(d, "cost", 0)
	var rank_met := rank(weapon_id) >= needed
	var lab := lab_ready()
	var owned := owned_paths(weapon_id).has(path)
	var weapon_owned := _app.arsenal.is_owned(ArsenalService.WEAPONS, weapon_id)
	return {"owned": owned, "rank": needed, "rank_met": rank_met, "lab": lab, "cost": cost, "weapon_owned": weapon_owned,
		"affordable": not owned and rank_met and lab and weapon_owned and _app.economy.can_afford(Economy.CREDITS, cost)}


func unlock_evolution(weapon_id: String, path: String) -> bool:
	var info := evolution_info(weapon_id, path)
	if not bool(info.affordable):
		return false
	if not _app.economy.spend(Economy.CREDITS, int(info.cost), "evolution:%s.%s" % [weapon_id, path]):
		return false
	var table := _app.save.section("evolutions")
	var owned: Array = table.get("unlocked", [])
	owned.append("%s.%s" % [weapon_id, path])
	table["unlocked"] = owned
	_app.save.mark_dirty()
	_app.analytics.track(Analytics.ITEM_UNLOCKED, {"category": "evolutions", "id": "%s.%s" % [weapon_id, path], "source": "purchase"})
	changed.emit()
	return true


func any_affordable_evolution() -> bool:
	for weapon_id: String in _app.data.weapon_defs():
		for path: String in evolution_table(weapon_id):
			if bool(evolution_info(weapon_id, path).affordable):
				return true
	return false


## What a run can evolve into: {weapon_id: [paths]}.
func run_evolutions() -> Dictionary:
	var out: Dictionary = {}
	if not lab_ready():
		return out
	for weapon_id: String in _app.data.weapon_defs():
		var paths := owned_paths(weapon_id)
		if not paths.is_empty():
			out[weapon_id] = paths
	return out
