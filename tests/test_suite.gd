class_name TestSuite
extends RefCounted
## Base class for a group of tests. Any method whose name starts with `test_`
## is run by TestRunner. Use the `check*` helpers; a failed check records the
## failure and the test carries on, so one run reports everything that is wrong.

var app: AppRoot
var host: Node
var failures: PackedStringArray = []
var checks := 0
var _current := ""


func begin(test_name: String) -> void:
	_current = test_name


func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [_current, message])
	return condition


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance, "%s (expected ~%s, got %s)" % [message, str(expected), str(actual)])


## Fresh in-memory profile for the next test.
func fresh_profile() -> MemorySaveBackend:
	var backend := MemorySaveBackend.new()
	app.boot(backend)
	return backend


# ---------------------------------------------------------------------------
# Helpers for tests that drive the real scene tree.

func wait_frames(count: int) -> void:
	for i in count:
		await host.get_tree().process_frame


func wait_seconds(seconds: float) -> void:
	await host.get_tree().create_timer(seconds).timeout


## Mouse press or release at a viewport position, pushed through the engine's
## GUI input path (hit-testing, filtering and layering included).
func press_at(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.global_position = at
	host.get_viewport().push_input(event, true)


func tap_at(at: Vector2) -> void:
	press_at(at, true)
	await wait_frames(1)
	press_at(at, false)
	await wait_frames(1)


## One finger going down or lifting, as the screen reports it. Unlike
## `press_at` this does not move the "mouse": use it for second fingers.
func touch_at(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = down
	event.position = at
	host.get_viewport().push_input(event, true)


func drag_to(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	host.get_viewport().push_input(event, true)
