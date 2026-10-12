class_name HazardSystem
extends RefCounted
## Telegraphed danger zones that hurt the player: a circle fills in over its
## delay, then detonates. Used by volatile elites and the boss. The fill-in is
## the telegraph - the player always gets the full delay to step out.

const MAX := 40

var count := 0

var _a: Arena
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _age := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _color: Array[Color] = []


func setup(arena: Arena) -> void:
	_a = arena
	for arr: PackedFloat32Array in [_x, _y, _radius, _delay, _age, _damage]:
		arr.resize(MAX)
	_color.resize(MAX)


func add(x: float, y: float, radius: float, delay: float, damage: float, color: Color) -> void:
	if count >= MAX:
		return
	var i := count
	count += 1
	_x[i] = x
	_y[i] = y
	_radius[i] = radius
	_delay[i] = delay
	_age[i] = 0.0
	_damage[i] = damage
	_color[i] = color


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
			_color[i] = _color[last]
			continue
		_age[i] = age
		var t := age / _delay[i]
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
