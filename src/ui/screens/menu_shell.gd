class_name MenuShell
extends CanvasLayer
## Everything outside a run: top bar, the five tab screens, bottom navigation,
## plus the dialog and toast layers they share. Hidden (not destroyed) while a
## run is in progress so returning to the menu is instant.

signal play_pressed(mode: String)

var top_bar: TopBar
var nav: BottomNav
var toasts: ToastLayer

var _background: ArenaBackground
var _root: Control
var _content: Control
var _dialogs: Control
var _screens: Dictionary = {}
var _current := ""
var _drift := Vector2.ZERO
var _active := true


func _ready() -> void:
	layer = 5
	_background = ArenaBackground.new()
	_background.layer = -9
	add_child(_background)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)

	var safe := SafeArea.new()
	_root.add_child(safe)
	var column := UiKit.vbox(12)
	safe.add_child(column)

	top_bar = TopBar.new()
	column.add_child(top_bar)
	top_bar.profile_pressed.connect(func() -> void: open_dialog(ProfileModal.new()))
	top_bar.settings_pressed.connect(func() -> void: open_dialog(SettingsModal.new(self)))
	top_bar.shop_pressed.connect(func() -> void: show_tab("shop"))

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.clip_contents = true
	column.add_child(_content)

	nav = BottomNav.new()
	column.add_child(nav)
	nav.tab_selected.connect(show_tab)

	_screens = {
		"home": HomeScreen.new(),
		"upgrades": UpgradesScreen.new(),
		"arsenal": ArsenalScreen.new(),
		"missions": MissionsScreen.new(),
		"shop": ShopScreen.new(),
	}
	for id: String in _screens:
		var screen: MenuScreen = _screens[id]
		screen.shell = self
		screen.visible = false
		_content.add_child(screen)

	_dialogs = Control.new()
	_dialogs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialogs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dialogs)
	toasts = ToastLayer.new()
	_root.add_child(toasts)

	App.economy.changed.connect(func(_c: String, _b: int, _d: int) -> void: refresh_badges())
	App.missions.changed.connect(refresh_badges)
	App.achievements.changed.connect(refresh_badges)
	App.daily.changed.connect(refresh_badges)
	App.account.leveled_up.connect(_on_account_level)
	App.arsenal.unlocked.connect(func(_c: String, _i: String) -> void: refresh_badges())

	show_tab("home")
	App.analytics.track(Analytics.SCREEN_VIEW, {"screen": "home"})


func _process(delta: float) -> void:
	if not _active:
		return
	# The floor drifts slowly behind the menus so the screen is never static.
	_drift += Vector2(14.0, -22.0) * delta
	_background.track(_drift, 0.9, delta)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	_background.visible = on
	if on:
		App.missions.refresh()
		top_bar.refresh()
		show_tab("home", true)
		_announce_achievements()


func show_tab(id: String, force: bool = false) -> void:
	if not _screens.has(id) or (id == _current and not force):
		return
	if _screens.has(_current):
		(_screens[_current] as MenuScreen).hide_screen()
	_current = id
	nav.select(id)
	(_screens[id] as MenuScreen).show_screen()
	refresh_badges()
	App.analytics.track(Analytics.SCREEN_VIEW, {"screen": id})


func screen(id: String) -> MenuScreen:
	return _screens.get(id)


func refresh_current() -> void:
	if _screens.has(_current):
		(_screens[_current] as MenuScreen).refresh()
	refresh_badges()


func refresh_badges() -> void:
	nav.set_badge("upgrades", 1 if App.meta.any_affordable() else 0)
	nav.set_badge("arsenal", 1 if App.arsenal.any_affordable_unlock() else 0)
	nav.set_badge("missions", App.missions.claimable_count() + App.achievements.claimable_count())
	nav.set_badge("home", 1 if App.daily.can_claim() else 0)


func open_dialog(dialog: Modal) -> void:
	_dialogs.add_child(dialog)
	dialog.closed.connect(refresh_current)


func toast(message: String, color: Color = Palette.CYAN, icon_id: String = "info") -> void:
	toasts.show_toast(message, color, icon_id)


## "Not enough" feedback shared by every purchase button.
func deny(currency: String) -> void:
	App.audio.play("ui_error")
	App.haptics.warning()
	toast("Not enough %s" % ("Crystals" if currency == Economy.CRYSTALS else "Credits"), Palette.RED, "warning")


func request_play(mode: String) -> void:
	play_pressed.emit(mode)


func _on_account_level(level: int, _rewards: Dictionary) -> void:
	if _active:
		toast("Player Level %d" % level, Palette.CYAN, "star")


func _announce_achievements() -> void:
	var fresh := App.achievements.poll_newly_completed()
	if fresh.size() == 1:
		toast("Achievement: %s" % str(fresh[0].name), Palette.VIOLET, "trophy")
	elif fresh.size() > 1:
		# One line, not a stack: the Missions badge carries the detail.
		toast("%d achievements ready to claim" % fresh.size(), Palette.VIOLET, "trophy")


## Returns false when there is nothing left to go back from (leave the app).
func handle_back() -> bool:
	if _dialogs.get_child_count() > 0:
		var top := _dialogs.get_child(_dialogs.get_child_count() - 1) as Modal
		if top != null:
			return top.handle_back()
	if _current != "home":
		App.audio.play("ui_back")
		show_tab("home")
		return true
	return false
