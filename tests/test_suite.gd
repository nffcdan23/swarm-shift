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
