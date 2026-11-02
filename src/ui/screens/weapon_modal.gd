class_name WeaponModal
extends Modal
## One weapon in depth: its Mastery rank and what each rank gives, what you have
## done with it, and its two evolutions with exactly what each one needs.

var _shell: MenuShell
var _id := ""
var _content: VBoxContainer


func _init(shell: MenuShell, weapon_id: String) -> void:
	_shell = shell
	_id = weapon_id
	var def := App.data.weapon(weapon_id)
	heading = GameData.text(def, "name", weapon_id).to_upper()
	accent = GameData.color(def, "color", Palette.CYAN)
	card_width = 660.0


func _build(into: VBoxContainer) -> void:
	_content = UiKit.vbox(10)
	var scroller := UiKit.scroll(_content)
	scroller.custom_minimum_size = Vector2(0, minf(get_viewport_rect().size.y - 300.0, 980.0))
	into.add_child(scroller)
	_fill()


func _fill() -> void:
	for child in _content.get_children():
		child.queue_free()
	var def := App.data.weapon(_id)
	_content.add_child(UiKit.paragraph(GameData.text(def, "tagline"), UiTheme.SMALL, Palette.MUTED))
	_add_mastery(def)
	_add_evolutions(def)
	_add_start_choice()
	_content.add_child(UiKit.gap(4))


func _add_mastery(def: Dictionary) -> void:
	var mastery := App.mastery
	var state := mastery.progress(_id)
	var rank := int(state.rank)
	var head := UiKit.hbox(10)
	var title := UiKit.label("MASTERY  -  %s" % mastery.rank_name(rank), UiTheme.BODY, accent.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.caption("MASTERED" if bool(state.maxed) else "%s / %s XP" % [Fmt.commas(int(state.into)), Fmt.commas(int(state.needed))], UiTheme.TINY, Palette.MUTED))
	_content.add_child(head)
	var bar := MeterBar.make(accent, 12.0)
	bar.set_value(float(state.fraction), true)
	_content.add_child(bar)
	var record := mastery.record(_id)
	_content.add_child(UiKit.caption("%s KILLS  -  %s DAMAGE  -  %d RUNS" % [Fmt.compact(float(record.kills)), Fmt.compact(float(record.damage)), int(record.runs)], UiTheme.TINY, Palette.DIM.lightened(0.3)))

	_content.add_child(UiKit.divider(accent))
	var rewards := _rank_rewards(def)
	for number in range(1, mastery.max_rank() + 1):
		var earned := rank >= number
		var row := UiKit.hbox(10)
		row.add_child(IconGlyph.make("check" if earned else "lock", 22.0, Palette.GREEN if earned else Palette.DIM))
		var label_text := UiKit.caption(mastery.rank_name(number), UiTheme.TINY, Palette.TEXT if earned else Palette.MUTED)
		label_text.custom_minimum_size = Vector2(130, 0)
		row.add_child(label_text)
		row.add_child(UiKit.paragraph(str(rewards.get(number, "")), UiTheme.TINY + 1, Palette.TEXT if earned else Palette.MUTED))
		_content.add_child(row)


## One line per rank saying what it gives.
func _rank_rewards(def: Dictionary) -> Dictionary:
	var lines := {1: "Can be chosen as a starting weapon (Flex Rack)", 5: "Master finish, and counts towards the PARAGON skin"}
	for perk in App.mastery.perks(_id):
		lines[int(perk.rank)] = str(perk.desc)
	var table := GameData.dict(def, "evolutions")
	for path: String in table:
		var entry: Dictionary = table[path]
		var rank := GameData.integer(entry, "rank")
		var text := "Evolution: %s" % GameData.text(entry, "name", path)
		lines[rank] = "%s, %s" % [lines[rank], text] if lines.has(rank) else text
	return lines


func _add_evolutions(def: Dictionary) -> void:
	var table := GameData.dict(def, "evolutions")
	if table.is_empty():
		return
	_content.add_child(UiKit.gap(2))
	_content.add_child(UiKit.caption("EVOLUTIONS", UiTheme.SMALL, Palette.GOLD))
	_content.add_child(UiKit.paragraph("At its final level a weapon can evolve. If you own both, you choose on the card, mid-run.", UiTheme.TINY, Palette.MUTED))
	for path: String in table:
		_content.add_child(_evolution_card(path, table[path]))


func _evolution_card(path: String, entry: Dictionary) -> PanelContainer:
	var color := GameData.color(entry, "color", Palette.GOLD)
	var info := App.mastery.evolution_info(_id, path)
	var owned := bool(info.owned)
	var card := UiKit.card(color if owned else Palette.LINE.lightened(0.25), 12, 6)
	var row := UiKit.hbox(12)
	var text := UiKit.vbox(3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label(GameData.text(entry, "name", path).to_upper(), UiTheme.SMALL, Palette.TEXT if owned else Palette.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	head.add_child(UiKit.tag(GameData.text(entry, "role"), color))
	text.add_child(head)
	text.add_child(UiKit.paragraph(GameData.text(entry, "desc"), UiTheme.TINY + 1, Palette.TEXT.darkened(0.2)))
	row.add_child(text)
	var action := _evolution_action(path, info)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(action)
	UiKit.card_body(card).add_child(row)
	return card


func _evolution_action(path: String, info: Dictionary) -> Control:
	if bool(info.owned):
		return UiKit.tag("OWNED", Palette.GREEN)
	if not bool(info.lab):
		return UiKit.tag("EVOLUTION LAB", Palette.MUTED, UiTheme.TINY - 1)
	if not bool(info.rank_met):
		return UiKit.tag("RANK %d" % int(info.rank), Palette.MUTED, UiTheme.TINY)
	var affordable := bool(info.affordable)
	var buy := NeonButton.make(Fmt.compact(float(info.cost)), NeonButton.Kind.PRIMARY if affordable else NeonButton.Kind.SECONDARY,
		Palette.CREDITS if affordable else Palette.MUTED, "credit", 60.0, UiTheme.SMALL)
	buy.min_width = 140.0
	buy.click_sound = ""
	buy.pressed.connect(_unlock.bind(path))
	return buy


func _add_start_choice() -> void:
	var options := App.arsenal.start_weapon_options()
	if not options.has(_id):
		return
	var current := App.arsenal.start_weapon() == _id
	var core_own := GameData.text(GameData.dict(App.data.cores(), App.arsenal.selected_core()), "start_weapon") == _id
	if current and core_own:
		return
	_content.add_child(UiKit.gap(2))
	var button := NeonButton.make("BACK TO CORE WEAPON" if current else "START RUNS WITH THIS", NeonButton.Kind.SECONDARY, Palette.CYAN, "", 64.0, UiTheme.SMALL)
	button.pressed.connect(func() -> void:
		App.arsenal.select_start_weapon("" if current else _id)
		App.haptics.light()
		_fill())
	_content.add_child(button)


func _unlock(path: String) -> void:
	if not App.mastery.unlock_evolution(_id, path):
		_shell.deny(Economy.CREDITS)
		return
	App.audio.play("ui_purchase")
	App.haptics.success()
	_shell.toast("%s unlocked" % GameData.text(App.mastery.evolution_def(_id, path), "name", path), Palette.GREEN, "check")
	_fill()
	_shell.refresh_badges()
