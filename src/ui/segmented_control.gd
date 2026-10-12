class_name SegmentedControl
extends HBoxContainer
## A row of mutually exclusive options ("CORES | WEAPONS | SKINS").

signal changed(index: int)

var selected := 0

var _buttons: Array[NeonButton] = []
var _labels: PackedStringArray = []
var _badges: Array[PanelContainer] = []


static func make(labels: PackedStringArray, initial: int = 0) -> SegmentedControl:
	var control := SegmentedControl.new()
	control._labels = labels
	control.selected = initial
	control.add_theme_constant_override("separation", 10)
	for i in labels.size():
		var button := NeonButton.make(labels[i], NeonButton.Kind.SECONDARY, Palette.CYAN, "", 64.0, UiTheme.SMALL)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.click_sound = "ui_tab"
		button.pressed.connect(control._on_pressed.bind(i))
		control.add_child(button)
		control._buttons.append(button)
		var badge := UiKit.badge()
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -30.0
		badge.offset_top = -8.0
		button.add_child(badge)
		control._badges.append(badge)
	control._restyle()
	return control


func _on_pressed(index: int) -> void:
	if index == selected:
		return
	selected = index
	_restyle()
	changed.emit(index)


func select(index: int) -> void:
	selected = clampi(index, 0, _buttons.size() - 1)
	_restyle()


func set_badge(index: int, count: int) -> void:
	if index >= 0 and index < _badges.size():
		UiKit.set_badge(_badges[index], count)


func _restyle() -> void:
	for i in _buttons.size():
		var active := i == selected
		_buttons[i].configure(_labels[i], NeonButton.Kind.PRIMARY if active else NeonButton.Kind.SECONDARY,
			Palette.CYAN if active else Palette.MUTED, "", UiTheme.SMALL)
