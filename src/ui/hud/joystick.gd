class_name Joystick
extends Control
## One-thumb movement. Touch anywhere that is not a button and drag: the stick
## appears under the thumb, so there is no fixed position to find by feel.
##
## The anchor follows the thumb once it is dragged past the rim, which keeps a
## reversal of direction to a short flick instead of a long swipe back across
## the stick. Full speed is reached well before the rim.

const RADIUS := 78.0
const DEADZONE := 9.0
## Fraction of the radius at which movement reaches full speed.
const FULL_AT := 0.62

## Current input, length 0..1.
var vector := Vector2.ZERO
var enabled := true:
	set(value):
		enabled = value
		if not value:
			release()

var _finger := -1
var _origin := Vector2.ZERO
var _thumb := Vector2.ZERO
var _fade := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Purely a drawing surface: input comes through _unhandled_input so that
	# anything a HUD button consumes never reaches the stick.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _finger == -1:
			_finger = touch.index
			_origin = _to_local(touch.position)
			_thumb = _origin
			vector = Vector2.ZERO
		elif not touch.pressed and touch.index == _finger:
			release()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _finger:
			_thumb = _to_local(drag.position)
			var offset := _thumb - _origin
			var dist := offset.length()
			if dist > RADIUS:
				_origin = _thumb - offset / dist * RADIUS
				offset = _thumb - _origin
				dist = RADIUS
			if dist <= DEADZONE:
				vector = Vector2.ZERO
			else:
				var strength := clampf((dist - DEADZONE) / (RADIUS * FULL_AT - DEADZONE), 0.0, 1.0)
				vector = offset / dist * strength


func _to_local(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position


func release() -> void:
	_finger = -1
	vector = Vector2.ZERO


func is_held() -> bool:
	return _finger != -1


## Keyboard movement for desktop development; ignored while a finger is down.
func keyboard_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v.limit_length(1.0)


func current() -> Vector2:
	if _finger != -1:
		return vector
	return keyboard_vector() if enabled else Vector2.ZERO


func _process(delta: float) -> void:
	var target := 1.0 if _finger != -1 else 0.0
	if absf(_fade - target) > 0.01 or _finger != -1:
		_fade = lerpf(_fade, target, 1.0 - exp(-delta * 16.0))
		queue_redraw()


func _draw() -> void:
	if _fade < 0.02:
		return
	var ring := Palette.with_alpha(Palette.CYAN, 0.22 * _fade)
	draw_circle(_origin, RADIUS, Palette.with_alpha(Palette.CYAN, 0.05 * _fade))
	draw_arc(_origin, RADIUS, 0.0, TAU, 48, ring, 2.5, true)
	var knob := _origin + (_thumb - _origin).limit_length(RADIUS)
	draw_circle(knob, 30.0, Palette.with_alpha(Palette.CYAN, 0.2 * _fade))
	draw_arc(knob, 30.0, 0.0, TAU, 32, Palette.with_alpha(Palette.CYAN, 0.6 * _fade), 2.5, true)
