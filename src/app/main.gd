extends Node
## Root of the main scene: the game shell. It owns the two things that are
## ever on screen - the menus, or a run (Arena + HUD) - and the flow between
## them: start run -> play -> results -> again or home.
##
## Command-line modes (arguments after `--`):
##   --test[=suite]     automated tests, then exit        (tests/test_runner.gd)
##   --sim=N            balance simulation, then exit      (tests/sim_runner.gd)
##   --bench            performance scenarios, then exit   (tests/sim_runner.gd)
##   --shots=<folder>   screenshot tour of every screen    (tests/shot_tour.gd)
##   --device-check     on-device self-test, prints a report (src/app/device_check.gd)
##   --play             skip the menu and start a run
##   --autoplay         let the bot play (attract mode / soak test)
##   --perf             show the frame-time overlay in a run
##   --profile=<name>   use a separate save file instead of the real profile
##   --snap=<file.png>  save a screenshot after --snap-after seconds (default 3), then quit

var menu: MenuShell
var arena: Arena
var hud: Hud

var _results_layer: CanvasLayer
var _results: ResultsScreen
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _last_mode := CampaignService.MODE_SECTOR
var _busy := false
var _checkpoint_in := CHECKPOINT_SECONDS

## How often the run in progress is written to the profile, so that its
## rewards survive the app being closed or killed mid-fight.
const CHECKPOINT_SECONDS := 8.0


func _ready() -> void:
	# Development tooling lives in tests/ and is left out of exported builds,
	# so it is loaded by path here and never referenced by class name.
	if App.cli.has("test"):
		if _run_tool("res://tests/test_runner.gd"):
			return
	elif App.cli.has("sim") or App.cli.has("bench"):
		if _run_tool("res://tests/sim_runner.gd"):
			return

	get_tree().quit_on_go_back = false
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Palette.BG
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)

	_results_layer = CanvasLayer.new()
	_results_layer.layer = 20
	add_child(_results_layer)

	menu = MenuShell.new()
	add_child(menu)
	menu.play_pressed.connect(start_run)
	App.audio.play_music("menu")

	# A run that was cut short last time (app closed or killed) is paid out now.
	var recovered := {} if App.cli.has("device-check") else RunLedger.recover_pending(App)

	if App.cli.has("shots"):
		_run_tool("res://tests/shot_tour.gd")
	elif App.cli.has("device-check"):
		add_child(DeviceCheck.new(self))
	elif App.cli.has("play") or App.cli.has("autoplay"):
		start_run(App.cli_text("mode", CampaignService.MODE_SECTOR))
	elif not recovered.is_empty():
		menu.open_dialog(RecoveredRunModal.new(recovered))
		menu.refresh_current()
	if App.cli.has("snap"):
		_snap_later(App.cli_text("snap"), float(App.cli_text("snap-after", "3")))
	await _fade_to(0.0, 0.5)


## Development aid: capture whatever is on screen after a delay, then quit.
func _snap_later(path: String, seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.1)).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _process(delta: float) -> void:
	if not _run_in_progress():
		return
	_checkpoint_in -= delta
	if _checkpoint_in <= 0.0:
		_checkpoint_in = CHECKPOINT_SECONDS
		_checkpoint(false)


func _run_in_progress() -> bool:
	return in_run() and arena.state != Arena.State.ENDING and arena.state != Arena.State.ENDED


func _checkpoint(flush: bool) -> void:
	if _run_in_progress() and arena.autopilot == null:
		RunLedger.checkpoint(App, arena.build_result(false, false, true), flush)


func _run_tool(path: String) -> bool:
	if not ResourceLoader.exists(path):
		push_warning("%s is not part of this build." % path)
		return false
	var script := load(path) as GDScript
	if script == null:
		return false
	add_child(script.new())
	return true


# ------------------------------------------------------------------ run flow

func start_run(mode: String = CampaignService.MODE_SECTOR) -> void:
	if _busy:
		return
	_busy = true
	_last_mode = mode
	await _fade_to(1.0, 0.22)
	_teardown_run()
	menu.set_active(false)

	var config := RunConfig.from_profile(App, mode)
	config.autopilot = App.cli.has("autoplay")
	if App.cli.has("seed"):
		config.rng_seed = App.cli_int("seed", 0)
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.setup(App, config)
	hud = Hud.new(arena)
	add_child(hud)
	hud.quit_requested.connect(arena.abandon)
	arena.run_ended.connect(_on_run_ended)
	arena.start()
	_checkpoint_in = CHECKPOINT_SECONDS
	_busy = false
	await _fade_to(0.0, 0.3)


func _on_run_ended(result: Dictionary) -> void:
	var summary := RunLedger.settle(App, result)
	# Let the final explosion land before the summary covers it.
	if not bool(result.get("abandoned", false)):
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(arena):
		return
	App.audio.play_music("menu")
	_results = ResultsScreen.new(result, summary)
	_results_layer.add_child(_results)
	_results.play_again_pressed.connect(_on_play_again)
	_results.home_pressed.connect(_on_home)


func _on_play_again() -> void:
	# Interstitials live here and only here: between runs, never during one.
	await App.ads.maybe_show_interstitial("post_run")
	start_run(_last_mode)


func _on_home() -> void:
	await App.ads.maybe_show_interstitial("post_run")
	await _fade_to(1.0, 0.22)
	_teardown_run()
	menu.set_active(true)
	await _fade_to(0.0, 0.3)


func _teardown_run() -> void:
	if _results != null and is_instance_valid(_results):
		_results.queue_free()
	_results = null
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
	hud = null
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
	arena = null


func in_run() -> bool:
	return arena != null and is_instance_valid(arena)


# -------------------------------------------------------------------- shell

func _fade_to(alpha: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, seconds)
	await tween.finished


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_go_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			# The app may not come back: bank the run as it stands, on disk, now.
			_checkpoint(true)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_go_back()


## Android back / Escape: close the top-most thing, pause a run, or leave.
func _go_back() -> void:
	if App.ads.is_showing() or _busy:
		return
	if _results != null and is_instance_valid(_results):
		return
	if hud != null and is_instance_valid(hud):
		hud.handle_back()
		return
	if menu != null and not menu.handle_back():
		App.save.flush()
		get_tree().quit()
