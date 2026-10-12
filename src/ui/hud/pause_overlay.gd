class_name PauseOverlay
extends Modal
## Pause menu. Shows the run so far and the current build, with resume, audio
## toggles and a two-step quit so a stray tap cannot throw a run away.

signal resume_pressed
signal quit_pressed

var _arena: Arena
var _quit: NeonButton
var _quit_armed := false


func _init(arena: Arena) -> void:
	_arena = arena
	heading = "PAUSED"
	accent = Palette.CYAN
	dismissable = false


func _build(into: VBoxContainer) -> void:
	var stats := UiKit.hbox(26)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(UiKit.amount("clock", Fmt.time_mmss(_arena.time), Palette.TEXT))
	stats.add_child(UiKit.amount("skull", Fmt.compact(float(_arena.combat.kills)), Palette.TEXT))
	stats.add_child(UiKit.amount("credit", Fmt.compact(_arena.credits), Palette.CREDITS))
	into.add_child(stats)

	into.add_child(UiKit.caption("YOUR BUILD", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	into.add_child(BuildStrip.make(_arena))
	if not _arena.build.synergies.is_empty():
		var names: PackedStringArray = []
		for synergy_id in _arena.build.synergies:
			names.append(GameData.text(GameData.dict(_arena.data.synergies(), synergy_id), "name", synergy_id))
		into.add_child(UiKit.caption("SYNERGY  " + ", ".join(names), UiTheme.TINY, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	into.add_child(UiKit.divider())

	into.add_child(_slider_row("music", "MUSIC", SettingsService.MUSIC))
	into.add_child(_slider_row("sound", "SOUND", SettingsService.SFX))
	into.add_child(UiKit.gap(4))

	var resume := NeonButton.make("RESUME", NeonButton.Kind.PRIMARY, Palette.CYAN, "play", 92.0, UiTheme.HEADING)
	resume.pressed.connect(func() -> void:
		resume_pressed.emit()
		close())
	into.add_child(resume)

	_quit = NeonButton.make("END RUN", NeonButton.Kind.GHOST, Palette.MUTED, "", 68.0, UiTheme.SMALL)
	_quit.pressed.connect(_on_quit)
	into.add_child(_quit)


func _slider_row(icon_id: String, text: String, key: String) -> HBoxContainer:
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make(icon_id, 34.0, Palette.MUTED))
	var name_label := UiKit.caption(text, UiTheme.SMALL, Palette.MUTED)
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = App.settings.number(key, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 56)
	slider.value_changed.connect(func(v: float) -> void: App.settings.set_value(key, v))
	row.add_child(slider)
	return row


func _on_quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit.configure("TAP AGAIN TO END RUN", NeonButton.Kind.DANGER, Palette.RED, "", UiTheme.SMALL)
		return
	quit_pressed.emit()
	close()


func handle_back() -> bool:
	resume_pressed.emit()
	close()
	return true
