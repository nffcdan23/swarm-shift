class_name MeterBar
extends Control
## A drawn progress bar: rounded track, glowing fill, a bright leading edge,
## and - for health - a pale "ghost" that drains after a hit so the size of the
## loss registers.

var fill_color := Palette.CYAN:
	set(value):
		fill_color = value
		queue_redraw()

var back_color := Color(0.06, 0.09, 0.15, 0.85)
var show_ghost := false
var radius := 6.0
var segments := 0

var _value := 0.0
var _shown := 0.0
var _ghost := 0.0
var _flash := 0.0


static func make(color: Color, height: float = 14.0, ghost: bool = false) -> MeterBar:
	var bar := MeterBar.new()
	bar.fill_color = color
	bar.show_ghost = ghost
	bar.custom_minimum_size = Vector2(40, height)
	bar.radius = height * 0.5
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar


## Sets the target 0..1. The bar eases towards it; `snap` jumps immediately.
func set_value(value: float, snap: bool = false) -> void:
	value = clampf(value, 0.0, 1.0)
	if value < _value - 0.001:
		_flash = 1.0
	_value = value
	if snap:
		_shown = value
		_ghost = value
	queue_redraw()


func value() -> float:
	return _value


func _process(delta: float) -> void:
	var moving := false
	if absf(_shown - _value) > 0.0005:
		_shown = lerpf(_shown, _value, 1.0 - exp(-delta * 14.0))
		moving = true
	if _ghost > _shown:
		_ghost = maxf(_ghost - delta * 0.45, _shown)
		moving = true
	elif _ghost < _shown:
		_ghost = _shown
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		moving = true
	if moving:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := minf(radius, h * 0.5)
	_rounded(Rect2(0, 0, w, h), back_color, r)
	if show_ghost and _ghost > _shown + 0.002:
		_rounded(Rect2(0, 0, w * _ghost, h), Color(1, 1, 1, 0.55), r)
	if _shown > 0.002:
		var fw := maxf(w * _shown, h)
		var color := fill_color.lerp(Color.WHITE, _flash * 0.7)
		_rounded(Rect2(0, 0, fw, h), color, r)
		# Top sheen and a bright leading edge sell it as lit from within.
		_rounded(Rect2(2, 1.5, maxf(fw - 4.0, 0.0), h * 0.32), Color(1, 1, 1, 0.22), r * 0.5)
		if fw < w - 2.0:
			draw_rect(Rect2(fw - 2.5, 1.0, 2.5, h - 2.0), Color(1, 1, 1, 0.75))
	if segments > 1:
		for i in range(1, segments):
			var x := w * float(i) / float(segments)
			draw_rect(Rect2(x - 1.0, 0, 2.0, h), Color(0.02, 0.03, 0.06, 0.7))


func _rounded(rect: Rect2, color: Color, r: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	if r < 1.0:
		draw_rect(rect, color)
		return
	draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - r * 2.0, rect.size.y), color)
	draw_rect(Rect2(rect.position.x, rect.position.y + r, r, rect.size.y - r * 2.0), color)
	draw_rect(Rect2(rect.end.x - r, rect.position.y + r, r, rect.size.y - r * 2.0), color)
	draw_circle(rect.position + Vector2(r, r), r, color)
	draw_circle(Vector2(rect.end.x - r, rect.position.y + r), r, color)
	draw_circle(Vector2(rect.position.x + r, rect.end.y - r), r, color)
	draw_circle(rect.end - Vector2(r, r), r, color)
