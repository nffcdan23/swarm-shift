class_name ArsenalScreen
extends MenuScreen
## Cores (who you play), weapons (what can show up on level-up) and skins
## (how you look). All three use the same unlock rules from ArsenalService, so
## one card builder serves them all.

const SECTIONS: PackedStringArray = ["CORES", "WEAPONS", "SKINS"]
const CATEGORIES: PackedStringArray = [ArsenalService.CORES, ArsenalService.WEAPONS, ArsenalService.SKINS]

var _tabs: SegmentedControl
var _list: VBoxContainer
var _blurb: Label


func _build() -> void:
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	column.add_child(header("Arsenal"))
	_tabs = SegmentedControl.make(SECTIONS)
	_tabs.changed.connect(func(_i: int) -> void: refresh())
	column.add_child(_tabs)
	_blurb = UiKit.paragraph("", UiTheme.TINY + 1, Palette.MUTED)
	column.add_child(_blurb)
	_list = UiKit.vbox(10)
	column.add_child(UiKit.scroll(_list))


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var category := CATEGORIES[_tabs.selected]
	match category:
		ArsenalService.CORES:
			_blurb.text = "Each core starts with a different weapon and plays differently."
		ArsenalService.WEAPONS:
			_blurb.text = "Unlocked weapons can appear as upgrade choices during a run."
		_:
			_blurb.text = "Cosmetic colours for your core. No effect on gameplay."
	for id: String in App.arsenal.defs(category):
		_list.add_child(_card(category, id))
	_list.add_child(UiKit.gap(8))
	_tabs.set_badge(0, 1 if _any_affordable(ArsenalService.CORES) else 0)
	_tabs.set_badge(1, 1 if _any_affordable(ArsenalService.WEAPONS) else 0)


func _any_affordable(category: String) -> bool:
	for id: String in App.arsenal.defs(category):
		if bool(App.arsenal.unlock_info(category, id).affordable):
			return true
	return false


func _card(category: String, id: String) -> PanelContainer:
	var def := GameData.dict(App.arsenal.defs(category), id)
	var info := App.arsenal.unlock_info(category, id)
	var owned := bool(info.owned)
	var selected := (category == ArsenalService.CORES and App.arsenal.selected_core() == id) \
		or (category == ArsenalService.SKINS and App.arsenal.selected_skin() == id)
	var color := GameData.color(def, "color", Palette.CYAN)
	if category == ArsenalService.SKINS and GameData.text(def, "color").is_empty():
		color = GameData.color(GameData.dict(App.data.cores(), App.arsenal.selected_core()), "color", Palette.CYAN)
	var accent := color if owned else Palette.LINE.lightened(0.25)

	var card := UiKit.card(Palette.GOLD if selected else accent, 14, 8)
	if selected:
		UiKit.recolor_card(card, Palette.GOLD, Palette.PANEL.lerp(Palette.GOLD, 0.06))
	var row := UiKit.hbox(14)
	UiKit.card_body(card).add_child(row)

	var medallion := PanelContainer.new()
	medallion.custom_minimum_size = Vector2(84, 84)
	medallion.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.add_theme_stylebox_override("panel", UiTheme.box(Palette.with_alpha(color, 0.14 if owned else 0.04), Palette.with_alpha(color, 0.8 if owned else 0.3), 18, 2))
	var centred := CenterContainer.new()
	centred.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_id := "lock"
	if owned:
		icon_id = GameData.text(def, "icon", "star" if category == ArsenalService.WEAPONS else "boss")
	centred.add_child(IconGlyph.make(icon_id, 50.0, color if owned else Palette.DIM, owned))
	medallion.add_child(centred)
	row.add_child(medallion)

	var text := UiKit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox(10)
	head.add_child(UiKit.label(GameData.text(def, "name", id).to_upper(), UiTheme.BODY, Palette.TEXT if owned else Palette.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if selected:
		head.add_child(UiKit.tag("ACTIVE", Palette.GOLD))
	text.add_child(head)
	var blurb := GameData.text(def, "desc", GameData.text(def, "tagline"))
	if not blurb.is_empty():
		text.add_child(UiKit.paragraph(blurb, UiTheme.TINY + 1, Palette.MUTED))
	if category == ArsenalService.CORES:
		var start := App.data.weapon(GameData.text(def, "start_weapon"))
		text.add_child(UiKit.caption("STARTS WITH " + GameData.text(start, "name"), UiTheme.TINY, color if owned else Palette.DIM))
		for trait_text: String in GameData.list(def, "traits"):
			var good := not trait_text.begins_with("-")
			text.add_child(UiKit.label(trait_text, UiTheme.TINY + 1, (Palette.GREEN if good else Palette.RED) if owned else Palette.DIM))
	row.add_child(text)

	var action := _action(category, id, info, selected)
	if action != null:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action)
	return card


func _action(category: String, id: String, info: Dictionary, selected: bool) -> Control:
	if bool(info.owned):
		if category == ArsenalService.WEAPONS:
			return IconGlyph.make("check", 34.0, Palette.GREEN)
		if selected:
			return null
		var choose := NeonButton.make("SELECT", NeonButton.Kind.SECONDARY, Palette.CYAN, "", 64.0, UiTheme.SMALL)
		choose.min_width = 140.0
		choose.pressed.connect(_select.bind(category, id))
		return choose
	match str(info.kind):
		"product":
			return UiKit.tag("STARTER PACK", Palette.GOLD)
		"level", "crystals":
			if not bool(info.level_met):
				return UiKit.tag("PLAYER LV %d" % int(info.level), Palette.MUTED, UiTheme.TINY)
			var currency := str(info.currency)
			var color := Palette.currency(currency)
			var affordable := bool(info.affordable)
			var buy := NeonButton.make(Fmt.compact(float(info.cost)), NeonButton.Kind.PRIMARY if affordable else NeonButton.Kind.SECONDARY,
				color if affordable else Palette.MUTED, "crystal" if currency == Economy.CRYSTALS else "credit", 64.0, UiTheme.SMALL)
			buy.min_width = 150.0
			buy.click_sound = ""
			buy.pressed.connect(_unlock.bind(category, id, currency))
			return buy
	return null


func _select(category: String, id: String) -> void:
	if category == ArsenalService.CORES:
		App.arsenal.select_core(id)
	else:
		App.arsenal.select_skin(id)
	App.haptics.light()
	refresh()


func _unlock(category: String, id: String, currency: String) -> void:
	if not App.arsenal.unlock(category, id):
		shell.deny(currency)
		return
	App.audio.play("ui_purchase")
	App.haptics.success()
	var def := GameData.dict(App.arsenal.defs(category), id)
	shell.toast("%s unlocked" % GameData.text(def, "name", id), Palette.GREEN, "check")
	refresh()
	shell.refresh_badges()
