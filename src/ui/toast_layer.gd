class_name ToastLayer
extends Control
## Brief, non-blocking messages that stack at the top of the screen:
## "Not enough Credits", "Achievement unlocked", and the like.

const LIFETIME := 2.4
const MAX_VISIBLE := 3

var _stack: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = UiKit.vbox(10)
	_stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# Below the top bar and screen titles, over the least important area.
	_stack.offset_top = 236.0
	_stack.offset_left = 40.0
	_stack.offset_right = -40.0
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_stack)


func show_toast(message: String, color: Color = Palette.CYAN, icon_id: String = "info") -> void:
	while _stack.get_child_count() >= MAX_VISIBLE:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	var style := UiTheme.box(Palette.PANEL_SOLID, Palette.with_alpha(color, 0.9), 14, 2, 12.0)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := UiKit.hbox(12)
	row.add_child(IconGlyph.make(icon_id, 30.0, color))
	row.add_child(UiKit.label(message, UiTheme.SMALL, Palette.TEXT))
	panel.add_child(row)
	_stack.add_child(panel)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	tween.tween_interval(LIFETIME)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)
