class_name Boss
extends Node2D
## The sector boss. It occupies one slot in the EnemySystem (so every weapon
## can hit it with no special cases) but its behaviour is driven from here: a
## small state machine cycling through attack patterns that get faster and more
## varied across three health phases.
##
## Every attack is telegraphed before it can hurt: lanes for charges and
## lasers, filling circles for ground blasts, slow readable bullets for bursts.

enum S { INACTIVE, INTRO, IDLE, BURST, CHARGE_AIM, CHARGE_RUN, CHARGE_REST, SUMMON, LASER_AIM, LASER_FIRE, ZONES, DYING }

const C_BODY := Color("ff3d6e")

var active := false
var display_name := ""
var enemy_id := -1
var x := 0.0
var y := 0.0
var centre := Vector2.ZERO
var arena_radius := 540.0
var phase := 0
var body_radius := 60.0

var _a: Arena
var _def: Dictionary
var _attacks: Dictionary
var _phases: Array = []
var _state := S.INACTIVE
var _timer := 0.0
var _queue: Array = []
var _idx := -1
var _damage_scale := 1.0
var _contact := 30.0
var _speed := 48.0

var _volleys_left := 0
var _burst_angle := 0.0
var _charge_dir := Vector2.RIGHT
var _charges_left := 0
var _charge_total := 0.0
var _laser_angle := 0.0
var _laser_dir := 1.0
var _laser_tick := 0.0
var _laser_beams := 3
var _zone_waves := 0
var _spin := 0.0
var _intro := 0.0

var _glow: Sprite2D
var _shell: Sprite2D
var _ring: Sprite2D
var _core: Sprite2D
var _core_material: ShaderMaterial
var _beam_cell := 0.0
var _sprite_scale := 0.45


func setup(arena: Arena) -> void:
	_a = arena
	_beam_cell = arena.gfx.cell("beam")
	visible = false
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/sprites/atlas/glow.png")
	_glow.material = additive
	_glow.modulate = Color(C_BODY.r, C_BODY.g, C_BODY.b, 0.5)
	add_child(_glow)
	_shell = Sprite2D.new()
	_shell.texture = load("res://assets/sprites/boss_shell.png")
	add_child(_shell)
	_ring = Sprite2D.new()
	_ring.texture = load("res://assets/sprites/boss_ring.png")
	add_child(_ring)
	_core = Sprite2D.new()
	_core.texture = load("res://assets/sprites/boss_core.png")
	_core_material = ShaderMaterial.new()
	_core_material.shader = load("res://assets/shaders/flash.gdshader")
	_core.material = _core_material
	add_child(_core)


func spawn(boss_id: String, at: Vector2, hp_scale: float, damage_scale: float) -> void:
	_def = GameData.dict(GameData.dict(_a.data.stages, "bosses"), boss_id)
	_attacks = GameData.dict(_def, "attacks")
	_phases = GameData.list(_def, "phases")
	display_name = GameData.text(_def, "name", "BOSS")
	body_radius = GameData.num(_def, "radius", 60.0)
	arena_radius = GameData.num(_def, "arena_radius", 540.0)
	_contact = GameData.num(_def, "contact_damage", 30.0) * damage_scale
	_speed = GameData.num(_def, "speed", 48.0)
	_damage_scale = damage_scale
	_sprite_scale = GameData.num(_def, "size", 230.0) / 512.0
	x = at.x
	y = at.y
	centre = at
	phase = 0
	var enemies := _a.enemies
	# Any type will do as the carrier; make_boss() overrides what matters.
	_idx = enemies.spawn(0, x, y)
	if _idx < 0:
		# Field is full: clear a slot for the boss rather than skip the fight.
		enemies.count -= 1
		_idx = enemies.spawn(0, x, y)
	enemies.make_boss(_idx, GameData.num(_def, "hp", 12000.0) * hp_scale, _contact, body_radius)
	enemies.xp[_idx] = GameData.num(_def, "xp", 150.0)
	enemy_id = enemies.id[_idx]
	active = true
	visible = true
	_state = S.INTRO
	_intro = 0.0
	_timer = 1.5
	_queue.clear()
	position = at


func hp_fraction() -> float:
	if not active:
		return 0.0
	var enemies := _a.enemies
	if not enemies.is_valid(_idx, enemy_id):
		_idx = enemies.find_id(enemy_id)
		if _idx < 0:
			return 0.0
	return clampf(enemies.hp[_idx] / maxf(enemies.max_hp[_idx], 1.0), 0.0, 1.0)


func update(dt: float) -> void:
	if not active:
		return
	if _state == S.DYING:
		_update_dying(dt)
		return
	var enemies := _a.enemies
	if not enemies.is_valid(_idx, enemy_id):
		_idx = enemies.find_id(enemy_id)
		if _idx < 0 or enemies.hp[_idx] <= 0.0:
			return
	var player := _a.player
	var fraction := enemies.hp[_idx] / maxf(enemies.max_hp[_idx], 1.0)
	_check_phase(fraction)
	var phase_cfg: Dictionary = _phases[phase] if phase < _phases.size() else {}
	enemies.damage[_idx] = _contact

	var to_player := Vector2(player.x - x, player.y - y)
	var dist := to_player.length() + 0.001
	var dir := to_player / dist
	_timer -= dt

	match _state:
		S.INTRO:
			_intro = minf(_intro + dt / 1.5, 1.0)
			if _timer <= 0.0:
				_state = S.IDLE
				_timer = 0.6
		S.IDLE:
			if dist > body_radius + 110.0:
				var speed := _speed * GameData.num(phase_cfg, "speed_mult", 1.0)
				x += dir.x * speed * dt
				y += dir.y * speed * dt
			if _timer <= 0.0:
				_begin_attack(phase_cfg)
		S.BURST:
			if _timer <= 0.0:
				_fire_volley()
				_volleys_left -= 1
				if _volleys_left > 0:
					_timer = GameData.num(GameData.dict(_attacks, "burst"), "interval", 0.6)
				else:
					_to_idle(phase_cfg)
		S.CHARGE_AIM:
			var cfg := GameData.dict(_attacks, "charge")
			var progress := 1.0 - _timer / maxf(_charge_total, 0.01)
			# Track the player for the first half, then commit.
			if progress < 0.55:
				_charge_dir = dir
			var reach := GameData.num(cfg, "speed", 760.0) * GameData.num(cfg, "duration", 0.7)
			_a.gfx.telegraphs.lane(x, y, x + _charge_dir.x * reach, y + _charge_dir.y * reach, body_radius * 2.0, C_BODY, clampf(progress, 0.0, 1.0))
			if _timer <= 0.0:
				_state = S.CHARGE_RUN
				_timer = GameData.num(cfg, "duration", 0.7)
				_a.sfx("boss_charge")
				_a.fx.shake(0.25)
		S.CHARGE_RUN:
			var cfg := GameData.dict(_attacks, "charge")
			var speed := GameData.num(cfg, "speed", 760.0)
			x += _charge_dir.x * speed * dt
			y += _charge_dir.y * speed * dt
			enemies.damage[_idx] = GameData.num(cfg, "damage", 34.0) * _damage_scale
			_a.gfx.particles.burst(x, y, 2, 40.0, 160.0, 0.25, 0.5, 26.0, 4.0, C_BODY, 3.0)
			var from_centre := Vector2(x, y) - centre
			var limit := arena_radius - body_radius
			var hit_wall := from_centre.length() > limit
			if hit_wall:
				var clamped := centre + from_centre.normalized() * limit
				x = clamped.x
				y = clamped.y
				_a.fx.explosion(x, y, 150.0, C_BODY, 1.6)
				_a.sfx("explosion_l")
			if _timer <= 0.0 or hit_wall:
				_state = S.CHARGE_REST
				_timer = GameData.num(cfg, "recover", 0.6)
		S.CHARGE_REST:
			if _timer <= 0.0:
				_charges_left -= 1
				if _charges_left > 0:
					_start_charge(0.72)
				else:
					_to_idle(phase_cfg)
		S.SUMMON:
			if _a.step_count % 4 == 0:
				_a.fx.ring(x, y, body_radius * 2.6, body_radius * 0.8, 0.3, C_BODY, 0.08)
			if _timer <= 0.0:
				_summon()
				_to_idle(phase_cfg)
		S.LASER_AIM:
			var cfg := GameData.dict(_attacks, "laser")
			var reach := GameData.num(cfg, "length", 640.0)
			var progress := 1.0 - _timer / maxf(GameData.num(cfg, "telegraph", 1.1), 0.01)
			for k in _laser_beams:
				var angle := _laser_angle + TAU * float(k) / float(_laser_beams)
				_a.gfx.telegraphs.lane(x, y, x + cos(angle) * reach, y + sin(angle) * reach, GameData.num(cfg, "width", 22.0) * 1.6, C_BODY, clampf(progress, 0.0, 1.0))
			if _timer <= 0.0:
				_state = S.LASER_FIRE
				_timer = GameData.num(cfg, "duration", 4.0)
				_laser_tick = 0.0
				_a.sfx("boss_laser")
		S.LASER_FIRE:
			_update_laser(dt)
			if _timer <= 0.0:
				_to_idle(phase_cfg)
		S.ZONES:
			if _timer <= 0.0:
				_drop_zones()
				_zone_waves -= 1
				if _zone_waves > 0:
					_timer = GameData.num(GameData.dict(_attacks, "zones"), "wave_interval", 0.9)
				else:
					_to_idle(phase_cfg)

	enemies.x[_idx] = x
	enemies.y[_idx] = y
	_draw_wall()
	_draw_body(dt, enemies.flash[_idx], fraction)


# -------------------------------------------------------------------- attacks

func _begin_attack(phase_cfg: Dictionary) -> void:
	if _queue.is_empty():
		_queue = GameData.list(phase_cfg, "attacks").duplicate()
		# Shuffle with the run's RNG so fights differ but replays do not.
		for i in range(_queue.size() - 1, 0, -1):
			var j := _a.rng.randi_range(0, i)
			var held: Variant = _queue[i]
			_queue[i] = _queue[j]
			_queue[j] = held
	if _queue.is_empty():
		_timer = 1.0
		return
	var attack: String = _queue.pop_back()
	match attack:
		"burst":
			_state = S.BURST
			_volleys_left = GameData.integer(GameData.dict(_attacks, "burst"), "volleys", 3)
			_burst_angle = _a.rng.randf() * TAU
			_timer = 0.35
		"charge":
			_charges_left = 1 + phase * GameData.integer(GameData.dict(_attacks, "charge"), "charges_per_phase", 1)
			_start_charge(1.0)
		"summon":
			_state = S.SUMMON
			_timer = GameData.num(GameData.dict(_attacks, "summon"), "cast_time", 0.8)
			_a.sfx("surge")
		"laser":
			var cfg := GameData.dict(_attacks, "laser")
			_state = S.LASER_AIM
			_laser_beams = GameData.integer(cfg, "beams", 3)
			_laser_angle = _a.rng.randf() * TAU
			_laser_dir = -_laser_dir
			_timer = GameData.num(cfg, "telegraph", 1.1)
		"zones":
			_state = S.ZONES
			_zone_waves = GameData.integer(GameData.dict(_attacks, "zones"), "waves", 2)
			_timer = 0.2
		_:
			_timer = 0.5


func _to_idle(phase_cfg: Dictionary) -> void:
	_state = S.IDLE
	_timer = GameData.num(phase_cfg, "idle", 1.2)


func _start_charge(telegraph_scale: float) -> void:
	_state = S.CHARGE_AIM
	_charge_total = GameData.num(GameData.dict(_attacks, "charge"), "telegraph", 0.95) * telegraph_scale
	_timer = _charge_total
	_a.sfx("dash_warn")


func _fire_volley() -> void:
	var cfg := GameData.dict(_attacks, "burst")
	var amount := GameData.integer(cfg, "bullets", 14) + phase * GameData.integer(cfg, "bullets_per_phase", 3)
	var speed := GameData.num(cfg, "bullet_speed", 205.0)
	var dmg := GameData.num(cfg, "damage", 14.0) * _damage_scale
	for k in amount:
		var angle := _burst_angle + TAU * float(k) / float(amount)
		_a.bullets.spawn(x + cos(angle) * body_radius, y + sin(angle) * body_radius, cos(angle) * speed, sin(angle) * speed, dmg)
	_burst_angle += GameData.num(cfg, "spin", 0.22)
	_a.fx.ring(x, y, body_radius, body_radius * 2.4, 0.25, C_BODY, 0.12)
	_a.sfx("enemy_shoot", 0.7)


func _summon() -> void:
	var cfg := GameData.dict(_attacks, "summon")
	var spawns := GameData.dict(cfg, "spawns")
	for enemy_id_key: String in spawns:
		var amount := int(spawns[enemy_id_key])
		if enemy_id_key == "swarmer":
			amount += phase * GameData.integer(cfg, "extra_per_phase", 4)
		_a.enemies.queue_spawn(enemy_id_key, x, y, amount, body_radius + 110.0)
	_a.fx.shockwave(x, y, body_radius + 150.0, C_BODY)
	_a.sfx("boss_spawn", 1.3)


func _update_laser(dt: float) -> void:
	var cfg := GameData.dict(_attacks, "laser")
	var reach := GameData.num(cfg, "length", 640.0)
	var width := GameData.num(cfg, "width", 22.0)
	var player := _a.player
	_laser_angle += GameData.num(cfg, "rot_speed", 0.5) * _laser_dir * (1.0 + 0.2 * float(phase)) * dt
	_laser_tick -= dt
	var bite := _laser_tick <= 0.0
	if bite:
		_laser_tick = GameData.num(cfg, "tick", 0.3)
	var beams := _a.gfx.beams
	var flicker := 0.85 + 0.15 * sin(_a.time * 55.0)
	for k in _laser_beams:
		var angle := _laser_angle + TAU * float(k) / float(_laser_beams)
		var ux := cos(angle)
		var uy := sin(angle)
		beams.add_segment(x, y, x + ux * reach, y + uy * reach, width * 3.4 * flicker, Color(C_BODY.r, C_BODY.g, C_BODY.b, 0.85), _beam_cell)
		beams.add_segment(x, y, x + ux * reach, y + uy * reach, width * 0.9, Color(1, 1, 1, 0.95), _beam_cell)
		if bite:
			var rx := player.x - x
			var ry := player.y - y
			var along := rx * ux + ry * uy
			if along > 0.0 and along < reach and absf(rx * uy - ry * ux) < width * 0.5 + player.radius * 0.6:
				player.take_hit(GameData.num(cfg, "damage", 18.0) * _damage_scale, x, y)


func _drop_zones() -> void:
	var cfg := GameData.dict(_attacks, "zones")
	var player := _a.player
	var radius := GameData.num(cfg, "radius", 88.0)
	var delay := GameData.num(cfg, "telegraph", 1.15)
	var dmg := GameData.num(cfg, "damage", 28.0) * _damage_scale
	var spread := GameData.num(cfg, "spread", 260.0)
	var amount := GameData.integer(cfg, "count", 6) + phase
	# The first is always under the player: standing still is never safe.
	_a.hazards.add(player.x, player.y, radius, delay, dmg, C_BODY)
	for k in amount - 1:
		var angle := _a.rng.randf() * TAU
		var dist := sqrt(_a.rng.randf()) * spread
		var at := Vector2(player.x + cos(angle) * dist, player.y + sin(angle) * dist)
		var offset := at - centre
		if offset.length() > arena_radius - radius * 0.5:
			at = centre + offset.normalized() * (arena_radius - radius * 0.5)
		_a.hazards.add(at.x, at.y, radius, delay + _a.rng.randf() * 0.25, dmg, C_BODY)
	_a.sfx("dash_warn", 0.8)


func _check_phase(fraction: float) -> void:
	var target := phase
	for i in _phases.size():
		var entry: Dictionary = _phases[i]
		if fraction > GameData.num(entry, "hp_above", 0.0):
			target = i
			break
	if target > phase:
		phase = target
		_queue.clear()
		# Abort whatever it was doing; the stagger is the player's reward.
		_state = S.IDLE
		_timer = 1.1
		_a.on_boss_phase(phase)


# ------------------------------------------------------------------- visuals

func _draw_wall() -> void:
	var pulse := 0.55 + 0.25 * sin(_a.time * 3.0)
	var zones := _a.gfx.zones
	zones.add_raw(centre.x, centre.y, arena_radius * 2.0, Color(C_BODY.r, C_BODY.g, C_BODY.b, pulse), 0.018, 0.012, 0.0, 0.0)
	zones.add_raw(centre.x, centre.y, arena_radius * 2.06, Color(C_BODY.r, C_BODY.g, C_BODY.b, pulse * 0.35), 0.05, 0.04, 0.0, 0.0)


func _draw_body(dt: float, flash: float, fraction: float) -> void:
	position = Vector2(x, y)
	_spin += dt * (0.6 + 0.5 * float(phase))
	var grow := _intro if _state == S.INTRO else 1.0
	var eased := 1.0 - (1.0 - grow) * (1.0 - grow)
	var s := _sprite_scale * eased
	var throb := 1.0 + 0.03 * sin(_a.time * 4.0)
	_core.scale = Vector2(s, s) * throb
	_ring.scale = Vector2(s, s)
	_shell.scale = Vector2(s, s) * (1.0 + 0.05 * sin(_a.time * 2.2))
	_ring.rotation = _spin
	_shell.rotation = -_spin * 0.6
	_glow.scale = Vector2(5.2, 5.2) * eased
	# Runs hotter as it gets hurt.
	var heat := 1.0 - fraction
	_glow.modulate = Color(1.0, 0.24 + 0.3 * heat, 0.43 - 0.2 * heat, 0.45 + 0.25 * heat)
	_core_material.set_shader_parameter("flash", flash * 0.8)
	var charging := _state == S.CHARGE_AIM or _state == S.LASER_AIM or _state == S.SUMMON
	_shell.modulate = Color(1.6, 1.6, 1.6) if charging and int(_a.time * 16.0) % 2 == 0 else Color.WHITE


# ---------------------------------------------------------------------- death

func die() -> void:
	_state = S.DYING
	_timer = 1.5


func _update_dying(dt: float) -> void:
	_timer -= dt
	var t := 1.0 - clampf(_timer / 1.5, 0.0, 1.0)
	_spin += dt * (2.0 + 10.0 * t)
	_ring.rotation = _spin
	_shell.rotation = -_spin
	var s := _sprite_scale * (1.0 + 0.5 * t)
	_core.scale = Vector2(s, s)
	_ring.scale = Vector2(s, s) * (1.0 + t)
	_shell.scale = Vector2(s, s) * (1.0 + 1.6 * t)
	modulate = Color(1, 1, 1, 1.0 - t * t)
	_core_material.set_shader_parameter("flash", t)
	if _a.step_count % 5 == 0:
		var angle := randf() * TAU
		var dist := randf() * body_radius * 1.6
		_a.fx.explosion(x + cos(angle) * dist, y + sin(angle) * dist, 70.0 + 80.0 * t, C_BODY, 0.6)
	if _timer <= 0.0:
		active = false
		visible = false
		modulate = Color.WHITE
		_state = S.INACTIVE


func is_dying() -> bool:
	return _state == S.DYING


## Whether the arena wall is up (the fight is on).
func wall_up() -> bool:
	return active and _state != S.DYING


## Steering hint for the autopilot: a push away from whatever attack is live.
func threat_vector(px: float, py: float) -> Vector2:
	if not active or _state == S.DYING:
		return Vector2.ZERO
	var out := Vector2.ZERO
	var rel := Vector2(px - x, py - y)
	var dist := rel.length() + 0.001
	if dist < body_radius + 200.0:
		out += rel / dist * (1.0 - dist / (body_radius + 200.0)) * 2.0
	if _state == S.CHARGE_AIM or _state == S.CHARGE_RUN:
		var along := rel.dot(_charge_dir)
		if along > -40.0:
			var side := rel - _charge_dir * along
			var off := side.length()
			if off < body_radius + 90.0:
				var away := side / off if off > 1.0 else _charge_dir.orthogonal()
				out += away * 3.0
	if _state == S.LASER_AIM or _state == S.LASER_FIRE:
		for k in _laser_beams:
			var angle := _laser_angle + TAU * float(k) / float(_laser_beams)
			var beam := Vector2(cos(angle), sin(angle))
			var along := rel.dot(beam)
			if along <= 0.0:
				continue
			var cross := rel.x * beam.y - rel.y * beam.x
			if absf(cross) < 120.0:
				# Step off the beam, and run with the rotation rather than into it.
				out += beam.orthogonal() * (-signf(cross) if cross != 0.0 else 1.0) * 2.5
				out += beam.orthogonal() * _laser_dir * 1.5
	return out
