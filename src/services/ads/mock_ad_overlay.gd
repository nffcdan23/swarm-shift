class_name MockAdOverlay
extends CanvasLayer
## The fake ad shown by MockAdProvider. Deliberately plain: it should never be
## mistaken for part of the game.

signal finished(completed: bool)

var _title := ""
var _placement := ""
var _seconds := 2.0
var _rewarded := false
var _elapsed := 0.0
var _done := false
var _countdown: Label
var _close: Button


func configure(title: String, placement: String, seconds: float, rewarded: bool) -> void:
	_title = title
	_placement = placement
	_seconds = seconds
	_rewarded = rewarded


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.04, 0.98)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	backdrop.add_child(box)

	box.add_child(_label("TEST " + _title, 44, Color(1, 1, 1)))
	box.add_child(_label("placement: " + _placement, 24, Color(0.6, 0.65, 0.72)))
	box.add_child(_label("Mock ad provider - no real ad network is connected.", 22, Color(0.6, 0.65, 0.72)))
	_countdown = _label("", 30, Color(1.0, 0.82, 0.36))
	box.add_child(_countdown)

	_close = Button.new()
	_close.text = "CLOSE"
	_close.custom_minimum_size = Vector2(300, 84)
	_close.add_theme_font_size_override("font_size", 28)
	_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(_on_close)
	box.add_child(_close)
	_refresh()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 0)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_refresh()


func _refresh() -> void:
	var left := maxf(_seconds - _elapsed, 0.0)
	if left > 0.0:
		_countdown.text = ("Reward in %d..." if _rewarded else "Skip in %d...") % int(ceilf(left))
		_close.text = "CLOSE (NO REWARD)" if _rewarded else "CLOSE"
		_close.disabled = not _rewarded
	else:
		_countdown.text = "Reward earned" if _rewarded else ""
		_close.text = "CLOSE"
		_close.disabled = false


func _on_close() -> void:
	if _done:
		return
	_done = true
	var completed := _elapsed >= _seconds
	finished.emit(completed)
	queue_free()
