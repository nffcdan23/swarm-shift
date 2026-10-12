class_name RunBuild
extends RefCounted
## What the player has assembled this run - weapons, passives, augments and any
## synergies those unlocked - reduced to one flat table of modifiers.
##
## Every source of power speaks the same language, a dictionary of
## `key -> amount`:
##   "damage_pct": 0.12          +12% to the `damage` player stat
##   "max_hp": 20                +20 flat to `max_hp`
##   "w.pulse.projectiles": 1    +1 projectile on the Pulse Cannon only
##   "fx.volatile": 1            switches a special effect on
## Meta upgrades, the chosen core, in-run passives, augments and synergies are
## all just summed into `mods`, so new content is data, not code.

var weapons: Dictionary = {}
var weapon_order: Array[String] = []
var passives: Dictionary = {}
var passive_order: Array[String] = []
var augments: Array[String] = []
var synergies: Array[String] = []
var mods: Dictionary = {}

var _data: GameData
var _base_mods: Dictionary


func _init(data: GameData, base_mods: Dictionary) -> void:
	_data = data
	_base_mods = base_mods
	recompute()


func recompute() -> void:
	mods = _base_mods.duplicate()
	for passive_id in passive_order:
		_add_mods(GameData.dict(GameData.dict(_data.passives(), passive_id), "mods"), float(passives[passive_id]))
	for augment_id in augments:
		_add_mods(GameData.dict(GameData.dict(_data.augments(), augment_id), "mods"), 1.0)
	for synergy_id in synergies:
		_add_mods(GameData.dict(GameData.dict(_data.synergies(), synergy_id), "mods"), 1.0)


func _add_mods(source: Dictionary, times: float) -> void:
	for key: String in source:
		mods[key] = float(mods.get(key, 0.0)) + float(source[key]) * times


func mod(key: String, fallback: float = 0.0) -> float:
	return float(mods.get(key, fallback))


func enabled(key: String) -> bool:
	return float(mods.get(key, 0.0)) > 0.0


## Final value of a player stat: (base + flat) * (1 + percent).
func player_stat(stat: String, base: float) -> float:
	return (base + mod(stat)) * maxf(1.0 + mod(stat + "_pct"), 0.05)


func weapon_level(weapon_id: String) -> int:
	return int(weapons.get(weapon_id, 0))


func passive_level(passive_id: String) -> int:
	return int(passives.get(passive_id, 0))


func set_weapon(weapon_id: String, level: int) -> void:
	if not weapons.has(weapon_id):
		weapon_order.append(weapon_id)
	weapons[weapon_id] = level


func set_passive(passive_id: String, level: int) -> void:
	if not passives.has(passive_id):
		passive_order.append(passive_id)
	passives[passive_id] = level


func add_augment(augment_id: String) -> void:
	if not augments.has(augment_id):
		augments.append(augment_id)


## True if the build holds the thing named by a requirement token.
func has(token: String) -> bool:
	var parts := token.split(":")
	if parts.size() != 2:
		return false
	match parts[0]:
		"w": return weapons.has(parts[1])
		"p": return passives.has(parts[1])
		"a": return augments.has(parts[1])
	return false


## Activates any synergy whose requirements are now all met. Returns the ids
## that switched on with this call.
func refresh_synergies() -> Array[String]:
	var fresh: Array[String] = []
	var table := _data.synergies()
	for synergy_id: String in table:
		if synergies.has(synergy_id):
			continue
		var met := true
		for token: String in GameData.list(table[synergy_id], "requires"):
			if not has(token):
				met = false
				break
		if met:
			synergies.append(synergy_id)
			fresh.append(synergy_id)
	if not fresh.is_empty():
		recompute()
	return fresh
