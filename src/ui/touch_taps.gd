class_name TouchTaps
extends Node
## Lets every finger press buttons, not only the first one on the glass.
##
## Godot turns one touch at a time into mouse events - the first finger down -
## and buttons listen to the mouse. In a one-thumb game that thumb is usually
## already on the screen steering, so a tap from the other hand on PAUSE or on
## an upgrade card would otherwise do nothing at all, which reads as a freeze.
##
## This node mirrors the engine's rule to know which finger is "the mouse" and
## turns a quick, still tap by any other finger into a click at that spot. The
## GUI then does its own hit-testing and layering, so no button has to change.

const MAX_SECONDS := 0.7
## Viewport units; the design width is 720.
const MAX_TRAVEL := 44.0

## Taps converted since launch. Tests and the device self-test read this.
static var converted := 0

## Every finger currently on the glass, by touch index.
static var _down: Dictionary = {}

var _primary := -1
## touch index -> {"at": Vector2, "msec": int}
var _others: Dictionary = {}


## True while that finger is on the screen.
static func is_down(index: int) -> bool:
	return _down.has(index)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_down[touch.index] = true
	else:
		_down.erase(touch.index)
	if touch.pressed:
		if _primary == -1:
			_primary = touch.index
		elif touch.index != _primary:
			_others[touch.index] = {"at": touch.position, "msec": Time.get_ticks_msec()}
		return
	if touch.index == _primary:
		_primary = -1
		return
	if not _others.has(touch.index):
		return
	var start: Dictionary = _others[touch.index]
	_others.erase(touch.index)
	if touch.canceled:
		return
	var held := float(Time.get_ticks_msec() - int(start.msec)) / 1000.0
	var origin: Vector2 = start.at
	if held <= MAX_SECONDS and origin.distance_to(touch.position) <= MAX_TRAVEL:
		# Deferred so the click is not delivered from inside this event's own dispatch.
		_click.call_deferred(touch.position)


func _click(at: Vector2) -> void:
	if not is_inside_tree() or not Input.emulate_mouse_from_touch:
		return
	converted += 1
	var viewport := get_viewport()
	# Press and release together: nothing the steering thumb does in between
	# can move the "mouse" off the button.
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = at
		click.global_position = at
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		viewport.push_input(click, true)
