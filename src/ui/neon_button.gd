class_name NeonButton
extends Button
## The game's button. Adds what a stock Button lacks for a touch game: a
## squash-and-spring press animation, click sound, a light haptic tick, and an
## optional vector icon beside the label.

enum Kind { PRIMARY, SECONDARY, GHOST, DANGER }

## Set false for buttons that play their own sound (purchase, claim).
var click_sound := "ui_click"
## Lower bound on width; the button still grows to fit its label.
var min_width := 0.0:
	set(value):
		min_width = value
		if _row != null:
			_fit()

var _kind := Kind.SECONDARY
var _accent := Palette.CYAN
var _row: HBoxContainer
var _glyph: IconGlyph
var _label: Label
var _tween: Tween


static func make(text_value: String, kind: Kind = Kind.SECONDARY, accent: Color = Palette.CYAN, icon_id: String = "",
		height: float = 84.0, font_size: int = UiTheme.BODY) -> NeonButton:
	var button := NeonButton.new()
	button.custom_minimum_size = Vector2(0, height)
	button.configure(text_value, kind, accent, icon_id, font_size)
	return button


func configure(text_value: String, kind: Kind, accent: Color, icon_id: String, font_size: int) -> void:
	_kind = kind
	_accent = accent
	focus_mode = Control.FOCUS_NONE
	text = ""
	if _row == null:
		_row = HBoxContainer.new()
		_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_theme_constant_override("separation", 12)
		add_child(_row)
		_glyph = IconGlyph.make("star", float(font_size) * 1.25)
		_row.add_child(_glyph)
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_override("font", UiTheme.font_wide())
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_row.add_child(_label)
		button_down.connect(_on_down)
		button_up.connect(_on_up)
		pressed.connect(_on_pressed)
		resized.connect(_on_resized)
	_label.add_theme_font_size_override("font_size", font_size)
	_glyph.custom_minimum_size = Vector2(float(font_size) * 1.25, float(font_size) * 1.25)
	set_label(text_value)
	set_icon(icon_id)
	_restyle()


func set_label(text_value: String) -> void:
	_label.text = text_value
	_label.visible = not text_value.is_empty()
	_fit()


func set_icon(icon_id: String) -> void:
	_glyph.visible = not icon_id.is_empty()
	if not icon_id.is_empty():
		_glyph.icon_id = icon_id
	_fit()


## A Button sizes itself from its own `text`, which is empty here because the
## label is a child. Reserve room for the real content instead.
func _fit() -> void:
	var needed := _row.get_combined_minimum_size().x + 48.0
	custom_minimum_size.x = maxf(min_width, needed)


func set_accent(accent: Color) -> void:
	_accent = accent
	_restyle()


func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	_restyle()


func _restyle() -> void:
	var fill: Color
	var border: Color
	var ink: Color
	match _kind:
		Kind.PRIMARY:
			fill = _accent
			border = _accent.lightened(0.35)
			ink = Color(0.02, 0.05, 0.09)
		Kind.GHOST:
			fill = Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			ink = _accent
		Kind.DANGER:
			fill = Palette.with_alpha(Palette.RED, 0.14)
			border = Palette.RED
			ink = Palette.RED
		_:
			fill = Palette.with_alpha(_accent, 0.1)
			border = Palette.with_alpha(_accent, 0.75)
			ink = _accent.lightened(0.25)
	if disabled:
		fill = Color(0.07, 0.09, 0.13, 0.75)
		border = Palette.with_alpha(Palette.DIM, 0.5)
		ink = Palette.DIM
	var glow := 16.0 if _kind == Kind.PRIMARY and not disabled else 0.0
	var normal := UiTheme.box(fill, border, 16, 2 if _kind != Kind.GHOST else 0, glow)
	var down := UiTheme.box(fill.lightened(0.18) if _kind == Kind.PRIMARY else Palette.with_alpha(_accent, 0.28), border, 16, 2 if _kind != Kind.GHOST else 0, glow)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", normal)
	add_theme_stylebox_override("pressed", down)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_label.add_theme_color_override("font_color", ink)
	_glyph.color = ink


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _on_down() -> void:
	_spring(0.94, 0.06)


func _on_up() -> void:
	_spring(1.0, 0.22)


func _spring(target: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	pivot_offset = size * 0.5
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(target, target), seconds).set_trans(Tween.TRANS_BACK if target >= 1.0 else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_pressed() -> void:
	if not click_sound.is_empty():
		App.audio.play(click_sound)
	App.haptics.light()


## Draws attention to the button with a soft repeating pulse.
func pulse(on: bool) -> void:
	if has_meta("pulse_tween"):
		var old: Tween = get_meta("pulse_tween")
		if old != null and old.is_valid():
			old.kill()
		remove_meta("pulse_tween")
		modulate = Color.WHITE
	if not on:
		return
	var tween := create_tween().set_loops()
	tween.tween_property(self, "modulate", Color(1.18, 1.18, 1.18), 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	set_meta("pulse_tween", tween)
