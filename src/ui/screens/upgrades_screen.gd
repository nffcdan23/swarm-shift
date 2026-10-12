class_name UpgradesScreen
extends MenuScreen
## Permanent upgrades bought with Credits. One row each: what it does, how far
## along it is, and what the next level costs. Rows are rebuilt on refresh,
## which is simpler than patching them and happens rarely.

var _list: VBoxContainer
var _summary: Label


func _build() -> void:
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	column.add_child(header("Upgrades", "Permanent boosts that apply to every run."))
	_summary = UiKit.caption("", UiTheme.TINY, Palette.CYAN)
	column.add_child(_summary)
	_list = UiKit.vbox(10)
	column.add_child(UiKit.scroll(_list))


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var owned := 0
	var total := 0
	for id: String in App.meta.ids():
		owned += App.meta.level(id)
		total += App.meta.max_level(id)
		_list.add_child(_row(id))
	_list.add_child(UiKit.gap(8))
	_summary.text = "%d / %d UPGRADES INSTALLED" % [owned, total]


func _row(id: String) -> PanelContainer:
	var def := App.meta.def(id)
	var level := App.meta.level(id)
	var cap := App.meta.max_level(id)
	var maxed := App.meta.is_maxed(id)
	var affordable := App.meta.can_buy(id)
	var accent := Palette.GOLD if maxed else (Palette.CYAN if affordable else Palette.LINE.lightened(0.25))

	var card := UiKit.card(accent, 14, 6)
	var row := UiKit.hbox(14)
	UiKit.card_body(card).add_child(row)

	var medallion := PanelContainer.new()
	medallion.custom_minimum_size = Vector2(76, 76)
	medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.add_theme_stylebox_override("panel", UiTheme.box(Palette.with_alpha(accent, 0.1), Palette.with_alpha(accent, 0.7), 16, 2))
	var centred := CenterContainer.new()
	centred.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centred.add_child(IconGlyph.make(GameData.text(def, "icon", "star"), 46.0, Palette.GOLD if maxed else Palette.TEXT))
	medallion.add_child(centred)
	row.add_child(medallion)

	var text := UiKit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.label(GameData.text(def, "name", id), UiTheme.BODY, Palette.TEXT))
	text.add_child(UiKit.paragraph(GameData.text(def, "desc"), UiTheme.TINY + 1, Palette.MUTED))
	text.add_child(_pips(level, cap, accent))
	row.add_child(text)

	if maxed:
		var done := UiKit.tag("MAX", Palette.GOLD, UiTheme.SMALL)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(done)
	else:
		var price := App.meta.cost(id)
		var buy := NeonButton.make(Fmt.compact(float(price)), NeonButton.Kind.PRIMARY if affordable else NeonButton.Kind.SECONDARY,
			Palette.CREDITS if affordable else Palette.MUTED, "credit", 68.0, UiTheme.SMALL)
		buy.min_width = 150.0
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.click_sound = ""
		buy.pressed.connect(_buy.bind(id))
		row.add_child(buy)
	return card


func _pips(level: int, cap: int, accent: Color) -> HBoxContainer:
	var row := UiKit.hbox(4)
	for i in cap:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(clampf(200.0 / float(cap), 14.0, 30.0), 7)
		pip.color = Palette.with_alpha(accent, 0.95) if i < level else Color(0.14, 0.2, 0.3)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	return row


func _buy(id: String) -> void:
	if not App.meta.buy(id):
		shell.deny(Economy.CREDITS)
		return
	App.audio.play("ui_purchase")
	App.haptics.success()
	refresh()
	shell.refresh_badges()
