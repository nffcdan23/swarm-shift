class_name SignalRace
extends RefCounted
## Waits for whichever of several signals on one object fires first.
##
##   var result := await SignalRace.first(bridge, ["rewarded_dismissed", "rewarded_failed_to_show"], 300.0)
##
## Returns [signal_name, arg1, arg2...] for the winner (up to two arguments),
## or [] if none fired within `timeout` seconds. A signal without arguments
## returns a one-element array, so it can be told apart from a timeout.

const POLL := 0.05


static func first(source: Object, signal_names: Array, timeout: float) -> Array:
	var state := {"result": []}
	var handlers := {}
	for signal_name: String in signal_names:
		var handler := func(a: Variant = null, b: Variant = null) -> void:
			if state.result.is_empty():
				var won: Array = [signal_name]
				for value: Variant in [a, b]:
					if value != null:
						won.append(value)
				state.result = won
		handlers[signal_name] = handler
		source.connect(signal_name, handler)
	var tree := Engine.get_main_loop() as SceneTree
	var waited := 0.0
	while state.result.is_empty() and waited < timeout and is_instance_valid(source):
		await tree.create_timer(POLL).timeout
		waited += POLL
	if is_instance_valid(source):
		for signal_name: String in signal_names:
			source.disconnect(signal_name, handlers[signal_name])
	return state.result
