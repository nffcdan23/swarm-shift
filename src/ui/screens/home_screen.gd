class_name HomeScreen
extends MenuScreen
## The front door. One job: get the player into a run - and show, at a glance,
## the three things that carry over between runs: the Player Level and how far
## it is from the next one, what that next level unlocks, and how close the
## Credits balance is to the next permanent upgrade. Below that: the selected
## core, which sector to play (and what is different about it), and PLAY.

var _preview: CorePreview
var _core_name: Label
var _player_level: Label
var _player_xp: Label
var _player_bar: MeterBar
var _player_next: Label
var _goal_name: Label
var _goal_amount: Label
var _goal_bar: MeterBar
var _goal_button: Button
var _sector_title: Label
var _sector_info: Label
var _sector_reward: Label
var _sector_tags: HBoxContainer
var _prev: NeonButton
var _next: NeonButton
var _mode: SegmentedControl
var _mode_hint: Label
var _play: NeonButton
var _daily_badge: PanelContainer
var _trophy_badge: PanelContainer
var _endless := false


func _build() -> void:
	var column := UiKit.vbox(10)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	column.add_child(_logo())
	column.add_child(UiKit.caption(GameData.text(App.data.game, "tagline"), UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_progress_card())

	_preview = CorePreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_preview)
	_core_name = UiKit.caption("", UiTheme.SMALL, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_core_name)

	_mode = SegmentedControl.make(PackedStringArray(["SECTORS", "OVERDRIVE"]))
	_mode.changed.connect(_on_mode_changed)
	column.add_child(_mode)
	_mode_hint = UiKit.caption("", UiTheme.TINY, Palette.DIM.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_mode_hint)

	var selector := UiKit.card(Palette.CYAN, 14, 4)
	var row := UiKit.hbox(8)
	_prev = NeonButton.make("", NeonButton.Kind.GHOST, Palette.CYAN, "arrow_left", 84.0)
	_prev.min_width = 78.0
	_prev.pressed.connect(_step_sector.bind(-1))
	row.add_child(_prev)
	var middle := UiKit.vbox(2)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sector_title = UiKit.title("", UiTheme.TITLE, Palette.TEXT)
	middle.add_child(_sector_title)
	_sector_info = UiKit.caption("", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	middle.add_child(_sector_info)
	_sector_reward = UiKit.caption("", UiTheme.TINY, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	middle.add_child(_sector_reward)
	_sector_tags = UiKit.hbox(8)
	_sector_tags.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(_sector_tags)
	row.add_child(middle)
	_next = NeonButton.make("", NeonButton.Kind.GHOST, Palette.CYAN, "arrow_right", 84.0)
	_next.min_width = 78.0
	_next.pressed.connect(_step_sector.bind(1))
	row.add_child(_next)
	UiKit.card_body(selector).add_child(row)
	column.add_child(selector)

	_play = NeonButton.make("PLAY", NeonButton.Kind.PRIMARY, Palette.CYAN, "play", 116.0, 44)
	_play.pressed.connect(_on_play)
	column.add_child(_play)
	_play.pulse(true)

	var extras := UiKit.hbox(12)
	var daily := NeonButton.make("DAILY REWARD", NeonButton.Kind.SECONDARY, Palette.AMBER, "gift", 72.0, UiTheme.SMALL)
	daily.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daily.pressed.connect(func() -> void: shell.open_dialog(DailyRewardModal.new(shell)))
	_daily_badge = _corner_badge(daily)
	extras.add_child(daily)
	var trophies := NeonButton.make("ACHIEVEMENTS", NeonButton.Kind.SECONDARY, Palette.VIOLET, "trophy", 72.0, UiTheme.SMALL)
	trophies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trophies.pressed.connect(_open_achievements)
	_trophy_badge = _corner_badge(trophies)
	extras.add_child(trophies)
	column.add_child(extras)
	column.add_child(UiKit.gap(2))


## Permanent progress, always in view: PLAYER LEVEL with its XP numbers and
## bar, the next unlock, and the next permanent upgrade against the balance.
func _progress_card() -> PanelContainer:
	var card := UiKit.card(Palette.CYAN, 14, 6)
	var body := UiKit.card_body(card)

	var head := UiKit.hbox(10)
	head.add_child(IconGlyph.make("star", 30.0, Palette.CYAN, true))
	_player_level = UiKit.label("PLAYER LEVEL 1", UiTheme.BODY, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_player_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_player_level)
	_player_xp = UiKit.label("0 / 0 XP", UiTheme.SMALL, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, true)
	head.add_child(_player_xp)
	body.add_child(head)
	_player_bar = MeterBar.make(Palette.CYAN, 14.0)
	_player_bar.back_color = Color(0.1, 0.15, 0.24, 0.95)
	body.add_child(_player_bar)
	_player_next = UiKit.caption("", UiTheme.TINY, Palette.MUTED)
	_player_next.clip_text = true
	body.add_child(_player_next)

	# Credits always have a visible purpose: the cheapest upgrade still to buy.
	_goal_button = Button.new()
	_goal_button.flat = true
	_goal_button.focus_mode = Control.FOCUS_NONE
	_goal_button.custom_minimum_size = Vector2(0, 50)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_goal_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_goal_button.pressed.connect(func() -> void:
		App.audio.play("ui_click")
		shell.show_tab("upgrades"))
	var goal := UiKit.vbox(4)
	goal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var goal_row := UiKit.hbox(8)
	goal_row.add_child(IconGlyph.make("credit", 24.0, Palette.CREDITS))
	_goal_name = UiKit.caption("", UiTheme.TINY, Palette.MUTED)
	_goal_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal_name.clip_text = true
	goal_row.add_child(_goal_name)
	_goal_amount = UiKit.label("", UiTheme.TINY, Palette.CREDITS, HORIZONTAL_ALIGNMENT_RIGHT, true)
	goal_row.add_child(_goal_amount)
	goal.add_child(goal_row)
	_goal_bar = MeterBar.make(Palette.CREDITS, 8.0)
	_goal_bar.back_color = Color(0.1, 0.15, 0.24, 0.95)
	goal.add_child(_goal_bar)
	_goal_button.add_child(goal)
	body.add_child(UiKit.divider())
	body.add_child(_goal_button)
	return card


## The title, coloured in three parts around the slashes.
func _logo() -> HBoxContainer:
	var row := UiKit.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var title_text := App.data.title()
	var parts := title_text.split("//")
	var colors: Array[Color] = [Palette.CYAN, Palette.TEXT]
	for i in parts.size():
		if i > 0:
			row.add_child(_logo_part("//", Palette.MAGENTA))
		row.add_child(_logo_part(parts[i], colors[mini(i, colors.size() - 1)]))
	return row


func _logo_part(text: String, color: Color) -> Label:
	var part := UiKit.label(text, UiTheme.DISPLAY, color, HORIZONTAL_ALIGNMENT_CENTER)
	part.add_theme_font_override("font", UiTheme.font_title())
	# A wide, faint outline in the same colour reads as a neon halo.
	part.add_theme_constant_override("outline_size", 16)
	part.add_theme_color_override("font_outline_color", Palette.with_alpha(color, 0.16))
	return part


func _corner_badge(button: Control) -> PanelContainer:
	var badge := UiKit.badge()
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -24.0
	badge.offset_top = -8.0
	button.add_child(badge)
	return badge


func refresh() -> void:
	_refresh_progress()
	var core_id := App.arsenal.selected_core()
	var core := GameData.dict(App.data.cores(), core_id)
	_preview.set_color(App.arsenal.player_color())
	var weapon := App.data.weapon(GameData.text(core, "start_weapon"))
	_core_name.text = "%s CORE  -  %s" % [GameData.text(core, "name", core_id), GameData.text(weapon, "name").to_upper()]

	var unlocked := App.campaign.endless_unlocked()
	if not unlocked:
		_endless = false
	_mode.visible = unlocked
	_mode.select(1 if _endless else 0)
	var unlock_sector := GameData.integer(App.data.stages, "endless_unlock_sector", 3)
	_mode_hint.visible = not unlocked
	_mode_hint.text = "CLEAR SECTOR %d TO UNLOCK OVERDRIVE" % unlock_sector

	for child in _sector_tags.get_children():
		child.queue_free()
	if _endless:
		_sector_title.text = "OVERDRIVE"
		var best := App.campaign.endless_best()
		_sector_info.text = "ENDLESS  -  BEST %s" % Fmt.time_mmss(best) if best > 0.0 else "ENDLESS  -  HOW LONG CAN YOU LAST?"
		_sector_reward.text = "A BOSS EVERY 5 MINUTES"
		_prev.set_enabled(false)
		_next.set_enabled(false)
	else:
		var tier := App.campaign.selected()
		var brief := App.campaign.sector_brief(tier)
		_sector_title.text = "SECTOR %02d" % tier
		var best := App.campaign.best_time(tier)
		var status := "CLEARED  -  BEST %s" % Fmt.time_mmss(best) if best > 0.0 else "NOT YET CLEARED"
		var sector_name := str(brief.name) if not str(brief.name).is_empty() else GameData.text(App.campaign.theme(tier), "name", "")
		_sector_info.text = "%s  -  %s" % [sector_name, status]
		var bonus := float(App.campaign.scaling(float(tier)).reward) - 1.0
		_sector_reward.text = "+%d%% REWARDS" % int(round(bonus * 100.0)) if bonus > 0.001 else "DEFEAT THE BOSS TO CLEAR"
		for mutator: Dictionary in brief.mutators:
			_sector_tags.add_child(UiKit.tag(str(mutator.name), mutator.color))
		var fresh: Array = brief.new
		if not fresh.is_empty():
			_sector_tags.add_child(UiKit.tag("NEW: " + ", ".join(PackedStringArray(fresh)), Palette.CYAN))
		_prev.set_enabled(tier > 1)
		_next.set_enabled(tier < App.campaign.max_selectable())
	UiKit.set_badge(_daily_badge, 1 if App.daily.can_claim() else 0)
	UiKit.set_badge(_trophy_badge, App.achievements.claimable_count())


func _refresh_progress() -> void:
	var account := App.account
	_player_level.text = "PLAYER LEVEL %d" % account.level()
	_player_bar.set_value(account.progress())
	if account.is_max():
		_player_xp.text = "MAX LEVEL"
		_player_next.text = "EVERYTHING IS UNLOCKED"
	else:
		_player_xp.text = "%s / %s XP" % [Fmt.commas(account.xp()), Fmt.commas(account.xp_needed(account.level()))]
		var ahead := account.next_unlock()
		if int(ahead.level) > 0:
			_player_next.text = "NEXT UNLOCK  -  LV %d: %s" % [int(ahead.level), ", ".join(PackedStringArray(ahead.names))]
		else:
			_player_next.text = "%s XP TO PLAYER LEVEL %d" % [Fmt.commas(account.xp_to_next()), account.level() + 1]

	var goal := App.meta.next_goal()
	if str(goal.id).is_empty():
		_goal_name.text = "EVERY UPGRADE INSTALLED"
		_goal_amount.text = ""
		_goal_bar.set_value(1.0)
	else:
		var balance := App.economy.balance(Economy.CREDITS)
		_goal_name.text = ("READY: %s" if bool(goal.affordable) else "NEXT UPGRADE: %s") % str(goal.name)
		_goal_name.add_theme_color_override("font_color", Palette.CREDITS if bool(goal.affordable) else Palette.MUTED)
		_goal_amount.text = "%s / %s" % [Fmt.compact(float(mini(balance, int(goal.cost)))), Fmt.compact(float(goal.cost))]
		_goal_bar.set_value(float(goal.progress))


func _step_sector(by: int) -> void:
	App.campaign.select(App.campaign.selected() + by)
	refresh()
	UiKit.pop(_sector_title, 1.12)


func _on_mode_changed(index: int) -> void:
	_endless = index == 1
	refresh()


func _on_play() -> void:
	App.haptics.medium()
	shell.request_play(CampaignService.MODE_ENDLESS if _endless else CampaignService.MODE_SECTOR)


func _open_achievements() -> void:
	shell.show_tab("missions")
	var missions := shell.screen("missions") as MissionsScreen
	if missions != null:
		missions.show_achievements()
