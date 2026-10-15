class_name PauseOverlay
extends Modal
## Pause menu. Shows the run so far and the current build, with resume and
## audio sliders. Ending the run is a separate, explicit step that says exactly
## what will be banked - nothing earned in a run is ever lost by leaving it.

signal resume_pressed
signal quit_pressed

var _arena: Arena
var _main: VBoxContainer
var _confirm: VBoxContainer
var _left := false


func _init(arena: Arena) -> void:
	_arena = arena
	heading = "PAUSED"
	accent = Palette.CYAN
	dismissable = false


func _build(into: VBoxContainer) -> void:
	_main = UiKit.vbox(16)
	into.add_child(_main)
	_confirm = UiKit.vbox(16)
	_confirm.visible = false
	into.add_child(_confirm)

	var stats := UiKit.hbox(26)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(UiKit.amount("clock", Fmt.time_mmss(_arena.time), Palette.TEXT))
	stats.add_child(UiKit.amount("skull", Fmt.compact(float(_arena.combat.kills)), Palette.TEXT))
	stats.add_child(UiKit.amount("upgrade", "RUN LV %d" % _arena.level, Palette.ENERGY))
	stats.add_child(UiKit.amount("credit", Fmt.compact(_arena.credits), Palette.CREDITS))
	_main.add_child(stats)

	_main.add_child(UiKit.caption("YOUR BUILD", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_main.add_child(BuildStrip.make(_arena))
	if not _arena.build.synergies.is_empty():
		var names: PackedStringArray = []
		for synergy_id in _arena.build.synergies:
			names.append(GameData.text(GameData.dict(_arena.data.synergies(), synergy_id), "name", synergy_id))
		_main.add_child(UiKit.caption("SYNERGY  " + ", ".join(names), UiTheme.TINY, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_main.add_child(UiKit.divider())

	# The same legend as the first-run hint, always one pause away.
	var legend := UiKit.vbox(6)
	legend.add_child(_legend_row("xp", Palette.ENERGY, "Green energy raises your Run Level - this run only"))
	legend.add_child(_legend_row("credit", Palette.CREDITS, "Gold Credits are banked for permanent upgrades"))
	_main.add_child(legend)
	_main.add_child(UiKit.divider())

	_main.add_child(_slider_row("music", "MUSIC", SettingsService.MUSIC))
	_main.add_child(_slider_row("sound", "SOUND", SettingsService.SFX))
	_main.add_child(UiKit.gap(4))

	var resume := NeonButton.make("RESUME", NeonButton.Kind.PRIMARY, Palette.CYAN, "play", 92.0, UiTheme.HEADING)
	resume.pressed.connect(_resume)
	_main.add_child(resume)

	var quit := NeonButton.make("END RUN", NeonButton.Kind.GHOST, Palette.MUTED, "", 68.0, UiTheme.SMALL)
	quit.pressed.connect(_show_confirm)
	_main.add_child(quit)


func _legend_row(icon_id: String, color: Color, text: String) -> HBoxContainer:
	var row := UiKit.hbox(10)
	row.add_child(IconGlyph.make(icon_id, 24.0, color))
	row.add_child(UiKit.paragraph(text, UiTheme.TINY + 1, Palette.MUTED))
	return row


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


## What ending the run now would bank. The same sum the results screen shows.
func preview() -> Dictionary:
	return RunLedger.compute(App, _arena.build_result(false, false, true))


func is_confirming() -> bool:
	return _confirm != null and _confirm.visible


func _show_confirm() -> void:
	for child in _confirm.get_children():
		child.queue_free()
	var banked := preview()
	_confirm.add_child(UiKit.title("END THIS RUN?", UiTheme.HEADING, Palette.TEXT))
	_confirm.add_child(UiKit.paragraph("You keep everything you have earned so far. It is banked the moment the run ends.",
		UiTheme.SMALL, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var card := UiKit.card(Palette.GOLD, 18, 10)
	var body := UiKit.card_body(card)
	body.add_child(UiKit.caption("YOU WILL BANK", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var rewards := UiKit.hbox(28)
	rewards.alignment = BoxContainer.ALIGNMENT_CENTER
	rewards.add_child(UiKit.amount("credit", "+%s" % Fmt.commas(int(banked.credits)), Palette.CREDITS, UiTheme.HEADING))
	rewards.add_child(UiKit.amount("star", "+%s XP" % Fmt.commas(int(banked.account_xp)), Palette.CYAN, UiTheme.HEADING))
	body.add_child(rewards)
	body.add_child(UiKit.caption("CREDITS AND PLAYER XP ARE PERMANENT", UiTheme.TINY, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UiKit.caption("RUN LEVEL %d AND THIS BUILD END WITH THE RUN" % _arena.level, UiTheme.TINY, Palette.ENERGY, HORIZONTAL_ALIGNMENT_CENTER))
	_confirm.add_child(card)

	var keep := NeonButton.make("KEEP PLAYING", NeonButton.Kind.PRIMARY, Palette.CYAN, "play", 92.0, UiTheme.HEADING)
	keep.pressed.connect(_hide_confirm)
	_confirm.add_child(keep)
	var end := NeonButton.make("END RUN AND BANK", NeonButton.Kind.DANGER, Palette.RED, "", 76.0, UiTheme.SMALL)
	end.click_sound = "ui_back"
	end.pressed.connect(_end_run)
	_confirm.add_child(end)

	_main.visible = false
	_confirm.visible = true


func _hide_confirm() -> void:
	_confirm.visible = false
	_main.visible = true


func _resume() -> void:
	if _left:
		return
	_left = true
	resume_pressed.emit()
	close()


func _end_run() -> void:
	# One exit only: a second tap during the close animation must not end it twice.
	if _left:
		return
	_left = true
	quit_pressed.emit()
	close()


func handle_back() -> bool:
	if is_confirming():
		_hide_confirm()
		return true
	_resume()
	return true
