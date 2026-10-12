class_name DeviceCheck
extends Node
## On-device self-test. Launch the installed app with the argument
## `--device-check` and it reports on the things a simulator or a Mac cannot
## prove: the real screen and safe area, the renderer, audio, file storage,
## touch routing, and how the game runs under load on this hardware.
##
##   xcrun devicectl device process launch --console --device <id> <bundle-id> -- --device-check
##
## Every line is printed with a `[device-check]` prefix and, when the run
## completes, written to user://device_check.txt (the app's Documents folder).
## On iOS the engine's console output is not forwarded to an attached Mac, so
## the file is the reliable copy. `SHOT_READY <name>` marks a moment worth a
## screenshot; the check holds still for a few seconds after each.
##
## It never touches the player's profile: storage is tested with its own file,
## the run it plays is not settled, and analytics is paused while it runs.

## Seconds to hold still at each screenshot point (`--hold=N` overrides).
const DEFAULT_HOLD := 2.6
const REPORT_PATH := "user://device_check.txt"

var _main: Node
var _lines: PackedStringArray = []
var _passes := 0
var _warnings: PackedStringArray = []
var _failures: PackedStringArray = []


func _init(main: Node) -> void:
	_main = main


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	App.analytics.enabled = false
	# Remove the previous report first: if this run is interrupted, there must
	# be no stale file that could be mistaken for its result.
	if FileAccess.file_exists(REPORT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPORT_PATH))
	_say("generated: " + Time.get_datetime_string_from_system(false, true))
	await get_tree().create_timer(1.2).timeout
	_check_platform()
	_check_display()
	await _shot("menu")
	await _check_input()
	await _check_audio()
	_check_storage()
	await _check_gameplay()
	_finish()


# ------------------------------------------------------------------ reporting

func _say(text: String) -> void:
	_lines.append(text)
	print("[device-check] ", text)


func _pass(what: String) -> void:
	_passes += 1
	_say("PASS  " + what)


func _warn(what: String) -> void:
	_warnings.append(what)
	_say("WARN  " + what)


func _fail(what: String) -> void:
	_failures.append(what)
	_say("FAIL  " + what)


func _expect(condition: bool, what: String) -> void:
	if condition:
		_pass(what)
	else:
		_fail(what)


func _shot(shot_name: String) -> void:
	_say("SHOT_READY " + shot_name)
	# stderr is unbuffered, so this marker reaches an attached console at once.
	printerr("[device-check] SHOT_READY " + shot_name)
	var hold := float(App.cli_text("hold", str(DEFAULT_HOLD)))
	await get_tree().create_timer(maxf(hold, 0.5)).timeout


# ------------------------------------------------------------------- sections

func _check_platform() -> void:
	_say("--- platform")
	_say("device: %s | %s %s | %d cores" % [OS.get_model_name(), OS.get_name(), OS.get_version(), OS.get_processor_count()])
	_say("engine: %s | debug build: %s" % [str(Engine.get_version_info().get("string", "?")), str(OS.is_debug_build())])
	_say("game: %s v%s" % [App.data.title(), GameData.text(App.data.game, "version")])
	_expect(App.data.errors.is_empty(), "all data tables loaded from the installed pack")
	_expect(App.data.validate().is_empty(), "data cross-references resolve (sprites, audio, scripts all present)")


func _check_display() -> void:
	_say("--- display")
	var window := DisplayServer.window_get_size()
	var view := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	_say("renderer: %s / %s on %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	_say("window: %dx%d px | canvas: %dx%d units | scale: %.2f px per unit" % [window.x, window.y, int(view.x), int(view.y), float(window.x) / maxf(view.x, 1.0)])
	_say("screen: %.0f Hz | density scale %.1f | orientation %d" % [DisplayServer.screen_get_refresh_rate(), DisplayServer.screen_get_scale(), DisplayServer.screen_get_orientation()])
	_expect(window.y > window.x, "running in portrait (%dx%d)" % [window.x, window.y])
	_expect(absf(view.x - 720.0) < 1.0 and view.y >= 1279.0, "canvas keeps its 720-wide design space and grows taller (%dx%d)" % [int(view.x), int(view.y)])
	_say("safe area: x %d, y %d, %dx%d px" % [safe.position.x, safe.position.y, safe.size.x, safe.size.y])
	var top := safe.position.y
	var bottom := window.y - safe.end.y
	_say("unsafe insets: top %d px, bottom %d px, left %d px, right %d px" % [top, bottom, safe.position.x, window.x - safe.end.x])

	# Ask the game's own SafeArea what it actually applies.
	var probe := SafeArea.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(probe)
	var applied_top := probe.get_theme_constant("margin_top")
	var applied_bottom := probe.get_theme_constant("margin_bottom")
	_say("HUD margins applied: top %d, bottom %d, left %d, right %d canvas units" % [applied_top, applied_bottom,
		probe.get_theme_constant("margin_left"), probe.get_theme_constant("margin_right")])
	var units_per_px := view.y / maxf(float(window.y), 1.0)
	_expect(float(applied_top) >= float(top) * units_per_px, "top margin clears the notch / Dynamic Island")
	_expect(float(applied_bottom) >= float(bottom) * units_per_px, "bottom margin clears the home indicator")
	if OS.has_feature("mobile") and top == 0:
		_warn("the OS reported no top inset; check the HUD against the camera cut-out by eye")
	layer.queue_free()


func _check_input() -> void:
	_say("--- input")
	_expect(DisplayServer.is_touchscreen_available() or not OS.has_feature("mobile"), "touchscreen is available")
	_say("mouse events emulated from touch (drives buttons): %s" % str(Input.is_emulating_mouse_from_touch()))
	# Feed synthetic touch events to the joystick's handler in this build.
	var layer := CanvasLayer.new()
	add_child(layer)
	var stick := Joystick.new()
	layer.add_child(stick)
	await get_tree().process_frame
	var centre := get_viewport().get_visible_rect().get_center() + Vector2(0, 260)
	var down := InputEventScreenTouch.new()
	down.index = 7
	down.pressed = true
	down.position = centre
	stick._unhandled_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = centre + Vector2(0.0, -Joystick.RADIUS)
	stick._unhandled_input(drag)
	_expect(stick.current().y < -0.99, "a drag up on the joystick steers up at full speed")
	var up := InputEventScreenTouch.new()
	up.index = 7
	up.pressed = false
	stick._unhandled_input(up)
	_expect(stick.current() == Vector2.ZERO, "lifting the finger stops")
	layer.queue_free()
	_say("note: this proves the game's handling of touches; only a finger proves the glass")


func _check_audio() -> void:
	_say("--- audio")
	var driver := str(AudioServer.call("get_driver_name")) if AudioServer.has_method("get_driver_name") else "?"
	_say("driver: %s | mix rate %d Hz | output latency %.0f ms | device: %s" % [driver, int(AudioServer.get_mix_rate()), AudioServer.get_output_latency() * 1000.0, AudioServer.output_device])
	_expect(AudioServer.get_mix_rate() > 0.0, "audio server is running")
	for bus in AudioServer.bus_count:
		_say("bus %-6s %6.1f dB%s" % [AudioServer.get_bus_name(bus), AudioServer.get_bus_volume_db(bus), "  (muted)" if AudioServer.is_bus_mute(bus) else ""])

	var missing: PackedStringArray = []
	var sfx := GameData.dict(App.data.audio, "sfx")
	for id: String in sfx:
		if not ResourceLoader.exists(AudioService.SFX_DIR + GameData.text(sfx[id], "file") + ".wav"):
			missing.append(id)
	var music := GameData.dict(App.data.audio, "music")
	for id: String in music:
		if not ResourceLoader.exists(AudioService.MUSIC_DIR + GameData.text(music[id], "file") + ".wav"):
			missing.append(id)
	_expect(missing.is_empty(), "all %d sound effects and %d music tracks are in the build" % [sfx.size(), music.size()])

	var before := App.audio.played_count
	App.audio.play("level_up")
	App.audio.play_music("menu")
	await get_tree().create_timer(1.2).timeout
	var state := App.audio.debug_state()
	_expect(App.audio.played_count > before, "a sound effect was accepted for playback")
	# Playback position only advances if the audio thread is really mixing.
	_expect(bool(state.music_playing) and float(state.music_position) > 0.3, "music is being mixed (position %.2f s)" % float(state.music_position))
	_say("note: this proves audio is being produced. The game uses the 'ambient' session, so the")
	_say("      Ring/Silent switch mutes it. If you hear nothing, check silent mode and volume.")
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(30, 0.8)
		_say("haptics: sent one test pulse - you should have felt a short tap")


func _check_storage() -> void:
	_say("--- storage")
	_say("user data: " + OS.get_user_data_dir())
	var path := "user://device_check.save"
	var writer := SaveService.new(LocalSaveBackend.new(path))
	writer.load_or_create()
	var marker := "check-%d" % Time.get_ticks_usec()
	writer.state["marker"] = marker
	var wrote := writer.flush()
	_expect(wrote and FileAccess.file_exists(path), "a save file can be written")
	var reader := SaveService.new(LocalSaveBackend.new(path))
	reader.load_or_create()
	_expect(str(reader.state.get("marker", "")) == marker and reader.integrity_ok and not reader.is_new_profile, "it reads back intact after a fresh load")
	writer.state["marker"] = marker + "-second"
	writer.flush()
	_expect(FileAccess.file_exists(path + ".bak"), "the previous version is kept as a backup")
	writer.backend.erase()
	_expect(not FileAccess.file_exists(path), "test files cleaned up")
	var profile := "user://profile.save"
	if FileAccess.file_exists(profile):
		var size := FileAccess.get_file_as_bytes(profile).size()
		_pass("your profile exists on this device (%d bytes, account level %d) and was left untouched" % [size, App.account.level()])
	else:
		_warn("no profile file yet")


func _check_gameplay() -> void:
	_say("--- gameplay under load")
	if _main.get("menu") != null:
		(_main.get("menu") as MenuShell).set_active(false)
	var config := RunConfig.for_testing(App.data, 7)
	config.color = App.arsenal.player_color()
	config.theme = App.campaign.theme(1)
	var arena := Arena.new()
	add_child(arena)
	arena.setup(App, config)
	var hud := Hud.new(arena)
	add_child(hud)
	arena.start()

	var early := await _measure(arena, 6.0)
	_say("opening: %s" % _describe(early))
	await _shot("run_early")
	_expect(arena.combat.kills > 0, "the core fires and kills on its own (%d kills)" % arena.combat.kills)

	# The level-up screen as a player sees it.
	var bot := arena.autopilot
	arena.autopilot = null
	arena.add_xp(arena.xp_needed + 1.0)
	await get_tree().create_timer(1.0).timeout
	_expect(arena.state == Arena.State.CHOOSING, "levelling up pauses the run for a choice")
	await _shot("level_up")
	if arena.state == Arena.State.CHOOSING:
		arena.choose(0)
	arena.autopilot = bot

	# Late-run pressure with a strong build: the worst case for frame time.
	var max_level := GameData.integer(App.data.weapons, "max_level", 5)
	for weapon_id: String in ["pulse", "missile", "chain", "nova"]:
		arena.grant_weapon(weapon_id, max_level - 1)
	arena.director.timeline_time = 235.0
	var heavy := await _measure(arena, 7.0)
	await _shot("run_heavy")
	var heavier := await _measure(arena, 7.0)
	_say("late swarm: %s" % _describe(heavy))
	_say("late swarm, continued: %s" % _describe(heavier))
	var worst := minf(float(heavy.low), float(heavier.low))
	var typical := minf(float(heavy.fps), float(heavier.fps))
	_expect(typical >= 55.0, "holds at least 55 fps on average under load (%.0f)" % typical)
	if worst < 45.0:
		_warn("slowest second dipped to %.0f fps" % worst)
	else:
		_pass("slowest second stayed at %.0f fps" % worst)
	_expect(arena.combat.kills > 50, "sustained combat (%d kills, level %d, peak %d enemies)" % [arena.combat.kills, arena.level, arena.peak_enemies])
	var finite := not (is_nan(arena.player.x) or is_nan(arena.player.y))
	_expect(finite, "simulation state is sane")

	# Results screen layout, from a preview that pays nothing out.
	arena.autopilot = null
	arena.set_paused(true)
	var result := arena.build_result(false, true, false)
	var summary := RunLedger.compute(App, result)
	summary["level_before"] = App.account.level()
	summary["xp_before"] = App.account.xp()
	summary["level_after"] = App.account.level()
	summary["xp_after"] = App.account.xp()
	summary["level_ups"] = []
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	layer.add_child(ResultsScreen.new(result, summary))
	await get_tree().create_timer(1.6).timeout
	await _shot("results")


## Lets the run play for `seconds`, keeping the bot alive, and measures frames.
func _measure(arena: Arena, seconds: float) -> Dictionary:
	var frames := 0
	var elapsed := 0.0
	var window_frames := 0
	var window_time := 0.0
	var low := INF
	var step_sum := 0.0
	var step_worst := 0.0
	arena.step_ms_worst = 0.0
	var last := Time.get_ticks_usec()
	while elapsed < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000000.0
		last = now
		elapsed += dt
		frames += 1
		window_frames += 1
		window_time += dt
		step_sum += arena.step_ms
		step_worst = maxf(step_worst, arena.step_ms_worst)
		arena.player.hp = maxf(arena.player.hp, arena.player.max_hp * 0.6)
		if window_time >= 1.0:
			low = minf(low, float(window_frames) / window_time)
			window_frames = 0
			window_time = 0.0
	return {
		"fps": float(frames) / maxf(elapsed, 0.001),
		"low": low if low < INF else float(frames) / maxf(elapsed, 0.001),
		"step": step_sum / float(maxi(frames, 1)),
		"step_worst": step_worst,
		"enemies": arena.enemies.count,
		"shots": arena.projectiles.count,
	}


func _describe(m: Dictionary) -> String:
	return "%.0f fps avg, slowest second %.0f fps | sim %.2f ms per step (worst %.1f) | %d enemies, %d projectiles on screen" % [
		float(m.fps), float(m.low), float(m.step), float(m.step_worst), int(m.enemies), int(m.shots)]


func _finish() -> void:
	_say("--- result")
	for warning in _warnings:
		_say("warning: " + warning)
	for failure in _failures:
		_say("failed: " + failure)
	var verdict := "RESULT %s - %d passed, %d warnings, %d failed" % ["PASS" if _failures.is_empty() else "FAIL", _passes, _warnings.size(), _failures.size()]
	_say(verdict)
	printerr("[device-check] " + verdict)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	await get_tree().create_timer(0.5).timeout
	# iOS does not let an app end itself; whoever launched the check closes it.
	get_tree().quit()
