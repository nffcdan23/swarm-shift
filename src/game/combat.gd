class_name Combat
extends RefCounted
## Damage resolution and everything that chains off a hit or a kill.
##
## Weapons never touch enemy health directly: they call `hit()` (one target) or
## `blast()` (area). That keeps crits, bonus-damage rules, damage numbers,
## statistics and the augment triggers (explosions on death, lightning on crit,
## shatter, barrages...) in one place.
##
## Area effects are queued and resolved in `flush()` rather than applied at
## once. That is what makes chain reactions safe: an explosion that kills ten
## enemies whose deaths each cause an explosion simply adds ten entries to the
## queue. A per-step cap turns a huge chain into a wave that visibly rolls
## across the swarm instead of a one-frame spike.

const MAX_BLASTS_PER_STEP := 16
## Headroom, on top of one explosion per enemy that can exist, before the
## queue refuses more. A chain adds at most one per kill, so a whole field
## dying at once still fits; the limit is a backstop that turns a runaway (a
## bad data edit, a future weapon) into dropped effects instead of a hang.
const BLAST_QUEUE_HEADROOM := 256

var total_damage := 0.0
## Area hits resolved so far (tests use it to check the per-step budget).
var blasts_resolved := 0
## Longest the explosion queue may get. Set by the arena from the enemy cap.
var max_queued_blasts := 512 + BLAST_QUEUE_HEADROOM
var kills := 0
var elites_killed := 0
var bosses_killed := 0

var source_names: Array[String] = []
var damage_by_source := PackedFloat32Array()

# Effect switches and parameters, cached from the build by `refresh()`.
var seeker_turn := 0.0
var explosive_pct := 0.0
var explosive_radius := 0.0
var split_pct := 0.55

var _a: Arena
var _blasts: Array[Dictionary] = []
var _arcs: Array[Vector3] = []
var _bonus_projectile_flags := 0

var _volatile := false
var _volatile_damage := 0.0
var _volatile_radius := 0.0
var _volatile_chill := false
var _storm := false
var _storm_damage := 0.0
var _storm_arcs := 0
var _storm_cooldown := 0.12
var _storm_ready_at := 0.0
var _shatter := false
var _shatter_shards := 0
var _shatter_damage := 0.0
var _chilled_bonus := 0.0
var _barrage := false
var _barrage_every := 40
var _barrage_count := 6
var _barrage_damage := 0.0
var _barrage_radius := 74.0
var _barrage_progress := 0
var _siphon := false
var _siphon_every := 12
var _siphon_progress := 0

var _src_volatile := 0
var _src_storm := 0
var _src_shatter := 0
var _src_barrage := 0
var _src_other := 0

var _drop_cfg: Dictionary
var _drop_ready: Dictionary = {}
var _elite_cfg: Dictionary
var _bomb_damage := 400.0
var _bomb_radius := 620.0
var _shard_cell := 0.0
var _missile_cell := 0.0

const C_VOLATILE := Color(1.0, 0.55, 0.2)
const C_STORM := Color(0.73, 0.65, 1.0)
const C_ICE := Color(0.56, 0.85, 1.0)
const C_BARRAGE := Color(1.0, 0.42, 0.3)


func setup(arena: Arena) -> void:
	_a = arena
	_src_other = source("other")
	_src_volatile = source("volatile")
	_src_storm = source("storm_crit")
	_src_shatter = source("shatter")
	_src_barrage = source("barrage")
	var pickups := GameData.dict(arena.data.game, "pickups")
	_drop_cfg = GameData.dict(pickups, "special_drops")
	_bomb_damage = GameData.num(pickups, "bomb_damage", 400.0)
	_bomb_radius = GameData.num(pickups, "bomb_radius", 620.0)
	_elite_cfg = GameData.dict(arena.data.enemies, "elite")
	_shard_cell = arena.gfx.cell("shard")
	_missile_cell = arena.gfx.cell("missile")


## Interns a damage source name; the id is used for per-weapon damage totals.
func source(source_name: String) -> int:
	var existing := source_names.find(source_name)
	if existing >= 0:
		return existing
	source_names.append(source_name)
	damage_by_source.append(0.0)
	return source_names.size() - 1


## Re-reads effect switches after the build changes.
func refresh() -> void:
	var b := _a.build
	_volatile = b.enabled("fx.volatile")
	_volatile_damage = b.mod("fx.volatile_damage")
	_volatile_radius = b.mod("fx.volatile_radius") * (1.0 + b.mod("fx.volatile_radius_pct"))
	_volatile_chill = b.enabled("fx.volatile_chill")
	_storm = b.enabled("fx.storm")
	_storm_damage = b.mod("fx.storm_damage")
	_storm_arcs = int(b.mod("fx.storm_arcs"))
	_storm_cooldown = b.mod("fx.storm_cooldown", 0.12)
	_shatter = b.enabled("fx.shatter")
	_shatter_shards = int(b.mod("fx.shatter_shards"))
	_shatter_damage = b.mod("fx.shatter_damage")
	_chilled_bonus = b.mod("fx.chilled_damage_pct")
	_barrage = b.enabled("fx.barrage")
	_barrage_every = maxi(int(b.mod("fx.barrage_kills", 40.0)), 1)
	_barrage_count = int(b.mod("fx.barrage_count", 6.0))
	_barrage_damage = b.mod("fx.barrage_damage")
	_barrage_radius = b.mod("fx.barrage_radius", 74.0)
	_siphon = b.enabled("fx.siphon")
	_siphon_every = maxi(int(b.mod("fx.siphon_kills", 12.0)), 1)
	seeker_turn = b.mod("fx.seeker_turn")
	explosive_pct = b.mod("fx.explosive_damage_pct")
	explosive_radius = b.mod("fx.explosive_radius")
	split_pct = b.mod("fx.split_damage_pct", 0.55)
	_bonus_projectile_flags = 0
	if b.enabled("fx.seeker"):
		_bonus_projectile_flags |= ProjectileSystem.F_SEEK
	if b.enabled("fx.explosive"):
		_bonus_projectile_flags |= ProjectileSystem.F_EXPLODE
	if b.enabled("fx.split"):
		_bonus_projectile_flags |= ProjectileSystem.F_SPLIT


## Flags that augments add to ordinary bullets (seeking, exploding, splitting).
func projectile_flags() -> int:
	return _bonus_projectile_flags


# ----------------------------------------------------------------------- hits

## One target, one hit. `base_damage` is the weapon's own number; player
## multipliers and crits are applied here. Returns true on a kill.
func hit(i: int, base_damage: float, src: int, kb_x: float = 0.0, kb_y: float = 0.0, can_crit: bool = true) -> bool:
	var a := _a
	var enemies := a.enemies
	if enemies.hp[i] <= 0.0:
		return false
	var player := a.player
	var dmg := base_damage * player.damage
	var crit := can_crit and a.rng.randf() < player.crit_chance
	if crit:
		dmg *= player.crit_mult
	if _chilled_bonus > 0.0 and enemies.is_cold(i):
		dmg *= 1.0 + _chilled_bonus
	var ex := enemies.x[i]
	var ey := enemies.y[i]
	var top := ey - enemies.radius[i]
	var killed := enemies.hurt(i, dmg, kb_x, kb_y)
	total_damage += dmg
	damage_by_source[src] += dmg
	a.fx.number(ex, top, dmg, crit)
	if not killed:
		a.sfx("enemy_hit")
	if crit and _storm and a.time >= _storm_ready_at:
		_storm_ready_at = a.time + _storm_cooldown
		_arcs.append(Vector3(ex, ey, float(enemies.id[i])))
	return killed


## Queues an area hit. Resolved in `flush()`.
func blast(x: float, y: float, radius: float, base_damage: float, src: int, color: Color,
		kb: float = 140.0, chill_time: float = 0.0, can_crit: bool = false) -> void:
	if radius <= 0.0 or not (is_finite(x) and is_finite(y) and is_finite(radius)):
		return
	if _blasts.size() >= max_queued_blasts:
		_a.diag.blasts_dropped += 1
		return
	_blasts.append({"x": x, "y": y, "r": radius, "dmg": base_damage, "src": src, "color": color,
		"kb": kb, "chill": chill_time, "crit": can_crit})
	if _blasts.size() > _a.diag.blast_queue_peak:
		_a.diag.blast_queue_peak = _blasts.size()


func flush() -> void:
	var a := _a
	var enemies := a.enemies
	var processed := 0
	# New blasts may be appended while this loop runs; that is the chain.
	while processed < _blasts.size() and processed < MAX_BLASTS_PER_STEP:
		var b := _blasts[processed]
		processed += 1
		var bx := float(b.x)
		var by := float(b.y)
		var r := float(b.r)
		var color: Color = b.color
		a.fx.explosion(bx, by, r, color)
		a.sfx("explosion_l" if r > 150.0 else ("explosion_m" if r > 75.0 else "explosion_s"))
		var found := enemies.overlap(bx, by, r)
		var kb := float(b.kb)
		var chill_time := float(b.chill)
		for h in found:
			var e := enemies.hits[h]
			var dx := enemies.x[e] - bx
			var dy := enemies.y[e] - by
			var d := sqrt(dx * dx + dy * dy) + 0.001
			if chill_time > 0.0:
				enemies.apply_cold(e, chill_time)
			hit(e, float(b.dmg), int(b.src), dx / d * kb, dy / d * kb, bool(b.crit))
	blasts_resolved += processed
	if processed >= _blasts.size():
		_blasts.clear()
	else:
		_blasts = _blasts.slice(processed)

	if not _arcs.is_empty():
		for arc in _arcs:
			_resolve_storm(arc.x, arc.y, int(arc.z))
		_arcs.clear()


func _resolve_storm(x: float, y: float, from_id: int) -> void:
	var enemies := _a.enemies
	var found := enemies.overlap(x, y, 230.0)
	var struck := 0
	# Copy first: hitting can kill, and kills must not disturb this list.
	var targets := PackedInt32Array()
	for h in found:
		var e := enemies.hits[h]
		if enemies.id[e] != from_id:
			targets.append(e)
			if targets.size() >= _storm_arcs:
				break
	for e in targets:
		_a.fx.lightning(x, y, enemies.x[e], enemies.y[e], C_STORM, 9.0)
		hit(e, _storm_damage, _src_storm, 0.0, 0.0, false)
		struck += 1
	if struck > 0:
		_a.sfx("lightning")


# ---------------------------------------------------------------------- kills

## Called by EnemySystem the moment an enemy's health reaches zero. Its data is
## still in the arrays. Must not start an overlap query (see EnemySystem).
func on_enemy_killed(i: int) -> void:
	var a := _a
	var enemies := a.enemies
	var f := enemies.flags[i]
	var ex := enemies.x[i]
	var ey := enemies.y[i]
	var r := enemies.radius[i]
	var type_idx := enemies.type[i]
	var def := enemies.type_defs[type_idx]
	var color := enemies.type_colors[type_idx]
	kills += 1

	if (f & EnemySystem.F_BOSS) != 0:
		bosses_killed += 1
		a.on_boss_killed(ex, ey)
		return

	var elite := (f & EnemySystem.F_ELITE) != 0
	a.fx.death(ex, ey, Color(1.0, 0.85, 0.4) if elite else color, r)
	if elite:
		elites_killed += 1
		a.sfx("elite_die")
		a.fx.shake(0.3)
		a.haptic("heavy")
		a.fx.explosion(ex, ey, r * 3.0, Color(1.0, 0.85, 0.4))
	else:
		a.sfx("enemy_die")
		if r > 24.0:
			a.fx.shake(0.07)

	if (f & EnemySystem.F_NO_DROPS) == 0:
		_drops(i, ex, ey, def, elite)

	var split := GameData.dict(def, "split")
	if not split.is_empty():
		enemies.queue_spawn(GameData.text(split, "into"), ex, ey, GameData.integer(split, "count", 2), r)

	if (f & EnemySystem.F_VOLATILE) != 0:
		var vol := GameData.dict(GameData.dict(_elite_cfg, "affixes"), "volatile")
		a.hazards.add(ex, ey, GameData.num(vol, "death_blast_radius", 130.0), GameData.num(vol, "death_blast_delay", 0.9),
			GameData.num(vol, "death_blast_damage", 26.0) * enemies.damage_mult, Color(1.0, 0.45, 0.2))

	if _volatile:
		blast(ex, ey, _volatile_radius * a.player.area, _volatile_damage, _src_volatile, C_VOLATILE, 110.0,
			1.6 if _volatile_chill else 0.0)
	if _shatter and enemies.is_cold(i):
		_shatter_burst(ex, ey)
	if _barrage:
		_barrage_progress += 1
		if _barrage_progress >= _barrage_every:
			_barrage_progress = 0
			launch_barrage()
	if _siphon:
		_siphon_progress += 1
		if _siphon_progress >= _siphon_every:
			_siphon_progress = 0
			a.player.heal(1.0)


func _drops(i: int, ex: float, ey: float, def: Dictionary, elite: bool) -> void:
	var a := _a
	var luck := 1.0 + a.player.luck
	a.pickups.drop_xp(ex, ey, a.enemies.xp[i])
	if elite:
		a.pickups.drop(PickupSystem.KIND_CACHE, ex, ey)
		a.pickups.drop(PickupSystem.KIND_CREDIT, ex, ey, GameData.num(_elite_cfg, "credit_value", 25.0))
		return
	if a.rng.randf() < GameData.num(def, "credit_chance", 0.0) * luck:
		a.pickups.drop(PickupSystem.KIND_CREDIT, ex, ey, GameData.num(def, "credit_value", 1.0))
	# Rare helpers, each on its own minimum-interval timer so luck never floods.
	for drop_name: String in _drop_cfg:
		var cfg: Dictionary = _drop_cfg[drop_name]
		if a.time < float(_drop_ready.get(drop_name, 0.0)):
			continue
		if a.rng.randf() < GameData.num(cfg, "chance", 0.0) * luck:
			_drop_ready[drop_name] = a.time + GameData.num(cfg, "min_interval", 30.0)
			match drop_name:
				"repair": a.pickups.drop(PickupSystem.KIND_REPAIR, ex, ey)
				"magnet": a.pickups.drop(PickupSystem.KIND_MAGNET, ex, ey)
				"bomb": a.pickups.drop(PickupSystem.KIND_BOMB, ex, ey)


func _shatter_burst(x: float, y: float) -> void:
	var a := _a
	var offset := a.rng.randf() * TAU
	for k in _shatter_shards:
		var angle := offset + TAU * float(k) / float(_shatter_shards)
		a.projectiles.spawn(x, y, cos(angle) * 520.0, sin(angle) * 520.0, _shatter_damage, 0.42, 9.0,
			_shard_cell, 44.0, C_ICE, 1, ProjectileSystem.F_NO_CRIT, 60.0, _src_shatter)
	a.sfx("shatter")


func launch_barrage() -> void:
	var a := _a
	var player := a.player
	var offset := a.rng.randf() * TAU
	for k in _barrage_count:
		var angle := offset + TAU * float(k) / float(_barrage_count)
		launch_missile(player.x, player.y, angle, _barrage_damage, _barrage_radius * player.area, _src_barrage, C_BARRAGE)
	a.sfx("shoot_missile")
	a.fx.shockwave(player.x, player.y, 90.0, C_BARRAGE)


func launch_missile(x: float, y: float, angle: float, dmg: float, blast_radius: float, src: int, color: Color,
		speed: float = 420.0, turn_rate: float = 7.0, lifetime: float = 3.0) -> void:
	_a.projectiles.spawn(x + cos(angle) * 20.0, y + sin(angle) * 20.0, cos(angle) * speed, sin(angle) * speed,
		dmg, lifetime, 10.0, _missile_cell, 46.0, color, 0,
		ProjectileSystem.F_HOMING | ProjectileSystem.F_EXPLODE | ProjectileSystem.F_BLAST_ONLY | ProjectileSystem.F_TRAIL,
		170.0, src, blast_radius, turn_rate)


## The bomb pickup: one enormous blast centred on the player.
func detonate_bomb() -> void:
	var a := _a
	var player := a.player
	blast(player.x, player.y, _bomb_radius, _bomb_damage / maxf(player.damage, 0.01), _src_other, Color(1.0, 0.7, 0.3), 380.0)
	a.bullets.clear_circle(player.x, player.y, _bomb_radius)
	a.fx.shake(0.7)
	a.haptic("heavy")


func pending_blasts() -> int:
	return _blasts.size()


func clear() -> void:
	_blasts.clear()
	_arcs.clear()
