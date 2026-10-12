class_name ProfileModal
extends Modal
## Account level and lifetime statistics.


func _init() -> void:
	heading = "PROFILE"
	accent = Palette.CYAN


func _build(into: VBoxContainer) -> void:
	var account := App.account
	var top := UiKit.hbox(16)
	top.add_child(IconGlyph.make("profile", 64.0, Palette.CYAN, true))
	var info := UiKit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.label("LEVEL %d" % account.level(), UiTheme.HEADING, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var bar := MeterBar.make(Palette.CYAN, 14.0)
	bar.set_value(account.progress(), true)
	info.add_child(bar)
	if account.is_max():
		info.add_child(UiKit.caption("MAX LEVEL", UiTheme.TINY, Palette.GOLD))
	else:
		info.add_child(UiKit.caption("%s / %s XP" % [Fmt.commas(account.xp()), Fmt.commas(account.xp_needed(account.level()))], UiTheme.TINY, Palette.MUTED))
	top.add_child(info)
	into.add_child(top)

	if not account.is_max():
		var next := account.level_rewards(account.level() + 1)
		var teaser := UiKit.hbox(12)
		teaser.add_child(UiKit.caption("NEXT LEVEL", UiTheme.TINY, Palette.MUTED))
		teaser.add_child(UiKit.reward_row(next, UiTheme.TINY + 1))
		into.add_child(teaser)
		var unlocks: Array = next.get("unlocks", [])
		if not unlocks.is_empty():
			into.add_child(UiKit.caption("UNLOCKS " + ", ".join(PackedStringArray(unlocks)), UiTheme.TINY, Palette.GOLD))
	into.add_child(UiKit.divider())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	for entry in StatsService.DISPLAY:
		var name_label := UiKit.label(str(entry.label), UiTheme.SMALL, Palette.MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		grid.add_child(UiKit.label(App.stats.display_value(entry), UiTheme.SMALL, Palette.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, true))
	into.add_child(grid)
