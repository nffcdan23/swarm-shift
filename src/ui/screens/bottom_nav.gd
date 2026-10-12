class_name BottomNav
extends PanelContainer
## Thumb-reach tab bar. The centre tab is the game; the others are the systems
## that feed it. Red badges mark tabs with something to claim or afford.

signal tab_selected(id: String)

const TABS: Array[Dictionary] = [
	{"id": "upgrades", "icon": "upgrade", "label": "UPGRADES"},
	{"id": "arsenal", "icon": "arsenal", "label": "ARSENAL"},
	{"id": "home", "icon": "play", "label": "PLAY"},
	{"id": "missions", "icon": "missions", "label": "MISSIONS"},
	{"id": "shop", "icon": "shop", "label": "SHOP"},
]

var _glyphs: Dictionary = {}
var _labels: Dictionary = {}
var _badges: Dictionary = {}
var _marks: Dictionary = {}
var _current := "home"


func _ready() -> void:
	var style := UiTheme.box(Color(0.03, 0.05, 0.09, 0.94), Palette.with_alpha(Palette.LINE, 0.9), 22, 2)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(0, 104)
	var row := UiKit.hbox(0)
	add_child(row)
	for tab in TABS:
		var id := str(tab.id)
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_on_pressed.bind(id))
		row.add_child(button)

		var stack := UiKit.vbox(4)
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		button.add_child(stack)
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(44, 4)
		mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mark.color = Palette.CYAN
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(mark)
		var glyph := IconGlyph.make(str(tab.icon), 40.0, Palette.MUTED)
		stack.add_child(glyph)
		var caption := UiKit.caption(str(tab.label), UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		stack.add_child(caption)

		var badge := UiKit.badge()
		badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		badge.offset_left = 14.0
		badge.offset_top = 10.0
		button.add_child(badge)

		_glyphs[id] = glyph
		_labels[id] = caption
		_badges[id] = badge
		_marks[id] = mark
	select("home")


func _on_pressed(id: String) -> void:
	if id == _current:
		return
	App.audio.play("ui_tab")
	App.haptics.light()
	select(id)
	tab_selected.emit(id)


func select(id: String) -> void:
	_current = id
	for tab_id: String in _glyphs:
		var active := tab_id == id
		var glyph: IconGlyph = _glyphs[tab_id]
		glyph.color = Palette.CYAN if active else Palette.MUTED
		glyph.glow = active
		(_labels[tab_id] as Label).add_theme_color_override("font_color", Palette.TEXT if active else Palette.MUTED)
		(_marks[tab_id] as ColorRect).color = Palette.CYAN if active else Color(0, 0, 0, 0)
	var chosen: IconGlyph = _glyphs[id]
	UiKit.pop(chosen, 1.25)


func current() -> String:
	return _current


func set_badge(id: String, count: int) -> void:
	if _badges.has(id):
		UiKit.set_badge(_badges[id], count)
