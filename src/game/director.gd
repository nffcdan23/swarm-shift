class_name Director
extends RefCounted
## Paces the run. Reads the timeline in stages.json: continuous spawn tracks
## (enemies per second, keyframed over time), scripted events (surges, elites)
## and the boss. Difficulty comes from three places multiplied together - the
## timeline's own curves, the sector tier, and in Endless the cycle count.

var timeline_time := 0.0
var cycle := 0
var boss_active := false
## Half extents of what the camera can see, in world units. Set by the arena.
var view_half := Vector2(420.0, 760.0)
var spawned_total := 0

var _a: Arena
var _timeline: Dictionary
var _scale: Dictionary = {}
var _tracks: Array[Dictionary] = []
var _events: Array = []
var _next_event := 0
var _boss_time := 300.0
var _boss_warning := 6.0
var _warned := false
var _max_enemies := 420
var _affix_ids: Array = []
var _margin := 70.0


func setup(arena: Arena) -> void:
	_a = arena
	_timeline = GameData.dict(arena.data.stages, "timeline")
	_boss_time = GameData.num(_timeline, "boss_time", 300.0)
	_boss_warning = GameData.num(_timeline, "boss_warning", 6.0)
	_max_enemies = GameData.integer(arena.data.run_cfg(), "max_enemies", 420)
	_events = GameData.list(_timeline, "events").duplicate()
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	_affix_ids = GameData.dict(GameData.dict(arena.data.enemies, "elite"), "affixes").keys()
	for track: Dictionary in GameData.list(_timeline, "tracks"):
		_tracks.append({"type": arena.enemies.type_of(GameData.text(track, "enemy")), "rate": GameData.list(track, "rate"), "acc": 0.0})
	_rescale()


func _rescale() -> void:
	var per_cycle := GameData.num(GameData.dict(_a.data.stages, "scaling"), "endless_cycle_tiers", 2.0)
	_scale = _a.app.campaign.scaling(effective_tier(per_cycle))


## Sector tier plus whatever Endless cycles have added.
func effective_tier(per_cycle: float = -1.0) -> float:
	if per_cycle < 0.0:
		per_cycle = GameData.num(GameData.dict(_a.data.stages, "scaling"), "endless_cycle_tiers", 2.0)
	return float(_a.config.tier) + float(cycle) * per_cycle


func boss_time() -> float:
	return _boss_time


## 0..1 progress towards the boss, for the HUD.
func progress() -> float:
	return clampf(timeline_time / _boss_time, 0.0, 1.0)


func update(dt: float) -> void:
	var enemies := _a.enemies
	var t := timeline_time
	enemies.hp_mult = GameData.curve(GameData.list(_timeline, "hp_curve"), t) * float(_scale.hp)
	enemies.damage_mult = GameData.curve(GameData.list(_timeline, "damage_curve"), t) * float(_scale.damage)
	enemies.speed_mult = float(_scale.speed)
	if boss_active:
		return
	timeline_time += dt
	t = timeline_time

	if not _warned and t >= _boss_time - _boss_warning:
		_warned = true
		_a.on_boss_warning()
	if t >= _boss_time:
		boss_active = true
		_a.spawn_boss(GameData.text(_timeline, "boss"), float(_scale.boss_hp), float(_scale.damage))
		return

	while _next_event < _events.size() and t >= float(_events[_next_event].t):
		_fire(_events[_next_event])
		_next_event += 1

	var room := _max_enemies - enemies.count
	var spawn_scale := float(_scale.spawn)
	# Ease off as the field fills so the cap is approached, not slammed into.
	if room < _max_enemies / 6:
		spawn_scale *= 0.5
	for track in _tracks:
		var acc := float(track.acc) + GameData.curve(track.rate, t) * spawn_scale * dt
		while acc >= 1.0:
			acc -= 1.0
			if room > 0:
				var at := spawn_point()
				if enemies.spawn(int(track.type), at.x, at.y) >= 0:
					spawned_total += 1
					room -= 1
		track.acc = acc


func _fire(event: Dictionary) -> void:
	var enemies := _a.enemies
	match GameData.text(event, "type"):
		"surge":
			var spawns := GameData.dict(event, "spawns")
			var total := 0
			for enemy_id: String in spawns:
				total += int(spawns[enemy_id])
			var placed := 0
			var offset := _a.rng.randf()
			# 1 puts the ring on the screen edge; less brings it inside the view
			# (the opening wave starts in sight so the action begins at once).
			var distance := GameData.num(event, "distance", 1.0)
			var origin := _centre()
			for enemy_id: String in spawns:
				var type_idx := enemies.type_of(enemy_id)
				for k in int(spawns[enemy_id]):
					# Evenly spaced around the screen edge: a closing ring.
					var at := origin + (_edge_point((float(placed) + offset) / float(maxi(total, 1))) - origin) * distance
					if enemies.spawn(type_idx, at.x, at.y) >= 0:
						spawned_total += 1
					placed += 1
			var label := GameData.text(event, "label", "SWARM SURGE")
			if not label.is_empty():
				_a.announce(label, "warning")
				_a.sfx("surge")
				_a.haptic("warning")
		"elite":
			var at := spawn_point()
			var affix: String = _affix_ids[_a.rng.randi_range(0, _affix_ids.size() - 1)] if not _affix_ids.is_empty() else ""
			var enemy_id := GameData.text(event, "enemy")
			if enemies.spawn(enemies.type_of(enemy_id), at.x, at.y, true, affix) >= 0:
				spawned_total += 1
			var escort := GameData.dict(event, "escort")
			for escort_id: String in escort:
				enemies.queue_spawn(escort_id, at.x, at.y, int(escort[escort_id]), 90.0)
			var affix_name := GameData.text(GameData.dict(GameData.dict(GameData.dict(_a.data.enemies, "elite"), "affixes"), affix), "name", "ELITE")
			var enemy_name := GameData.text(GameData.dict(_a.data.enemy_types(), enemy_id), "name", enemy_id).to_upper()
			_a.announce("ELITE  %s %s" % [affix_name, enemy_name], "elite")
			_a.sfx("surge")


## A point just outside the camera view. A third of the time it is placed
## ahead of the player's movement so running in a straight line is never safe.
func spawn_point() -> Vector2:
	var rng := _a.rng
	var velocity := _a.player.velocity
	if velocity.length_squared() > 2500.0 and rng.randf() < 0.35:
		return _edge_ray(velocity.angle() + rng.randf_range(-0.9, 0.9))
	return _edge_point(rng.randf())


## Point on the spawn rectangle at perimeter fraction `u` (0..1).
func _edge_point(u: float) -> Vector2:
	var half := view_half + Vector2(_margin, _margin)
	var w := half.x * 2.0
	var h := half.y * 2.0
	var d := fposmod(u, 1.0) * (w + h) * 2.0
	var local: Vector2
	if d < w:
		local = Vector2(-half.x + d, -half.y)
	elif d < w + h:
		local = Vector2(half.x, -half.y + (d - w))
	elif d < w * 2.0 + h:
		local = Vector2(half.x - (d - w - h), half.y)
	else:
		local = Vector2(-half.x, half.y - (d - w * 2.0 - h))
	return _centre() + local


## Where a ray from the screen centre at `angle` leaves the spawn rectangle.
func _edge_ray(angle: float) -> Vector2:
	var half := view_half + Vector2(_margin, _margin)
	var dir := Vector2(cos(angle), sin(angle))
	var tx := half.x / maxf(absf(dir.x), 0.0001)
	var ty := half.y / maxf(absf(dir.y), 0.0001)
	return _centre() + dir * minf(tx, ty)


func _centre() -> Vector2:
	return Vector2(_a.player.x, _a.player.y)


## Endless mode: the boss is dead, start the next and harder loop.
func begin_next_cycle() -> void:
	cycle += 1
	timeline_time = 0.0
	_next_event = 0
	_warned = false
	boss_active = false
	for track in _tracks:
		track.acc = 0.0
	_rescale()


func reward_scale() -> Dictionary:
	return _scale
