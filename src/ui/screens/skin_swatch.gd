class_name SkinSwatch
extends Control
## A live, animated skin in a small square, for the Arsenal. The same layers as
## in a run, so what you buy is what you get.

var _core: CoreVisual
var _skin: Dictionary
var _tint: Color
var _bare := false


static func make(skin: Dictionary, core_color: Color, pixels: float, locked: bool = false) -> SkinSwatch:
	var swatch := SkinSwatch.new()
	swatch._skin = skin
	swatch._tint = core_color
	swatch._bare = locked
	swatch.custom_minimum_size = Vector2(pixels, pixels)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return swatch


func _ready() -> void:
	_core = CoreVisual.new()
	add_child(_core)
	_core.build(_skin, _tint)
	if _bare:
		_core.modulate = Color(1, 1, 1, 0.55)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_core.position = size * 0.5
	# The body fills about 60% of the sprite: this lets the plates and aura fit.
	var pixels := minf(size.x, size.y)
	_core.scale = Vector2.ONE * (pixels / 330.0)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_core.animate(delta)
