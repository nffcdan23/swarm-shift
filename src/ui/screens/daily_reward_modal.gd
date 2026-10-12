class_name DailyRewardModal
extends Modal
## Seven-day login calendar. Shows the whole week so the good days are visible
## in advance; today's reward can be taken as is or doubled with an optional ad.

var _shell: MenuShell
var _buttons: VBoxContainer
var _busy := false


func _init(shell: MenuShell = null) -> void:
	_shell = shell
	heading = "DAILY REWARD"
	accent = Palette.AMBER


func _build(into: VBoxContainer) -> void:
	var cycle := App.daily.cycle()
	var current := App.daily.current_index()
	var claimable := App.daily.can_claim()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for i in cycle.size():
		grid.add_child(_cell(i, cycle[i], current, claimable))
	into.add_child(grid)
	into.add_child(UiKit.paragraph("Come back any day for the next reward. Missing a day never resets your progress.",
		UiTheme.TINY + 1, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	_buttons = UiKit.vbox(10)
	into.add_child(_buttons)
	_fill_buttons()


func _cell(index: int, reward: Dictionary, current: int, claimable: bool) -> PanelContainer:
	var today := index == current and claimable
	var taken := index < current
	var color := Palette.AMBER if today else (Palette.DIM if taken else Palette.LINE.lightened(0.3))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(128, 122)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.with_alpha(color, 0.14 if today else 0.05), color, 14, 2, 12.0 if today else 0.0))
	var box := UiKit.vbox(4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(UiKit.caption("DAY %d" % (index + 1), UiTheme.TINY, color if not taken else Palette.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	if taken:
		box.add_child(IconGlyph.make("check", 34.0, Palette.GREEN))
	else:
		var crystals := int(reward.get("crystals", 0))
		var credits := int(reward.get("credits", 0))
		if credits > 0:
			box.add_child(UiKit.amount("credit", Fmt.compact(float(credits)), Palette.CREDITS, UiTheme.SMALL))
		if crystals > 0:
			box.add_child(UiKit.amount("crystal", str(crystals), Palette.CRYSTALS, UiTheme.SMALL))
	panel.add_child(box)
	return panel


func _fill_buttons() -> void:
	for child in _buttons.get_children():
		child.queue_free()
	if not App.daily.can_claim():
		_buttons.add_child(UiKit.caption("COME BACK TOMORROW FOR DAY %d" % (App.daily.current_index() + 1), UiTheme.SMALL, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		return
	var claim := NeonButton.make("CLAIM", NeonButton.Kind.PRIMARY, Palette.AMBER, "gift", 92.0, UiTheme.HEADING)
	claim.click_sound = ""
	claim.pressed.connect(_claim.bind(false))
	_buttons.add_child(claim)
	if App.ads.rewarded_available(AdsService.DAILY_DOUBLE):
		var double := NeonButton.make("CLAIM DOUBLE", NeonButton.Kind.SECONDARY, Palette.GREEN, "ad", 72.0, UiTheme.SMALL)
		double.click_sound = ""
		double.pressed.connect(_claim.bind(true))
		_buttons.add_child(double)


func _claim(doubled: bool) -> void:
	if _busy:
		return
	_busy = true
	var multiplier := 1
	if doubled:
		var earned: bool = await App.ads.show_rewarded(AdsService.DAILY_DOUBLE)
		# If the ad was skipped the player still gets the normal reward.
		multiplier = 2 if earned else 1
	var reward := App.daily.claim(multiplier)
	_busy = false
	if reward.is_empty():
		return
	App.audio.play("ui_claim")
	App.haptics.success()
	if _shell != null:
		var parts: PackedStringArray = []
		if int(reward.get("credits", 0)) > 0:
			parts.append("+%s Credits" % Fmt.commas(int(reward.credits)))
		if int(reward.get("crystals", 0)) > 0:
			parts.append("+%d Crystals" % int(reward.crystals))
		_shell.toast("  ".join(parts), Palette.AMBER, "gift")
	close()
