class_name HomeScreen
extends MenuScreen
## The front door. One job: get the player into a run. Title, the selected
## core, which sector to play, and a very large PLAY button - with the daily
## reward and achievements one tap away.

var _preview: CorePreview
var _core_name: Label
var _sector_title: Label
var _sector_info: Label
var _sector_reward: Label
var _prev: NeonButton
var _next: NeonButton
var _mode: SegmentedControl
var _mode_hint: Label
var _play: NeonButton
var _daily_badge: PanelContainer
var _trophy_badge: PanelContainer
var _endless := false


func _build() -> void:
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	column.add_child(UiKit.gap(6))
	column.add_child(_logo())
	column.add_child(UiKit.caption(GameData.text(App.data.game, "tagline"), UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

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

	if _endless:
		_sector_title.text = "OVERDRIVE"
		var best := App.campaign.endless_best()
		_sector_info.text = "ENDLESS  -  BEST %s" % Fmt.time_mmss(best) if best > 0.0 else "ENDLESS  -  HOW LONG CAN YOU LAST?"
		_sector_reward.text = "A BOSS EVERY 5 MINUTES"
		_prev.set_enabled(false)
		_next.set_enabled(false)
	else:
		var tier := App.campaign.selected()
		var theme_def := App.campaign.theme(tier)
		_sector_title.text = "SECTOR %02d" % tier
		var best := App.campaign.best_time(tier)
		var status := "CLEARED  -  BEST %s" % Fmt.time_mmss(best) if best > 0.0 else "NOT YET CLEARED"
		_sector_info.text = "%s  -  %s" % [GameData.text(theme_def, "name", ""), status]
		var bonus := float(App.campaign.scaling(float(tier)).reward) - 1.0
		_sector_reward.text = "+%d%% REWARDS" % int(round(bonus * 100.0)) if bonus > 0.001 else "DEFEAT THE BOSS TO CLEAR"
		_prev.set_enabled(tier > 1)
		_next.set_enabled(tier < App.campaign.max_selectable())
	UiKit.set_badge(_daily_badge, 1 if App.daily.can_claim() else 0)
	UiKit.set_badge(_trophy_badge, App.achievements.claimable_count())


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
