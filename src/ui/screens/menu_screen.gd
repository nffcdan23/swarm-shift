class_name MenuScreen
extends Control
## Base for the tab screens inside MenuShell. A screen builds itself once in
## `_build()` and brings its contents up to date in `refresh()`, which the shell
## calls whenever the screen is shown or the profile changes underneath it.

var shell: MenuShell
var _built := false
var _tween: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_screen() -> void:
	if not _built:
		_built = true
		_build()
	visible = true
	refresh()
	# Own tween (rather than UiKit.enter) so rapid tab switching cannot stack
	# slides and leave the screen parked off its home position.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	position = Vector2(0, 18)
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_property(self, "position", Vector2.ZERO, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_screen() -> void:
	visible = false


## Create controls. Called once, the first time the screen is shown.
func _build() -> void:
	pass


## Update controls from the profile. Called every time the screen is shown.
func refresh() -> void:
	pass


## Standard screen header: title, optional one-line explanation.
func header(title_text: String, subtitle: String = "") -> VBoxContainer:
	var box := UiKit.vbox(2)
	var title_label := UiKit.title(title_text, UiTheme.TITLE, Palette.TEXT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(title_label)
	if not subtitle.is_empty():
		box.add_child(UiKit.paragraph(subtitle, UiTheme.SMALL, Palette.MUTED))
	return box
