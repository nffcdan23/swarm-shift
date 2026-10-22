class_name HazardSystem
extends RefCounted
## Telegraphed danger zones that hurt the player: a circle fills in over its
## delay, then detonates. Used by volatile elites, Bombers, Mortar shells,
## bombardments and the boss. The fill-in is the telegraph - the player always
## gets the full delay to step out, and nothing here ever hurts without one.
##
## A zone may be given an origin, in which case a shell is drawn flying from
## there to the zone so the player can see who fired it.

const MAX := 64
## Shortest warning any zone may give. Data cannot ask for less.
const MIN_DELAY := 0.45

var count := 0
## Zones created since the run began.
var spawned_total := 0
## The least warning any zone has given this run, in seconds.
var shortest_warning := INF

var _a: Arena
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _age := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _from_x := PackedFloat32Array()
var _from_y := PackedFloat32Array()
var _has_origin := PackedByteArray()
## FxSystem.Shake tier to request on detonation, or -1 (most zones: none).
var _shake := PackedInt32Array()
var _color: Array[Color] = []
var _glow_cell := 0.0
var _orb_cell := 0.0


func setup(arena: Arena) -> void:
	_a = arena
	for arr: PackedFloat32Array in [_x, _y, _radius, _delay, _age, _damage, _from_x, _from_y]:
		arr.resize(MAX)
	_has_origin.resize(MAX)
	_shake.resize(MAX)
	_color.resize(MAX)
	_glow_cell = arena.gfx.cell("glow")
	_orb_cell = arena.gfx.cell("orb")


## Adds a zone that detonates after `delay` seconds. Pass `from_x`/`from_y`
## to draw a shell arcing in from that point.
## `shake_tier` (an FxSystem.Shake) makes the detonation shake the camera;
## only boss attacks use it. Mortars, Bombers and bombardments do not.
func add(x: float, y: float, radius: float, delay: float, damage: float, color: Color,
		from_x: float = NAN, from_y: float = NAN, shake_tier: int = -1) -> void:
	if count >= MAX or not (is_finite(x) and is_finite(y)) or radius <= 0.0:
		return
	var i := count
	count += 1
	spawned_total += 1
	_x[i] = x
	_y[i] = y
	_radius[i] = radius
	_delay[i] = maxf(delay, MIN_DELAY)
	shortest_warning = minf(shortest_warning, _delay[i])
	_age[i] = 0.0
	_damage[i] = damage
	_color[i] = color
	_has_origin[i] = 1 if is_finite(from_x) and is_finite(from_y) else 0
	_from_x[i] = from_x if _has_origin[i] != 0 else x
	_from_y[i] = from_y if _has_origin[i] != 0 else y
	_shake[i] = shake_tier


func x_of(i: int) -> float:
	return _x[i]


func y_of(i: int) -> float:
	return _y[i]


func radius_of(i: int) -> float:
	return _radius[i]


## Seconds until zone `i` detonates.
func time_left(i: int) -> float:
	return _delay[i] - _age[i]


func update(dt: float) -> void:
	var zones := _a.gfx.zones
	var player := _a.player
	var i := 0
	while i < count:
		var age := _age[i] + dt
		var r := _radius[i]
		var color := _color[i]
		if age >= _delay[i]:
			_a.fx.explosion(_x[i], _y[i], r, color, 1.4)
			if _shake[i] >= 0:
				_a.fx.shake(_shake[i])
			_a.sfx("explosion_m")
			var dx := player.x - _x[i]
			var dy := player.y - _y[i]
			if dx * dx + dy * dy < (r + player.radius * 0.5) * (r + player.radius * 0.5):
				player.take_hit(_damage[i], _x[i], _y[i])
			count -= 1
			var last := count
			_x[i] = _x[last]
			_y[i] = _y[last]
			_radius[i] = _radius[last]
			_delay[i] = _delay[last]
			_age[i] = _age[last]
			_damage[i] = _damage[last]
			_from_x[i] = _from_x[last]
			_from_y[i] = _from_y[last]
			_has_origin[i] = _has_origin[last]
			_shake[i] = _shake[last]
			_color[i] = _color[last]
			continue
		_age[i] = age
		var t := age / _delay[i]
		if _has_origin[i] != 0:
			# The shell: rises, hangs and comes down on the centre of its zone.
			var sx := lerpf(_from_x[i], _x[i], t)
			var sy := lerpf(_from_y[i], _y[i], t) - sin(t * PI) * 90.0
			var swell := 1.0 + 0.7 * sin(t * PI)
			_a.gfx.beams.add_sprite(sx, sy, 0.0, 54.0 * swell, Color(color.r, color.g, color.b, 0.8), _glow_cell)
			_a.gfx.beams.add_sprite(sx, sy, 0.0, 22.0 * swell, Color(1, 1, 1, 0.95), _orb_cell)
		# Outline of the full blast, plus a disc that grows to meet it.
		zones.add_raw(_x[i], _y[i], r * 2.0, Color(color.r, color.g, color.b, 0.55 + 0.35 * t), 0.05, 0.03, 0.1, 0.0)
		zones.add_raw(_x[i], _y[i], r * 2.0 * t, Color(color.r, color.g, color.b, 0.16 + 0.3 * t), 1.0, 0.06, 1.0, 0.0)
		i += 1


## Direction away from any zones covering the point, weighted by how deep in
## it is. Zero when the point is safe. Used by the autopilot.
func threat_at(x: float, y: float, margin: float) -> Vector2:
	var away := Vector2.ZERO
	for i in count:
		var dx := x - _x[i]
		var dy := y - _y[i]
		var reach := _radius[i] + margin
		var d2 := dx * dx + dy * dy
		if d2 < reach * reach:
			var d := sqrt(d2) + 0.001
			away += Vector2(dx / d, dy / d) * (1.0 - d / reach)
	return away


func clear() -> void:
	count = 0
