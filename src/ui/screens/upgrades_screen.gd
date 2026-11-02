class_name UpgradesScreen
extends MenuScreen
## The Research tab: everything permanent bought with Credits, one branch at a
## time. Rows come in the four kinds MetaService knows:
##   track      what it does, what it gives now and after the next purchase,
##              how far along it is, and what that purchase costs. The x1 / x5 /
##              MAX switch buys several levels at once.
##   unlock     a one-off that changes how runs play.
##   doctrine   a trade-off, shown as gains and costs. One is active at a time.
##   awakening  a core's own ability.
## Anything not yet available says exactly what it is waiting for.
##
## Rows are rebuilt on refresh, which is simpler than patching them and
## happens rarely.

const QUANTITIES: Array[int] = [1, 5, 999]

var _list: VBoxContainer
var _summary: Label
var _branches: SegmentedControl
var _quantity: SegmentedControl
var _buy_label: Label
var _amount := 1
var _branch_ids: Array = []


func _build() -> void:
	var column := UiKit.vbox(10)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	column.add_child(header("Research", "Permanent, bought with Credits, and it applies to every run."))

	_branch_ids = App.meta.categories()
	var names := PackedStringArray()
	for category: String in _branch_ids:
		var def := App.meta.category_def(category)
		names.append(GameData.text(def, "short", GameData.text(def, "name", category.to_upper())))
	_branches = SegmentedControl.make(names, 0, UiTheme.TINY)
	_branches.changed.connect(func(_i: int) -> void: refresh())
	column.add_child(_branches)

	var bar := UiKit.hbox(12)
	_summary = UiKit.caption("", UiTheme.TINY, Palette.CYAN)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_summary)
	_buy_label = UiKit.caption("BUY", UiTheme.TINY, Palette.MUTED)
	bar.add_child(_buy_label)
	_quantity = SegmentedControl.make(PackedStringArray(["x1", "x5", "MAX"]))
	_quantity.custom_minimum_size = Vector2(300, 0)
	_quantity.changed.connect(_on_quantity)
	bar.add_child(_quantity)
	column.add_child(bar)

	_list = UiKit.vbox(10)
	column.add_child(UiKit.scroll(_list))


func _on_quantity(index: int) -> void:
	_amount = QUANTITIES[clampi(index, 0, QUANTITIES.size() - 1)]
	refresh()


## Opens on a branch by id (used by the lobby's goals).
func show_branch(category: String) -> void:
	var index := _branch_ids.find(category)
	if index >= 0:
		_branches.select(index)
		refresh()


func _branch() -> String:
	return str(_branch_ids[_branches.selected])


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var category := _branch()
	var ids := App.meta.ids_in(category)
	_list.add_child(_category_header(category, ids))
	var has_tracks := false
	for id in ids:
		has_tracks = has_tracks or App.meta.kind(id) == MetaService.KIND_TRACK
		_list.add_child(_row(id, category))
	_list.add_child(UiKit.gap(8))
	_quantity.visible = has_tracks
	_buy_label.visible = has_tracks
	_summary.text = "%d / %d RESEARCHED" % [App.meta.total_levels(), App.meta.total_max_levels()]
	for i in _branch_ids.size():
		_branches.set_badge(i, 1 if _branch_affordable(str(_branch_ids[i])) else 0)


func _branch_affordable(category: String) -> bool:
	for id in App.meta.ids_in(category):
		if App.meta.can_buy(id):
			return true
	return false


func _category_header(category: String, ids: Array[String]) -> VBoxContainer:
	var def := App.meta.category_def(category)
	var color := GameData.color(def, "color", Palette.CYAN)
	var owned := 0
	var total := 0
	for id in ids:
		owned += App.meta.level(id)
		total += App.meta.max_level(id)
	var box := UiKit.vbox(2)
	var row := UiKit.hbox(10)
	var name_label := UiKit.title(GameData.text(def, "name", category.to_upper()), UiTheme.HEADING, color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(UiKit.caption("%d / %d" % [owned, total], UiTheme.TINY, color))
	box.add_child(row)
	box.add_child(UiKit.paragraph(GameData.text(def, "blurb"), UiTheme.TINY, Palette.MUTED))
	box.add_child(UiKit.divider(color))
	return box


func _row(id: String, category: String) -> PanelContainer:
	var def := App.meta.def(id)
	var kind := App.meta.kind(id)
	var level := App.meta.level(id)
	var cap := App.meta.max_level(id)
	var maxed := App.meta.is_maxed(id)
	var locked := not App.meta.is_unlocked(id)
	var tint := GameData.color(App.meta.category_def(category), "color", Palette.CYAN)
	# How many levels one tap would buy at the chosen quantity.
	var wanted := mini(_amount, cap - level) if kind == MetaService.KIND_TRACK else 1
	var buying := App.meta.affordable_count(id, wanted)
	var affordable := buying > 0
	var active := kind == MetaService.KIND_DOCTRINE and App.meta.active_doctrine() == id
	var accent := Palette.GOLD if maxed else (Palette.DIM if locked else (tint if affordable else Palette.LINE.lightened(0.25)))

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
	centred.add_child(IconGlyph.make("lock" if locked else GameData.text(def, "icon", "star"), 46.0,
		Palette.GOLD if maxed else (Palette.DIM if locked else Palette.TEXT)))
	medallion.add_child(centred)
	row.add_child(medallion)

	var text := UiKit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox(8)
	var name_label := UiKit.label(GameData.text(def, "name", id), UiTheme.BODY, Palette.MUTED if locked else Palette.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	head.add_child(name_label)
	if kind == MetaService.KIND_TRACK:
		head.add_child(UiKit.caption("LV %d / %d" % [level, cap], UiTheme.TINY, Palette.GOLD if maxed else Palette.MUTED))
	elif active:
		head.add_child(UiKit.tag("ACTIVE", Palette.GOLD))
	text.add_child(head)
	match kind:
		MetaService.KIND_TRACK:
			text.add_child(UiKit.paragraph(GameData.text(def, "desc") + " per level", UiTheme.TINY, Palette.MUTED))
			text.add_child(_effect_line(id, level, mini(level + maxi(buying, 1), cap), maxed, locked, tint))
			text.add_child(_pips(level, mini(level + buying, cap), cap, accent))
		MetaService.KIND_DOCTRINE:
			text.add_child(UiKit.paragraph(GameData.text(def, "desc"), UiTheme.TINY, Palette.MUTED))
			for line: String in GameData.list(def, "pros"):
				text.add_child(UiKit.label(line, UiTheme.TINY + 1, Palette.GREEN if not locked else Palette.DIM))
			for line: String in GameData.list(def, "cons"):
				text.add_child(UiKit.label(line, UiTheme.TINY + 1, Palette.RED if not locked else Palette.DIM))
		_:
			text.add_child(UiKit.paragraph(GameData.text(def, "desc"), UiTheme.TINY + 1, Palette.TEXT.darkened(0.2) if not locked else Palette.MUTED))
	row.add_child(text)

	var action := _action(id, kind, maxed, locked, active, buying, affordable)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(action)
	return card


func _action(id: String, kind: String, maxed: bool, locked: bool, active: bool, buying: int, affordable: bool) -> Control:
	if kind == MetaService.KIND_DOCTRINE and maxed:
		var toggle := NeonButton.make("REMOVE" if active else "SELECT", NeonButton.Kind.SECONDARY, Palette.MUTED if active else Palette.CYAN, "", 64.0, UiTheme.SMALL)
		toggle.min_width = 150.0
		toggle.pressed.connect(_toggle_doctrine.bind(id))
		return toggle
	if maxed:
		return UiKit.tag("MAX" if kind == MetaService.KIND_TRACK else "DONE", Palette.GOLD, UiTheme.SMALL)
	if locked:
		return _lock_reason(id)
	# Price of what the tap buys; when nothing is affordable, of one level.
	var count := maxi(buying, 1)
	var price := App.meta.cost_for(id, count)
	var box := UiKit.vbox(2)
	var buy := NeonButton.make(Fmt.compact(float(price)), NeonButton.Kind.PRIMARY if affordable else NeonButton.Kind.SECONDARY,
		Palette.CREDITS if affordable else Palette.MUTED, "credit", 64.0, UiTheme.SMALL)
	buy.min_width = 150.0
	buy.click_sound = ""
	buy.pressed.connect(_buy.bind(id, count))
	box.add_child(buy)
	if count > 1:
		box.add_child(UiKit.caption("%d LEVELS" % count, UiTheme.TINY - 2, Palette.CREDITS, HORIZONTAL_ALIGNMENT_CENTER))
	return box


## What a locked row is waiting for: a Player Level, then other research.
func _lock_reason(id: String) -> Control:
	var gate := App.meta.unlock_level(id)
	if App.account.level() < gate:
		return UiKit.tag("PLAYER LV %d" % gate, Palette.MUTED, UiTheme.TINY)
	var box := UiKit.vbox(2)
	box.custom_minimum_size = Vector2(150, 0)
	box.add_child(UiKit.caption("NEEDS", UiTheme.TINY - 2, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	for need in App.meta.missing_requirements(id):
		var text := str(need.name)
		if int(need.get("level", 1)) > 1:
			text += " %d" % int(need.level)
		box.add_child(UiKit.paragraph(text, UiTheme.TINY - 2, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	return box


## "Damage  +12%  ->  +16%": what is owned now and what the purchase makes it.
func _effect_line(id: String, level: int, after: int, maxed: bool, locked: bool, tint: Color) -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.add_child(UiKit.caption(App.meta.stat_label(id), UiTheme.TINY, Palette.DIM.lightened(0.3)))
	var now := App.meta.effect_text(id, level)
	row.add_child(UiKit.label(now, UiTheme.SMALL, Palette.GOLD if maxed else (Palette.MUTED if locked or level == 0 else Palette.TEXT), HORIZONTAL_ALIGNMENT_LEFT, true))
	if not maxed:
		row.add_child(UiKit.label(">", UiTheme.SMALL, Palette.DIM))
		row.add_child(UiKit.label(App.meta.effect_text(id, after), UiTheme.SMALL, Palette.DIM.lightened(0.2) if locked else tint, HORIZONTAL_ALIGNMENT_LEFT, true))
	return row


## Filled to the level owned; the levels this purchase adds are shown lit.
func _pips(level: int, after: int, cap: int, accent: Color) -> HBoxContainer:
	var row := UiKit.hbox(4)
	for i in cap:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(clampf(200.0 / float(cap), 14.0, 30.0), 7)
		if i < level:
			pip.color = Palette.with_alpha(accent, 0.95)
		elif i < after:
			pip.color = Palette.with_alpha(Palette.CREDITS, 0.55)
		else:
			pip.color = Color(0.14, 0.2, 0.3)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	return row


func _buy(id: String, count: int) -> void:
	var bought := App.meta.buy_many(id, count)
	if bought <= 0:
		shell.deny(Economy.CREDITS)
		return
	App.audio.play("ui_purchase")
	App.haptics.success()
	if bought > 1:
		shell.toast("%s  +%d levels" % [GameData.text(App.meta.def(id), "name", id), bought], Palette.GREEN, "check")
	refresh()
	shell.refresh_badges()


func _toggle_doctrine(id: String) -> void:
	App.meta.select_doctrine("" if App.meta.active_doctrine() == id else id)
	App.haptics.light()
	refresh()
