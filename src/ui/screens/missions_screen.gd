class_name MissionsScreen
extends MenuScreen
## Daily missions and achievements: the two lists of "do this, get that".

var _tabs: SegmentedControl
var _list: VBoxContainer
var _footer: Label
var _show_achievements := false


func _build() -> void:
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	column.add_child(header("Missions"))
	_tabs = SegmentedControl.make(PackedStringArray(["DAILY", "ACHIEVEMENTS"]), 1 if _show_achievements else 0)
	_tabs.changed.connect(func(index: int) -> void:
		_show_achievements = index == 1
		refresh())
	column.add_child(_tabs)
	_list = UiKit.vbox(10)
	column.add_child(UiKit.scroll(_list))
	_footer = UiKit.caption("", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_footer)


## Opens straight on the achievements list (used by the home screen shortcut).
func show_achievements() -> void:
	_show_achievements = true
	if _built:
		_tabs.select(1)
		refresh()


func refresh() -> void:
	App.missions.refresh()
	for child in _list.get_children():
		child.queue_free()
	_tabs.set_badge(0, App.missions.claimable_count())
	_tabs.set_badge(1, App.achievements.claimable_count())
	if _show_achievements:
		_fill_achievements()
	else:
		_fill_daily()
	_list.add_child(UiKit.gap(8))


func _process(_delta: float) -> void:
	if visible and _built and not _show_achievements:
		_footer.text = "NEW MISSIONS IN " + _clock(App.clock.seconds_until_next_day())


func _clock(seconds: int) -> String:
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]


# -------------------------------------------------------------------- daily

func _fill_daily() -> void:
	for mission in App.missions.active():
		_list.add_child(_progress_card(str(mission.text), float(mission.progress), float(mission.target),
			bool(mission.complete), bool(mission.claimed), mission.reward, _claim_mission.bind(str(mission.id)), Palette.CYAN))

	var bonus := App.missions.bonus_reward()
	var claimable := App.missions.all_claimed() and not App.missions.bonus_claimed()
	var card := UiKit.card(Palette.GOLD if claimable else Palette.LINE.lightened(0.25), 16, 8)
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make("gift", 48.0, Palette.GOLD if not App.missions.bonus_claimed() else Palette.DIM, claimable))
	var text := UiKit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.label("Daily bonus", UiTheme.BODY, Palette.TEXT))
	text.add_child(UiKit.paragraph("Claim all three missions to open it.", UiTheme.TINY + 1, Palette.MUTED))
	text.add_child(UiKit.reward_row(bonus))
	row.add_child(text)
	if App.missions.bonus_claimed():
		row.add_child(IconGlyph.make("check", 34.0, Palette.GREEN))
	elif claimable:
		var claim := NeonButton.make("CLAIM", NeonButton.Kind.PRIMARY, Palette.GOLD, "", 64.0, UiTheme.SMALL)
		claim.min_width = 130.0
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.click_sound = ""
		claim.pressed.connect(_claim_bonus)
		row.add_child(claim)
	UiKit.card_body(card).add_child(row)
	_list.add_child(card)
	_footer.visible = true


func _claim_mission(id: String) -> void:
	if App.missions.claim(id).is_empty():
		return
	_celebrate()


func _claim_bonus() -> void:
	if App.missions.claim_bonus().is_empty():
		return
	_celebrate()


# ------------------------------------------------------------- achievements

func _fill_achievements() -> void:
	_footer.visible = false
	var entries := App.achievements.all()
	# Claimable first, then in progress, then already claimed.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(a) < _rank(b))
	for entry in entries:
		_list.add_child(_progress_card(str(entry.name), float(entry.progress), float(entry.target), bool(entry.complete),
			bool(entry.claimed), {"crystals": entry.crystals}, _claim_achievement.bind(str(entry.id)), Palette.VIOLET, str(entry.text)))


func _rank(entry: Dictionary) -> int:
	if bool(entry.claimed):
		return 2
	return 0 if bool(entry.complete) else 1


func _claim_achievement(id: String) -> void:
	if App.achievements.claim(id) <= 0:
		return
	_celebrate()


# ------------------------------------------------------------------- shared

func _progress_card(title_text: String, progress: float, target: float, complete: bool, claimed: bool, reward: Dictionary,
		on_claim: Callable, accent: Color, detail: String = "") -> PanelContainer:
	var claimable := complete and not claimed
	var card := UiKit.card(accent if claimable else Palette.LINE.lightened(0.25), 16, 8)
	var row := UiKit.hbox(14)
	var text := UiKit.vbox(6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.label(title_text, UiTheme.BODY, Palette.MUTED if claimed else Palette.TEXT))
	if not detail.is_empty():
		text.add_child(UiKit.paragraph(detail, UiTheme.TINY + 1, Palette.MUTED))
	var bar_row := UiKit.hbox(10)
	var bar := MeterBar.make(Palette.GREEN if complete else accent, 10.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_value(progress / maxf(target, 1.0), true)
	bar_row.add_child(bar)
	bar_row.add_child(UiKit.label("%s / %s" % [Fmt.compact(progress), Fmt.compact(target)], UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	text.add_child(bar_row)
	text.add_child(UiKit.reward_row(reward))
	row.add_child(text)
	if claimed:
		row.add_child(IconGlyph.make("check", 34.0, Palette.GREEN))
	elif claimable:
		var claim := NeonButton.make("CLAIM", NeonButton.Kind.PRIMARY, accent, "", 64.0, UiTheme.SMALL)
		claim.min_width = 130.0
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.click_sound = ""
		claim.pressed.connect(on_claim)
		row.add_child(claim)
	UiKit.card_body(card).add_child(row)
	return card


func _celebrate() -> void:
	App.audio.play("ui_claim")
	App.haptics.success()
	refresh()
	shell.refresh_badges()
