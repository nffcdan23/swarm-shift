class_name Director
extends RefCounted
## Paces the run. Reads the timeline in stages.json: continuous spawn tracks
## (enemies per second, keyframed over time), scripted events and the boss.
##
## Difficulty comes from four places:
##   - the timeline's own curves (more enemies, tougher, and later faster);
##   - which tracks and events the sector has unlocked (`min_sector`) - new
##     enemy types and set pieces, not just bigger numbers;
##   - the sector's mutators (CampaignService.mutator_effects);
##   - the tier scaling, and in Endless the cycle count.
##
## Set pieces: `surge` (a closing ring), `elite`, `pack` (one tight group from
## one side), `pincer` (two walls from opposite sides), `line` (ranged enemies
## spread along one edge) and `bombard` (telegraphed blast zones around the
## player). Every one of them is announced, and nothing spawns on top of the
## player or hurts without a visible warning.

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
var _gate := 1
var _mutators: Dictionary = {}
var _repeating: Array[Dictionary] = []
var _speed_curve: Array = []
var _bombard_cfg: Dictionary = {}
var _bombard_left := 0
var _bombard_timer := 0.0
var _bombard_first := false

## Events the director will fire at most in one step, however far time jumped.
const MAX_EVENTS_PER_STEP := 6


func setup(arena: Arena) -> void:
	_a = arena
	_timeline = GameData.dict(arena.data.stages, "timeline")
	_boss_time = GameData.num(_timeline, "boss_time", 300.0)
	_boss_warning = GameData.num(_timeline, "boss_warning", 6.0)
	_max_enemies = arena.max_enemy_count()
	_speed_curve = GameData.list(_timeline, "speed_curve")
	_bombard_cfg = GameData.dict(_timeline, "bombard")
	# Overdrive is only reachable after the sectors that introduce everything.
	_gate = 999 if arena.config.mode == CampaignService.MODE_ENDLESS else arena.config.tier
	for event: Dictionary in GameData.list(_timeline, "events"):
		if _in_sector(event):
			_events.append(event)
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	_affix_ids = GameData.dict(GameData.dict(arena.data.enemies, "elite"), "affixes").keys()
	for track: Dictionary in GameData.list(_timeline, "tracks"):
		if not _in_sector(track):
			continue
		_tracks.append({"type": arena.enemies.type_of(GameData.text(track, "enemy")), "enemy": GameData.text(track, "enemy"),
			"rate": GameData.list(track, "rate"), "acc": 0.0, "mult": 1.0})
	_rescale()


func _in_sector(entry: Dictionary) -> bool:
	return _gate >= GameData.integer(entry, "min_sector", 1) and _gate <= GameData.integer(entry, "max_sector", 100000)


## Mutators in force right now (ids), for the HUD and tests.
func mutator_ids() -> Array[String]:
	return _a.app.campaign.mutator_ids(_a.config.mode, _a.config.tier, cycle)


func _rescale() -> void:
	var per_cycle := GameData.num(GameData.dict(_a.data.stages, "scaling"), "endless_cycle_tiers", 2.0)
	_scale = _a.app.campaign.scaling(effective_tier(per_cycle))
	_mutators = _a.app.campaign.mutator_effects(mutator_ids())
	var track_mults: Dictionary = _mutators.tracks
	for track in _tracks:
		track.mult = float(track_mults.get(str(track.enemy), 1.0))
	_repeating.clear()
	for every: Dictionary in _mutators.every:
		var seconds := maxf(GameData.num(every, "seconds", 30.0), 5.0)
		_repeating.append({"seconds": seconds, "next": GameData.num(every, "from", seconds), "event": GameData.dict(every, "event")})


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


## Tools and tests only: holds the timeline still - no spawns, no events, no
## boss - while the enemy scaling above stays in force.
var paused := false


func update(dt: float) -> void:
	var enemies := _a.enemies
	var t := timeline_time
	enemies.hp_mult = GameData.curve(GameData.list(_timeline, "hp_curve"), t) * float(_scale.hp) * float(_mutators.hp)
	enemies.damage_mult = GameData.curve(GameData.list(_timeline, "damage_curve"), t) * float(_scale.damage)
	var late_speed := GameData.curve(_speed_curve, t) if not _speed_curve.is_empty() else 1.0
	enemies.speed_mult = float(_scale.speed) * late_speed * float(_mutators.speed)
	if paused:
		return
	_update_bombardment(dt)
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

	var fired := 0
	while _next_event < _events.size() and t >= float(_events[_next_event].t) and fired < MAX_EVENTS_PER_STEP:
		_fire(_events[_next_event])
		_next_event += 1
		fired += 1
	for entry in _repeating:
		# Mutator set pieces stop a little before the boss so its entrance is clean.
		if t >= float(entry.next) and t < _boss_time - 12.0 and fired < MAX_EVENTS_PER_STEP:
			entry.next = maxf(float(entry.next) + float(entry.seconds), t)
			_fire(entry.event)
			fired += 1

	var room := _max_enemies - enemies.count
	var spawn_scale := float(_scale.spawn) * float(_mutators.spawn)
	# Ease off as the field fills so the cap is approached, not slammed into.
	@warning_ignore("integer_division")
	if room < _max_enemies / 6:
		spawn_scale *= 0.5
	for track in _tracks:
		var acc := float(track.acc) + GameData.curve(track.rate, t) * float(track.mult) * spawn_scale * dt
		# However large the rate or the step, one track adds a bounded number.
		var budget := 24
		while acc >= 1.0 and budget > 0:
			acc -= 1.0
			budget -= 1
			if room > 0:
				var at := spawn_point()
				if enemies.spawn(int(track.type), at.x, at.y) >= 0:
					spawned_total += 1
					room -= 1
		track.acc = minf(acc, 1.0)


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
		"pack":
			# One tight group from one side: a wedge to sidestep, not a ring.
			var at := spawn_point()
			enemies.queue_spawn(GameData.text(event, "enemy"), at.x, at.y, GameData.integer(event, "count", 5), 90.0)
			spawned_total += GameData.integer(event, "count", 5)
			_announce_event(event, "PACK INBOUND")
		"pincer":
			# Two walls closing from opposite sides; the way out is across.
			var type_idx := enemies.type_of(GameData.text(event, "enemy"))
			var total := GameData.integer(event, "count", 30)
			var side := _a.rng.randf()
			for k in total:
				var along := lerpf(-0.085, 0.085, float(k >> 1) / float(maxi((total >> 1) - 1, 1)))
				var at := _edge_point(side + (0.5 if (k & 1) == 1 else 0.0) + along)
				if enemies.spawn(type_idx, at.x, at.y) >= 0:
					spawned_total += 1
			_announce_event(event, "PINCER")
		"line":
			# Ranged enemies spread along one edge: a firing line to break.
			var type_idx := enemies.type_of(GameData.text(event, "enemy"))
			var total := GameData.integer(event, "count", 5)
			var side := _a.rng.randf()
			for k in total:
				var at := _edge_point(side + (float(k) - float(total - 1) * 0.5) * 0.035)
				if enemies.spawn(type_idx, at.x, at.y) >= 0:
					spawned_total += 1
			_announce_event(event, "FIRING LINE")
		"bombard":
			_bombard_left = mini(_bombard_left + GameData.integer(event, "count", 5), 16)
			_bombard_timer = 0.6
			_bombard_first = true
			_announce_event(event, "BOMBARDMENT")
		"elite":
			var at := spawn_point()
			var affix: String = _affix_ids[_a.rng.randi_range(0, _affix_ids.size() - 1)] if not _affix_ids.is_empty() else ""
			if not str(_mutators.elite_affix).is_empty() and _affix_ids.has(str(_mutators.elite_affix)):
				affix = str(_mutators.elite_affix)
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


func _announce_event(event: Dictionary, fallback: String) -> void:
	var label := GameData.text(event, "label", fallback)
	if label.is_empty():
		return
	_a.announce(label, "warning")
	_a.sfx("surge")
	_a.haptic("warning")


## Shells land one after another around the player. Each is a hazard zone, so
## each shows its full blast circle for the whole fuse before it goes off; the
## first is aimed where the player is heading and the rest are scattered, which
## leaves gaps to move through rather than a wall.
func _update_bombardment(dt: float) -> void:
	if _bombard_left <= 0:
		return
	_bombard_timer -= dt
	if _bombard_timer > 0.0:
		return
	_bombard_timer = GameData.num(_bombard_cfg, "interval", 0.4)
	_bombard_left -= 1
	var player := _a.player
	var rng := _a.rng
	var at := Vector2(player.x, player.y)
	if _bombard_first:
		_bombard_first = false
		at += player.velocity * 0.3
	else:
		var angle := rng.randf() * TAU
		at += Vector2.from_angle(angle) * sqrt(rng.randf()) * GameData.num(_bombard_cfg, "spread", 250.0)
	_a.hazards.add(at.x, at.y, GameData.num(_bombard_cfg, "radius", 84.0), GameData.num(_bombard_cfg, "delay", 1.25),
		GameData.num(_bombard_cfg, "damage", 20.0) * _a.enemies.damage_mult, Color(1.0, 0.55, 0.3), at.x, at.y - 900.0)


## True while shells are still due to land.
func bombarding() -> bool:
	return _bombard_left > 0


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
	_bombard_left = 0
	for track in _tracks:
		track.acc = 0.0
	_rescale()


func reward_scale() -> Dictionary:
	return _scale
