class_name TestRunner
extends Node
## Headless test entry point:
##   godot --headless --path . -- --test                 run everything
##   godot --headless --path . -- --test=services        run one suite
##   godot --headless --path . -- --test=gameplay --only=boss --trace
##                                    run tests whose name contains "boss",
##                                    printing each name as it starts
## Exits with status 1 if any check fails.

const SUITES := {
	"scripts": "res://tests/test_scripts.gd",
	"data": "res://tests/test_data.gd",
	"services": "res://tests/test_services.gd",
	"gameplay": "res://tests/test_gameplay.gd",
	"ui": "res://tests/test_ui.gd",
}


func _ready() -> void:
	await get_tree().process_frame
	var only := App.cli_text("test", "1")
	var pick := App.cli_text("only")
	var trace := App.cli.has("trace")
	var total_checks := 0
	var failures: PackedStringArray = []
	var started := Time.get_ticks_msec()
	for suite_name: String in SUITES:
		if only != "1" and only != suite_name:
			continue
		var path: String = SUITES[suite_name]
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failures.append("%s: suite failed to load" % suite_name)
			continue
		var suite: TestSuite = script.new()
		suite.app = App
		suite.host = self
		var ran := 0
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			if not pick.is_empty() and not method_name.contains(pick):
				continue
			if trace:
				print("    > ", method_name)
			suite.begin(method_name)
			@warning_ignore("redundant_await")
			await suite.call(method_name)
			ran += 1
		total_checks += suite.checks
		failures.append_array(suite.failures)
		print("  %-10s %2d tests, %4d checks, %d failed" % [suite_name, ran, suite.checks, suite.failures.size()])
	print("")
	for failure in failures:
		print("  FAIL  ", failure)
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	print("%s - %d checks, %d failed (%.1fs)" % ["PASSED" if failures.is_empty() else "FAILED", total_checks, failures.size(), seconds])
	get_tree().quit(0 if failures.is_empty() else 1)
