class_name MockPurchaseDialog
extends CanvasLayer
## Confirmation sheet used by MockStoreProvider. Plain on purpose.

signal finished(approved: bool)

var _product := ""
var _price := ""
var _done := false


func configure(product: String, price: String) -> void:
	_product = product
	_price = price


func _ready() -> void:
	layer = 121
	process_mode = Node.PROCESS_MODE_ALWAYS
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	backdrop.add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)
	box.add_child(_label("TEST PURCHASE", 34, Color(1, 1, 1)))
	box.add_child(_label("%s  -  %s" % [_product, _price], 28, Color(1.0, 0.82, 0.36)))
	box.add_child(_label("Mock store provider. No real payment is made.", 22, Color(0.62, 0.67, 0.74)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_button("CANCEL", false))
	row.add_child(_button("BUY", true))


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, approve: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 84)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(_resolve.bind(approve))
	return button


func _resolve(approved: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(approved)
	queue_free()
