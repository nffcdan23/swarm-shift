class_name FieldPool
extends RefCounted
## Lingering ground fields left behind by a weapon: each slows what stands in it
## and burns it on a slow tick. Capped, because every live field is a draw call
## and a query, and the oldest makes way for a new one.

var _max := 3
var _tick := 0.5
var _chill := 1.0
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _r := PackedFloat32Array()
var _age := PackedFloat32Array()
var _next := PackedFloat32Array()


func _init(cap: int, tick: float, chill_time: float) -> void:
	_max = cap
	_tick = tick
	_chill = chill_time


func count() -> int:
	return _x.size()


func add(x: float, y: float, radius: float) -> void:
	if _x.size() >= _max:
		_drop(0)
	_x.append(x)
	_y.append(y)
	_r.append(radius)
	_age.append(0.0)
	_next.append(0.0)


func _drop(i: int) -> void:
	_x.remove_at(i)
	_y.remove_at(i)
	_r.remove_at(i)
	_age.remove_at(i)
	_next.remove_at(i)


## Ages, draws and applies every field. `alpha` is the strength of the draw.
func update(a: Arena, dt: float, lifetime: float, damage: float, src: int, color: Color, alpha: float) -> void:
	var enemies := a.enemies
	var i := _x.size() - 1
	while i >= 0:
		_age[i] += dt
		if _age[i] >= lifetime:
			_drop(i)
			i -= 1
			continue
		var fade := minf((lifetime - _age[i]) * 2.0, 1.0)
		a.gfx.zones.add_raw(_x[i], _y[i], _r[i] * 2.0, Color(color.r, color.g, color.b, alpha * fade), 0.04, 0.03, 0.06, 0.0)
		_next[i] -= dt
		if _next[i] <= 0.0:
			_next[i] = _tick
			var found := enemies.overlap(_x[i], _y[i], _r[i])
			for h in found:
				var e := enemies.hits[h]
				enemies.apply_cold(e, _chill)
				a.combat.hit(e, damage, src, 0.0, 0.0, false)
		i -= 1


func clear() -> void:
	_x.clear()
	_y.clear()
	_r.clear()
	_age.clear()
	_next.clear()
