class_name UiTheme
extends RefCounted
## Typography and control styling, built once in code. All sizes are in the
## 720-wide design space; the engine scales the whole canvas to the device.
##
## Swapping the typeface is a one-line change: load a font into `_base()`
## (for example a licensed display font dropped into assets/fonts/).

const DISPLAY := 62
const TITLE := 40
const HEADING := 30
const BODY := 24
const SMALL := 20
const TINY := 17

static var _theme: Theme
static var _font: Font
static var _font_wide: Font
static var _font_title: Font
static var _knob: Texture2D


static func _base() -> Font:
	return ThemeDB.fallback_font


## Body text.
static func font() -> Font:
	if _font == null:
		_font = _base()
	return _font


## Slightly tracked-out: buttons, labels, anything in capitals.
static func font_wide() -> Font:
	if _font_wide == null:
		var variation := FontVariation.new()
		variation.base_font = _base()
		variation.spacing_glyph = 2
		_font_wide = variation
	return _font_wide


## Widely tracked: titles and banners.
static func font_title() -> Font:
	if _font_title == null:
		var variation := FontVariation.new()
		variation.base_font = _base()
		variation.spacing_glyph = 7
		_font_title = variation
	return _font_title


static func box(fill: Color, border: Color, radius: int = 18, border_width: int = 2, glow: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.corner_detail = 8
	style.anti_aliasing = true
	if glow > 0.0:
		style.shadow_color = Palette.with_alpha(border, 0.22)
		style.shadow_size = int(glow)
	return style


## The glass panel used for cards and dialogs.
static func panel(accent: Color = Palette.CYAN, radius: int = 20) -> StyleBoxFlat:
	var style := box(Palette.PANEL, Palette.with_alpha(accent, 0.5), radius, 2, 14.0)
	style.set_content_margin_all(0)
	return style


static func knob() -> Texture2D:
	if _knob == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Palette.with_alpha(Palette.CYAN, 0.5), Palette.with_alpha(Palette.CYAN, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 56
		tex.height = 56
		_knob = tex
	return _knob


## Drops the cached resources. Called once as the app exits.
static func release() -> void:
	_theme = null
	_font = null
	_font_wide = null
	_font_title = null
	_knob = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = BODY

	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_constant("line_spacing", "Label", 2)

	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())

	var normal := box(Palette.PANEL_RAISED, Palette.with_alpha(Palette.CYAN, 0.6), 16, 2)
	var hover := box(Palette.PANEL_RAISED.lightened(0.06), Palette.CYAN, 16, 2, 10.0)
	var pressed := box(Palette.with_alpha(Palette.CYAN, 0.22), Palette.CYAN, 16, 2, 14.0)
	var disabled := box(Color(0.06, 0.08, 0.12, 0.7), Palette.with_alpha(Palette.DIM, 0.6), 16, 2)
	for style: StyleBoxFlat in [normal, hover, pressed, disabled]:
		style.content_margin_left = 22
		style.content_margin_right = 22
		style.content_margin_top = 10
		style.content_margin_bottom = 10
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font_wide())
	t.set_font_size("font_size", "Button", BODY)
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_color("font_hover_color", "Button", Palette.TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Palette.TEXT)
	t.set_color("font_disabled_color", "Button", Palette.DIM)

	var track := box(Color(0.08, 0.12, 0.2, 0.9), Palette.with_alpha(Palette.LINE, 0.9), 8, 1)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var filled := box(Palette.with_alpha(Palette.CYAN, 0.85), Palette.CYAN, 8, 0)
	filled.content_margin_top = 7
	filled.content_margin_bottom = 7
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", knob())
	t.set_icon("grabber_highlight", "HSlider", knob())
	t.set_icon("grabber_disabled", "HSlider", knob())

	var scroll_track := StyleBoxEmpty.new()
	var scroll_grab := box(Palette.with_alpha(Palette.CYAN, 0.35), Color.TRANSPARENT, 4, 0)
	scroll_grab.content_margin_left = 3
	scroll_grab.content_margin_right = 3
	for bar: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, scroll_track)
		t.set_stylebox("scroll_focus", bar, scroll_track)
		t.set_stylebox("grabber", bar, scroll_grab)
		t.set_stylebox("grabber_highlight", bar, scroll_grab)
		t.set_stylebox("grabber_pressed", bar, scroll_grab)

	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("separation", "VBoxContainer", 12)
	_theme = t
	return t
