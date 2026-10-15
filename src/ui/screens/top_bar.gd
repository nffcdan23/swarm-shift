class_name TopBar
extends HBoxContainer
## Always-visible strip above the menu screens: Player Level and progress on
## the left, both currencies and the settings gear on the right.

signal profile_pressed
signal settings_pressed
signal shop_pressed

var _level: Label
var _xp: MeterBar
var _credits: Label
var _crystals: Label
var _shown := {Economy.CREDITS: -1, Economy.CRYSTALS: -1}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(0, 76)

	var profile := Button.new()
	profile.flat = true
	profile.focus_mode = Control.FOCUS_NONE
	profile.custom_minimum_size = Vector2(230, 72)
	profile.add_theme_stylebox_override("normal", UiTheme.box(Palette.PANEL, Palette.with_alpha(Palette.CYAN, 0.45), 16, 2))
	profile.add_theme_stylebox_override("hover", UiTheme.box(Palette.PANEL, Palette.with_alpha(Palette.CYAN, 0.45), 16, 2))
	profile.add_theme_stylebox_override("pressed", UiTheme.box(Palette.PANEL_RAISED, Palette.CYAN, 16, 2))
	profile.pressed.connect(func() -> void:
		App.audio.play("ui_click")
		profile_pressed.emit())
	var inner := UiKit.hbox(12)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 12.0
	inner.offset_right = -14.0
	inner.add_child(IconGlyph.make("profile", 40.0, Palette.CYAN))
	var stack := UiKit.vbox(5)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_level = UiKit.caption("PLAYER LV 1", UiTheme.SMALL, Palette.TEXT)
	stack.add_child(_level)
	_xp = MeterBar.make(Palette.CYAN, 9.0)
	stack.add_child(_xp)
	inner.add_child(stack)
	profile.add_child(inner)
	add_child(profile)

	add_child(UiKit.spacer())
	_credits = _pill("credit", Palette.CREDITS)
	_crystals = _pill("crystal", Palette.CRYSTALS)

	var gear := NeonButton.make("", NeonButton.Kind.SECONDARY, Palette.MUTED, "gear", 64.0)
	gear.min_width = 64.0
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	add_child(gear)

	App.economy.changed.connect(_on_currency_changed)
	App.account.xp_changed.connect(func(_l: int, _x: int, _n: int) -> void: refresh())
	refresh()


func _pill(icon_id: String, color: Color) -> Label:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(136, 56)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := UiTheme.box(Palette.PANEL, Palette.with_alpha(color, 0.5), 28, 2)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", UiTheme.box(Palette.PANEL_RAISED, color, 28, 2))
	button.pressed.connect(func() -> void:
		App.audio.play("ui_click")
		shop_pressed.emit())
	var row := UiKit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12.0
	row.offset_right = -14.0
	row.add_child(IconGlyph.make(icon_id, 30.0, color))
	var amount := UiKit.label("0", UiTheme.SMALL, color, HORIZONTAL_ALIGNMENT_RIGHT, true)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount)
	button.add_child(row)
	add_child(button)
	return amount


func refresh() -> void:
	_level.text = "PLAYER LV %d" % App.account.level()
	_xp.set_value(App.account.progress())
	_set_amount(Economy.CREDITS, _credits, false)
	_set_amount(Economy.CRYSTALS, _crystals, false)


func _on_currency_changed(currency: String, _balance: int, _delta: int) -> void:
	_set_amount(currency, _credits if currency == Economy.CREDITS else _crystals, true)


func _set_amount(currency: String, label: Label, animate: bool) -> void:
	var balance := App.economy.balance(currency)
	if int(_shown[currency]) == balance:
		return
	_shown[currency] = balance
	label.text = Fmt.compact(float(balance))
	if animate and is_visible_in_tree():
		UiKit.pop(label, 1.25)
