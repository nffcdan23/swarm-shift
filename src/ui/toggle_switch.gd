class_name ToggleSwitch
extends Control
## An on/off switch sized for thumbs.

signal toggled(on: bool)

var on := false:
	set(value):
		on = value
		queue_redraw()

var _knob := 0.0


static func make(initial: bool) -> ToggleSwitch:
	var toggle := ToggleSwitch.new()
	toggle.on = initial
	toggle._knob = 1.0 if initial else 0.0
	toggle.custom_minimum_size = Vector2(96, 52)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return toggle


func _gui_input(event: InputEvent) -> void:
	var tapped := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if tapped:
		on = not on
		App.audio.play("ui_tab")
		App.haptics.light()
		toggled.emit(on)
		accept_event()


func _process(delta: float) -> void:
	var target := 1.0 if on else 0.0
	if absf(_knob - target) > 0.001:
		_knob = lerpf(_knob, target, 1.0 - exp(-delta * 18.0))
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var w := size.x
	var r := h * 0.5
	var track := Color(0.08, 0.12, 0.2).lerp(Palette.with_alpha(Palette.CYAN, 0.9), _knob)
	draw_circle(Vector2(r, r), r, track)
	draw_circle(Vector2(w - r, r), r, track)
	draw_rect(Rect2(r, 0, w - h, h), track)
	var x := lerpf(r, w - r, _knob)
	draw_circle(Vector2(x, r), r - 5.0, Color.WHITE if on else Palette.MUTED)
