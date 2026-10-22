class_name SettingsModal
extends Modal
## Player preferences: independent master / music / sound levels, haptics,
## and a few comfort options. Changes apply and save immediately. Below them,
## privacy and help: the privacy policy, support, reporting an ad, the ad
## privacy choices (only when the ad network says they must be offered) and
## the third-party licences.

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
	into.add_child(_shake_choice())
	into.add_child(UiKit.divider())
	_build_help(into)
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


## Off / Low / Normal. Low is the default on phones and tablets.
func _shake_choice() -> HBoxContainer:
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make("shockwave", 34.0, Palette.MUTED))
	row.add_child(UiKit.caption("SCREEN SHAKE", UiTheme.SMALL, Palette.TEXT))
	var choice := SegmentedControl.make(PackedStringArray(["OFF", "LOW", "NORMAL"]), maxi(SettingsService.SHAKE_LEVELS.find(App.settings.shake_level()), 0))
	choice.name = "ShakeLevel"
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.changed.connect(func(index: int) -> void: App.settings.set_value(SettingsService.SHAKE_LEVEL, SettingsService.SHAKE_LEVELS[index]))
	row.add_child(choice)
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


func _build_help(into: VBoxContainer) -> void:
	if App.ads.privacy_options_required():
		into.add_child(_help_button("PRIVACY CHOICES", "shield", _on_privacy_choices))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_child(_help_button("PRIVACY POLICY", "info", App.open_url.bind(App.data.link("privacy_policy"))))
	grid.add_child(_help_button("SUPPORT", "profile", App.open_url.bind(App.data.link("support"))))
	grid.add_child(_help_button("REPORT AN AD", "warning", _on_report_ad))
	grid.add_child(_help_button("LICENCES", "gear", _on_licences))
	into.add_child(grid)


func _help_button(text: String, icon_id: String, action: Callable) -> NeonButton:
	var button := NeonButton.make(text, NeonButton.Kind.GHOST, Palette.MUTED, icon_id, 60.0, UiTheme.TINY + 1)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _on_privacy_choices() -> void:
	await App.ads.show_privacy_options()
	if _shell != null:
		_shell.toast("Privacy choices saved", Palette.CYAN, "check")


func _on_report_ad() -> void:
	App.open_url(App.ads.report_ad_url())


func _on_licences() -> void:
	var licences := LicencesModal.new()
	if _shell != null:
		_shell.open_dialog(licences)
	else:
		get_parent().add_child(licences)


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset.configure("TAP AGAIN TO ERASE EVERYTHING", NeonButton.Kind.DANGER, Palette.RED, "warning", UiTheme.TINY + 1)
		return
	App.save.reset()
	App.boot(App.save.backend)
	get_tree().reload_current_scene()
