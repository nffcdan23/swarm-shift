class_name BuildStrip
extends VBoxContainer
## Compact read-out of the current build: weapons and passives with their
## levels, augments as icons. Shown on the level-up and pause screens so a
## choice can be made with the whole build in view.


static func make(arena: Arena) -> BuildStrip:
	var strip := BuildStrip.new()
	strip.add_theme_constant_override("separation", 10)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.fill(arena)
	return strip


func fill(arena: Arena) -> void:
	for child in get_children():
		child.queue_free()
	var data := arena.data
	var build := arena.build
	var max_weapon := GameData.integer(data.weapons, "max_level", 5)

	var weapons := _row()
	for weapon_id in build.weapon_order:
		var def := data.weapon(weapon_id)
		weapons.add_child(_chip(GameData.text(def, "icon", "star"), GameData.color(def, "color", Palette.CYAN),
			build.weapon_level(weapon_id), max_weapon))
	add_child(weapons)

	if not build.passive_order.is_empty() or not build.augments.is_empty():
		var extras := _row()
		for passive_id in build.passive_order:
			var def := GameData.dict(data.passives(), passive_id)
			extras.add_child(_chip(GameData.text(def, "icon", "star"), Palette.TEXT, build.passive_level(passive_id), GameData.integer(def, "max_level", 5)))
		for augment_id in build.augments:
			var def := GameData.dict(data.augments(), augment_id)
			var rarity := data.rarity(GameData.text(def, "rarity", "epic"))
			extras.add_child(_chip(GameData.text(def, "icon", "star"), GameData.color(rarity, "color", Palette.VIOLET), 0, 0))
		add_child(extras)


func _row() -> HBoxContainer:
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


func _chip(icon_id: String, color: Color, level: int, max_level: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var maxed := max_level > 0 and level >= max_level
	var style := UiTheme.box(Palette.with_alpha(color, 0.1), Palette.with_alpha(Palette.GOLD if maxed else color, 0.75), 12, 2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiKit.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(IconGlyph.make(icon_id, 40.0, color))
	if max_level > 0:
		box.add_child(UiKit.label("MAX" if maxed else str(level), UiTheme.TINY, Palette.GOLD if maxed else Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	panel.add_child(box)
	return panel
