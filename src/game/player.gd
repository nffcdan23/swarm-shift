class_name PlayerUnit
extends Node2D
## The player's core. Movement is direct (near-instant response to input) and
## every combat number is resolved from the build into plain fields, which the
## weapons and combat code read each step.

var x := 0.0
var y := 0.0
var radius := 17.0
var hp := 100.0
var max_hp := 100.0
var alive := true
var velocity := Vector2.ZERO
## Last direction a weapon fired in; only used to orient visuals.
var aim_angle := 0.0
var invulnerable_for := 0.0
var damage_taken := 0.0
## Hits that got through (not ones absorbed by invulnerability).
var hits_taken := 0

# Resolved stats (see game.json -> player.base_stats).
var move_speed := 250.0
var damage := 1.0
var fire_rate := 1.0
var crit_chance := 0.05
var crit_mult := 1.6
var armor := 0.0
var regen := 0.0
var pickup_radius := 95.0
var luck := 0.0
var xp_gain := 1.0
var credit_gain := 1.0
var area := 1.0
var projectile_speed := 1.0
var extra_projectiles := 0
var extra_pierce := 0
var duration := 1.0

var _a: Arena
var _base: Dictionary
var _color := Color("2de2ff")
var _iframes := 0.55
var _armor_min := 0.3
var _flash := 0.0
var _phase_enabled := false
var _phase_interval := 10.0
var _phase_duration := 1.5
var _phase_cd := 0.0
var _phasing := 0.0
# Kinetic Buffer (research): one free hit, back every `_buffer_every` seconds.
var _buffer_every := 0.0
var _buffer_cd := 0.0
var _buffer_ready := false
# Last Stand (research): once per run.
var _last_stand := false

var _last_buffer_set := false
var _last_stand_used := false

var _visual: CoreVisual
var _shield: Sprite2D
var _trail: Dictionary = {}
var _trail_color := Color.WHITE


func setup(arena: Arena, color: Color) -> void:
	_a = arena
	_color = color
	_trail = GameData.dict(arena.config.skin_def, "trail")
	_trail_color = GameData.color(_trail, "color", _color)
	_trail_color.a = GameData.num(_trail, "alpha", 0.55)
	var cfg := GameData.dict(arena.data.game, "player")
	_base = GameData.dict(cfg, "base_stats")
	radius = GameData.num(cfg, "radius", 17.0)
	_iframes = GameData.num(cfg, "iframes", 0.55)
	_armor_min = GameData.num(cfg, "armor_min_fraction", 0.3)
	_build_visuals()
	apply_stats()
	hp = max_hp


func _build_visuals() -> void:
	_visual = CoreVisual.new()
	_visual.scale = Vector2(0.27, 0.27)
	add_child(_visual)
	_visual.build(_a.config.skin_def, _color)
	_shield = Sprite2D.new()
	_shield.texture = load("res://assets/sprites/player_ring.png")
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_shield.material = additive
	_shield.scale = Vector2(0.52, 0.52)
	_shield.modulate = Color(0.75, 0.95, 1.0, 0.9)
	_shield.visible = false
	add_child(_shield)


## Re-resolves every stat from the build. Call after the build changes.
func apply_stats() -> void:
	var b := _a.build
	var old_max := max_hp
	max_hp = maxf(round(b.player_stat("max_hp", GameData.num(_base, "max_hp", 100.0))), 1.0)
	move_speed = b.player_stat("move_speed", GameData.num(_base, "move_speed", 250.0))
	damage = b.player_stat("damage", GameData.num(_base, "damage", 1.0))
	fire_rate = b.player_stat("fire_rate", GameData.num(_base, "fire_rate", 1.0))
	crit_chance = clampf(b.player_stat("crit_chance", GameData.num(_base, "crit_chance", 0.05)), 0.0, 1.0)
	crit_mult = b.player_stat("crit_mult", GameData.num(_base, "crit_mult", 1.6))
	armor = b.player_stat("armor", GameData.num(_base, "armor", 0.0))
	regen = b.player_stat("regen", GameData.num(_base, "regen", 0.0))
	pickup_radius = b.player_stat("pickup_radius", GameData.num(_base, "pickup_radius", 95.0))
	luck = b.player_stat("luck", GameData.num(_base, "luck", 0.0))
	xp_gain = b.player_stat("xp_gain", GameData.num(_base, "xp_gain", 1.0))
	credit_gain = b.player_stat("credit_gain", GameData.num(_base, "credit_gain", 1.0))
	area = b.player_stat("area", GameData.num(_base, "area", 1.0))
	projectile_speed = b.player_stat("projectile_speed", GameData.num(_base, "projectile_speed", 1.0))
	extra_projectiles = int(b.player_stat("extra_projectiles", GameData.num(_base, "extra_projectiles", 0.0)))
	extra_pierce = int(b.mod("extra_pierce"))
	duration = b.player_stat("duration", GameData.num(_base, "duration", 1.0))
	# A larger maximum never costs current health; a smaller one clamps it.
	if max_hp < old_max:
		hp = minf(hp, max_hp)
	_phase_enabled = b.enabled("fx.phase")
	_phase_interval = b.mod("fx.phase_interval", 10.0)
	_phase_duration = b.mod("fx.phase_duration", 1.5)
	_buffer_every = b.mod("fx.buffer")
	if _buffer_every > 0.0 and not _last_buffer_set:
		_last_buffer_set = true
		_buffer_ready = true
	_last_stand = _last_stand or b.enabled("fx.last_stand")


func update(dt: float, input: Vector2) -> void:
	if not alive:
		_draw_state(dt)
		return
	var target := input.limit_length(1.0) * move_speed
	# A very short ease keeps direction changes from looking robotic without
	# adding any perceptible input lag.
	velocity = velocity.lerp(target, 1.0 - exp(-dt * 24.0))
	x += velocity.x * dt
	y += velocity.y * dt
	_a.confine(self)

	if regen > 0.0 and hp < max_hp:
		hp = minf(hp + regen * dt, max_hp)
	if invulnerable_for > 0.0:
		invulnerable_for -= dt
	if _phase_enabled:
		_phase_cd -= dt
		if _phase_cd <= 0.0:
			_phase_cd = _phase_interval
			_phasing = _phase_duration
			invulnerable_for = maxf(invulnerable_for, _phase_duration)
			_a.sfx("phase")
			_a.fx.ring(x, y, 20.0, 110.0, 0.3, Color(0.6, 0.85, 1.0), 0.1)
	if _phasing > 0.0:
		_phasing -= dt

	if _buffer_every > 0.0 and not _buffer_ready:
		_buffer_cd -= dt
		if _buffer_cd <= 0.0:
			_buffer_ready = true
			_a.fx.ring(x, y, 60.0, 30.0, 0.25, Color(0.75, 0.95, 1.0), 0.08)
	if velocity.length_squared() > 900.0 and _a.step_count % 2 == 0:
		_emit_trail()
	_draw_state(dt)


## One puff of the skin's trail. `rise` makes it drift up the screen like heat,
## `stretch` draws it as a streak. Looks only.
func _emit_trail() -> void:
	var drift := GameData.num(_trail, "drift", 0.25)
	_a.gfx.particles.emit(x - velocity.x * 0.03, y - velocity.y * 0.03,
		-velocity.x * drift, -velocity.y * drift - GameData.num(_trail, "rise", 0.0),
		GameData.num(_trail, "life", 0.3), GameData.num(_trail, "size", 20.0), GameData.num(_trail, "end", 3.0),
		_trail_color, GameData.num(_trail, "drag", 3.0), GameData.num(_trail, "stretch", 0.0))


func _draw_state(dt: float) -> void:
	position = Vector2(x, y)
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 5.0, 0.0)
	_visual.set_flash(_flash)
	_visual.animate(dt, 1.3 if _phasing > 0.0 else 1.0)
	_shield.visible = _buffer_ready
	if _buffer_ready:
		_shield.rotation = -_a.time * 2.2
		_shield.scale = Vector2.ONE * (0.52 + 0.02 * sin(_a.time * 7.0))
	if _phasing > 0.0:
		modulate = Color(0.65, 0.9, 1.0, 0.45)
	else:
		# Blink while the post-hit grace period lasts.
		var blink := invulnerable_for > 0.0 and int(_a.time * 22.0) % 2 == 0
		modulate = Color(1, 1, 1, 0.45 if blink else 1.0)


## Applies a hit from an enemy source. Returns false if it was ignored.
func take_hit(amount: float, from_x: float, from_y: float) -> bool:
	if not alive or invulnerable_for > 0.0 or not _a.is_playing():
		return false
	if _buffer_ready:
		_buffer_ready = false
		_buffer_cd = _buffer_every
		invulnerable_for = _iframes
		_a.sfx("phase")
		_a.fx.shockwave(x, y, 140.0, Color(0.75, 0.95, 1.0))
		return false
	var dealt := maxf(amount - armor, amount * _armor_min)
	hp -= dealt
	damage_taken += dealt
	hits_taken += 1
	invulnerable_for = _iframes
	_flash = 1.0
	_a.on_player_hit(dealt, from_x, from_y)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		_a.on_player_down()
	elif _last_stand and not _last_stand_used and hp < max_hp * 0.25:
		_last_stand_used = true
		invulnerable_for = 2.0
		_a.on_last_stand()
	return true


func heal(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	var before := hp
	hp = minf(hp + amount, max_hp)
	if hp - before >= 1.0:
		_a.fx.text(x, y - 46.0, "+%d" % int(hp - before), Color("5cff8a"), 1.0)


## Displaces the player (immovable bodies push the player out of themselves).
func nudge(dx: float, dy: float) -> void:
	x += dx
	y += dy


func revive(fraction: float, invulnerable_seconds: float) -> void:
	alive = true
	hp = maxf(max_hp * fraction, 1.0)
	invulnerable_for = invulnerable_seconds
	velocity = Vector2.ZERO
	visible = true


func hp_fraction() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func set_tint(color: Color) -> void:
	_color = color
	_visual.set_tint(color)
