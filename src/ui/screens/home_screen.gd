class_name HomeScreen
extends MenuScreen
## The front door. One job: get the player into a run - and show, at a glance,
## the three things that carry over between runs: the Player Level and how far
## it is from the next one, what that next level unlocks, and how close the
## Credits balance is to the next permanent upgrade. Below that: the selected
## core, which sector to play (and what is different about it), and PLAY.
##
## Three views share the sector card: SECTORS (with a Threat row once Threat is
## open), OVERDRIVE, and CHALLENGES, where the arrows switch between the Daily
## and the Weekly Challenge.

const VIEW_SECTORS := 0
const VIEW_OVERDRIVE := 1
const VIEW_CHALLENGES := 2
const THREAT_COLOR := Color("ff4d6d")

var _preview: CorePreview
var _core_name: Label
var _loadout: Label
var _player_level: Label
var _player_xp: Label
var _player_bar: MeterBar
var _player_next: Label
var _goal_rows: Array[Dictionary] = []
var _sector_title: Label
var _sector_info: Label
var _sector_reward: Label
var _sector_tags: HFlowContainer
var _prev: NeonButton
var _next: NeonButton
var _mode: SegmentedControl
var _mode_hint: Label
var _play: NeonButton
var _threat_row: HBoxContainer
var _threat_down: NeonButton
var _threat_up: NeonButton
var _threat_label: Label
var _threat_info: Label
var _challenge_timer: Label
var _daily_badge: PanelContainer
var _trophy_badge: PanelContainer
var _view := VIEW_SECTORS
var _tick := 0.0


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
	_loadout = UiKit.caption("", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_loadout)

	_mode = SegmentedControl.make(PackedStringArray(["SECTORS", "OVERDRIVE", "CHALLENGES"]))
	_mode.changed.connect(_on_mode_changed)
	column.add_child(_mode)
	_mode_hint = UiKit.caption("", UiTheme.TINY, Palette.DIM.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
	# Challenge rules can run long; they wrap instead of widening the lobby.
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# Tags wrap onto a second line rather than widen the card: a Weekly
	# Challenge can carry three long ones.
	_sector_tags = HFlowContainer.new()
	_sector_tags.alignment = FlowContainer.ALIGNMENT_CENTER
	_sector_tags.add_theme_constant_override("h_separation", 8)
	_sector_tags.add_theme_constant_override("v_separation", 4)
	middle.add_child(_sector_tags)
	middle.add_child(_build_threat_row())
	_threat_info = UiKit.caption("", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_threat_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_threat_info)
	_challenge_timer = UiKit.caption("", UiTheme.TINY, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	middle.add_child(_challenge_timer)
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
## bar, the next unlock, then three goals at three distances (see GoalService).
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

	body.add_child(UiKit.divider())
	for i in 3:
		body.add_child(_goal_row())
	return card


## One tappable line: icon, what it is, how far, a thin bar. Filled in later.
func _goal_row() -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var goal := UiKit.vbox(3)
	goal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := UiKit.hbox(8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := IconGlyph.make("credit", 22.0, Palette.CREDITS)
	line.add_child(icon)
	var title := UiKit.caption("", UiTheme.TINY, Palette.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	line.add_child(title)
	var amount := UiKit.label("", UiTheme.TINY, Palette.CREDITS, HORIZONTAL_ALIGNMENT_RIGHT, true)
	line.add_child(amount)
	goal.add_child(line)
	var bar := MeterBar.make(Palette.CREDITS, 6.0)
	bar.back_color = Color(0.1, 0.15, 0.24, 0.95)
	goal.add_child(bar)
	button.add_child(goal)
	var row := {"button": button, "icon": icon, "title": title, "amount": amount, "bar": bar, "tab": "upgrades", "branch": ""}
	button.pressed.connect(_open_goal.bind(row))
	_goal_rows.append(row)
	return button


func _open_goal(row: Dictionary) -> void:
	App.audio.play("ui_click")
	shell.show_tab(str(row.tab))
	if not str(row.branch).is_empty():
		var research := shell.screen("upgrades") as UpgradesScreen
		if research != null:
			research.show_branch(str(row.branch))


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


## THREAT  < n >: the level the next sector run is played at.
func _build_threat_row() -> HBoxContainer:
	_threat_row = UiKit.hbox(6)
	_threat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_threat_down = NeonButton.make("", NeonButton.Kind.GHOST, THREAT_COLOR, "arrow_left", 52.0)
	_threat_down.min_width = 58.0
	_threat_down.pressed.connect(_step_threat.bind(-1))
	_threat_row.add_child(_threat_down)
	_threat_label = UiKit.label("THREAT OFF", UiTheme.SMALL, THREAT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, true)
	_threat_label.custom_minimum_size = Vector2(150, 0)
	_threat_row.add_child(_threat_label)
	_threat_up = NeonButton.make("", NeonButton.Kind.GHOST, THREAT_COLOR, "arrow_right", 52.0)
	_threat_up.min_width = 58.0
	_threat_up.pressed.connect(_step_threat.bind(1))
	_threat_row.add_child(_threat_up)
	return _threat_row


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
	var skin_id := App.arsenal.selected_skin()
	var skin := GameData.dict(App.data.skins(), skin_id)
	_preview.show_skin(skin, App.arsenal.player_color())
	var weapon := App.data.weapon(App.arsenal.start_weapon())
	_core_name.text = "%s CORE  -  %s" % [GameData.text(core, "name", core_id), GameData.text(weapon, "name").to_upper()]
	# What else is equipped, on its own line so it can never widen the screen.
	var parts := PackedStringArray()
	if skin_id != "default":
		parts.append(GameData.text(skin, "name", skin_id))
	var doctrine := App.meta.active_doctrine()
	if not doctrine.is_empty():
		parts.append(GameData.text(App.meta.def(doctrine), "name", doctrine).to_upper())
	_loadout.text = "  -  ".join(parts)
	_loadout.visible = not parts.is_empty()

	var unlocked := App.campaign.endless_unlocked()
	if not unlocked:
		_view = VIEW_SECTORS
	_mode.visible = unlocked
	_mode.select(_view)
	_mode.set_badge(VIEW_CHALLENGES, App.challenges.open_count())
	var unlock_sector := GameData.integer(App.data.stages, "endless_unlock_sector", 3)
	_mode_hint.visible = not unlocked
	_mode_hint.text = "CLEAR SECTOR %d TO UNLOCK OVERDRIVE AND CHALLENGES" % unlock_sector
	_threat_row.visible = false
	_threat_info.visible = false
	_challenge_timer.visible = false
	_play.set_enabled(true)
	_sector_reward.add_theme_color_override("font_color", Palette.GOLD)

	for child in _sector_tags.get_children():
		child.queue_free()
	if _view == VIEW_CHALLENGES:
		_show_challenge()
	elif _view == VIEW_OVERDRIVE:
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
		_show_threat(tier)
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

	var goals: Array[Dictionary] = [App.goals.short_term(), App.goals.medium_term(), App.goals.long_term()]
	var fallbacks := PackedStringArray(["ALL RESEARCH COMPLETE", "EVERY WEAPON MASTERED", "EVERYTHING UNLOCKED"])
	for i in goals.size():
		_show_goal(_goal_rows[i], goals[i], fallbacks[i])


func _show_goal(row: Dictionary, goal: Dictionary, fallback: String) -> void:
	var title: Label = row.title
	var amount: Label = row.amount
	var bar: MeterBar = row.bar
	var icon: IconGlyph = row.icon
	if goal.is_empty():
		title.text = fallback
		title.add_theme_color_override("font_color", Palette.GOLD)
		amount.text = ""
		bar.set_value(1.0)
		return
	var color: Color = goal.color
	row.tab = goal.tab
	row.branch = goal.branch
	icon.icon_id = str(goal.icon)
	icon.color = color
	title.text = str(goal.title)
	title.add_theme_color_override("font_color", Palette.TEXT if bool(goal.ready) else Palette.MUTED)
	amount.text = str(goal.detail)
	amount.add_theme_color_override("font_color", color)
	bar.fill_color = color
	bar.set_value(float(goal.progress))


## The Threat row and its line: what the selected level adds, what it pays, and
## how far this sector's ladder has been climbed. Hidden until Threat opens.
func _show_threat(tier: int) -> void:
	var campaign := App.campaign
	if not campaign.threat_available():
		return
	_threat_row.visible = true
	_threat_info.visible = true
	var level := campaign.selected_threat()
	var top := campaign.max_threat(tier)
	var best := campaign.threat_cleared(tier)
	_threat_label.text = "THREAT %d" % level if level > 0 else "THREAT OFF"
	_threat_down.set_enabled(level > 0)
	_threat_up.set_enabled(level < top)
	_threat_info.add_theme_color_override("font_color", Palette.MUTED)
	if top == 0:
		_threat_info.text = "CLEAR THIS SECTOR TO OPEN ITS THREAT LADDER"
	elif level == 0:
		var next_level := best + 1
		var opens := campaign.threat_unlock_sector(next_level)
		if next_level <= campaign.threat_max() and not campaign.threat_level_open(next_level):
			_threat_info.text = "BEST HERE: THREAT %d  -  THREAT %d OPENS AT SECTOR %d" % [best, next_level, opens]
		else:
			_threat_info.text = "BEST HERE: THREAT %d  -  %d OF %d CLEARED" % [best, best, campaign.threat_max()] if best > 0 else "RAISE THE THREAT FOR NEW RULES AND BIGGER REWARDS"
	else:
		var added := campaign.mutator_def(campaign.threat_mutator(level))
		_threat_info.add_theme_color_override("font_color", THREAT_COLOR.lerp(Palette.TEXT, 0.35))
		_threat_info.text = "+ %s: %s" % [GameData.text(added, "name"), GameData.text(added, "desc")]
		_sector_tags.add_child(UiKit.tag("THREAT %d" % level, THREAT_COLOR))
		var bonus := campaign.threat_reward_mult(level) - 1.0
		if level > best:
			var crystals := campaign.threat_milestone_crystals(level)
			_sector_reward.text = "FIRST CLEAR: +%s CREDITS%s" % [Fmt.commas(campaign.threat_first_clear_credits(tier, level)),
				"  +%d CRYSTALS" % crystals if crystals > 0 else ""]
		else:
			_sector_reward.text = "THREAT %d CLEARED  -  +%d%% REWARDS" % [level, int(round(bonus * 100.0))]


## The Daily or Weekly Challenge in the sector card.
func _show_challenge() -> void:
	var challenges := App.challenges
	var kind := challenges.selected_kind()
	var c := challenges.challenge(kind)
	_sector_title.text = str(c.name)
	_sector_info.text = "SECTOR %02d  -  %s" % [int(c.tier), str(c.loadout)]
	var reward: Dictionary = c.reward
	var clock_ok := challenges.clock_ok()
	_sector_reward.add_theme_color_override("font_color", Palette.GOLD)
	if not clock_ok:
		_sector_reward.text = "CHECK YOUR DEVICE CLOCK"
		_sector_reward.add_theme_color_override("font_color", Palette.RED)
	elif bool(c.claimed):
		_sector_reward.text = "COMPLETED  -  REWARD COLLECTED"
		_sector_reward.add_theme_color_override("font_color", Palette.GREEN)
	else:
		_sector_reward.text = "CLEAR IT: +%s CREDITS  +%d CRYSTALS" % [Fmt.commas(int(reward.credits)), int(reward.crystals)]
	if int(c.threat) > 0:
		_sector_tags.add_child(UiKit.tag("THREAT %d" % int(c.threat), THREAT_COLOR))
	for rule_name: String in c.rule_names:
		_sector_tags.add_child(UiKit.tag(rule_name, Palette.AMBER))
	_mode_hint.visible = true
	_mode_hint.text = ". ".join(PackedStringArray(c.rule_descs)).to_upper()
	_challenge_timer.visible = true
	_update_countdown()
	_prev.set_enabled(kind == ChallengeService.WEEKLY)
	_next.set_enabled(kind == ChallengeService.DAILY)
	_play.set_enabled(clock_ok)


func _update_countdown() -> void:
	var kind := App.challenges.selected_kind()
	var left := App.challenges.seconds_left(kind)
	var best: Dictionary = App.challenges.best(App.challenges.period_id(kind, App.challenges.period_index(kind)))
	var note := ""
	if not best.is_empty():
		note = "  -  BEST: %s, %s KILLS" % ["CLEARED" if bool(best.cleared) else Fmt.time_mmss(float(best.time)), Fmt.commas(int(best.kills))]
	_challenge_timer.text = "NEW %s IN %s%s" % ["DAILY" if kind == ChallengeService.DAILY else "WEEKLY", Fmt.countdown(left), note]


func _process(delta: float) -> void:
	if _view != VIEW_CHALLENGES or not is_visible_in_tree():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	# A new period has started while the lobby was open: show the new challenge.
	if App.challenges.seconds_left(App.challenges.selected_kind()) <= 1:
		refresh()
	else:
		_update_countdown()


func _step_sector(by: int) -> void:
	if _view == VIEW_CHALLENGES:
		App.challenges.select(ChallengeService.WEEKLY if by > 0 else ChallengeService.DAILY)
	else:
		App.campaign.select(App.campaign.selected() + by)
	refresh()
	UiKit.pop(_sector_title, 1.12)


func _step_threat(by: int) -> void:
	App.campaign.select_threat(App.campaign.selected_threat() + by)
	refresh()
	UiKit.pop(_threat_label, 1.15)


func _on_mode_changed(index: int) -> void:
	_view = index
	refresh()


func _on_play() -> void:
	App.haptics.medium()
	match _view:
		VIEW_OVERDRIVE:
			shell.request_play(CampaignService.MODE_ENDLESS)
		VIEW_CHALLENGES:
			if App.challenges.can_play():
				shell.request_play(CampaignService.MODE_CHALLENGE)
		_:
			shell.request_play(CampaignService.MODE_SECTOR)


func _open_achievements() -> void:
	shell.show_tab("missions")
	var missions := shell.screen("missions") as MissionsScreen
	if missions != null:
		missions.show_achievements()
