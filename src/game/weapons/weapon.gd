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
##
## An evolved weapon (`evolve()`) adds its evolution's `mods` on top of the
## levels. They may name stats the base table lacks, which is how an evolution
## switches on behaviour in the script: `stat("blast_radius", 0.0)`.

const MASTER_FINISH := Color("ffd98a")

var id := ""
var level := 1
var def: Dictionary = {}
## The path taken at the final level ("" until then).
var evolution := ""
var color := Color.WHITE
## Interned damage-source id, for the per-weapon damage breakdown.
var src := 0

var _a: Arena
var _stats: Dictionary = {}
var _evolution_mods: Dictionary = {}
var _cd := 0.0
var _is_projectile := false


func setup(arena: Arena, weapon_id: String) -> void:
	_a = arena
	id = weapon_id
	def = arena.data.weapon(weapon_id)
	color = _themed(GameData.color(def, "color", Color.WHITE))
	src = arena.combat.source(weapon_id)
	_is_projectile = GameData.list(def, "tags").has("projectile")
	_on_setup()
	refresh()


func set_level(new_level: int) -> void:
	level = new_level
	refresh()


## A skin leans every weapon's colour towards its own, and a weapon at Master
## rank carries a gold finish over that. Looks, nothing else.
func _themed(base: Color) -> Color:
	var skin := _a.config.skin_def
	var themed := base
	if skin.has("weapon_tint"):
		themed = base.lerp(GameData.color(skin, "weapon_tint"), GameData.num(skin, "weapon_tint_amount", 0.35))
	if _a.config.mastered.has(id):
		themed = themed.lerp(MASTER_FINISH, 0.35)
	return themed


func evolve(path: String) -> void:
	evolution = path
	var entry := GameData.dict(GameData.dict(def, "evolutions"), path)
	_evolution_mods = GameData.dict(entry, "mods")
	color = _themed(GameData.color(entry, "color", color))
	_on_evolved()
	refresh()


## Recomputes stats. Called on level-up and whenever the build changes.
func refresh() -> void:
	var adds: Dictionary = {}
	var pcts: Dictionary = {}
	var levels := GameData.list(def, "levels")
	for li in mini(level, levels.size()):
		var entry: Dictionary = levels[li]
		_route(GameData.dict(entry, "mods"), "", adds, pcts)
	_route(_evolution_mods, "", adds, pcts)
	_route(_a.build.mods, "w.%s." % id, adds, pcts)
	var base := GameData.dict(def, "base")
	for key: String in base:
		_stats[key] = (float(base[key]) + float(adds.get(key, 0.0))) * maxf(1.0 + float(pcts.get(key, 0.0)), 0.1)
	for key: String in adds:
		if not base.has(key):
			_stats[key] = float(adds[key]) * maxf(1.0 + float(pcts.get(key, 0.0)), 0.1)
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
##
## `flags` adds ProjectileSystem flags of the weapon's own. A shot with a
## `blast_radius` deals all its damage as a blast where it lands.
func fire_bullet(x: float, y: float, angle: float, dmg: float, speed: float, reach: float, radius: float,
		sprite_cell: float, sprite_size: float, pierce: int, kb: float, flags: int = 0, blast_radius: float = 0.0, turn_rate: float = 0.0) -> void:
	var player := _a.player
	var v := speed * player.projectile_speed
	var combat := _a.combat
	var blast := combat.explosive_radius
	var bits := combat.projectile_flags() | flags
	if blast_radius > 0.0:
		blast = blast_radius
		bits |= ProjectileSystem.F_EXPLODE | ProjectileSystem.F_BLAST_ONLY
	_a.projectiles.spawn(x, y, cos(angle) * v, sin(angle) * v, dmg, reach / maxf(v, 1.0), radius * player.area,
		sprite_cell, sprite_size * player.area, color, pierce + player.extra_pierce, bits, kb, src,
		blast * player.area, turn_rate)


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


## Called once when the weapon evolves, before its stats are recomputed.
func _on_evolved() -> void:
	pass


func update(_dt: float) -> void:
	pass


## Drop any persistent objects (mines, black holes) - the run is ending.
func clear() -> void:
	pass
