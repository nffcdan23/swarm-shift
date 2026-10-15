class_name ResultsScreen
extends Control
## End-of-run summary. The pay-off screen: what happened in the run, then the
## rewards collected one line at a time - Credits first, then Player XP into
## the Player Level bar - and the next run one tap away.
##
## It is given the finished `result` and the `summary` that RunLedger.settle()
## produced. By the time this shows, everything has already been saved; the
## sequence is presentation only, which is why a tap can skip straight to the
## end of it without changing what was earned.

signal play_again_pressed
signal home_pressed

const MAX_EXTRA_LINES := 3
const XP_PARTS: Array[Array] = [
	["time", "Time survived"], ["kills", "Enemies defeated"], ["level", "Run Level reached"],
	["bosses", "Bosses defeated"], ["clear", "Sector cleared"],
]

var _result: Dictionary
var _summary: Dictionary
var _credits_label: Label
var _credits_shown := 0
var _credit_rows: Array[Control] = []
var _credit_steps: Array[int] = []
var _xp_label: Label
var _xp_shown := 0
var _xp_rows: Array[Control] = []
var _xp_steps: Array[int] = []
var _xp_bar: MeterBar
var _xp_level: Label
var _xp_numbers: Label
var _xp_note: Label
var _next_note: Label
var _stat_values: Array[Label] = []
var _actions: VBoxContainer
var _double: NeonButton
var _skip_hint: Label
var _tweens: Array[Tween] = []
var _busy := false
var _skipped := false
var _done := false


func _init(result: Dictionary, summary: Dictionary) -> void:
	_result = result
	_summary = summary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.theme()
	gui_input.connect(_on_gui_input)

	var scrim := ColorRect.new()
	scrim.color = Color(0.008, 0.012, 0.027, 0.88)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var safe := SafeArea.new()
	safe.base_padding = 28
	add_child(safe)
	var column := UiKit.vbox(12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	safe.add_child(column)

	var cleared := bool(_result.get("cleared", false))
	var abandoned := bool(_result.get("abandoned", false))
	var endless := str(_result.get("mode", "")) == CampaignService.MODE_ENDLESS
	var accent := Palette.GREEN if cleared else (Palette.MUTED if abandoned else Palette.RED)
	var headline := "SECTOR CLEARED" if cleared else ("RUN ENDED" if abandoned or endless else "CORE DESTROYED")

	var title := UiKit.title(headline, 52, accent)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	column.add_child(title)
	var where := "OVERDRIVE  -  CYCLE %d" % (int(_result.get("cycle", 0)) + 1) if endless else "SECTOR %02d" % int(_result.get("tier", 1))
	column.add_child(UiKit.caption(where, UiTheme.SMALL, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if bool(_summary.get("new_best", false)):
		var best := UiKit.tag("NEW BEST", Palette.GOLD, UiTheme.SMALL)
		best.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(best)

	# The cards scroll if a small screen cannot fit them, so the buttons below
	# are always on screen whatever the run produced.
	var cards := UiKit.vbox(12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_child(_stats_card())
	cards.add_child(_rewards_card())
	var extras := _extras_card()
	if extras != null:
		cards.add_child(extras)
	var scroller := UiKit.scroll(cards)
	scroller.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(scroller)

	_actions = UiKit.vbox(10)
	_double = NeonButton.make("DOUBLE CREDITS", NeonButton.Kind.SECONDARY, Palette.AMBER, "ad", 76.0)
	_double.visible = int(_summary.get("credits", 0)) > 0 and not bool(_summary.get("doubled", false)) \
		and App.ads.rewarded_available(AdsService.DOUBLE_REWARDS)
	_double.pressed.connect(_on_double)
	_actions.add_child(_double)
	var again := NeonButton.make("PLAY AGAIN", NeonButton.Kind.PRIMARY, Palette.CYAN, "play", 96.0, UiTheme.HEADING)
	again.pressed.connect(func() -> void: _leave(play_again_pressed))
	_actions.add_child(again)
	var home := NeonButton.make("HOME", NeonButton.Kind.GHOST, Palette.MUTED, "home", 64.0, UiTheme.SMALL)
	home.pressed.connect(func() -> void: _leave(home_pressed))
	_actions.add_child(home)
	column.add_child(_actions)
	_actions.modulate.a = 0.0
	_set_actions_enabled(false)

	_skip_hint = UiKit.caption("TAP TO SKIP", UiTheme.TINY, Palette.DIM.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_skip_hint)

	var index := 0
	for child in column.get_children() + cards.get_children():
		if child != _actions and child != scroller:
			UiKit.enter(child as Control, 0.05 * float(index))
		index += 1
	_play_sequence()


# ------------------------------------------------------------------ building

func _stats_card() -> PanelContainer:
	var card := UiKit.card(Palette.LINE.lightened(0.3), 16, 8)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(_stat("clock", "TIME SURVIVED", Fmt.time_mmss(float(_result.get("time", 0.0))), Palette.TEXT))
	grid.add_child(_stat("skull", "ENEMIES DEFEATED", Fmt.compact(float(_result.get("kills", 0))), Palette.TEXT))
	grid.add_child(_stat("upgrade", "RUN LEVEL", str(int(_result.get("level", 1))), Palette.ENERGY))
	grid.add_child(_stat("trophy", "BOSSES DEFEATED", str(int(_result.get("bosses", 0))), Palette.TEXT))
	UiKit.card_body(card).add_child(grid)
	return card


func _stat(icon_id: String, caption: String, value: String, color: Color) -> VBoxContainer:
	var box := UiKit.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(IconGlyph.make(icon_id, 28.0, Palette.MUTED))
	var number := UiKit.label(value, UiTheme.HEADING, color, HORIZONTAL_ALIGNMENT_CENTER, true)
	box.add_child(number)
	_stat_values.append(number)
	var name_label := UiKit.paragraph(caption, UiTheme.TINY - 3, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.add_theme_font_override("font", UiTheme.font_wide())
	box.add_child(name_label)
	return box


func _rewards_card() -> PanelContainer:
	var card := UiKit.card(Palette.GOLD, 18, 8)
	var body := UiKit.card_body(card)
	body.add_child(UiKit.caption("REWARDS BANKED", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	# --- Credits ---
	var credits_head := UiKit.hbox(10)
	credits_head.add_child(IconGlyph.make("credit", 36.0, Palette.CREDITS, true))
	var credits_name := UiKit.caption("CREDITS", UiTheme.SMALL, Palette.CREDITS)
	credits_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_head.add_child(credits_name)
	_credits_label = UiKit.label("+0", UiTheme.TITLE, Palette.CREDITS, HORIZONTAL_ALIGNMENT_RIGHT, true)
	credits_head.add_child(_credits_label)
	var crystals := int(_summary.get("crystals", 0))
	if crystals > 0:
		credits_head.add_child(UiKit.amount("crystal", "+%d" % crystals, Palette.CRYSTALS, UiTheme.HEADING))
	body.add_child(credits_head)
	_add_part(body, _credit_rows, _credit_steps, "Picked up in the run", int(_summary.get("credits_collected", _summary.get("credits", 0))), Palette.CREDITS)
	_add_part(body, _credit_rows, _credit_steps, "Survival bonus", int(_summary.get("credits_survival", 0)), Palette.CREDITS)
	_add_part(body, _credit_rows, _credit_steps, "Sector cleared", int(_summary.get("credits_clear", 0)), Palette.CREDITS)
	if bool(_summary.get("first_clear", false)):
		body.add_child(UiKit.caption("FIRST CLEAR BONUS", UiTheme.TINY, Palette.CRYSTALS, HORIZONTAL_ALIGNMENT_RIGHT))
	body.add_child(UiKit.divider())

	# --- Player XP and the Player Level bar ---
	var xp_head := UiKit.hbox(10)
	xp_head.add_child(IconGlyph.make("star", 36.0, Palette.CYAN, true))
	var xp_name := UiKit.caption("PLAYER XP", UiTheme.SMALL, Palette.CYAN)
	xp_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_head.add_child(xp_name)
	_xp_label = UiKit.label("+0", UiTheme.TITLE, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, true)
	xp_head.add_child(_xp_label)
	body.add_child(xp_head)
	var parts: Dictionary = _summary.get("xp_parts", {})
	if parts.is_empty():
		_add_part(body, _xp_rows, _xp_steps, "This run", int(_summary.get("account_xp", 0)), Palette.CYAN)
	for entry in XP_PARTS:
		_add_part(body, _xp_rows, _xp_steps, str(entry[1]), int(parts.get(entry[0], 0)), Palette.CYAN)

	var level_before := int(_summary.get("level_before", 1))
	var bar_row := UiKit.hbox(12)
	_xp_level = UiKit.caption("PLAYER LV %d" % level_before, UiTheme.SMALL, Palette.TEXT)
	_xp_level.custom_minimum_size = Vector2(170, 0)
	bar_row.add_child(_xp_level)
	_xp_bar = MeterBar.make(Palette.CYAN, 16.0)
	_xp_bar.back_color = Color(0.1, 0.15, 0.24, 0.95)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.set_value(_fraction(level_before, int(_summary.get("xp_before", 0))), true)
	bar_row.add_child(_xp_bar)
	_xp_numbers = UiKit.label(_numbers(level_before, int(_summary.get("xp_before", 0))), UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, true)
	_xp_numbers.custom_minimum_size = Vector2(150, 0)
	bar_row.add_child(_xp_numbers)
	body.add_child(bar_row)
	_xp_note = UiKit.paragraph("", UiTheme.TINY + 1, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_xp_note.add_theme_font_override("font", UiTheme.font_wide())
	_xp_note.visible = false
	body.add_child(_xp_note)
	_next_note = UiKit.paragraph("", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_next_note.visible = false
	body.add_child(_next_note)
	return card


## One breakdown line ("Survival bonus  +30"). Lines worth nothing are left out.
func _add_part(into: VBoxContainer, rows: Array[Control], steps: Array[int], text: String, amount: int, color: Color) -> void:
	if amount <= 0:
		return
	var row := UiKit.hbox(8)
	var name_label := UiKit.label(text, UiTheme.TINY + 1, Palette.MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(UiKit.gap(46.0, true))
	row.add_child(name_label)
	row.add_child(UiKit.label("+%s" % Fmt.commas(amount), UiTheme.TINY + 1, color.darkened(0.1), HORIZONTAL_ALIGNMENT_RIGHT, true))
	row.modulate.a = 0.0
	into.add_child(row)
	rows.append(row)
	steps.append(amount)


func _extras_card() -> PanelContainer:
	# Each entry is [icon, text, colour]; only the ones shown become controls.
	var lines: Array[Array] = []
	for synergy_id: String in _summary.get("new_synergies", []):
		var def := GameData.dict(App.data.synergies(), synergy_id)
		lines.append(["star", "Synergy discovered: %s" % GameData.text(def, "name", synergy_id), Palette.GOLD])
	var completed: Array = _summary.get("missions_completed", [])
	if not completed.is_empty():
		lines.append(["missions", "%d mission%s complete - claim in Missions" % [completed.size(), "" if completed.size() == 1 else "s"], Palette.GREEN])
	for entry in App.achievements.poll_newly_completed():
		lines.append(["trophy", "Achievement: %s" % str(entry.name), Palette.VIOLET])

	var sources: Dictionary = _result.get("damage_by_source", {})
	var total := maxf(float(_result.get("damage", 0.0)), 1.0)
	var names := sources.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(sources[a]) > float(sources[b]))
	if lines.is_empty() and names.is_empty():
		return null
	var card := UiKit.card(Palette.LINE.lightened(0.3), 16, 6)
	var body := UiKit.card_body(card)
	# A busy run can earn a dozen of these; the screen shows the first few.
	for i in mini(lines.size(), MAX_EXTRA_LINES):
		body.add_child(_line(str(lines[i][0]), str(lines[i][1]), lines[i][2]))
	if lines.size() > MAX_EXTRA_LINES:
		body.add_child(UiKit.caption("+ %d MORE" % (lines.size() - MAX_EXTRA_LINES), UiTheme.TINY, Palette.MUTED))
	if not names.is_empty():
		if not lines.is_empty():
			body.add_child(UiKit.divider())
		body.add_child(UiKit.caption("TOP DAMAGE", UiTheme.TINY, Palette.MUTED))
		for i in mini(names.size(), 2 if lines.size() > 1 else 3):
			body.add_child(_damage_row(str(names[i]), float(sources[names[i]]) / total))
	return card


func _line(icon_id: String, text: String, color: Color) -> HBoxContainer:
	var row := UiKit.hbox(10)
	row.add_child(IconGlyph.make(icon_id, 24.0, color))
	row.add_child(UiKit.paragraph(text, UiTheme.TINY + 1, color))
	return row


func _damage_row(source_id: String, share: float) -> HBoxContainer:
	var row := UiKit.hbox(10)
	var weapon := App.data.weapon(source_id)
	var augment := GameData.dict(App.data.augments(), source_id)
	var display := GameData.text(weapon, "name", GameData.text(augment, "name", source_id.capitalize()))
	var color := GameData.color(weapon, "color", Palette.AMBER)
	var name_label := UiKit.label(display, UiTheme.TINY + 1, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(210, 0)
	name_label.clip_text = true
	row.add_child(name_label)
	var bar := MeterBar.make(color, 9.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_value(share)
	row.add_child(bar)
	var pct := UiKit.label(Fmt.percent(share), UiTheme.TINY + 1, Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	pct.custom_minimum_size = Vector2(62, 0)
	row.add_child(pct)
	return row


# ----------------------------------------------------------------- sequence

func _fraction(level: int, xp: int) -> float:
	if level >= App.account.max_level():
		return 1.0
	return clampf(float(xp) / float(maxi(App.account.xp_needed(level), 1)), 0.0, 1.0)


func _numbers(level: int, xp: int) -> String:
	if level >= App.account.max_level():
		return "MAX"
	return "%s / %s" % [Fmt.commas(xp), Fmt.commas(App.account.xp_needed(level))]


## True once the reward sequence has finished or been skipped.
func is_settled() -> bool:
	return _done


func _wait(seconds: float) -> void:
	if _skipped or not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


func _track(tween: Tween) -> Tween:
	_tweens.append(tween)
	return tween


## Credits arrive line by line, then Player XP, then the level bar fills.
func _play_sequence() -> void:
	await _wait(0.4)
	for value in _stat_values:
		if _skipped:
			break
		UiKit.pop(value, 1.25)
		App.audio.play("count_tick", 1.0)
		await _wait(0.1)

	for i in _credit_rows.size():
		if _skipped:
			break
		_reveal(_credit_rows[i])
		_credits_shown = _count(_credits_label, _credits_shown, _credits_shown + _credit_steps[i], 0.4)
		App.audio.play("pickup_credit")
		await _wait(0.5)
	if not _skipped and not _credit_rows.is_empty():
		UiKit.pop(_credits_label, 1.2)
		App.haptics.light()
		await _wait(0.25)

	for i in _xp_rows.size():
		if _skipped:
			break
		_reveal(_xp_rows[i])
		_xp_shown = _count(_xp_label, _xp_shown, _xp_shown + _xp_steps[i], 0.32)
		await _wait(0.34)

	# Walk the bar through each level gained, pausing to announce it.
	var level := int(_summary.get("level_before", 1))
	var gained: Array = _summary.get("level_ups", [])
	for entry: Dictionary in gained:
		if _skipped:
			break
		_xp_bar.set_value(1.0)
		await _wait(0.42)
		if _skipped:
			break
		level = int(entry.level)
		_xp_level.text = "PLAYER LV %d" % level
		UiKit.pop(_xp_level, 1.3)
		_xp_bar.set_value(0.0, true)
		_show_level_note([entry])
		App.audio.play("reward")
		App.haptics.success()
		await _wait(0.5)
	if not _skipped:
		_xp_bar.set_value(_fraction(int(_summary.get("level_after", level)), int(_summary.get("xp_after", 0))))
		await _wait(0.35)
	_finish()


func _reveal(row: Control) -> void:
	_track(row.create_tween()).tween_property(row, "modulate:a", 1.0, 0.18)


## Counts a "+N" label up and returns the value it will end on.
func _count(label: Label, from: int, to: int, seconds: float) -> int:
	var span := maxf(float(to - from), 1.0)
	var tick := func(v: float) -> void:
		label.text = "+%s" % Fmt.commas(int(v))
		App.audio.play("count_tick", 1.0 + 0.4 * (v - float(from)) / span)
	var tween := _track(create_tween())
	tween.tween_method(tick, float(from), float(to), seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return to


func _show_level_note(entries: Array) -> void:
	var credits := 0
	var crystals := 0
	var unlocks: Array = []
	var reached := 0
	for entry: Dictionary in entries:
		var rewards: Dictionary = entry.get("rewards", {})
		credits += int(rewards.get("credits", 0))
		crystals += int(rewards.get("crystals", 0))
		unlocks.append_array(rewards.get("unlocks", []))
		reached = int(entry.get("level", reached))
	var note := "PLAYER LEVEL %d!   +%s Credits" % [reached, Fmt.compact(float(credits))]
	if crystals > 0:
		note += "   +%d Crystals" % crystals
	if not unlocks.is_empty():
		note += "\nNOW AVAILABLE: " + ", ".join(PackedStringArray(unlocks))
	_xp_note.text = note
	_xp_note.visible = true
	UiKit.pop(_xp_note, 1.1)


## Puts every number, bar and line in its final state and opens the buttons.
## Safe to call more than once: a skip calls it, then the sequence does.
func _finish() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()
	for row in _credit_rows:
		row.modulate.a = 1.0
	for row in _xp_rows:
		row.modulate.a = 1.0
	_credits_shown = int(_summary.get("credits", 0)) * (2 if bool(_summary.get("doubled", false)) else 1)
	_credits_label.text = "+%s" % Fmt.commas(_credits_shown)
	_xp_shown = int(_summary.get("account_xp", 0))
	_xp_label.text = "+%s" % Fmt.commas(_xp_shown)
	var level_after := int(_summary.get("level_after", _summary.get("level_before", 1)))
	var xp_after := int(_summary.get("xp_after", _summary.get("xp_before", 0)))
	_xp_level.text = "PLAYER LV %d" % level_after
	_xp_bar.set_value(_fraction(level_after, xp_after), true)
	_xp_numbers.text = _numbers(level_after, xp_after)
	var gained: Array = _summary.get("level_ups", [])
	if not gained.is_empty():
		_show_level_note(gained)
	var ahead := App.account.next_unlock()
	if int(ahead.level) > 0:
		_next_note.text = "NEXT UNLOCK  -  PLAYER LV %d: %s" % [int(ahead.level), ", ".join(PackedStringArray(ahead.names))]
		_next_note.visible = true
	if _done:
		return
	_done = true
	_skip_hint.visible = false
	_set_actions_enabled(true)
	create_tween().tween_property(_actions, "modulate:a", 1.0, 0.2)


func _set_actions_enabled(enabled: bool) -> void:
	for child in _actions.get_children():
		if child is NeonButton:
			(child as NeonButton).set_enabled(enabled)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Jumps to the end of the reward sequence. Changes nothing that was earned.
func skip() -> void:
	if _done:
		return
	_skipped = true
	_finish()


func _on_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		skip()


func _on_double() -> void:
	if _busy or not _done:
		return
	_busy = true
	var earned: bool = await App.ads.show_rewarded(AdsService.DOUBLE_REWARDS)
	_busy = false
	if not earned:
		return
	var extra := RunLedger.double_credits(App, _summary)
	_double.visible = false
	if extra <= 0:
		return
	App.audio.play("ui_purchase")
	App.haptics.success()
	_credits_shown = _count(_credits_label, _credits_shown, _credits_shown + extra, 0.7)


func _leave(which: Signal) -> void:
	if _busy:
		return
	_busy = true
	which.emit()
