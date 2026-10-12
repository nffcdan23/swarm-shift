class_name Weapon
extends RefCounted
## Base class for an auto-firing weapon. A weapon is a data block in
## weapons.json plus a small script that overrides `update()`.
##
## Stats are resolved as (base + flat) * (1 + percent), where the adds come
## from the weapon's own level-ups and from any build modifier addressed to it
## ("w.<id>.<stat>"). Subclasses read the result once in `_on_stats()` and keep
## it in typed fields, so the per-step code does no dictionary lookups.
##
## To add a weapon: add its block to weapons.json and drop a script with the
## matching name in this folder. Nothing else needs to know about it.

var id := ""
var level := 1
var def: Dictionary = {}
var color := Color.WHITE
## Interned damage-source id, for the per-weapon damage breakdown.
var src := 0

var _a: Arena
var _stats: Dictionary = {}
var _cd := 0.0
var _is_projectile := false


func setup(arena: Arena, weapon_id: String) -> void:
	_a = arena
	id = weapon_id
	def = arena.data.weapon(weapon_id)
	color = GameData.color(def, "color", Color.WHITE)
	src = arena.combat.source(weapon_id)
	_is_projectile = GameData.list(def, "tags").has("projectile")
	_on_setup()
	refresh()


func set_level(new_level: int) -> void:
	level = new_level
	refresh()


## Recomputes stats. Called on level-up and whenever the build changes.
func refresh() -> void:
	var adds: Dictionary = {}
	var pcts: Dictionary = {}
	var levels := GameData.list(def, "levels")
	for li in mini(level, levels.size()):
		var entry: Dictionary = levels[li]
		_route(GameData.dict(entry, "mods"), "", adds, pcts)
	_route(_a.build.mods, "w.%s." % id, adds, pcts)
	var base := GameData.dict(def, "base")
	for key: String in base:
		_stats[key] = (float(base[key]) + float(adds.get(key, 0.0))) * maxf(1.0 + float(pcts.get(key, 0.0)), 0.1)
	_on_stats()


func _route(mods: Dictionary, prefix: String, adds: Dictionary, pcts: Dictionary) -> void:
	for key: String in mods:
		if not prefix.is_empty() and not key.begins_with(prefix):
			continue
		var stat_key := key.substr(prefix.length())
		if stat_key.begins_with("w.") or stat_key.begins_with("fx.") or stat_key.begins_with("run."):
			continue
		if stat_key.ends_with("_pct"):
			var target := stat_key.trim_suffix("_pct")
			pcts[target] = float(pcts.get(target, 0.0)) + float(mods[key])
		else:
			adds[stat_key] = float(adds.get(stat_key, 0.0)) + float(mods[key])


func stat(key: String, fallback: float = 0.0) -> float:
	return float(_stats.get(key, fallback))


## Seconds between shots after the player's fire-rate bonus.
func cooldown_time(base: float) -> float:
	return maxf(base / maxf(_a.player.fire_rate, 0.1), 0.04)


## Projectile count including the player's +projectile bonus, where it applies.
func shot_count(base: float) -> int:
	return int(base) + (_a.player.extra_projectiles if _is_projectile else 0)


## Fires one ordinary bullet, picking up whatever augments add to bullets.
func fire_bullet(x: float, y: float, angle: float, dmg: float, speed: float, reach: float, radius: float,
		sprite_cell: float, sprite_size: float, pierce: int, kb: float) -> void:
	var player := _a.player
	var v := speed * player.projectile_speed
	var combat := _a.combat
	_a.projectiles.spawn(x, y, cos(angle) * v, sin(angle) * v, dmg, reach / maxf(v, 1.0), radius * player.area,
		sprite_cell, sprite_size * player.area, color, pierce, combat.projectile_flags(), kb, src,
		combat.explosive_radius * player.area)


## Best thing to shoot from a point: the closest living enemy in range.
func acquire(x: float, y: float, reach: float) -> int:
	var enemies := _a.enemies
	var near := enemies.nearest_idx
	# The enemy loop already found the one closest to the player this step.
	if x == _a.player.x and y == _a.player.y and near >= 0 and near < enemies.count and enemies.hp[near] > 0.0:
		return near if enemies.nearest_dist <= reach else -1
	return enemies.nearest(x, y, reach)


# ------------------------------------------------------------------- virtuals

func _on_setup() -> void:
	pass


func _on_stats() -> void:
	pass


func update(_dt: float) -> void:
	pass


## Drop any persistent objects (mines, black holes) - the run is ending.
func clear() -> void:
	pass
