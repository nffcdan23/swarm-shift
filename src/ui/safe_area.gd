class_name SafeArea
extends MarginContainer
## Keeps its children clear of notches, rounded corners and the home indicator.
## Converts the OS-reported safe rectangle (in physical pixels) into the
## canvas's design units and applies it as margins, plus a small base padding.

var base_padding := 12


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(apply)
	apply()


func apply() -> void:
	var window := DisplayServer.window_get_size()
	var view := get_viewport_rect().size
	var left := 0.0
	var top := 0.0
	var right := 0.0
	var bottom := 0.0
	if window.x > 0 and window.y > 0 and OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var scale_x := view.x / float(window.x)
		var scale_y := view.y / float(window.y)
		left = maxf(float(safe.position.x), 0.0) * scale_x
		top = maxf(float(safe.position.y), 0.0) * scale_y
		right = maxf(float(window.x - safe.end.x), 0.0) * scale_x
		bottom = maxf(float(window.y - safe.end.y), 0.0) * scale_y
	add_theme_constant_override("margin_left", int(left) + base_padding)
	add_theme_constant_override("margin_top", int(top) + base_padding)
	add_theme_constant_override("margin_right", int(right) + base_padding)
	add_theme_constant_override("margin_bottom", int(bottom) + base_padding)
