class_name Modal
extends Control
## Base for dialogs: dims the screen, centres a glass card, animates in and
## out, and closes on a tap outside or the Android back button.
##
## Subclasses override `_build(body)` to add content, and may set `accent`,
## `heading` and `dismissable` before the node enters the tree.

signal closed

var accent := Palette.CYAN
var heading := ""
var dismissable := true
var card_width := 620.0

var _scrim: ColorRect
var _card: PanelContainer
var _body: VBoxContainer
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.theme()

	_scrim = ColorRect.new()
	_scrim.color = Palette.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_card = UiKit.card(accent, 28, 16)
	_card.custom_minimum_size = Vector2(card_width, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	centre.add_child(_card)
	_body = UiKit.card_body(_card)

	if not heading.is_empty():
		var top := UiKit.hbox(12)
		var title_label := UiKit.title(heading, UiTheme.HEADING, accent.lightened(0.3))
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title_label)
		if dismissable:
			var close_button := NeonButton.make("", NeonButton.Kind.GHOST, Palette.MUTED, "close", 56.0)
			close_button.min_width = 56.0
			close_button.click_sound = "ui_back"
			close_button.pressed.connect(close)
			top.add_child(close_button)
		_body.add_child(top)
		_body.add_child(UiKit.divider(accent))

	_build(_body)

	_scrim.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.92, 0.92)
	await get_tree().process_frame
	_card.pivot_offset = _card.size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_scrim, "modulate:a", 1.0, 0.18)
	tween.tween_property(_card, "modulate:a", 1.0, 0.18)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	App.audio.play("ui_open")


## Override to fill the dialog.
func _build(_into: VBoxContainer) -> void:
	pass


func _on_scrim_input(event: InputEvent) -> void:
	if dismissable and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()


## Returns true if this dialog consumed the back action.
func handle_back() -> bool:
	if dismissable:
		close()
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_scrim, "modulate:a", 0.0, 0.14)
	tween.tween_property(_card, "modulate:a", 0.0, 0.14)
	tween.tween_property(_card, "scale", Vector2(0.94, 0.94), 0.14)
	tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	closed.emit()
	queue_free()
