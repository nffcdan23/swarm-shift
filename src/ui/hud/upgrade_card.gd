class_name UpgradeCard
extends Button
## One of the three choices on the level-up screen. Big, tappable, and readable
## at a glance: icon, name, what it does, and where it sits in its level track.
## Border and glow are in the rarity colour.

var offer: Dictionary = {}

var _accent := Palette.CYAN
var _tween: Tween


static func make(p_offer: Dictionary) -> UpgradeCard:
	var card := UpgradeCard.new()
	card.offer = p_offer
	card._build()
	return card


func _build() -> void:
	_accent = offer.get("color", Palette.CYAN)
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(640, 188)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restyle(false)

	var row := UiKit.hbox(20)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22.0
	row.offset_right = -22.0
	row.offset_top = 16.0
	row.offset_bottom = -16.0
	add_child(row)

	# Icon medallion.
	var medallion := PanelContainer.new()
	medallion.custom_minimum_size = Vector2(124, 124)
	medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.add_theme_stylebox_override("panel", UiTheme.box(Palette.with_alpha(_accent, 0.12), Palette.with_alpha(_accent, 0.85), 22, 2, 10.0))
	var icon_color: Color = offer.get("icon_color", _accent.lightened(0.25))
	var glyph := IconGlyph.make(str(offer.get("icon", "star")), 78.0, icon_color, true)
	var centred := CenterContainer.new()
	centred.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centred.add_child(glyph)
	medallion.add_child(centred)
	row.add_child(medallion)

	var text := UiKit.vbox(6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)

	var head := UiKit.hbox(10)
	var name_label := UiKit.label(str(offer.get("name", "")).to_upper(), UiTheme.HEADING, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	head.add_child(name_label)
	head.add_child(UiKit.tag(_status_text(), _accent))
	text.add_child(head)

	text.add_child(UiKit.paragraph(str(offer.get("desc", "")), UiTheme.SMALL + 1, Palette.TEXT.darkened(0.12)))

	var foot := UiKit.hbox(10)
	foot.add_child(UiKit.caption(str(offer.get("rarity_name", "")), UiTheme.TINY, _accent))
	foot.add_child(UiKit.spacer())
	var max_level := int(offer.get("max_level", 0))
	if max_level > 1:
		foot.add_child(_pips(int(offer.get("level", 1)), max_level))
	text.add_child(foot)

	for child in [row, medallion, text]:
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _status_text() -> String:
	var kind := str(offer.get("kind", ""))
	if kind == UpgradeSystem.KIND_WEAPON or kind == UpgradeSystem.KIND_PASSIVE:
		if bool(offer.get("is_new", false)):
			return "NEW"
		# The pick that completes an item. It used to say "MAX LEVEL", which
		# playtesters read as "this is already maxed - why is it offered?".
		if int(offer.get("level", 1)) >= int(offer.get("max_level", 1)):
			return "FINAL UPGRADE"
		return "LEVEL %d" % int(offer.get("level", 1))
	if kind == UpgradeSystem.KIND_AUGMENT:
		return "AUGMENT"
	return "INSTANT"


## Level track: filled up to the level this pick would reach, the new pip lit.
func _pips(level: int, max_level: int) -> HBoxContainer:
	var row := UiKit.hbox(5)
	for i in max_level:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(22, 8)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < level - 1:
			pip.color = Palette.with_alpha(_accent, 0.75)
		elif i == level - 1:
			pip.color = Color.WHITE
		else:
			pip.color = Color(0.16, 0.22, 0.32)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
	return row


func _restyle(lit: bool) -> void:
	var fill := Palette.PANEL_SOLID.lerp(_accent, 0.2 if lit else 0.07)
	fill.a = 0.96
	var normal := UiTheme.box(fill, _accent if lit else Palette.with_alpha(_accent, 0.8), 22, 3 if lit else 2, 22.0 if lit else 12.0)
	var down := UiTheme.box(Palette.PANEL_SOLID.lerp(_accent, 0.28), _accent.lightened(0.3), 22, 3, 24.0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", normal)
	add_theme_stylebox_override("pressed", down)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Flies in from below with a slight overshoot.
func appear(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2(0.86, 0.86)
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	pivot_offset = size * 0.5
	App.audio.play("card_show", 1.0 + delay * 1.2)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The chosen card swells and lights up.
func celebrate() -> void:
	_restyle(true)
	pivot_offset = size * 0.5
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate", Color(1.35, 1.35, 1.35, 1.0), 0.12)


## The ones not chosen drop back.
func dismiss() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.tween_property(self, "scale", Vector2(0.92, 0.92), 0.18)
