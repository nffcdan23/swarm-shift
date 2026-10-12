class_name UiKit
extends RefCounted
## Small factories for the controls every screen is built from, so screens
## read as layout rather than styling.


static func label(text: String, size: int = UiTheme.BODY, color: Color = Palette.TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, wide: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wide:
		l.add_theme_font_override("font", UiTheme.font_wide())
	return l


## Capitalised, tracked-out label for headings.
static func caption(text: String, size: int = UiTheme.SMALL, color: Color = Palette.MUTED,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(text.to_upper(), size, color, align, true)


static func title(text: String, size: int = UiTheme.TITLE, color: Color = Palette.TEXT) -> Label:
	var l := label(text.to_upper(), size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UiTheme.font_title())
	return l


## Wrapping body text.
static func paragraph(text: String, size: int = UiTheme.SMALL, color: Color = Palette.MUTED,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func hbox(separation: int = 12) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func vbox(separation: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func spacer(horizontal: bool = true) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func gap(pixels: float, horizontal: bool = false) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.custom_minimum_size = Vector2(pixels, 0) if horizontal else Vector2(0, pixels)
	return s


static func margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(child)
	return m


## Glass card. Returns the panel; put content in the VBox from `card_body()`.
static func card(accent: Color = Palette.CYAN, padding: int = 20, separation: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.panel(accent))
	var body := vbox(separation)
	body.name = "Body"
	var m := margin(body, padding, padding, padding, padding)
	m.name = "Pad"
	p.add_child(m)
	return p


static func card_body(panel: PanelContainer) -> VBoxContainer:
	return panel.get_node("Pad/Body") as VBoxContainer


static func recolor_card(panel: PanelContainer, accent: Color, fill: Color = Palette.PANEL) -> void:
	var style := UiTheme.panel(accent)
	style.bg_color = fill
	panel.add_theme_stylebox_override("panel", style)


## Icon plus amount, e.g. a price or a reward.
static func amount(icon_id: String, text: String, color: Color, size: int = UiTheme.BODY) -> HBoxContainer:
	var row := hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(IconGlyph.make(icon_id, float(size) * 1.15, color))
	row.add_child(label(text, size, color, HORIZONTAL_ALIGNMENT_LEFT, true))
	return row


## A reward bundle such as {"credits": 150, "crystals": 5, "account_xp": 40}.
static func reward_row(bundle: Dictionary, size: int = UiTheme.SMALL) -> HBoxContainer:
	var row := hbox(16)
	if int(bundle.get("credits", 0)) > 0:
		row.add_child(amount("credit", Fmt.compact(float(bundle.credits)), Palette.CREDITS, size))
	if int(bundle.get("crystals", 0)) > 0:
		row.add_child(amount("crystal", Fmt.compact(float(bundle.crystals)), Palette.CRYSTALS, size))
	if int(bundle.get("account_xp", 0)) > 0:
		row.add_child(amount("star", "%s XP" % Fmt.compact(float(bundle.account_xp)), Palette.CYAN, size))
	return row


## Small filled tag ("NEW", "MAX", "BEST VALUE").
static func tag(text: String, color: Color, size: int = UiTheme.TINY) -> PanelContainer:
	var p := PanelContainer.new()
	var style := UiTheme.box(Palette.with_alpha(color, 0.18), Palette.with_alpha(color, 0.9), 8, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(label(text.to_upper(), size, color, HORIZONTAL_ALIGNMENT_CENTER, true))
	return p


## Red notification dot with a count; hidden at zero.
static func badge() -> PanelContainer:
	var p := PanelContainer.new()
	var style := UiTheme.box(Palette.RED, Color(1, 1, 1, 0.9), 14, 2)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(28, 28)
	var l := label("", UiTheme.TINY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Count"
	p.add_child(l)
	p.visible = false
	return p


static func set_badge(panel: PanelContainer, count: int) -> void:
	panel.visible = count > 0
	(panel.get_node("Count") as Label).text = str(mini(count, 99))


static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func divider(color: Color = Palette.LINE) -> ColorRect:
	var line := ColorRect.new()
	line.color = Palette.with_alpha(color, 0.7)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Fades a control in, sliding it too when it is free to move (a container
## owns its children's positions, so those only fade).
static func enter(node: Control, delay: float = 0.0, offset: Vector2 = Vector2(0, 26), seconds: float = 0.28) -> void:
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "modulate:a", 1.0, seconds).set_delay(delay)
	if offset != Vector2.ZERO and not (node.get_parent() is Container):
		var home := node.position
		node.position = home + offset
		tween.tween_property(node, "position", home, seconds).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Quick scale pop to acknowledge a change (currency gained, level bought).
static func pop(node: Control, strength: float = 1.18) -> void:
	node.pivot_offset = node.size * 0.5
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(strength, strength), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
