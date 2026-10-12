class_name LevelUpOverlay
extends Control
## The level-up choice: three cards, pick one. Also used for elite caches.
##
## Because the player's thumb is already on the glass steering when this
## appears, the cards ignore input for a moment and until the screen has been
## released - otherwise the first pick of every run would be an accident.

signal picked(index: int)
signal reroll_pressed
signal ad_reroll_pressed

const INPUT_GUARD := 0.45

var _arena: Arena
var _scrim: ColorRect
var _column: VBoxContainer
var _cards: Array[UpgradeCard] = []
var _title: Label
var _subtitle: Label
var _reroll: NeonButton
var _ad_reroll: NeonButton
var _strip_holder: Control
var _armed := false
var _guard := 0.0
var _resolved := false


func _init(arena: Arena) -> void:
	_arena = arena


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_scrim = ColorRect.new()
	_scrim.color = Palette.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_column = UiKit.vbox(18)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_column)

	_title = UiKit.title("LEVEL UP", UiTheme.DISPLAY, Palette.GREEN)
	_column.add_child(_title)
	_subtitle = UiKit.caption("CHOOSE AN UPGRADE", UiTheme.SMALL, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_column.add_child(_subtitle)
	_column.add_child(UiKit.gap(6))

	var buttons := UiKit.hbox(16)
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_reroll = NeonButton.make("REROLL", NeonButton.Kind.SECONDARY, Palette.CYAN, "reroll", 76.0, UiTheme.SMALL)
	_reroll.min_width = 250.0
	_reroll.pressed.connect(func() -> void: reroll_pressed.emit())
	buttons.add_child(_reroll)
	_ad_reroll = NeonButton.make("REROLL", NeonButton.Kind.SECONDARY, Palette.AMBER, "ad", 76.0, UiTheme.SMALL)
	_ad_reroll.min_width = 250.0
	_ad_reroll.pressed.connect(func() -> void: ad_reroll_pressed.emit())
	buttons.add_child(_ad_reroll)
	_column.add_child(buttons)

	_strip_holder = UiKit.vbox(0)
	_column.add_child(_strip_holder)


func present(offers: Array, is_cache: bool) -> void:
	_resolved = false
	_armed = false
	_guard = INPUT_GUARD
	visible = true
	for card in _cards:
		card.queue_free()
	_cards.clear()

	_title.text = "ELITE CACHE" if is_cache else "LEVEL %d" % _arena.level
	_title.add_theme_color_override("font_color", Palette.GOLD if is_cache else Palette.GREEN)
	_subtitle.text = "CHOOSE YOUR REWARD" if is_cache else "CHOOSE AN UPGRADE"

	var buttons := _column.get_node("Buttons")
	for i in offers.size():
		var card := UpgradeCard.make(offers[i])
		card.disabled = true
		card.pressed.connect(_on_card.bind(i))
		_column.add_child(card)
		_column.move_child(card, buttons.get_index())
		_cards.append(card)
		card.appear(0.06 + 0.08 * float(i))

	for child in _strip_holder.get_children():
		child.queue_free()
	_strip_holder.add_child(BuildStrip.make(_arena))
	_refresh_rerolls()

	_scrim.modulate.a = 0.0
	create_tween().tween_property(_scrim, "modulate:a", 1.0, 0.16)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.5, 1.5)
	create_tween().tween_property(_title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_rerolls() -> void:
	var free := _arena.rerolls_left
	_reroll.visible = free > 0
	_reroll.set_label("REROLL  x%d" % free)
	# The ad option only appears once the free rerolls are spent.
	_ad_reroll.visible = free <= 0 and _arena.ad_rerolls_left > 0 and App.ads.rewarded_available(AdsService.REROLL)
	_ad_reroll.set_label("FREE REROLL")


func _process(delta: float) -> void:
	if not visible or _armed:
		return
	_guard -= delta
	if _guard <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_armed = true
		for card in _cards:
			card.disabled = false


func _on_card(index: int) -> void:
	if not _armed or _resolved:
		return
	_resolved = true
	App.audio.play("upgrade_pick")
	App.haptics.medium()
	for i in _cards.size():
		_cards[i].disabled = true
		if i == index:
			_cards[i].celebrate()
		else:
			_cards[i].dismiss()
	await get_tree().create_timer(0.3).timeout
	picked.emit(index)


func dismiss() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.14)
	tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0)
