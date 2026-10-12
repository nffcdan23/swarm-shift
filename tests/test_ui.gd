extends TestSuite
## Smoke tests for the interface. They cannot judge how a screen looks (the
## screenshot tour is for that) but they do prove every screen, dialog and
## overlay builds from real data without errors, and that the flows between
## them hold together.


func _frames(count: int) -> void:
	for i in count:
		await host.get_tree().process_frame


func _arena(config: RunConfig) -> Arena:
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	return arena


func test_every_icon_referenced_by_data_exists() -> void:
	var wanted: Dictionary = {}
	for table: Dictionary in [app.data.weapon_defs(), app.data.passives(), app.data.augments(), app.data.meta_upgrades(), app.data.products()]:
		for id: String in table:
			wanted[GameData.text(table[id], "icon", "star")] = id
	for currency: String in GameData.dict(app.data.game, "currencies"):
		wanted[GameData.text(GameData.dict(app.data.game, "currencies")[currency], "icon")] = currency
	for tab in BottomNav.TABS:
		wanted[str(tab.icon)] = str(tab.id)
	for icon_id: String in wanted:
		check(IconLibrary.has(icon_id), "icon '%s' (used by '%s') is defined" % [icon_id, wanted[icon_id]])


func test_menu_builds_every_screen() -> void:
	fresh_profile()
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	for tab in BottomNav.TABS:
		var id := str(tab.id)
		shell.show_tab(id)
		await _frames(1)
		var screen := shell.screen(id)
		check(screen != null and screen.visible, "tab '%s' shows its screen" % id)
		check(screen.get_child_count() > 0, "screen '%s' built its contents" % id)
	check(shell.handle_back(), "back from a tab returns home")
	check_eq(shell.nav.current(), "home", "home tab is selected after back")
	check(not shell.handle_back(), "back on home has nothing left to close")
	shell.queue_free()
	await _frames(1)


func test_screens_survive_a_rich_profile() -> void:
	fresh_profile()
	app.account.add_xp(400000, "test")
	app.economy.grant(Economy.CREDITS, 500000, "test")
	app.economy.grant(Economy.CRYSTALS, 5000, "test")
	for id: String in app.meta.ids():
		while app.meta.buy(id):
			pass
	for category: String in [ArsenalService.WEAPONS, ArsenalService.CORES, ArsenalService.SKINS]:
		for id: String in app.arsenal.defs(category):
			app.arsenal.unlock(category, id)
	for tier in range(1, 6):
		app.campaign.record_run(CampaignService.MODE_SECTOR, tier, true, 300.0)
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	for tab in BottomNav.TABS:
		shell.show_tab(str(tab.id))
		await _frames(1)
	var arsenal := shell.screen("arsenal") as ArsenalScreen
	check(arsenal != null, "arsenal screen exists")
	check(app.arsenal.select_core("tempest"), "an unlocked core can be selected")
	shell.refresh_current()
	check(app.campaign.endless_unlocked(), "endless is unlocked on this profile")
	check_eq(app.arsenal.unlocked_weapons().size(), app.data.weapon_defs().size(), "every weapon unlocked")
	shell.queue_free()
	await _frames(1)


func test_dialogs_open_and_close() -> void:
	fresh_profile()
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	var dialogs: Array[Modal] = [SettingsModal.new(shell), ProfileModal.new(), DailyRewardModal.new(shell)]
	for dialog in dialogs:
		var title := dialog.heading
		shell.open_dialog(dialog)
		await _frames(3)
		check(dialog.is_inside_tree(), "%s opened" % title)
		check(shell.handle_back(), "%s consumes the back action" % title)
		await host.get_tree().create_timer(0.3).timeout
		check(not is_instance_valid(dialog), "%s closed and freed" % title)
	shell.queue_free()
	await _frames(1)


func test_settings_apply_immediately() -> void:
	fresh_profile()
	app.settings.set_value(SettingsService.MUSIC, 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioService.BUS_MUSIC)), "music at zero mutes the music bus")
	app.settings.set_value(SettingsService.MUSIC, 0.5)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioService.BUS_MUSIC)), "raising it unmutes")
	var fired := app.haptics.fired
	app.settings.set_value(SettingsService.HAPTICS, false)
	app.haptics.heavy()
	check_eq(app.haptics.fired, fired, "haptics off means no haptic requests")
	app.settings.set_value(SettingsService.HAPTICS, true)
	app.haptics.heavy()
	check_eq(app.haptics.fired, fired + 1, "haptics on lets them through")


func test_hud_level_up_flow() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 31)
	config.autopilot = false
	var arena := _arena(config)
	var hud := Hud.new(arena)
	host.add_child(hud)
	await _frames(2)
	var overlay := hud.get_child(0).get_child(hud.get_child(0).get_child_count() - 1) as LevelUpOverlay
	check(overlay != null, "HUD owns a level-up overlay")
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(1.0 / 30.0)
	check_eq(arena.state, Arena.State.CHOOSING, "gaining a level pauses for a choice")
	await _frames(2)
	check(overlay.visible, "the overlay is shown")
	check_eq(arena.current_offers.size(), 3, "three cards are offered")
	var rerolls := arena.rerolls_left
	if rerolls > 0:
		check(arena.reroll(), "reroll works while choosing")
		check_eq(arena.rerolls_left, rerolls - 1, "reroll is consumed")
	var weapons_before := arena.build.weapon_order.size() + arena.build.passive_order.size() + arena.build.augments.size()
	var level_before := arena.build.weapon_level("pulse")
	arena.choose(0)
	check_eq(arena.state, Arena.State.PLAYING, "picking a card resumes play")
	var grew := arena.build.weapon_order.size() + arena.build.passive_order.size() + arena.build.augments.size() > weapons_before
	check(grew or arena.build.weapon_level("pulse") > level_before, "the pick changed the build")
	check(arena.player.invulnerable_for > 0.0, "player gets a moment of safety after choosing")
	hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)


func test_pause_and_back_button() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 31)
	config.autopilot = false
	var arena := _arena(config)
	var hud := Hud.new(arena)
	host.add_child(hud)
	await _frames(2)
	check(hud.handle_back(), "back during play is handled")
	check_eq(arena.state, Arena.State.PAUSED, "back pauses the run")
	var time_before := arena.time
	await _frames(3)
	check_eq(arena.time, time_before, "the simulation does not advance while paused")
	await host.get_tree().create_timer(0.1).timeout
	check(hud.handle_back(), "back again is handled")
	check_eq(arena.state, Arena.State.PLAYING, "back again resumes")
	hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)


func test_results_screen_builds() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 12))
	for i in 900:
		if arena.state == Arena.State.ENDED:
			break
		arena.step(1.0 / 30.0)
	var result := arena.build_result(false, true, false)
	var summary := RunLedger.settle(app, result)
	var screen := ResultsScreen.new(result, summary)
	host.add_child(screen)
	await _frames(3)
	check(screen.get_child_count() >= 2, "results screen built its layout")
	var pressed: Array = []
	screen.play_again_pressed.connect(func() -> void: pressed.append("again"))
	screen.home_pressed.connect(func() -> void: pressed.append("home"))
	screen._leave(screen.play_again_pressed)
	screen._leave(screen.home_pressed)
	check_eq(pressed, ["again"], "leaving the results screen fires exactly one action")
	screen.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)


func test_joystick_turns_drags_into_direction() -> void:
	var stick := Joystick.new()
	host.add_child(stick)
	await _frames(1)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(300, 800)
	stick._unhandled_input(down)
	check(stick.is_held(), "a touch grabs the stick")
	check_eq(stick.current(), Vector2.ZERO, "no movement before dragging")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(300 + Joystick.RADIUS, 800)
	stick._unhandled_input(drag)
	check_near(stick.current().x, 1.0, 0.001, "a full drag right is full speed right")
	check_near(stick.current().y, 0.0, 0.001, "with no vertical component")
	drag.position = Vector2(300 + 4, 800)
	stick._unhandled_input(drag)
	check_eq(stick.current(), Vector2.ZERO, "tiny movements sit inside the dead zone")
	var other := InputEventScreenDrag.new()
	other.index = 1
	other.position = Vector2(0, 0)
	stick._unhandled_input(other)
	check_eq(stick.current(), Vector2.ZERO, "a second finger does not steal the stick")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	stick._unhandled_input(up)
	check(not stick.is_held(), "lifting the finger releases it")
	stick.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# Real input: these push synthetic touches through the engine's input pipeline
# instead of calling handlers, so they cover hit-testing, input filtering and
# layering as well as the logic behind the buttons.

func _press(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.global_position = at
	host.get_viewport().push_input(event, true)


func _tap(at: Vector2) -> void:
	_press(at, true)
	await _frames(1)
	_press(at, false)
	await _frames(1)


func _touch(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = down
	event.position = at
	host.get_viewport().push_input(event, true)


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	host.get_viewport().push_input(event, true)


func test_tapping_play_starts_a_run() -> void:
	fresh_profile()
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(3)
	var requested: Array = []
	shell.play_pressed.connect(func(mode: String) -> void: requested.append(mode))
	var home := shell.screen("home") as HomeScreen
	var play := home._play
	check(play.get_global_rect().size.x > 300.0, "PLAY is a large target (%.0f wide)" % play.get_global_rect().size.x)
	await _tap(play.get_global_rect().get_center())
	check_eq(requested, [CampaignService.MODE_SECTOR], "tapping PLAY requests a sector run")
	shell.queue_free()
	await _frames(1)


func test_tapping_a_tab_switches_screen() -> void:
	fresh_profile()
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(3)
	# The Upgrades tab is the first fifth of the navigation bar.
	var bar := shell.nav.get_global_rect()
	await _tap(Vector2(bar.position.x + bar.size.x * 0.1, bar.get_center().y))
	check_eq(shell.nav.current(), "upgrades", "tapping the first tab opens Upgrades")
	check(shell.screen("upgrades").visible, "the Upgrades screen is visible")
	check(not shell.screen("home").visible, "the home screen is hidden")
	shell.queue_free()
	await _frames(1)


func test_touch_controls_drive_the_player() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 31)
	config.autopilot = false
	var arena := _arena(config)
	var hud := Hud.new(arena)
	host.add_child(hud)
	await _frames(2)
	var centre := host.get_viewport().get_visible_rect().get_center()
	var start_x := arena.player.x
	_touch(0, centre, true)
	_drag(0, centre + Vector2(Joystick.RADIUS, 0.0))
	await _frames(1)
	check_near(arena.move_input.x, 1.0, 0.01, "dragging right steers right")
	for i in 20:
		arena.step(1.0 / 60.0)
	check(arena.player.x > start_x + 40.0, "the player actually moved right (%.0f)" % (arena.player.x - start_x))
	_touch(0, centre, false)
	await _frames(1)
	check_eq(arena.move_input, Vector2.ZERO, "releasing stops the input")
	hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)


func test_pause_button_and_card_tap() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 31)
	config.autopilot = false
	var arena := _arena(config)
	var hud := Hud.new(arena)
	host.add_child(hud)
	await _frames(2)

	# The pause button sits in the top-right corner of the safe area.
	var view := host.get_viewport().get_visible_rect()
	await _tap(Vector2(view.end.x - 44.0, 64.0))
	check_eq(arena.state, Arena.State.PAUSED, "tapping the pause button pauses")
	check_eq(arena.move_input, Vector2.ZERO, "and that tap did not also steer the player")
	hud.handle_back()
	await host.get_tree().create_timer(0.25).timeout
	check_eq(arena.state, Arena.State.PLAYING, "resumed")

	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(1.0 / 30.0)
	await _frames(2)
	check_eq(arena.state, Arena.State.CHOOSING, "level-up is waiting for a choice")
	var overlay := hud.get_child(0).get_child(hud.get_child(0).get_child_count() - 1) as LevelUpOverlay
	var card := overlay._cards[1]
	# An immediate tap must be ignored: the thumb was already on the screen.
	await _tap(card.get_global_rect().get_center())
	check_eq(arena.state, Arena.State.CHOOSING, "a tap inside the guard window does nothing")
	await host.get_tree().create_timer(LevelUpOverlay.INPUT_GUARD + 0.4).timeout
	var chosen: Dictionary = arena.current_offers[1]
	await _tap(card.get_global_rect().get_center())
	await host.get_tree().create_timer(0.5).timeout
	check_eq(arena.state, Arena.State.PLAYING, "tapping a card after the guard resumes play")
	var kind := str(chosen.kind)
	var id := str(chosen.id)
	var took := (kind == UpgradeSystem.KIND_WEAPON and arena.build.weapons.has(id)) \
		or (kind == UpgradeSystem.KIND_PASSIVE and arena.build.passives.has(id)) \
		or (kind == UpgradeSystem.KIND_AUGMENT and arena.build.augments.has(id)) \
		or kind in [UpgradeSystem.KIND_HEAL, UpgradeSystem.KIND_CREDITS, UpgradeSystem.KIND_PURGE]
	check(took, "the tapped card (%s) is the one that was applied" % id)
	hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)
