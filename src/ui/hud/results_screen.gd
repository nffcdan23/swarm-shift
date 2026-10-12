class_name ResultsScreen
extends Control
## End-of-run summary. The pay-off screen: numbers count up, the account bar
## fills (and levels), and the next run is one tap away.
##
## It is given the finished `result` and the `summary` that RunLedger.settle()
## produced - by the time this shows, everything has already been saved.

signal play_again_pressed
signal home_pressed

var _result: Dictionary
var _summary: Dictionary
var _credits_label: Label
var _credits_shown := 0
var _double: NeonButton
var _xp_bar: MeterBar
var _xp_level: Label
var _xp_note: Label
var _busy := false


func _init(result: Dictionary, summary: Dictionary) -> void:
	_result = result
	_summary = summary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.theme()

	var scrim := ColorRect.new()
	scrim.color = Color(0.008, 0.012, 0.027, 0.88)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var safe := SafeArea.new()
	safe.base_padding = 28
	add_child(safe)
	var column := UiKit.vbox(16)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	safe.add_child(column)

	var cleared := bool(_result.get("cleared", false))
	var abandoned := bool(_result.get("abandoned", false))
	var endless := str(_result.get("mode", "")) == CampaignService.MODE_ENDLESS
	var accent := Palette.GREEN if cleared else (Palette.MUTED if abandoned else Palette.RED)
	var headline := "SECTOR CLEARED" if cleared else ("RUN ENDED" if abandoned or endless else "CORE DESTROYED")

	var title := UiKit.title(headline, 54, accent)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	column.add_child(title)
	var where := "OVERDRIVE  -  CYCLE %d" % (int(_result.get("cycle", 0)) + 1) if endless else "SECTOR %02d" % int(_result.get("tier", 1))
	column.add_child(UiKit.caption(where, UiTheme.SMALL, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if bool(_summary.get("new_best", false)):
		var best := UiKit.tag("NEW BEST", Palette.GOLD, UiTheme.SMALL)
		best.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(best)

	column.add_child(_stats_card())
	column.add_child(_rewards_card())
	var extras := _extras_card()
	if extras != null:
		column.add_child(extras)

	_double = NeonButton.make("DOUBLE CREDITS", NeonButton.Kind.SECONDARY, Palette.AMBER, "ad", 84.0)
	_double.visible = int(_summary.get("credits", 0)) > 0 and App.ads.rewarded_available(AdsService.DOUBLE_REWARDS)
	_double.pressed.connect(_on_double)
	column.add_child(_double)

	var again := NeonButton.make("PLAY AGAIN", NeonButton.Kind.PRIMARY, Palette.CYAN, "play", 100.0, UiTheme.HEADING)
	again.pressed.connect(func() -> void: _leave(play_again_pressed))
	column.add_child(again)
	var home := NeonButton.make("HOME", NeonButton.Kind.GHOST, Palette.MUTED, "home", 72.0, UiTheme.SMALL)
	home.pressed.connect(func() -> void: _leave(home_pressed))
	column.add_child(home)

	var index := 0
	for child in column.get_children():
		UiKit.enter(child as Control, 0.05 * float(index))
		index += 1
	_animate_rewards()


func _stats_card() -> PanelContainer:
	var card := UiKit.card(Palette.LINE.lightened(0.3), 18, 10)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(_stat("clock", "TIME", Fmt.time_mmss(float(_result.get("time", 0.0)))))
	grid.add_child(_stat("skull", "KILLS", Fmt.compact(float(_result.get("kills", 0)))))
	grid.add_child(_stat("upgrade", "LEVEL", str(int(_result.get("level", 1)))))
	grid.add_child(_stat("damage", "DAMAGE", Fmt.compact(float(_result.get("damage", 0.0)))))
	UiKit.card_body(card).add_child(grid)
	return card


func _stat(icon_id: String, caption: String, value: String) -> VBoxContainer:
	var box := UiKit.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(IconGlyph.make(icon_id, 30.0, Palette.MUTED))
	box.add_child(UiKit.label(value, UiTheme.HEADING, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true))
	box.add_child(UiKit.caption(caption, UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	return box


func _rewards_card() -> PanelContainer:
	var card := UiKit.card(Palette.GOLD, 20, 12)
	var body := UiKit.card_body(card)

	var row := UiKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var credits := UiKit.hbox(8)
	credits.add_child(IconGlyph.make("credit", 40.0, Palette.CREDITS, true))
	_credits_label = UiKit.label("+0", UiTheme.TITLE, Palette.CREDITS, HORIZONTAL_ALIGNMENT_LEFT, true)
	credits.add_child(_credits_label)
	row.add_child(credits)
	var crystals := int(_summary.get("crystals", 0))
	if crystals > 0:
		var gems := UiKit.hbox(8)
		gems.add_child(IconGlyph.make("crystal", 40.0, Palette.CRYSTALS, true))
		gems.add_child(UiKit.label("+%d" % crystals, UiTheme.TITLE, Palette.CRYSTALS, HORIZONTAL_ALIGNMENT_LEFT, true))
		row.add_child(gems)
	body.add_child(row)
	if bool(_summary.get("first_clear", false)):
		body.add_child(UiKit.caption("FIRST CLEAR BONUS", UiTheme.TINY, Palette.CRYSTALS, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UiKit.divider())

	var xp_row := UiKit.hbox(12)
	_xp_level = UiKit.caption("LEVEL %d" % int(_summary.get("level_before", 1)), UiTheme.SMALL, Palette.CYAN)
	_xp_level.custom_minimum_size = Vector2(120, 0)
	xp_row.add_child(_xp_level)
	_xp_bar = MeterBar.make(Palette.CYAN, 16.0)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.set_value(_fraction(int(_summary.get("level_before", 1)), int(_summary.get("xp_before", 0))), true)
	xp_row.add_child(_xp_bar)
	xp_row.add_child(UiKit.label("+%s XP" % Fmt.compact(float(_summary.get("account_xp", 0))), UiTheme.SMALL, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, true))
	body.add_child(xp_row)
	_xp_note = UiKit.caption("", UiTheme.TINY, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_xp_note.visible = false
	body.add_child(_xp_note)
	return card


func _extras_card() -> PanelContainer:
	var lines: Array[Control] = []
	for synergy_id: String in _summary.get("new_synergies", []):
		var def := GameData.dict(App.data.synergies(), synergy_id)
		lines.append(_line("star", "Synergy discovered: %s" % GameData.text(def, "name", synergy_id), Palette.GOLD))
	var completed: Array = _summary.get("missions_completed", [])
	if not completed.is_empty():
		lines.append(_line("missions", "%d mission%s complete - claim in Missions" % [completed.size(), "" if completed.size() == 1 else "s"], Palette.GREEN))
	for entry in App.achievements.poll_newly_completed():
		lines.append(_line("trophy", "Achievement: %s" % str(entry.name), Palette.VIOLET))

	var sources: Dictionary = _result.get("damage_by_source", {})
	var total := maxf(float(_result.get("damage", 0.0)), 1.0)
	var names := sources.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(sources[a]) > float(sources[b]))
	if lines.is_empty() and names.is_empty():
		return null
	var card := UiKit.card(Palette.LINE.lightened(0.3), 18, 8)
	var body := UiKit.card_body(card)
	for line in lines:
		body.add_child(line)
	if not names.is_empty():
		if not lines.is_empty():
			body.add_child(UiKit.divider())
		body.add_child(UiKit.caption("TOP DAMAGE", UiTheme.TINY, Palette.MUTED))
		for i in mini(names.size(), 3):
			body.add_child(_damage_row(str(names[i]), float(sources[names[i]]) / total))
	return card


func _line(icon_id: String, text: String, color: Color) -> HBoxContainer:
	var row := UiKit.hbox(10)
	row.add_child(IconGlyph.make(icon_id, 26.0, color))
	row.add_child(UiKit.paragraph(text, UiTheme.SMALL, color))
	return row


func _damage_row(source_id: String, share: float) -> HBoxContainer:
	var row := UiKit.hbox(10)
	var weapon := App.data.weapon(source_id)
	var augment := GameData.dict(App.data.augments(), source_id)
	var display := GameData.text(weapon, "name", GameData.text(augment, "name", source_id.capitalize()))
	var color := GameData.color(weapon, "color", Palette.AMBER)
	var name_label := UiKit.label(display, UiTheme.SMALL, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(210, 0)
	name_label.clip_text = true
	row.add_child(name_label)
	var bar := MeterBar.make(color, 10.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_value(share)
	row.add_child(bar)
	var pct := UiKit.label(Fmt.percent(share), UiTheme.SMALL, Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	pct.custom_minimum_size = Vector2(62, 0)
	row.add_child(pct)
	return row


# ----------------------------------------------------------------- animation

func _fraction(level: int, xp: int) -> float:
	if level >= App.account.max_level():
		return 1.0
	return clampf(float(xp) / float(maxi(App.account.xp_needed(level), 1)), 0.0, 1.0)


func _animate_rewards() -> void:
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree():
		return
	_count_credits(int(_summary.get("credits", 0)), 0.9)
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	# Walk the bar through each level gained, pausing to announce it.
	var level := int(_summary.get("level_before", 1))
	var gained: Array = _summary.get("level_ups", [])
	for entry: Dictionary in gained:
		_xp_bar.set_value(1.0)
		await get_tree().create_timer(0.42).timeout
		if not is_inside_tree():
			return
		level = int(entry.level)
		_xp_level.text = "LEVEL %d" % level
		UiKit.pop(_xp_level, 1.3)
		_xp_bar.set_value(0.0, true)
		var rewards: Dictionary = entry.rewards
		var note := "LEVEL UP!  +%s Credits" % Fmt.compact(float(rewards.get("credits", 0)))
		if int(rewards.get("crystals", 0)) > 0:
			note += "  +%d Crystals" % int(rewards.crystals)
		var unlocks: Array = rewards.get("unlocks", [])
		if not unlocks.is_empty():
			note += "\nNOW AVAILABLE: " + ", ".join(PackedStringArray(unlocks))
		_xp_note.text = note
		_xp_note.visible = true
		UiKit.pop(_xp_note, 1.12)
		App.audio.play("reward")
		App.haptics.success()
	_xp_bar.set_value(_fraction(int(_summary.get("level_after", level)), int(_summary.get("xp_after", 0))))


func _count_credits(target: int, seconds: float) -> void:
	var from := _credits_shown
	var span := maxf(float(target - from), 1.0)
	var tick := func(v: float) -> void:
		_credits_shown = int(v)
		_credits_label.text = "+%s" % Fmt.commas(_credits_shown)
		App.audio.play("count_tick", 1.0 + 0.4 * (v - float(from)) / span)
	var tween := create_tween()
	tween.tween_method(tick, float(from), float(target), seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: UiKit.pop(_credits_label, 1.2))


func _on_double() -> void:
	if _busy:
		return
	_busy = true
	var earned: bool = await App.ads.show_rewarded(AdsService.DOUBLE_REWARDS)
	_busy = false
	if not earned:
		return
	var extra := RunLedger.double_credits(App, _summary)
	_double.visible = false
	App.audio.play("ui_purchase")
	App.haptics.success()
	_count_credits(_credits_shown + extra, 0.7)


func _leave(which: Signal) -> void:
	if _busy:
		return
	_busy = true
	which.emit()
