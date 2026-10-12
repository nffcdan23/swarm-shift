class_name DamageNumbers
extends Node2D
## Pooled floating combat text. Capped and recycled: when the pool is busy,
## ordinary hits are dropped first and critical hits still get through, so the
## screen never turns into a wall of digits.

const LIFETIME := 0.6

var enabled := true

var _labels: Array[Label] = []
var _age := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _base_scale := PackedFloat32Array()
var _active := 0
var _cap := 44


func setup(cap: int, font: Font) -> void:
	_cap = cap
	_age.resize(cap)
	_vx.resize(cap)
	_vy.resize(cap)
	_base_scale.resize(cap)
	for i in cap:
		var label := Label.new()
		label.visible = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(160, 44)
		label.pivot_offset = Vector2(80, 22)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font != null:
			label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_constant_override("outline_size", 7)
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.92))
		add_child(label)
		_labels.append(label)


func pop(x: float, y: float, text: String, color: Color, scale_mult: float = 1.0, important: bool = false) -> void:
	if not enabled or not _has_room(important):
		return
	_show(x, y, text, color, scale_mult)


func number(x: float, y: float, amount: float, crit: bool) -> void:
	# Check for room before formatting: at peak this is called hundreds of
	# times a second and most calls are dropped.
	if not enabled or not _has_room(crit):
		return
	if crit:
		_show(x, y, Fmt.compact(amount) + "!", Color(1.0, 0.86, 0.3), 1.35)
	else:
		_show(x, y, Fmt.compact(amount), Color(0.93, 0.97, 1.0), 0.85)


func _has_room(important: bool) -> bool:
	if important:
		if _active >= _cap:
			_release(0)
		return true
	if _active >= _cap:
		return false
	# Ordinary numbers back off once the pool is half full.
	return not (_active * 2 > _cap and randf() < 0.6)


func _show(x: float, y: float, text: String, color: Color, scale_mult: float) -> void:
	var i := _active
	_active += 1
	var label := _labels[i]
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(x - 80.0 + randf_range(-10.0, 10.0), y - 22.0)
	label.visible = true
	_age[i] = 0.0
	_vx[i] = randf_range(-26.0, 26.0)
	_vy[i] = -randf_range(70.0, 105.0)
	_base_scale[i] = scale_mult


func update(delta: float) -> void:
	var i := 0
	while i < _active:
		var age := _age[i] + delta
		if age >= LIFETIME:
			_release(i)
			continue
		_age[i] = age
		var label := _labels[i]
		var t := age / LIFETIME
		label.position += Vector2(_vx[i], _vy[i]) * delta
		_vy[i] += 150.0 * delta
		# Quick overshoot on entry, then settle and fade.
		var punch := 1.0 + 0.55 * maxf(1.0 - t * 5.0, 0.0)
		var s := _base_scale[i] * punch
		label.scale = Vector2(s, s)
		label.modulate.a = 1.0 - smoothstep(0.55, 1.0, t)
		i += 1


func _release(i: int) -> void:
	_active -= 1
	var last := _active
	_labels[i].visible = false
	if i != last:
		# Keep live labels packed at the front of the pool.
		var moved := _labels[last]
		_labels[last] = _labels[i]
		_labels[i] = moved
		_age[i] = _age[last]
		_vx[i] = _vx[last]
		_vy[i] = _vy[last]
		_base_scale[i] = _base_scale[last]


func clear() -> void:
	for i in _active:
		_labels[i].visible = false
	_active = 0
