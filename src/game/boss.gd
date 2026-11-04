class_name Boss
extends Node2D
## A sector boss. It occupies one slot in the EnemySystem (so every weapon
## can hit it with no special cases) but its behaviour is driven from here: a
## small state machine cycling through attack patterns that get faster and more
## varied across its health phases.
##
## Each sector has its own boss (stages.json "bosses", picked by
## CampaignService.boss_for): its own look (shell, core and ring sprites tinted
## in its colour), phases and attacks. An attack entry's "type" says which
## pattern it is (its key, if absent), so one boss can carry two versions of a
## pattern, such as a fixed cross of lasers and a sweeping one.
##
## Every attack is telegraphed before it can hurt: lanes for charges, lasers
## and aimed fans, filling circles for ground blasts and teleport landings, a
## wind-up for spirals, slow readable bullets for bursts.

enum S { INACTIVE, INTRO, IDLE, BURST, CHARGE_AIM, CHARGE_RUN, CHARGE_REST, SUMMON, LASER_AIM, LASER_FIRE, ZONES,
	SPIRAL_AIM, SPIRAL, FAN_AIM, FAN, BLINK_AIM, DYING }

## Attack patterns the boss knows. Data refers to these by "type".
const ATTACK_TYPES := ["burst", "charge", "summon", "laser", "zones", "spiral", "fan", "blink"]
const C_BODY := Color("ff3d6e")
const LOOK_DIR := "res://assets/sprites/bosses/"
const DEFAULT_LOOK := {"shell": "claw", "core": "eye", "ring": "segmented"}

var active := false
var boss_id := ""
var display_name := ""
var title := ""
## This boss's colour: body, telegraphs, arena wall.
var color := C_BODY
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
## Threat modifiers (CampaignService.mutator_effects "boss"): shorter rests and
## bigger volleys. Read once at spawn.
var _idle_mult := 1.0
var _bullets_mult := 1.0
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
## The attack in progress: its entry in "attacks".
var _cfg: Dictionary = {}
var _spiral_dir := 1.0
var _fan_left := 0
var _fan_dir := Vector2.RIGHT
var _blinks_left := 0
var _blink_to := Vector2.ZERO
var _blink_total := 0.0
## 0 = solid; rises while it fades out to blink.
var _fade := 0.0
## Attacks started this fight, by name: {attack: times}. For tests and tuning.
var used: Dictionary = {}
var _spin := 0.0
var _intro := 0.0

var _glow: Sprite2D
var _shell: Sprite2D
var _ring: Sprite2D
var _core: Sprite2D
var _core_material: ShaderMaterial
var _tints: Array[ShaderMaterial] = []
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
	var shader: Shader = load("res://assets/shaders/boss_tint.gdshader")
	_shell = _tinted_sprite(shader)
	_ring = _tinted_sprite(shader)
	_core = _tinted_sprite(shader)
	_core_material = _core.material
	_apply_look(DEFAULT_LOOK, C_BODY)


func _tinted_sprite(shader: Shader) -> Sprite2D:
	var sprite := Sprite2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	sprite.material = mat
	_tints.append(mat)
	add_child(sprite)
	return sprite


## Puts on a boss's look: which shell, core and ring, in its colour.
func _apply_look(look: Dictionary, tint: Color) -> void:
	_shell.texture = _part("shell", GameData.text(look, "shell", DEFAULT_LOOK.shell))
	_core.texture = _part("core", GameData.text(look, "core", DEFAULT_LOOK.core))
	_ring.texture = _part("ring", GameData.text(look, "ring", DEFAULT_LOOK.ring))
	for mat in _tints:
		mat.set_shader_parameter("tint", tint)
	_glow.modulate = Color(tint.r, tint.g, tint.b, 0.5)


static func part_path(kind: String, id: String) -> String:
	return "%sboss_%s_%s.png" % [LOOK_DIR, kind, id]


func _part(kind: String, id: String) -> Texture2D:
	var path := part_path(kind, id)
	if not ResourceLoader.exists(path):
		path = part_path(kind, str(DEFAULT_LOOK[kind]))
	return load(path)


func spawn(id: String, at: Vector2, hp_scale: float, damage_scale: float) -> void:
	boss_id = id
	_def = GameData.dict(GameData.dict(_a.data.stages, "bosses"), id)
	_attacks = GameData.dict(_def, "attacks")
	_phases = GameData.list(_def, "phases").duplicate(true)
	var mods: Dictionary = GameData.dict(_a.director.mutators(), "boss")
	_idle_mult = clampf(GameData.num(mods, "idle_mult", 1.0), 0.4, 2.0)
	_bullets_mult = clampf(GameData.num(mods, "bullets_mult", 1.0), 0.5, 2.0)
	# Final Protocol: the last phase ends early and a fourth takes over.
	var final_phase := GameData.dict(mods, "final_phase")
	if not final_phase.is_empty() and not _phases.is_empty():
		var below := clampf(GameData.num(final_phase, "below", 0.2), 0.05, 0.3)
		(_phases[_phases.size() - 1] as Dictionary)["hp_above"] = below
		# Its last stand uses everything this boss has.
		var every := GameData.list(final_phase, "attacks")
		if every.is_empty():
			every = _attacks.keys()
		_phases.append({"hp_above": 0.0, "attacks": every,
			"idle": GameData.num(final_phase, "idle", 0.7), "speed_mult": GameData.num(final_phase, "speed_mult", 1.5)})
	var opening := clampi(GameData.integer(mods, "phase_floor", 0), 0, maxi(_phases.size() - 2, 0))
	display_name = GameData.text(_def, "name", "BOSS")
	title = GameData.text(_def, "title")
	color = GameData.color(_def, "color", C_BODY)
	_apply_look(GameData.dict(_def, "look"), color)
	body_radius = GameData.num(_def, "radius", 60.0)
	arena_radius = GameData.num(_def, "arena_radius", 540.0)
	_contact = GameData.num(_def, "contact_damage", 30.0) * damage_scale
	_speed = GameData.num(_def, "speed", 48.0)
	_damage_scale = damage_scale
	_sprite_scale = GameData.num(_def, "size", 230.0) / 512.0
	x = at.x
	y = at.y
	centre = at
	# Boss's Wrath (Threat) opens in a later phase's attack set.
	phase = opening
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
	_fade = 0.0
	_cfg = {}
	used.clear()
	_queue.clear()
	position = at


## Where its phases change, as health fractions: for the boss bar.
func phase_marks() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for entry: Dictionary in _phases:
		var above := GameData.num(entry, "hp_above", 0.0)
		if above > 0.0 and above < 1.0:
			out.append(above)
	return out


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
					_timer = GameData.num(_cfg, "interval", 0.6)
				else:
					_to_idle(phase_cfg)
		S.CHARGE_AIM:
			var cfg := _cfg
			var progress := 1.0 - _timer / maxf(_charge_total, 0.01)
			# Track the player for the first half, then commit.
			if progress < 0.55:
				_charge_dir = dir
			var reach := GameData.num(cfg, "speed", 760.0) * GameData.num(cfg, "duration", 0.7)
			_a.gfx.telegraphs.lane(x, y, x + _charge_dir.x * reach, y + _charge_dir.y * reach, body_radius * 2.0, color, clampf(progress, 0.0, 1.0))
			if _timer <= 0.0:
				_state = S.CHARGE_RUN
				_timer = GameData.num(cfg, "duration", 0.7)
				_a.sfx("boss_charge")
				_a.fx.shake(FxSystem.Shake.MEDIUM)
		S.CHARGE_RUN:
			var cfg := _cfg
			var speed := GameData.num(cfg, "speed", 760.0)
			x += _charge_dir.x * speed * dt
			y += _charge_dir.y * speed * dt
			enemies.damage[_idx] = GameData.num(cfg, "damage", 34.0) * _damage_scale
			_a.gfx.particles.burst(x, y, 2, 40.0, 160.0, 0.25, 0.5, 26.0, 4.0, color, 3.0)
			var from_centre := Vector2(x, y) - centre
			var limit := arena_radius - body_radius
			var hit_wall := from_centre.length() > limit
			if hit_wall:
				var clamped := centre + from_centre.normalized() * limit
				x = clamped.x
				y = clamped.y
				_a.fx.explosion(x, y, 150.0, color, 1.6)
				_a.fx.shake(FxSystem.Shake.MEDIUM)
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
				_a.fx.ring(x, y, body_radius * 2.6, body_radius * 0.8, 0.3, color, 0.08)
			if _timer <= 0.0:
				_summon()
				_to_idle(phase_cfg)
		S.LASER_AIM:
			var cfg := _cfg
			var reach := GameData.num(cfg, "length", 640.0)
			var progress := 1.0 - _timer / maxf(GameData.num(cfg, "telegraph", 1.1), 0.01)
			for k in _laser_beams:
				var angle := _laser_angle + TAU * float(k) / float(_laser_beams)
				_a.gfx.telegraphs.lane(x, y, x + cos(angle) * reach, y + sin(angle) * reach, GameData.num(cfg, "width", 22.0) * 1.6, color, clampf(progress, 0.0, 1.0))
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
					_timer = GameData.num(_cfg, "wave_interval", 0.9)
				else:
					_to_idle(phase_cfg)
		S.SPIRAL_AIM:
			if _a.step_count % 3 == 0:
				_a.fx.ring(x, y, body_radius * 2.2, body_radius * 0.9, 0.25, color, 0.1)
			if _timer <= 0.0:
				_state = S.SPIRAL
				_timer = GameData.num(_cfg, "duration", 3.0)
				_laser_tick = 0.0
		S.SPIRAL:
			_laser_tick -= dt
			if _laser_tick <= 0.0:
				_laser_tick += GameData.num(_cfg, "interval", 0.12)
				_fire_spiral()
			if _timer <= 0.0:
				_to_idle(phase_cfg)
		S.FAN_AIM:
			var progress := 1.0 - _timer / maxf(GameData.num(_cfg, "telegraph", 0.5), 0.01)
			if progress < 0.7:
				_fan_dir = dir
			_a.gfx.telegraphs.lane(x, y, x + _fan_dir.x * 520.0, y + _fan_dir.y * 520.0, 36.0, color, clampf(progress, 0.0, 1.0))
			if _timer <= 0.0:
				_state = S.FAN
				_timer = 0.0
		S.FAN:
			if _timer <= 0.0:
				_fan_dir = dir
				_fire_fan()
				_fan_left -= 1
				if _fan_left > 0:
					_timer = GameData.num(_cfg, "interval", 0.45)
				else:
					_to_idle(phase_cfg)
		S.BLINK_AIM:
			var progress := 1.0 - _timer / maxf(_blink_total, 0.01)
			_fade = clampf(progress * 1.3, 0.0, 0.85)
			if _timer <= 0.0:
				_arrive()
				_blinks_left -= 1
				if _blinks_left > 0:
					_start_blink(0.8)
				else:
					_fade = 0.0
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
	_cfg = GameData.dict(_attacks, attack)
	used[attack] = int(used.get(attack, 0)) + 1
	match attack_type(attack):
		"burst":
			_state = S.BURST
			_volleys_left = GameData.integer(_cfg, "volleys", 3)
			_burst_angle = _a.rng.randf() * TAU
			_timer = 0.35
		"charge":
			_charges_left = 1 + phase * GameData.integer(_cfg, "charges_per_phase", 1)
			_start_charge(1.0)
		"summon":
			_state = S.SUMMON
			_timer = GameData.num(_cfg, "cast_time", 0.8)
			_a.sfx("surge")
		"laser":
			_state = S.LASER_AIM
			_laser_beams = GameData.integer(_cfg, "beams", 3)
			_laser_angle = _a.rng.randf() * TAU
			_laser_dir = -_laser_dir
			_timer = GameData.num(_cfg, "telegraph", 1.1)
		"zones":
			_state = S.ZONES
			_zone_waves = GameData.integer(_cfg, "waves", 2)
			_timer = 0.2
		"spiral":
			_state = S.SPIRAL_AIM
			_burst_angle = _a.rng.randf() * TAU
			_spiral_dir = -_spiral_dir
			_timer = GameData.num(_cfg, "telegraph", 0.6)
			_a.sfx("surge", 1.2)
		"fan":
			_state = S.FAN_AIM
			_fan_left = GameData.integer(_cfg, "volleys", 3) + phase * GameData.integer(_cfg, "volleys_per_phase", 0)
			_timer = GameData.num(_cfg, "telegraph", 0.5)
			_a.sfx("dash_warn", 1.2)
		"blink":
			_blinks_left = GameData.integer(_cfg, "blinks", 1) + phase * GameData.integer(_cfg, "blinks_per_phase", 1)
			_start_blink(1.0)
		_:
			_timer = 0.5


## The pattern an attack entry runs: its "type", or its own name.
func attack_type(attack: String) -> String:
	return GameData.text(GameData.dict(_attacks, attack), "type", attack)


func _to_idle(phase_cfg: Dictionary) -> void:
	_state = S.IDLE
	_timer = GameData.num(phase_cfg, "idle", 1.2) * _idle_mult


func _start_charge(telegraph_scale: float) -> void:
	_state = S.CHARGE_AIM
	_charge_total = GameData.num(_cfg, "telegraph", 0.95) * telegraph_scale
	_timer = _charge_total
	_a.sfx("dash_warn")


func _fire_volley() -> void:
	var cfg := _cfg
	var amount := int(round(float(GameData.integer(cfg, "bullets", 14) + phase * GameData.integer(cfg, "bullets_per_phase", 3)) * _bullets_mult))
	var speed := GameData.num(cfg, "bullet_speed", 205.0)
	var dmg := GameData.num(cfg, "damage", 14.0) * _damage_scale
	for k in amount:
		var angle := _burst_angle + TAU * float(k) / float(amount)
		_a.bullets.spawn(x + cos(angle) * body_radius, y + sin(angle) * body_radius, cos(angle) * speed, sin(angle) * speed, dmg)
	_burst_angle += GameData.num(cfg, "spin", 0.22)
	_a.fx.ring(x, y, body_radius, body_radius * 2.4, 0.25, color, 0.12)
	_a.sfx("enemy_shoot", 0.7)


func _summon() -> void:
	var cfg := _cfg
	var spawns := GameData.dict(cfg, "spawns")
	var grows := GameData.text(cfg, "grows", "swarmer")
	for enemy_id_key: String in spawns:
		var amount := int(spawns[enemy_id_key])
		if enemy_id_key == grows:
			amount += phase * GameData.integer(cfg, "extra_per_phase", 4)
		_a.enemies.queue_spawn(enemy_id_key, x, y, amount, body_radius + 110.0)
	_a.fx.shockwave(x, y, body_radius + 150.0, color)
	_a.sfx("boss_spawn", 1.3)


func _update_laser(dt: float) -> void:
	var cfg := _cfg
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
		beams.add_segment(x, y, x + ux * reach, y + uy * reach, width * 3.4 * flicker, Color(color.r, color.g, color.b, 0.85), _beam_cell)
		beams.add_segment(x, y, x + ux * reach, y + uy * reach, width * 0.9, Color(1, 1, 1, 0.95), _beam_cell)
		if bite:
			var rx := player.x - x
			var ry := player.y - y
			var along := rx * ux + ry * uy
			if along > 0.0 and along < reach and absf(rx * uy - ry * ux) < width * 0.5 + player.radius * 0.6:
				player.take_hit(GameData.num(cfg, "damage", 18.0) * _damage_scale, x, y)


func _drop_zones() -> void:
	var cfg := _cfg
	var player := _a.player
	var radius := GameData.num(cfg, "radius", 88.0)
	var delay := GameData.num(cfg, "telegraph", 1.15)
	var dmg := GameData.num(cfg, "damage", 28.0) * _damage_scale
	var spread := GameData.num(cfg, "spread", 260.0)
	var amount := GameData.integer(cfg, "count", 6) + phase
	# The first is always under the player: standing still is never safe.
	# One shake per volley, from the blast under the player.
	_a.hazards.add(player.x, player.y, radius, delay, dmg, color, NAN, NAN, FxSystem.Shake.MEDIUM)
	for k in amount - 1:
		var angle := _a.rng.randf() * TAU
		var dist := sqrt(_a.rng.randf()) * spread
		var at := Vector2(player.x + cos(angle) * dist, player.y + sin(angle) * dist)
		var offset := at - centre
		if offset.length() > arena_radius - radius * 0.5:
			at = centre + offset.normalized() * (arena_radius - radius * 0.5)
		_a.hazards.add(at.x, at.y, radius, delay + _a.rng.randf() * 0.25, dmg, color)
	_a.sfx("dash_warn", 0.8)


func _fire_spiral() -> void:
	var arms := GameData.integer(_cfg, "arms", 3) + phase * GameData.integer(_cfg, "arms_per_phase", 0)
	var speed := GameData.num(_cfg, "bullet_speed", 180.0)
	var dmg := GameData.num(_cfg, "damage", 12.0) * _damage_scale
	for k in arms:
		var angle := _burst_angle + TAU * float(k) / float(arms)
		_a.bullets.spawn(x + cos(angle) * body_radius, y + sin(angle) * body_radius, cos(angle) * speed, sin(angle) * speed, dmg)
	_burst_angle += GameData.num(_cfg, "turn", 0.26) * _spiral_dir
	if _a.step_count % 6 == 0:
		_a.sfx("enemy_shoot", 0.5)


## An aimed spread: `bullets` across `arc` degrees, centred on the player.
func _fire_fan() -> void:
	var amount := maxi(int(round(float(GameData.integer(_cfg, "bullets", 5) + phase * GameData.integer(_cfg, "bullets_per_phase", 1)) * _bullets_mult)), 1)
	var arc := deg_to_rad(GameData.num(_cfg, "arc", 50.0))
	var speed := GameData.num(_cfg, "bullet_speed", 250.0)
	var dmg := GameData.num(_cfg, "damage", 14.0) * _damage_scale
	var base := _fan_dir.angle()
	for k in amount:
		var angle := base if amount == 1 else base - arc * 0.5 + arc * float(k) / float(amount - 1)
		_a.bullets.spawn(x + cos(angle) * body_radius, y + sin(angle) * body_radius, cos(angle) * speed, sin(angle) * speed, dmg)
	_a.fx.ring(x, y, body_radius, body_radius * 1.8, 0.2, color, 0.1)
	_a.sfx("enemy_shoot", 0.8)


## Marks where it will land (a ground blast that goes off as it arrives) and
## starts fading out.
func _start_blink(telegraph_scale: float) -> void:
	_state = S.BLINK_AIM
	_blink_total = GameData.num(_cfg, "telegraph", 0.85) * telegraph_scale
	_timer = _blink_total
	var player := _a.player
	var angle := _a.rng.randf() * TAU
	var reach := GameData.num(_cfg, "distance", 220.0)
	var to := Vector2(player.x + cos(angle) * reach, player.y + sin(angle) * reach)
	var offset := to - centre
	var limit := arena_radius - body_radius - 30.0
	if offset.length() > limit:
		to = centre + offset.normalized() * limit
	_blink_to = to
	_a.hazards.add(to.x, to.y, GameData.num(_cfg, "radius", 110.0), _blink_total, GameData.num(_cfg, "damage", 30.0) * _damage_scale, color)
	_a.sfx("dash_warn", 0.9)


func _arrive() -> void:
	_a.fx.explosion(x, y, 90.0, color, 0.5)
	x = _blink_to.x
	y = _blink_to.y
	_a.fx.shockwave(x, y, body_radius * 2.4, color)
	_a.fx.shake(FxSystem.Shake.MEDIUM)
	_a.sfx("phase")
	var bullets := GameData.integer(_cfg, "bullets", 0)
	if bullets > 0:
		var speed := GameData.num(_cfg, "bullet_speed", 190.0)
		var dmg := GameData.num(_cfg, "bullet_damage", 12.0) * _damage_scale
		var start := _a.rng.randf() * TAU
		for k in bullets:
			var angle := start + TAU * float(k) / float(bullets)
			_a.bullets.spawn(x + cos(angle) * body_radius, y + sin(angle) * body_radius, cos(angle) * speed, sin(angle) * speed, dmg)


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
		_fade = 0.0
		_state = S.IDLE
		_timer = 1.1
		_a.on_boss_phase(phase)


# ------------------------------------------------------------------- visuals

func _draw_wall() -> void:
	var pulse := 0.55 + 0.25 * sin(_a.time * 3.0)
	var zones := _a.gfx.zones
	zones.add_raw(centre.x, centre.y, arena_radius * 2.0, Color(color.r, color.g, color.b, pulse), 0.018, 0.012, 0.0, 0.0)
	zones.add_raw(centre.x, centre.y, arena_radius * 2.06, Color(color.r, color.g, color.b, pulse * 0.35), 0.05, 0.04, 0.0, 0.0)


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
	var hot := color.lerp(Color(1.0, 0.85, 0.5), heat * 0.45)
	_glow.modulate = Color(hot.r, hot.g, hot.b, 0.45 + 0.25 * heat)
	# Fading out to blink.
	modulate = Color(1, 1, 1, 1.0 - _fade)
	_core_material.set_shader_parameter("flash", flash * 0.8)
	var charging := _state in [S.CHARGE_AIM, S.LASER_AIM, S.SUMMON, S.SPIRAL_AIM, S.FAN_AIM]
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
		_a.fx.explosion(x + cos(angle) * dist, y + sin(angle) * dist, 70.0 + 80.0 * t, color, 0.6)
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
	if _state == S.FAN_AIM or _state == S.FAN:
		# Get off the line it is aiming down.
		var along := rel.dot(_fan_dir)
		if along > 0.0:
			var cross := rel.x * _fan_dir.y - rel.y * _fan_dir.x
			if absf(cross) < 110.0:
				out += _fan_dir.orthogonal() * (-signf(cross) if cross != 0.0 else 1.0) * 2.0
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
