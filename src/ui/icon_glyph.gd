class_name IconGlyph
extends Control
## A vector icon from IconLibrary as a control. Optional soft glow behind it.

var icon_id := "star":
	set(value):
		icon_id = value
		queue_redraw()

var color := Palette.TEXT:
	set(value):
		color = value
		queue_redraw()

var glow := false:
	set(value):
		glow = value
		queue_redraw()

var weight := 1.0


static func make(id: String, pixels: float, tint: Color = Palette.TEXT, with_glow: bool = false) -> IconGlyph:
	var glyph := IconGlyph.new()
	glyph.icon_id = id
	glyph.color = tint
	glyph.glow = with_glow
	glyph.custom_minimum_size = Vector2(pixels, pixels)
	glyph.size = Vector2(pixels, pixels)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return glyph


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if glow:
		# Cheap bloom: the same strokes, much fatter and nearly transparent.
		IconLibrary.draw(self, icon_id, rect, Palette.with_alpha(color, 0.16), weight * 3.2)
		IconLibrary.draw(self, icon_id, rect, Palette.with_alpha(color, 0.22), weight * 1.9)
	IconLibrary.draw(self, icon_id, rect, color, weight)
