class_name ProfileModal
extends Modal
## The permanent Player Level - its XP, what the next level pays, and the road
## of unlocks ahead - plus lifetime statistics.


func _init() -> void:
	heading = "PROFILE"
	accent = Palette.CYAN


func _build(into: VBoxContainer) -> void:
	var account := App.account
	var top := UiKit.hbox(16)
	top.add_child(IconGlyph.make("profile", 64.0, Palette.CYAN, true))
	var info := UiKit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.label("PLAYER LEVEL %d" % account.level(), UiTheme.HEADING, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var bar := MeterBar.make(Palette.CYAN, 14.0)
	bar.set_value(account.progress(), true)
	info.add_child(bar)
	if account.is_max():
		info.add_child(UiKit.caption("MAX LEVEL", UiTheme.TINY, Palette.GOLD))
	else:
		info.add_child(UiKit.caption("%s / %s XP  -  %s TO GO" % [Fmt.commas(account.xp()), Fmt.commas(account.xp_needed(account.level())),
			Fmt.commas(account.xp_to_next())], UiTheme.TINY, Palette.MUTED))
	top.add_child(info)
	into.add_child(top)

	if not account.is_max():
		var next := account.level_rewards(account.level() + 1)
		var teaser := UiKit.hbox(12)
		teaser.add_child(UiKit.caption("NEXT LEVEL", UiTheme.TINY, Palette.MUTED))
		teaser.add_child(UiKit.reward_row(next, UiTheme.TINY + 1))
		into.add_child(teaser)
	into.add_child(UiKit.paragraph("Player XP comes from every run (time survived, enemies defeated, Run Level, bosses, sectors cleared), daily missions and achievements. It is never lost.",
		UiTheme.TINY, Palette.MUTED))

	var road := account.roadmap(5)
	if not road.is_empty():
		into.add_child(UiKit.divider())
		into.add_child(UiKit.caption("UNLOCKS BY PLAYER LEVEL", UiTheme.TINY, Palette.MUTED))
		for step in road:
			var reached := bool(step.reached)
			var line := UiKit.hbox(10)
			line.add_child(IconGlyph.make("check" if reached else "lock", 22.0, Palette.GREEN if reached else Palette.DIM.lightened(0.2)))
			var level_tag := UiKit.label("LV %d" % int(step.level), UiTheme.TINY + 1, Palette.GREEN if reached else Palette.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true)
			level_tag.custom_minimum_size = Vector2(74, 0)
			line.add_child(level_tag)
			line.add_child(UiKit.paragraph(", ".join(PackedStringArray(step.names)), UiTheme.TINY + 1, Palette.MUTED if reached else Palette.TEXT))
			into.add_child(line)
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
