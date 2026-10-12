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
var _spin := 0.0

var _glow: Sprite2D
var _core: Sprite2D
var _ring: Sprite2D
var _spark: Sprite2D
var _core_material: ShaderMaterial


func setup(arena: Arena, color: Color) -> void:
	_a = arena
	_color = color
	var cfg := GameData.dict(arena.data.game, "player")
	_base = GameData.dict(cfg, "base_stats")
	radius = GameData.num(cfg, "radius", 17.0)
	_iframes = GameData.num(cfg, "iframes", 0.55)
	_armor_min = GameData.num(cfg, "armor_min_fraction", 0.3)
	_build_visuals()
	apply_stats()
	hp = max_hp


func _build_visuals() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/sprites/atlas/glow.png")
	_glow.material = additive
	_glow.scale = Vector2(1.7, 1.7)
	_glow.modulate = Color(_color.r, _color.g, _color.b, 0.55)
	add_child(_glow)

	_ring = Sprite2D.new()
	_ring.texture = load("res://assets/sprites/player_ring.png")
	_ring.material = additive
	_ring.scale = Vector2(0.4, 0.4)
	_ring.modulate = _color
	add_child(_ring)

	_core = Sprite2D.new()
	_core.texture = load("res://assets/sprites/player_core.png")
	_core_material = ShaderMaterial.new()
	_core_material.shader = load("res://assets/shaders/flash.gdshader")
	_core.material = _core_material
	_core.scale = Vector2(0.27, 0.27)
	_core.modulate = _color
	add_child(_core)

	_spark = Sprite2D.new()
	_spark.texture = load("res://assets/sprites/atlas/orb.png")
	_spark.material = additive
	_spark.scale = Vector2(0.24, 0.24)
	_spark.modulate = Color(1, 1, 1, 0.9)
	add_child(_spark)


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
	duration = b.player_stat("duration", GameData.num(_base, "duration", 1.0))
	# A larger maximum never costs current health; a smaller one clamps it.
	if max_hp < old_max:
		hp = minf(hp, max_hp)
	_phase_enabled = b.enabled("fx.phase")
	_phase_interval = b.mod("fx.phase_interval", 10.0)
	_phase_duration = b.mod("fx.phase_duration", 1.5)


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

	if velocity.length_squared() > 900.0 and _a.step_count % 2 == 0:
		_a.gfx.particles.emit(x - velocity.x * 0.03, y - velocity.y * 0.03, -velocity.x * 0.25, -velocity.y * 0.25,
			0.3, 20.0, 3.0, Color(_color.r, _color.g, _color.b, 0.55), 3.0)
	_draw_state(dt)


func _draw_state(dt: float) -> void:
	position = Vector2(x, y)
	_spin += dt * 1.8
	_ring.rotation = _spin
	_core.rotation = -_spin * 0.35
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 5.0, 0.0)
	_core_material.set_shader_parameter("flash", _flash)
	var pulse := 1.0 + 0.06 * sin(_a.time * 6.0)
	_glow.scale = Vector2(1.7, 1.7) * pulse
	if _phasing > 0.0:
		modulate = Color(0.65, 0.9, 1.0, 0.45)
		_ring.scale = Vector2(0.52, 0.52)
	else:
		_ring.scale = Vector2(0.4, 0.4)
		# Blink while the post-hit grace period lasts.
		var blink := invulnerable_for > 0.0 and int(_a.time * 22.0) % 2 == 0
		modulate = Color(1, 1, 1, 0.45 if blink else 1.0)


## Applies a hit from an enemy source. Returns false if it was ignored.
func take_hit(amount: float, from_x: float, from_y: float) -> bool:
	if not alive or invulnerable_for > 0.0 or not _a.is_playing():
		return false
	var dealt := maxf(amount - armor, amount * _armor_min)
	hp -= dealt
	damage_taken += dealt
	invulnerable_for = _iframes
	_flash = 1.0
	_a.on_player_hit(dealt, from_x, from_y)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		_a.on_player_down()
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
	_ring.modulate = color
	_core.modulate = color
	_glow.modulate = Color(color.r, color.g, color.b, 0.55)
