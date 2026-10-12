class_name SettingsModal
extends Modal
## Player preferences: independent master / music / sound levels, haptics,
## and a few comfort options. Changes apply and save immediately.

var _shell: MenuShell
var _reset_armed := false
var _reset: NeonButton


func _init(shell: MenuShell = null) -> void:
	_shell = shell
	heading = "SETTINGS"
	accent = Palette.CYAN


func _build(into: VBoxContainer) -> void:
	into.add_child(_slider("sound", "MASTER", SettingsService.MASTER))
	into.add_child(_slider("music", "MUSIC", SettingsService.MUSIC))
	into.add_child(_slider("sound", "SOUND FX", SettingsService.SFX))
	into.add_child(UiKit.divider())
	into.add_child(_toggle("vibrate", "HAPTICS", SettingsService.HAPTICS, true))
	into.add_child(_toggle("damage", "DAMAGE NUMBERS", SettingsService.DAMAGE_NUMBERS, true))
	into.add_child(_toggle("area", "REDUCED EFFECTS", SettingsService.LOW_EFFECTS, false))
	into.add_child(_slider("shockwave", "SCREEN SHAKE", SettingsService.SCREEN_SHAKE))
	into.add_child(UiKit.divider())

	_reset = NeonButton.make("RESET ALL PROGRESS", NeonButton.Kind.GHOST, Palette.MUTED, "", 60.0, UiTheme.TINY + 1)
	_reset.pressed.connect(_on_reset)
	into.add_child(_reset)
	into.add_child(UiKit.caption("%s  v%s" % [App.data.title(), GameData.text(App.data.game, "version")], UiTheme.TINY, Palette.DIM, HORIZONTAL_ALIGNMENT_CENTER))


func _slider(icon_id: String, text: String, key: String) -> HBoxContainer:
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make(icon_id, 34.0, Palette.MUTED))
	var name_label := UiKit.caption(text, UiTheme.SMALL, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(200, 0)
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
	# A blip on release so the new level can be judged by ear.
	slider.drag_ended.connect(func(_changed: bool) -> void: App.audio.play("ui_click"))
	row.add_child(slider)
	return row


func _toggle(icon_id: String, text: String, key: String, fallback: bool) -> HBoxContainer:
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make(icon_id, 34.0, Palette.MUTED))
	var name_label := UiKit.caption(text, UiTheme.SMALL, Palette.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var toggle := ToggleSwitch.make(App.settings.enabled(key, fallback))
	toggle.toggled.connect(func(on: bool) -> void:
		App.settings.set_value(key, on)
		if key == SettingsService.HAPTICS and on:
			App.haptics.medium())
	row.add_child(toggle)
	return row


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset.configure("TAP AGAIN TO ERASE EVERYTHING", NeonButton.Kind.DANGER, Palette.RED, "warning", UiTheme.TINY + 1)
		return
	App.save.reset()
	App.boot(App.save.backend)
	get_tree().reload_current_scene()
