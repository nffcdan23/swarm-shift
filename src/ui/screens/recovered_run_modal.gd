class_name RecoveredRunModal
extends Modal
## Shown once at launch when the previous session ended in the middle of a run
## (the app was closed, killed, or crashed). The run was checkpointed while it
## was being played, so its rewards are paid out now rather than lost.

var _summary: Dictionary


func _init(summary: Dictionary) -> void:
	_summary = summary
	heading = "RUN RECOVERED"
	accent = Palette.GREEN


func _build(into: VBoxContainer) -> void:
	into.add_child(UiKit.paragraph("Your last run was cut short before it could finish. Everything it earned has been banked.",
		UiTheme.SMALL, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var stats := UiKit.hbox(26)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(UiKit.amount("clock", Fmt.time_mmss(float(_summary.get("time", 0.0))), Palette.TEXT))
	stats.add_child(UiKit.amount("skull", Fmt.compact(float(_summary.get("kills", 0))), Palette.TEXT))
	stats.add_child(UiKit.amount("upgrade", "RUN LV %d" % int(_summary.get("run_level", 1)), Palette.ENERGY))
	into.add_child(stats)
	into.add_child(UiKit.divider())

	var rewards := UiKit.hbox(28)
	rewards.alignment = BoxContainer.ALIGNMENT_CENTER
	rewards.add_child(UiKit.amount("credit", "+%s" % Fmt.commas(int(_summary.get("credits", 0))), Palette.CREDITS, UiTheme.HEADING))
	rewards.add_child(UiKit.amount("star", "+%s XP" % Fmt.commas(int(_summary.get("account_xp", 0))), Palette.CYAN, UiTheme.HEADING))
	into.add_child(rewards)

	var gained: Array = _summary.get("level_ups", [])
	if not gained.is_empty():
		into.add_child(UiKit.caption("PLAYER LEVEL %d REACHED" % int(_summary.get("level_after", 1)), UiTheme.SMALL, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	into.add_child(UiKit.gap(4))

	var ok := NeonButton.make("COLLECT", NeonButton.Kind.PRIMARY, Palette.GREEN, "", 88.0, UiTheme.HEADING)
	ok.pressed.connect(close)
	into.add_child(ok)
