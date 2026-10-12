class_name FxSystem
extends RefCounted
## Short-lived visual feedback: shockwave rings, flashes, lightning, explosions,
## death bursts and screen shake. Gameplay calls the named recipes below; the
## transient shapes are re-submitted to the draw layers each step by `update()`.
##
## Nothing here affects the simulation, so it is free to use unseeded randomness.

const MAX_RINGS := 64
const MAX_FLASHES := 72
const MAX_BOLTS := 40

## 0..1, decays over time. Camera offset scales with trauma squared.
var trauma := 0.0

var _g: ArenaGfx
var _glow_cell := 0.0
var _flare_cell := 0.0
var _beam_cell := 0.0
var _shake_decay := 2.6

var _ring_n := 0
var _ring_x := PackedFloat32Array()
var _ring_y := PackedFloat32Array()
var _ring_r0 := PackedFloat32Array()
var _ring_r1 := PackedFloat32Array()
var _ring_age := PackedFloat32Array()
var _ring_life := PackedFloat32Array()
var _ring_thick := PackedFloat32Array()
var _ring_fill := PackedFloat32Array()
var _ring_color: Array[Color] = []

var _flash_n := 0
var _flash_x := PackedFloat32Array()
var _flash_y := PackedFloat32Array()
var _flash_size := PackedFloat32Array()
var _flash_age := PackedFloat32Array()
var _flash_life := PackedFloat32Array()
var _flash_cell := PackedFloat32Array()
var _flash_color: Array[Color] = []

var _bolt_n := 0
var _bolt_points: Array[PackedVector2Array] = []
var _bolt_age := PackedFloat32Array()
var _bolt_life := PackedFloat32Array()
var _bolt_width := PackedFloat32Array()
var _bolt_color: Array[Color] = []


func setup(gfx: ArenaGfx, shake_decay: float) -> void:
	_g = gfx
	_shake_decay = shake_decay
	_glow_cell = gfx.cell("glow")
	_flare_cell = gfx.cell("flare")
	_beam_cell = gfx.cell("beam")
	for arr: PackedFloat32Array in [_ring_x, _ring_y, _ring_r0, _ring_r1, _ring_age, _ring_life, _ring_thick, _ring_fill]:
		arr.resize(MAX_RINGS)
	_ring_color.resize(MAX_RINGS)
	for arr: PackedFloat32Array in [_flash_x, _flash_y, _flash_size, _flash_age, _flash_life, _flash_cell]:
		arr.resize(MAX_FLASHES)
	_flash_color.resize(MAX_FLASHES)
	for arr: PackedFloat32Array in [_bolt_age, _bolt_life, _bolt_width]:
		arr.resize(MAX_BOLTS)
	_bolt_color.resize(MAX_BOLTS)
	_bolt_points.resize(MAX_BOLTS)


# ----------------------------------------------------------------- primitives

## Expanding ring from radius r0 to r1 over `life` seconds.
func ring(x: float, y: float, r0: float, r1: float, life: float, color: Color, thickness: float = 0.14, fill: float = 0.0) -> void:
	if _ring_n >= MAX_RINGS:
		return
	var i := _ring_n
	_ring_n += 1
	_ring_x[i] = x
	_ring_y[i] = y
	_ring_r0[i] = r0
	_ring_r1[i] = r1
	_ring_age[i] = 0.0
	_ring_life[i] = life
	_ring_thick[i] = thickness
	_ring_fill[i] = fill
	_ring_color[i] = color


func flash(x: float, y: float, size: float, color: Color, life: float = 0.14, flare: bool = false) -> void:
	if _flash_n >= MAX_FLASHES:
		return
	var i := _flash_n
	_flash_n += 1
	_flash_x[i] = x
	_flash_y[i] = y
	_flash_size[i] = size
	_flash_age[i] = 0.0
	_flash_life[i] = life
	_flash_cell[i] = _flare_cell if flare else _glow_cell
	_flash_color[i] = color


## Jagged arc between two points that lingers for a moment.
func lightning(x0: float, y0: float, x1: float, y1: float, color: Color, width: float = 11.0, life: float = 0.15) -> void:
	if _bolt_n >= MAX_BOLTS:
		return
	var a := Vector2(x0, y0)
	var b := Vector2(x1, y1)
	var span := a.distance_to(b)
	var segments := clampi(int(span / 30.0), 2, 9)
	var normal := (b - a).orthogonal().normalized()
	var points := PackedVector2Array()
	points.resize(segments + 1)
	points[0] = a
	points[segments] = b
	for s in range(1, segments):
		var along := float(s) / float(segments)
		points[s] = a.lerp(b, along) + normal * randf_range(-1.0, 1.0) * minf(span * 0.11, 26.0)
	var i := _bolt_n
	_bolt_n += 1
	_bolt_points[i] = points
	_bolt_age[i] = 0.0
	_bolt_life[i] = life
	_bolt_width[i] = width
	_bolt_color[i] = color
	flash(x1, y1, 46.0, color, 0.12)


func shake(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


# -------------------------------------------------------------------- recipes

func spark(x: float, y: float, color: Color, dir_x: float, dir_y: float) -> void:
	var angle := atan2(dir_y, dir_x) + PI
	_g.particles.burst(x, y, 3, 80.0, 260.0, 0.12, 0.26, 9.0, 1.0, color, 6.0, 1.6, angle, 1.6)


func death(x: float, y: float, color: Color, radius: float) -> void:
	var amount := 5 + int(radius * 0.22)
	_g.particles.burst(x, y, amount, 60.0, 190.0 + radius * 4.0, 0.25, 0.55, 7.0 + radius * 0.3, 1.0, color, 4.5, 1.2)
	flash(x, y, radius * 4.2, color, 0.16)
	if radius > 20.0:
		ring(x, y, radius * 0.6, radius * 2.6, 0.3, color, 0.2)


func explosion(x: float, y: float, radius: float, color: Color, strength: float = 1.0) -> void:
	ring(x, y, radius * 0.3, radius, 0.26, color, 0.2, 0.3)
	flash(x, y, radius * 2.7, color, 0.16)
	flash(x, y, radius * 1.3, Color(1, 1, 1, 0.9), 0.09)
	var amount := clampi(int(radius * 0.16), 4, 22)
	_g.particles.burst(x, y, amount, radius * 2.0, radius * 5.5, 0.22, 0.5, 11.0, 1.5, color, 5.5, 1.8)
	shake(clampf(radius / 900.0, 0.02, 0.3) * strength)


func shockwave(x: float, y: float, radius: float, color: Color) -> void:
	ring(x, y, 20.0, radius, 0.34, color, 0.1, 0.12)
	ring(x, y, 10.0, radius * 0.7, 0.28, Color(1, 1, 1, 0.7), 0.06)
	flash(x, y, radius * 1.4, color, 0.2)


func pickup_pop(x: float, y: float, color: Color) -> void:
	_g.particles.burst(x, y, 2, 30.0, 110.0, 0.14, 0.28, 7.0, 1.0, color, 5.0)


func number(x: float, y: float, amount: float, crit: bool) -> void:
	_g.numbers.number(x, y, amount, crit)


func text(x: float, y: float, message: String, color: Color, scale: float = 1.1) -> void:
	_g.numbers.pop(x, y, message, color, scale, true)


# --------------------------------------------------------------------- update

func update(delta: float) -> void:
	trauma = maxf(trauma - _shake_decay * delta, 0.0)

	var i := 0
	while i < _ring_n:
		var age := _ring_age[i] + delta
		if age >= _ring_life[i]:
			_ring_n -= 1
			var last := _ring_n
			_ring_x[i] = _ring_x[last]
			_ring_y[i] = _ring_y[last]
			_ring_r0[i] = _ring_r0[last]
			_ring_r1[i] = _ring_r1[last]
			_ring_age[i] = _ring_age[last]
			_ring_life[i] = _ring_life[last]
			_ring_thick[i] = _ring_thick[last]
			_ring_fill[i] = _ring_fill[last]
			_ring_color[i] = _ring_color[last]
			continue
		_ring_age[i] = age
		var t := age / _ring_life[i]
		var eased := 1.0 - (1.0 - t) * (1.0 - t)
		var radius := lerpf(_ring_r0[i], _ring_r1[i], eased)
		var color := _ring_color[i]
		color.a *= 1.0 - t
		_g.rings.add_raw(_ring_x[i], _ring_y[i], radius * 2.0, color, _ring_thick[i] * (1.0 - t * 0.6), 0.05, _ring_fill[i] * (1.0 - t), 0.0)
		i += 1

	i = 0
	while i < _flash_n:
		var age := _flash_age[i] + delta
		if age >= _flash_life[i]:
			_flash_n -= 1
			var last := _flash_n
			_flash_x[i] = _flash_x[last]
			_flash_y[i] = _flash_y[last]
			_flash_size[i] = _flash_size[last]
			_flash_age[i] = _flash_age[last]
			_flash_life[i] = _flash_life[last]
			_flash_cell[i] = _flash_cell[last]
			_flash_color[i] = _flash_color[last]
			continue
		_flash_age[i] = age
		var t := age / _flash_life[i]
		var color := _flash_color[i]
		color.a *= 1.0 - t
		_g.beams.add_sprite(_flash_x[i], _flash_y[i], 0.0, _flash_size[i] * (0.7 + 0.5 * t), color, _flash_cell[i])
		i += 1

	i = 0
	while i < _bolt_n:
		var age := _bolt_age[i] + delta
		if age >= _bolt_life[i]:
			_bolt_n -= 1
			var last := _bolt_n
			_bolt_points[i] = _bolt_points[last]
			_bolt_age[i] = _bolt_age[last]
			_bolt_life[i] = _bolt_life[last]
			_bolt_width[i] = _bolt_width[last]
			_bolt_color[i] = _bolt_color[last]
			continue
		_bolt_age[i] = age
		var t := age / _bolt_life[i]
		var color := _bolt_color[i]
		color.a *= 1.0 - t * t
		var width := _bolt_width[i] * (1.0 - 0.5 * t)
		var points := _bolt_points[i]
		for s in points.size() - 1:
			var a := points[s]
			var b := points[s + 1]
			_g.beams.add_segment(a.x, a.y, b.x, b.y, width, color, _beam_cell)
		i += 1


func clear() -> void:
	_ring_n = 0
	_flash_n = 0
	_bolt_n = 0
	trauma = 0.0
