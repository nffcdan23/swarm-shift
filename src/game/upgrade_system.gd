class_name UpgradeSystem
extends RefCounted
## Builds the three-card choice shown on level-up, and applies the pick.
##
## Each card ("offer") is a plain dictionary so the UI can render it without
## knowing anything about the rules:
##   kind      weapon | passive | augment | heal | credits | purge
##   id, name, desc, icon, rarity, color
##   level     level the item will be at after picking; max_level
##   is_new    true when this adds something the build does not have yet
##
## Shaping rules, in order of importance:
##   - never offer something that is already maxed or has no free slot
##   - early levels guarantee a new weapon so builds diversify quickly
##   - items the player already owns are weighted up, so builds come together
##   - luck raises the odds of the rarer cards

const KIND_WEAPON := "weapon"
const KIND_PASSIVE := "passive"
const KIND_AUGMENT := "augment"
const KIND_HEAL := "heal"
const KIND_CREDITS := "credits"
const KIND_PURGE := "purge"

var _a: Arena
var _data: GameData
var _weapon_max := 5
var _weapon_slots := 4
var _passive_slots := 5


func setup(arena: Arena) -> void:
	_a = arena
	_data = arena.data
	_weapon_max = GameData.integer(_data.weapons, "max_level", 5)
	_weapon_slots = GameData.integer(_data.run_cfg(), "weapon_slots", 4)
	_passive_slots = GameData.integer(_data.run_cfg(), "passive_slots", 5)


## Rolls `amount` distinct offers. `boosted` (elite caches) skews towards rarer cards.
func roll(amount: int, boosted: bool = false) -> Array[Dictionary]:
	var pool := _candidates(boosted)
	var picked: Array[Dictionary] = []

	var build := _a.build
	var wants_weapon := build.weapon_order.size() < 2 and _a.level >= 2
	if wants_weapon:
		var fresh: Array[Dictionary] = []
		for offer in pool:
			if str(offer.kind) == KIND_WEAPON and bool(offer.is_new):
				fresh.append(offer)
		if not fresh.is_empty():
			picked.append(_take(pool, fresh))

	while picked.size() < amount and not pool.is_empty():
		picked.append(_take(pool, pool))

	# Everything maxed: still give a meaningful choice.
	var fillers: Array[Dictionary] = [_heal_offer(), _credits_offer(), _purge_offer()]
	var filler_index := 0
	while picked.size() < amount:
		picked.append(fillers[filler_index % fillers.size()])
		filler_index += 1
	# Seeded shuffle so the guaranteed card is not always in the same slot.
	for i in range(picked.size() - 1, 0, -1):
		var j := _a.rng.randi_range(0, i)
		var held := picked[i]
		picked[i] = picked[j]
		picked[j] = held
	return picked


## Weighted draw of one offer from `from`, removing it from `pool`.
func _take(pool: Array[Dictionary], from: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for offer in from:
		total += float(offer.weight)
	var roll_at := _a.rng.randf() * total
	var chosen: Dictionary = from[from.size() - 1]
	for offer in from:
		roll_at -= float(offer.weight)
		if roll_at <= 0.0:
			chosen = offer
			break
	pool.erase(chosen)
	return chosen


func _candidates(boosted: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var build := _a.build
	var luck := _a.player.luck

	var weapon_defs := _data.weapon_defs()
	for weapon_id in build.weapon_order:
		var level := build.weapon_level(weapon_id)
		if level >= _weapon_max:
			continue
		var def: Dictionary = weapon_defs[weapon_id]
		var next: Dictionary = GameData.list(def, "levels")[level]
		var rarity := "epic" if level + 1 >= _weapon_max else ("rare" if level + 1 >= _weapon_max - 1 else "common")
		out.append(_offer(KIND_WEAPON, weapon_id, def, GameData.text(next, "desc"), rarity, level + 1, _weapon_max, false, 1.25, luck, boosted))
		out[out.size() - 1]["icon_color"] = GameData.color(def, "color", Palette.CYAN)
	if build.weapon_order.size() < _weapon_slots:
		for weapon_id in _a.config.weapon_pool:
			if build.weapons.has(weapon_id) or not weapon_defs.has(weapon_id):
				continue
			var def: Dictionary = weapon_defs[weapon_id]
			out.append(_offer(KIND_WEAPON, weapon_id, def, GameData.text(def, "tagline"), "rare", 1, _weapon_max, true, 0.85, luck, boosted))
			out[out.size() - 1]["icon_color"] = GameData.color(def, "color", Palette.CYAN)

	var passive_defs := _data.passives()
	var passive_room := build.passive_order.size() < _passive_slots
	for passive_id: String in passive_defs:
		var def: Dictionary = passive_defs[passive_id]
		var level := build.passive_level(passive_id)
		var cap := GameData.integer(def, "max_level", 5)
		if level >= cap or (level == 0 and not passive_room):
			continue
		out.append(_offer(KIND_PASSIVE, passive_id, def, GameData.text(def, "desc"), GameData.text(def, "rarity", "common"),
			level + 1, cap, level == 0, 1.1 if level > 0 else 0.8, luck, boosted))

	var augment_defs := _data.augments()
	for augment_id: String in augment_defs:
		if build.augments.has(augment_id):
			continue
		var def: Dictionary = augment_defs[augment_id]
		if not _requirements_met(GameData.dict(def, "requires")):
			continue
		out.append(_offer(KIND_AUGMENT, augment_id, def, GameData.text(def, "desc"), GameData.text(def, "rarity", "epic"), 1, 1, true, 1.0, luck, boosted))
	return out


func _requirements_met(req: Dictionary) -> bool:
	if _a.level < GameData.integer(req, "min_level", 0):
		return false
	for token: String in GameData.list(req, "all"):
		if not _a.build.has(token):
			return false
	var any := GameData.list(req, "any")
	if any.is_empty():
		return true
	for token: String in any:
		if _a.build.has(token):
			return true
	return false


func _offer(kind: String, id: String, def: Dictionary, desc: String, rarity_id: String, level: int, max_level: int,
		is_new: bool, bias: float, luck: float, boosted: bool) -> Dictionary:
	var rarity := _data.rarity(rarity_id)
	var weight := GameData.num(rarity, "weight", 1.0) * (1.0 + luck * GameData.num(rarity, "luck_factor", 0.0)) * bias
	if boosted and rarity_id != "common":
		weight *= 3.0
	return {
		"kind": kind, "id": id,
		"name": GameData.text(def, "name", id),
		"desc": desc,
		"icon": GameData.text(def, "icon", "star"),
		"rarity": rarity_id,
		"rarity_name": GameData.text(rarity, "name", rarity_id.to_upper()),
		"color": GameData.color(rarity, "color", Color.WHITE),
		"icon_color": Palette.TEXT if kind == KIND_PASSIVE else GameData.color(rarity, "color", Color.WHITE),
		"level": level, "max_level": max_level,
		"is_new": is_new,
		"weight": maxf(weight, 0.001),
	}


func _heal_offer() -> Dictionary:
	var fraction := GameData.num(_data.run_cfg(), "fallback_heal_fraction", 0.3)
	return {"kind": KIND_HEAL, "id": "repair", "name": "Field Repair", "desc": "Restore %d%% health" % int(fraction * 100.0),
		"icon": "heart", "rarity": "common", "rarity_name": "COMMON", "color": Color("5cff8a"),
		"level": 0, "max_level": 0, "is_new": false, "weight": 1.0}


func _credits_offer() -> Dictionary:
	var amount := GameData.integer(_data.run_cfg(), "fallback_credits", 40)
	return {"kind": KIND_CREDITS, "id": "salvage", "name": "Salvage", "desc": "+%d Credits" % amount,
		"icon": "credit", "rarity": "common", "rarity_name": "COMMON", "color": Color("ffd15c"),
		"level": 0, "max_level": 0, "is_new": false, "weight": 1.0}


func _purge_offer() -> Dictionary:
	return {"kind": KIND_PURGE, "id": "purge", "name": "Purge", "desc": "Detonate a blast that clears the screen",
		"icon": "bomb", "rarity": "common", "rarity_name": "COMMON", "color": Color("ff9a3d"),
		"level": 0, "max_level": 0, "is_new": false, "weight": 1.0}


# ---------------------------------------------------------------------- apply

func apply(offer: Dictionary) -> void:
	var a := _a
	var build := a.build
	var id := str(offer.id)
	match str(offer.kind):
		KIND_WEAPON:
			a.grant_weapon(id, int(offer.level))
		KIND_PASSIVE:
			build.set_passive(id, int(offer.level))
			var heal := GameData.num(GameData.dict(_data.passives(), id), "heal", 0.0)
			build.recompute()
			a.refresh_build()
			if heal > 0.0:
				a.player.heal(heal)
		KIND_AUGMENT:
			build.add_augment(id)
			build.recompute()
			a.refresh_build()
		KIND_HEAL:
			a.player.heal(a.player.max_hp * GameData.num(_data.run_cfg(), "fallback_heal_fraction", 0.3))
		KIND_CREDITS:
			a.add_credits(float(GameData.integer(_data.run_cfg(), "fallback_credits", 40)))
		KIND_PURGE:
			a.combat.detonate_bomb()
	for synergy_id in build.refresh_synergies():
		a.refresh_build()
		a.on_synergy(synergy_id)
