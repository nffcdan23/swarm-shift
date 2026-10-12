class_name Hud
extends CanvasLayer
## In-run interface. Deliberately small: health, energy, level, timer, kills
## and a pause button along the top edge, with the middle of the screen left
## clear for the fight. Everything else (level-up, pause, revive) is an overlay
## that only exists while it is needed.
##
## The HUD listens to the Arena's signals and reads its state each frame; the
## Arena never calls into the HUD.

signal quit_requested

var arena: Arena
var joystick: Joystick

var _root: Control
var _hp: MeterBar
var _hp_text: Label
var _xp: MeterBar
var _level: Label
var _timer: Label
var _boss_track: MeterBar
var _kills: Label
var _boss_box: VBoxContainer
var _boss_bar: MeterBar
var _boss_name: Label
var _banner: Label
var _banner_tween: Tween
var _synergy: PanelContainer
var _hint: PanelContainer
var _hint_label: Label
var _perf: Label
var _levelup: LevelUpOverlay
var _pause: PauseOverlay
var _revive: RevivePrompt

var _shown_hp := -1
var _shown_max := -1
var _shown_seconds := -1
var _shown_kills := -1
var _shown_level := -1
var _hint_stage := 0
var _start := Vector2.ZERO
var _reroll_busy := false


func _init(p_arena: Arena) -> void:
	arena = p_arena
	layer = 10


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)

	joystick = Joystick.new()
	_root.add_child(joystick)

	var safe := SafeArea.new()
	_root.add_child(safe)
	var column := UiKit.vbox(8)
	safe.add_child(column)

	_xp = MeterBar.make(Palette.ENERGY, 10.0)
	column.add_child(_xp)
	column.add_child(_build_top_row())
	column.add_child(_build_boss_box())
	column.add_child(UiKit.spacer(false))

	_build_banner()
	_build_synergy()
	_build_hint()
	_build_perf()

	_levelup = LevelUpOverlay.new(arena)
	_root.add_child(_levelup)
	_levelup.picked.connect(_on_card_picked)
	_levelup.reroll_pressed.connect(_on_reroll)
	_levelup.ad_reroll_pressed.connect(_on_ad_reroll)

	arena.choice_started.connect(_on_choice_started)
	arena.choice_finished.connect(_on_choice_finished)
	arena.announced.connect(_on_announced)
	arena.player_downed.connect(_on_player_downed)
	arena.boss_appeared.connect(_on_boss_appeared)
	arena.boss_gone.connect(_on_boss_gone)
	arena.synergy_activated.connect(_on_synergy)
	arena.run_ended.connect(_on_run_ended)

	_start = Vector2(arena.player.x, arena.player.y)
	_hint_stage = 0 if arena.config.show_tutorial else 2
	_refresh_hint()


# ----------------------------------------------------------------- building

func _build_top_row() -> HBoxContainer:
	var row := UiKit.hbox(10)

	var left := UiKit.hbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(IconGlyph.make("heart", 30.0, Palette.HEALTH))
	_hp = MeterBar.make(Palette.HEALTH, 22.0, true)
	_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp.custom_minimum_size = Vector2(150, 22)
	left.add_child(_hp)
	_hp_text = UiKit.label("100", UiTheme.SMALL, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_hp_text.custom_minimum_size = Vector2(52, 0)
	left.add_child(_hp_text)
	row.add_child(left)

	var middle := UiKit.vbox(0)
	middle.custom_minimum_size = Vector2(150, 0)
	_timer = UiKit.label("0:00", 36, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	middle.add_child(_timer)
	_boss_track = MeterBar.make(Palette.AMBER, 5.0)
	_boss_track.back_color = Color(0.12, 0.16, 0.24, 0.8)
	middle.add_child(_boss_track)
	_level = UiKit.caption("LV 1", UiTheme.SMALL, Palette.ENERGY, HORIZONTAL_ALIGNMENT_CENTER)
	middle.add_child(_level)
	row.add_child(middle)

	var right := UiKit.hbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(IconGlyph.make("skull", 28.0, Palette.MUTED))
	_kills = UiKit.label("0", UiTheme.BODY, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	right.add_child(_kills)
	var pause := NeonButton.make("", NeonButton.Kind.SECONDARY, Palette.CYAN, "pause", 60.0)
	pause.min_width = 60.0
	pause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pause.pressed.connect(open_pause)
	right.add_child(pause)
	row.add_child(right)
	return row


func _build_boss_box() -> VBoxContainer:
	_boss_box = UiKit.vbox(4)
	_boss_box.visible = false
	_boss_name = UiKit.caption("", UiTheme.SMALL, Palette.RED, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_box.add_child(_boss_name)
	_boss_bar = MeterBar.make(Palette.RED, 18.0, true)
	_boss_bar.segments = 3
	_boss_box.add_child(UiKit.margin(_boss_bar, 40, 0, 40, 0))
	return _boss_box


func _build_banner() -> void:
	_banner = UiKit.title("", UiTheme.TITLE, Palette.CYAN)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.anchor_top = 0.24
	_banner.anchor_bottom = 0.24
	_banner.offset_top = 0.0
	_banner.offset_bottom = 70.0
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.85))
	_banner.modulate.a = 0.0
	_root.add_child(_banner)


func _build_synergy() -> void:
	_synergy = PanelContainer.new()
	_synergy.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL_SOLID, Palette.GOLD, 18, 2, 22.0))
	_synergy.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_synergy.anchor_top = 0.34
	_synergy.anchor_bottom = 0.34
	_synergy.offset_left = 50.0
	_synergy.offset_right = -50.0
	_synergy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := UiKit.vbox(6)
	body.add_child(UiKit.caption("SYNERGY ACTIVATED", UiTheme.TINY, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var name_label := UiKit.title("", UiTheme.HEADING, Palette.GOLD)
	name_label.name = "Name"
	body.add_child(name_label)
	var desc := UiKit.paragraph("", UiTheme.SMALL, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	desc.name = "Desc"
	body.add_child(desc)
	var pad := UiKit.margin(body, 22, 16, 22, 18)
	pad.name = "Pad"
	_synergy.add_child(pad)
	_synergy.visible = false
	_root.add_child(_synergy)


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", UiTheme.box(Palette.with_alpha(Palette.PANEL_SOLID, 0.8), Palette.with_alpha(Palette.CYAN, 0.6), 16, 2))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_top = 0.74
	_hint.anchor_bottom = 0.74
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make("hand", 44.0, Palette.CYAN, true))
	_hint_label = UiKit.label("", UiTheme.BODY, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	row.add_child(_hint_label)
	_hint.add_child(UiKit.margin(row, 22, 14, 26, 14))
	_root.add_child(_hint)
	var pulse := _hint.create_tween().set_loops()
	pulse.tween_property(_hint, "modulate:a", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_hint, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func _build_perf() -> void:
	_perf = UiKit.label("", UiTheme.TINY, Palette.MUTED)
	_perf.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_perf.offset_left = 14.0
	_perf.offset_top = -64.0
	_perf.visible = App.cli.has("perf")
	_root.add_child(_perf)


# ------------------------------------------------------------------- update

func _process(_delta: float) -> void:
	if not is_instance_valid(arena):
		return
	var player := arena.player
	arena.move_input = joystick.current() if arena.autopilot == null else arena.move_input
	joystick.enabled = arena.state == Arena.State.PLAYING

	_hp.set_value(player.hp_fraction())
	var hp_now := int(ceilf(player.hp))
	var hp_max := int(player.max_hp)
	if hp_now != _shown_hp or hp_max != _shown_max:
		_shown_hp = hp_now
		_shown_max = hp_max
		_hp_text.text = str(hp_now)
		_hp.fill_color = Palette.HEALTH if player.hp_fraction() > 0.3 else Palette.RED.lightened(0.1)
	_xp.set_value(arena.xp_fraction())
	if arena.level != _shown_level:
		_shown_level = arena.level
		_level.text = "LV %d" % arena.level
		UiKit.pop(_level, 1.4)
	var seconds := int(arena.time)
	if seconds != _shown_seconds:
		_shown_seconds = seconds
		_timer.text = Fmt.time_mmss(arena.time)
	if arena.combat.kills != _shown_kills:
		_shown_kills = arena.combat.kills
		_kills.text = Fmt.compact(float(_shown_kills))

	var fighting := arena.boss.active and not arena.boss.is_dying()
	_boss_track.visible = not fighting
	if not fighting:
		_boss_track.set_value(arena.director.progress())
	else:
		_boss_bar.set_value(arena.boss.hp_fraction())

	if _hint_stage == 0 and Vector2(player.x, player.y).distance_to(_start) > 70.0:
		_hint_stage = 1
		_refresh_hint()
		var tutorial := App.save.section("tutorial")
		tutorial["moved"] = true
		App.save.mark_dirty()
		App.analytics.track(Analytics.TUTORIAL_STEP, {"step": "moved"})
	elif _hint_stage == 1 and arena.level > 1:
		_hint_stage = 2
		_refresh_hint()
		App.analytics.track(Analytics.TUTORIAL_STEP, {"step": "levelled"})

	if _perf.visible:
		_perf.text = "%d fps   step %.2f ms (worst %.1f)\n%d enemies  %d shots  %d pickups  %d bullets" % [
			Engine.get_frames_per_second(), arena.step_ms, arena.step_ms_worst,
			arena.enemies.count, arena.projectiles.count, arena.pickups.count, arena.bullets.count]


func _refresh_hint() -> void:
	match _hint_stage:
		0:
			_hint.visible = true
			_hint_label.text = "DRAG ANYWHERE TO MOVE"
		1:
			_hint.visible = true
			_hint_label.text = "COLLECT ENERGY TO LEVEL UP"
		_:
			_hint.visible = false


func _notification(what: int) -> void:
	# Losing focus mid-fight should never cost the player health.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if arena != null and arena.state == Arena.State.PLAYING and arena.autopilot == null:
			open_pause()


## Android back button / Escape. Returns true if something handled it.
func handle_back() -> bool:
	if _revive != null and is_instance_valid(_revive):
		return true
	if _pause != null and is_instance_valid(_pause):
		return _pause.handle_back()
	if arena.state == Arena.State.PLAYING:
		open_pause()
		return true
	return arena.state == Arena.State.CHOOSING


# ------------------------------------------------------------------ overlays

func open_pause() -> void:
	if arena.state != Arena.State.PLAYING or (_pause != null and is_instance_valid(_pause)):
		return
	arena.set_paused(true)
	joystick.release()
	_pause = PauseOverlay.new(arena)
	_pause.resume_pressed.connect(func() -> void: arena.set_paused(false))
	_pause.quit_pressed.connect(func() -> void:
		arena.set_paused(false)
		quit_requested.emit())
	_root.add_child(_pause)


func _on_choice_started(offers: Array, is_cache: bool) -> void:
	joystick.release()
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_levelup.present(offers, is_cache)


func _on_card_picked(index: int) -> void:
	arena.choose(index)


func _on_choice_finished() -> void:
	_levelup.dismiss()


func _on_reroll() -> void:
	arena.reroll()


func _on_ad_reroll() -> void:
	if _reroll_busy:
		return
	_reroll_busy = true
	var earned: bool = await App.ads.show_rewarded(AdsService.REROLL)
	_reroll_busy = false
	if earned:
		arena.reroll_from_ad()


func _on_player_downed(_can_use_ad: bool) -> void:
	joystick.release()
	_revive = RevivePrompt.new()
	_revive.revive_chosen.connect(arena.accept_ad_revive)
	_revive.declined.connect(arena.decline_revive)
	_root.add_child(_revive)


func _on_boss_appeared(display_name: String) -> void:
	_boss_name.text = display_name
	_boss_bar.set_value(1.0, true)
	_boss_box.visible = true
	_boss_box.modulate.a = 0.0
	create_tween().tween_property(_boss_box, "modulate:a", 1.0, 0.5)


func _on_boss_gone() -> void:
	var tween := create_tween()
	tween.tween_property(_boss_box, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void: _boss_box.visible = false)


func _on_run_ended(_result: Dictionary) -> void:
	joystick.enabled = false
	_hint.visible = false


func _on_announced(text: String, style: String) -> void:
	var color := Palette.CYAN
	var hold := 1.5
	var size := UiTheme.TITLE
	match style:
		"warning":
			color = Palette.AMBER
		"boss":
			color = Palette.RED
			hold = 2.2
			size = 46
		"elite":
			color = Palette.GOLD
			size = 32
		"good":
			color = Palette.GREEN
			hold = 2.0
			size = 46
		"title":
			color = Palette.TEXT
			hold = 1.8
			size = 52
	# Shrink long announcements until they fit the screen width.
	var room := _root.size.x - 48.0
	var font := UiTheme.font_title()
	while size > 22 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > room:
		size -= 2
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", size)
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(1.5, 1.5)
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.14)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.4)


func _on_synergy(synergy: Dictionary) -> void:
	(_synergy.get_node("Pad").get_child(0).get_node("Name") as Label).text = str(synergy.get("name", ""))
	(_synergy.get_node("Pad").get_child(0).get_node("Desc") as Label).text = str(synergy.get("desc", ""))
	_synergy.visible = true
	_synergy.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_synergy, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.2)
	tween.tween_property(_synergy, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _synergy.visible = false)
