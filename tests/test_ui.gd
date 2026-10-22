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


# ---------------------------------------------------------------------------
# Progression, Credits and upgrades as the player sees them.

func _texts(node: Node, into: Array = []) -> Array:
	if node is Label and (node as Label).is_visible_in_tree():
		into.append((node as Label).text)
	for child in node.get_children():
		_texts(child, into)
	return into


func _has_text(node: Node, wanted: String) -> bool:
	for text: String in _texts(node):
		if text.contains(wanted):
			return true
	return false


func _buttons(node: Node, into: Array[NeonButton] = []) -> Array[NeonButton]:
	if node is NeonButton and (node as NeonButton).is_visible_in_tree():
		into.append(node)
	for child in node.get_children():
		_buttons(child, into)
	return into


func _button(node: Node, wanted: String) -> NeonButton:
	for button in _buttons(node):
		if button._label.text.contains(wanted):
			return button
	return null


func test_lobby_shows_player_level_xp_and_next_goals() -> void:
	fresh_profile()
	app.account.add_xp(app.account.xp_needed(1) + 30, "test")
	app.economy.grant(Economy.CREDITS, 55, "test")
	var credits := app.economy.balance(Economy.CREDITS)
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(3)
	var home := shell.screen("home")
	check(_has_text(home, "PLAYER LEVEL 2"), "the lobby names the Player Level")
	check(_has_text(home, "30 / %s XP" % Fmt.commas(app.account.xp_needed(2))), "with Player XP and the amount needed, in numbers")
	check_near(home._player_bar.value(), app.account.progress(), 0.001, "and a bar showing progress to the next level")
	check(_has_text(home, "NEXT UNLOCK  -  LV 3"), "it says what the next level unlocks")
	var goal := app.meta.next_goal()
	check(_has_text(home, str(goal.name)), "and which permanent upgrade to save for (%s)" % str(goal.name))
	check(_has_text(home, "%d / %d" % [mini(credits, int(goal.cost)), int(goal.cost)]), "with Credits against its price")
	check(_has_text(shell.top_bar, "PLAYER LV 2"), "the top bar carries the Player Level on every screen")
	check(_has_text(shell.top_bar, Fmt.compact(float(credits))), "and the Credits balance")
	check(_has_text(home, "FIRST CONTACT"), "the sector is introduced by name")
	shell.queue_free()
	await _frames(1)


func test_upgrades_screen_rows_and_bulk_buying() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 3000, "test")
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	shell.show_tab("upgrades")
	await _frames(2)
	var screen := shell.screen("upgrades") as UpgradesScreen
	for heading: String in ["OFFENCE", "DEFENCE", "UTILITY", "ECONOMY"]:
		check(_has_text(screen, heading), "the %s category is shown" % heading)
	check(_has_text(screen, "Weapon Calibration"), "an upgrade shows its name")
	check(_has_text(screen, "+4% damage per level"), "its description")
	check(_has_text(screen, "LV 0 / 10"), "its current and maximum level")
	check(_has_text(screen, "DAMAGE"), "the stat it changes")
	check(_has_text(screen, "+0%") and _has_text(screen, "+4%"), "its effect now and after the next level")
	check(_button(screen, Fmt.compact(float(app.meta.cost("m_damage")))) != null, "and a button with its price")
	check(_has_text(screen, "PLAYER LV 3"), "an upgrade behind a Player Level says which one")

	# Buy five levels of damage with one tap.
	screen._quantity.select(1)
	screen._on_quantity(1)
	await _frames(2)
	var price := app.meta.cost_for("m_damage", 5)
	var five := _button(screen, Fmt.compact(float(price)))
	check(five != null, "in x5 mode the button shows the price of five levels (%d)" % price)
	check(_has_text(screen, "+20%"), "and the effect five levels would give")
	if five != null:
		await _tap(five.get_global_rect().get_center())
		await _frames(2)
	check_eq(app.meta.level("m_damage"), 5, "one tap bought five levels")
	check_eq(app.economy.balance(Economy.CREDITS), 3000 - price, "for exactly their price")
	check(_has_text(screen, "LV 5 / 10"), "and the row shows the new level")
	check(_has_text(screen, "+20%"), "and the new effect")
	shell.queue_free()
	await _frames(1)


func test_hud_separates_run_level_from_credits() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 31)
	config.autopilot = false
	var arena := _arena(config)
	var hud := Hud.new(arena)
	host.add_child(hud)
	await _frames(2)
	check_eq(hud._level.text, "RUN LV 1", "the HUD calls the temporary level the Run Level")
	check_eq(hud._credits.text, "0", "and starts the Credits tally at zero")
	check(hud._hint.visible and _has_text(hud._hint, "GOLD"), "a first-time player is told what green and gold mean")
	for k in 6:
		arena.pickups.drop(PickupSystem.KIND_CREDIT, arena.player.x + 20.0, arena.player.y, 4.0)
	arena.pickups.drop_xp(arena.player.x + 20.0, arena.player.y, arena.xp_needed + 1.0)
	for i in 30:
		arena.step(1.0 / 60.0)
	check_eq(arena.state, Arena.State.CHOOSING, "the green energy levelled the run up")
	arena.choose(0)
	await _frames(2)
	check_eq(hud._level.text, "RUN LV 2", "which the Run Level label shows")
	check_eq(hud._credits.text, "24", "and the gold pickups went to the Credits tally instead")
	check(not bool(app.save.section("tutorial").get("pickups", false)), "the legend is not marked as seen straight away")
	hud._hint_timer = 0.01
	await _frames(3)
	check(not hud._hint.visible, "the legend goes away after its time")
	check(bool(app.save.section("tutorial").get("pickups", false)), "and is remembered as seen")
	hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)


func test_ending_a_run_asks_first_and_banks_what_it_says() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 31)
	config.autopilot = false
	var arena := _arena(config)
	var hud := Hud.new(arena)
	host.add_child(hud)
	hud.quit_requested.connect(arena.abandon)
	var ended: Array = []
	arena.run_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	await _frames(2)
	arena.add_credits(37.0)
	for i in 120:
		arena.step(1.0 / 30.0)
	hud.open_pause()
	await host.get_tree().create_timer(0.35).timeout
	var pause := hud._pause
	check(_has_text(pause, "RUN LV"), "the pause menu shows the Run Level")
	var end_button := _button(pause, "END RUN")
	check(end_button != null, "and offers END RUN")
	await _tap(end_button.get_global_rect().get_center())
	await _frames(2)
	check_eq(ended.size(), 0, "one tap on END RUN does not end the run")
	check(pause.is_confirming(), "it asks first")
	var preview := pause.preview()
	check(_has_text(pause, "+%s" % Fmt.commas(int(preview.credits))), "showing the Credits that will be banked (%d)" % int(preview.credits))
	check(_has_text(pause, "+%s XP" % Fmt.commas(int(preview.account_xp))), "and the Player XP")
	check(int(preview.credits) >= 37, "which include everything picked up")

	await _tap(_button(pause, "KEEP PLAYING").get_global_rect().get_center())
	await _frames(2)
	check(not pause.is_confirming() and arena.state == Arena.State.PAUSED, "KEEP PLAYING returns to the pause menu")
	check_eq(ended.size(), 0, "with the run intact")

	await _tap(_button(pause, "END RUN").get_global_rect().get_center())
	await _frames(2)
	var bank := _button(pause, "END RUN AND BANK")
	await _tap(bank.get_global_rect().get_center())
	await _tap(bank.get_global_rect().get_center())
	await _frames(2)
	check_eq(ended.size(), 1, "confirming ends the run exactly once, even if tapped twice")
	if ended.size() == 1:
		check(bool(ended[0].abandoned), "as a run the player chose to leave")
		var summary := RunLedger.settle(app, ended[0])
		check_eq(int(summary.credits), int(preview.credits), "and banks exactly the Credits the dialog promised")
		check_eq(int(summary.account_xp), int(preview.account_xp), "and exactly the Player XP")
		check_eq(app.economy.balance(Economy.CREDITS), int(summary.credits) + _level_credits(summary), "which are now in the balance")
	hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await _frames(1)


func _level_credits(summary: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in summary.get("level_ups", []):
		total += int((entry.rewards as Dictionary).get("credits", 0))
	return total


func test_results_screen_lists_everything_and_collects_once() -> void:
	fresh_profile()
	var result := {
		"run_id": "ui-results", "mode": CampaignService.MODE_SECTOR, "tier": 1, "effective_tier": 1.0, "core": "vanguard",
		"time": 312.0, "kills": 2468, "elites": 4, "bosses": 1, "level": 27, "level_ups": 26, "damage": 150000.0,
		"credits_picked": 410, "credit_gain": 1.0, "cleared": true, "died": false, "abandoned": false,
		"synergies": [], "revives": 0, "weapons": {"pulse": 5}, "passives": {}, "augments": [], "damage_by_source": {"pulse": 150000.0}, "cycle": 0,
	}
	var summary := RunLedger.settle(app, result)
	var balance := app.economy.balance(Economy.CREDITS)
	var screen := ResultsScreen.new(result, summary)
	host.add_child(screen)
	await _frames(3)
	check(_has_text(screen, "5:12"), "time survived is shown")
	check(_has_text(screen, "2,468"), "enemies defeated")
	check(_has_text(screen, "27"), "Run Level reached")
	check(_has_text(screen, "BOSSES DEFEATED"), "bosses defeated")
	check(_has_text(screen, "CREDITS") and _has_text(screen, "PLAYER XP"), "Credits and Player XP earned")
	check(_has_text(screen, "PLAYER LV"), "and Player Level progress")
	check(not screen.is_settled(), "the rewards are collected in a sequence, not dumped")
	check(screen._actions.modulate.a < 0.5, "and the buttons wait for it")
	check_eq(screen._credits_label.text, "+0", "the Credits count starts from zero")

	await host.get_tree().create_timer(1.6).timeout
	check(not screen.is_settled(), "part-way through, it is still counting")
	check(screen._credits_label.text != "+0", "and Credits have started to arrive (%s)" % screen._credits_label.text)
	# A tap anywhere jumps to the end.
	await _tap(Vector2(40.0, 40.0))
	await _frames(2)
	check(screen.is_settled(), "a tap skips to the end")
	check_eq(screen._credits_label.text, "+%s" % Fmt.commas(int(summary.credits)), "showing the full Credits earned")
	check_eq(screen._xp_label.text, "+%s" % Fmt.commas(int(summary.account_xp)), "the full Player XP")
	check_eq(screen._xp_level.text, "PLAYER LV %d" % app.account.level(), "and the Player Level reached")
	check(_has_text(screen, "Picked up in the run") and _has_text(screen, "Survival bonus") and _has_text(screen, "Sector cleared"), "with where the Credits came from")
	check(_has_text(screen, "Time survived") and _has_text(screen, "Enemies defeated") and _has_text(screen, "Bosses defeated"), "and where the Player XP came from")
	check(_has_text(screen, "PLAYER LEVEL %d!" % app.account.level()), "the level-up is announced")
	check_eq(app.economy.balance(Economy.CREDITS), balance, "watching or skipping the sequence pays nothing extra")

	# Doubling through a rewarded ad works once, and only once.
	check(screen._double.visible, "the optional double-Credits offer is there")
	await screen._on_double()
	await screen._on_double()
	check_eq(app.economy.balance(Economy.CREDITS), balance + int(summary.credits), "the doubling paid once")
	var again := ResultsScreen.new(result, RunLedger.settle(app, result))
	host.add_child(again)
	await _frames(2)
	check(not again._double.visible, "and a second results screen for the same run does not offer it again")
	again.skip()
	check_eq(again._credits_label.text, "+%s" % Fmt.commas(int(summary.credits) * 2), "it shows what was actually banked")
	check_eq(app.economy.balance(Economy.CREDITS), balance + int(summary.credits), "and pays nothing more")
	again.queue_free()
	screen.queue_free()
	await _frames(1)


func test_recovered_run_dialog_builds() -> void:
	fresh_profile()
	RunLedger.checkpoint(app, {"run_id": "cut-short", "mode": CampaignService.MODE_SECTOR, "tier": 1, "effective_tier": 1.0,
		"time": 178.0, "kills": 1035, "level": 16, "level_ups": 15, "bosses": 0, "elites": 2, "damage": 40000.0,
		"credits_picked": 150, "credit_gain": 1.0, "synergies": [], "revives": 0, "weapons": {}}, true)
	var recovered := RunLedger.recover_pending(app)
	check(not recovered.is_empty(), "a run cut short is recovered")
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	var dialog := RecoveredRunModal.new(recovered)
	shell.open_dialog(dialog)
	await _frames(3)
	check(_has_text(dialog, "RUN RECOVERED"), "the player is told")
	check(_has_text(dialog, "+%s" % Fmt.commas(int(recovered.credits))), "how many Credits were saved")
	check(_has_text(dialog, "2:58") and _has_text(dialog, "RUN LV 16"), "and which run it was")
	shell.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# Scrolling lists by touch. A phone has no scroll wheel: a list only moves if
# the drag that starts on it reaches the ScrollContainer.

func _scrollers(node: Node, into: Array[ScrollContainer] = []) -> Array[ScrollContainer]:
	if node is ScrollContainer:
		into.append(node)
	for child in node.get_children():
		_scrollers(child, into)
	return into


## A finger dragged across the screen from `from`, as the engine reports the
## first finger: a press, motions with the button held, a release.
func _swipe(from: Vector2, by: Vector2, steps: int = 10) -> void:
	_press(from, true)
	await _frames(1)
	var at := from
	for i in steps:
		at += by / float(steps)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.relative = by / float(steps)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		host.get_viewport().push_input(motion, true)
		await _frames(1)
	_press(at, false)
	await _frames(3)


## Scrolls the list back to the top and lets any coasting stop.
func _rest(scroller: ScrollContainer) -> void:
	await host.get_tree().create_timer(0.35).timeout
	scroller.scroll_vertical = 0
	await _frames(2)


func test_upgrades_list_scrolls_from_anywhere_on_it() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 5000, "test")
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	shell.show_tab("upgrades")
	await host.get_tree().create_timer(0.4).timeout
	var screen := shell.screen("upgrades") as UpgradesScreen
	var scroller := _scrollers(screen)[0]
	check(DisplayServer.is_touchscreen_available(), "the engine's drag-to-scroll is active in this environment")
	var overflow := scroller.get_v_scroll_bar().max_value - scroller.get_v_scroll_bar().page
	check(overflow > 300.0, "the list is longer than the screen (%.0f px hidden)" % overflow)

	# 1. From a category heading (nothing there takes input).
	var heading: Control = screen._list.get_child(0)
	await _swipe(heading.get_global_rect().get_center(), Vector2(0.0, -260.0))
	check(scroller.scroll_vertical > 120, "dragging from a category heading scrolls the list (%d px)" % scroller.scroll_vertical)
	await _rest(scroller)

	# 2. From the body of an upgrade row - where a thumb actually lands.
	var row: Control = screen._list.get_child(2)
	var on_row := row.get_global_rect().position + Vector2(row.size.x * 0.4, row.size.y * 0.5)
	await _swipe(on_row, Vector2(0.0, -260.0))
	check(scroller.scroll_vertical > 120, "dragging from an upgrade row scrolls the list (%d px)" % scroller.scroll_vertical)
	await _rest(scroller)

	# 3. From a buy button: it scrolls, and it does not buy.
	var buy := _button(screen._list.get_child(1), Fmt.compact(float(app.meta.cost("m_damage"))))
	check(buy != null, "the first row has its buy button")
	var credits := app.economy.balance(Economy.CREDITS)
	await _swipe(buy.get_global_rect().get_center(), Vector2(0.0, -260.0))
	check(scroller.scroll_vertical > 120, "dragging from a buy button scrolls the list (%d px)" % scroller.scroll_vertical)
	check_eq(app.economy.balance(Economy.CREDITS), credits, "and a drag is not a purchase")
	check_eq(app.meta.level("m_damage"), 0, "nothing was bought")
	await _rest(scroller)

	# 4. A tap on the same button still buys, with the small wobble a real
	# finger has between touching down and lifting.
	buy = _button(screen._list.get_child(1), Fmt.compact(float(app.meta.cost("m_damage"))))
	await _swipe(buy.get_global_rect().get_center(), Vector2(3.0, -6.0), 2)
	check_eq(app.meta.level("m_damage"), 1, "a tap on the buy button still buys")
	check(scroller.scroll_vertical < 20, "and does not move the list (%d px)" % scroller.scroll_vertical)

	# 5. Buying keeps your place in the list.
	scroller.scroll_vertical = 500
	await _frames(2)
	var place := scroller.scroll_vertical
	app.meta.buy("m_hp")
	screen.refresh()
	await _frames(3)
	check(absi(scroller.scroll_vertical - place) <= 2, "the list stays where it was after a purchase (%d -> %d)" % [place, scroller.scroll_vertical])
	shell.queue_free()
	await _frames(1)


## What a stray purchase, claim or unlock would change.
func _holdings() -> Array:
	return [app.economy.balance(Economy.CREDITS), app.economy.balance(Economy.CRYSTALS), app.meta.total_levels(),
		app.arsenal.unlocked_weapons().size(), app.arsenal.selected_core(), app.arsenal.selected_skin(),
		app.missions.claimable_count(), app.achievements.claimable_count(), app.account.level(), app.account.xp()]


func _first_row(list: Control) -> PanelContainer:
	for child in list.get_children():
		if child is PanelContainer and not child.is_queued_for_deletion():
			return child
	return null


## Checks one list: nothing in it swallows a drag, and a swipe that starts on a
## row - and one that starts on a button - moves it without pressing anything.
func _check_list(label: String, screen: Control, list: VBoxContainer) -> void:
	var scroller := _scrollers(screen)[0] as ScrollList
	if not check(scroller != null, "%s: the list is a ScrollList" % label):
		return
	var blocking: PackedStringArray = []
	for control in scroller.blockers():
		blocking.append(control.get_class())
	check(blocking.is_empty(), "%s: nothing in the list swallows a drag (%s)" % [label, ", ".join(blocking)])

	# Make sure there is something to scroll to, whatever the screen size.
	var filler := UiKit.gap(1600.0)
	list.add_child(filler)
	await _frames(2)
	scroller.scroll_vertical = 0
	await _frames(1)
	var row := _first_row(list)
	if not check(row != null, "%s: the list has rows" % label):
		filler.queue_free()
		return
	var before := _holdings()
	await _swipe(row.get_global_rect().position + Vector2(row.size.x * 0.35, row.size.y * 0.5), Vector2(0.0, -240.0))
	check(scroller.scroll_vertical > 100, "%s: a swipe that starts on a row scrolls (%d px)" % [label, scroller.scroll_vertical])
	await _rest(scroller)
	var buttons := _buttons(row)
	if not buttons.is_empty():
		await _swipe(buttons[0].get_global_rect().get_center(), Vector2(0.0, -240.0))
		check(scroller.scroll_vertical > 100, "%s: a swipe that starts on a button scrolls (%d px)" % [label, scroller.scroll_vertical])
		await _rest(scroller)
	check_eq(_holdings(), before, "%s: and swiping bought, claimed or selected nothing" % label)
	filler.queue_free()
	await _frames(1)


func test_every_menu_list_scrolls_from_its_rows_and_buttons() -> void:
	fresh_profile()
	app.account.add_xp(30000, "test")
	app.economy.grant(Economy.CREDITS, 60000, "test")
	app.economy.grant(Economy.CRYSTALS, 900, "test")
	app.stats.add("kills", 12000.0)
	app.stats.add("runs", 12.0)
	app.missions.apply_run({"kills": 2000, "time": 320, "bosses": 1, "level_ups": 30, "level": 30, "damage": 90000, "credits": 500, "elites": 5, "runs": 1})
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)

	shell.show_tab("upgrades")
	await host.get_tree().create_timer(0.35).timeout
	var upgrades := shell.screen("upgrades") as UpgradesScreen
	await _check_list("Upgrades", upgrades, upgrades._list)

	shell.show_tab("arsenal")
	await host.get_tree().create_timer(0.35).timeout
	var arsenal := shell.screen("arsenal") as ArsenalScreen
	for section in ArsenalScreen.SECTIONS.size():
		arsenal._tabs.select(section)
		arsenal.refresh()
		await _frames(2)
		await _check_list("Arsenal / %s" % ArsenalScreen.SECTIONS[section], arsenal, arsenal._list)

	shell.show_tab("missions")
	await host.get_tree().create_timer(0.35).timeout
	var missions := shell.screen("missions") as MissionsScreen
	await _check_list("Missions / DAILY", missions, missions._list)
	missions.show_achievements()
	await _frames(2)
	await _check_list("Missions / ACHIEVEMENTS", missions, missions._list)

	shell.show_tab("shop")
	await host.get_tree().create_timer(0.35).timeout
	var shop := shell.screen("shop") as ShopScreen
	await _check_list("Shop", shop, shop._list)

	# Rows added after the list was built are opened up as well.
	var late := UiKit.card(Palette.CYAN)
	var late_button := NeonButton.make("LATE", NeonButton.Kind.SECONDARY, Palette.CYAN)
	UiKit.card_body(late).add_child(late_button)
	shop._list.add_child(late)
	await _frames(1)
	check_eq(late.mouse_filter, Control.MOUSE_FILTER_PASS, "a row added later lets drags through")
	check_eq(late_button.mouse_filter, Control.MOUSE_FILTER_PASS, "and so does a button inside it")
	late.queue_free()

	# Buttons that are not in a list are untouched: they must keep the touch.
	check_eq(shell.screen("home")._play.mouse_filter, Control.MOUSE_FILTER_STOP, "PLAY, outside any list, still keeps its touch to itself")
	shell.queue_free()
	await _frames(1)


func test_results_cards_scroll_and_skip_from_anywhere() -> void:
	fresh_profile()
	var result := {
		"run_id": "ui-scroll", "mode": CampaignService.MODE_SECTOR, "tier": 1, "effective_tier": 1.0, "core": "vanguard",
		"time": 200.0, "kills": 900, "elites": 2, "bosses": 0, "level": 15, "level_ups": 14, "damage": 40000.0,
		"credits_picked": 120, "credit_gain": 1.0, "cleared": false, "died": true, "abandoned": false,
		"synergies": [], "revives": 0, "weapons": {"pulse": 3}, "passives": {}, "augments": [], "damage_by_source": {"pulse": 40000.0}, "cycle": 0,
	}
	var screen := ResultsScreen.new(result, RunLedger.settle(app, result))
	host.add_child(screen)
	await _frames(3)
	var scroller := _scrollers(screen)[0] as ScrollList
	check(scroller != null, "the results cards are in a ScrollList")
	check(scroller.blockers().is_empty(), "nothing on the results cards swallows a touch")
	check(not screen.is_settled(), "the reward sequence is still playing")
	# A tap in the middle of a card - where the thumb is - skips the sequence.
	var card: Control = scroller.get_child(0).get_child(0)
	await _tap(card.get_global_rect().get_center())
	await _frames(2)
	check(screen.is_settled(), "tapping on a card skips to the end, not only tapping the background")
	screen.queue_free()
	await _frames(1)


func test_settings_privacy_and_help_rows() -> void:
	fresh_profile()
	for key: String in ["privacy_policy", "support", "report_ad"]:
		check(app.data.link(key).begins_with("https://"), "%s link is an https URL" % key)
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	var settings := SettingsModal.new(shell)
	shell.open_dialog(settings)
	await host.get_tree().create_timer(0.4).timeout
	for text: String in ["PRIVACY POLICY", "SUPPORT", "REPORT AN AD", "LICENCES"]:
		var button := _button(settings, text)
		if check(button != null, "%s row is there" % text):
			check(host.get_viewport().get_visible_rect().encloses(button.get_global_rect()), "%s row is on screen" % text)
	check(_button(settings, "PRIVACY CHOICES") == null, "no privacy choices row when the ad network does not ask for one")

	app.opened_urls.clear()
	await _tap(_button(settings, "PRIVACY POLICY").get_global_rect().get_center())
	await _tap(_button(settings, "SUPPORT").get_global_rect().get_center())
	check_eq(Array(app.opened_urls), [app.data.link("privacy_policy"), app.data.link("support")], "privacy policy and support open their pages")

	check(await app.ads.show_rewarded(AdsService.REVIVE), "an ad was shown")
	app.opened_urls.clear()
	await _tap(_button(settings, "REPORT AN AD").get_global_rect().get_center())
	var report := app.opened_urls[0] if not app.opened_urls.is_empty() else ""
	check(report.begins_with(app.data.link("report_ad") + "?"), "report an ad opens the report page")
	check(report.contains("format=rewarded") and report.contains("placement=revive"), "describing the last ad shown (%s)" % report)

	await _tap(_button(settings, "LICENCES").get_global_rect().get_center())
	await host.get_tree().create_timer(0.3).timeout
	var licences: LicencesModal = null
	for node in shell.find_children("*", "LicencesModal", true, false):
		licences = node
	if check(licences != null, "licences open from settings"):
		for wanted: String in ["Copyright (c) 2014-present, Godot Engine contributors", "FreeType", "Open Sans", "Expat", "Permission is hereby granted"]:
			check(_has_text(licences, wanted), "licences include %s" % wanted)
		check(not _has_text(licences, "Google Mobile Ads"), "no Google SDK notice where the SDK is not in the build")
		licences.close()
	shell.queue_free()
	await _frames(2)


func test_privacy_choices_row_when_required() -> void:
	fresh_profile()
	var fake := FakeAdMobBridge.new()
	fake.privacy_required = true
	app.ads = AdsService.new(app, AdMobAdProvider.new(fake))
	await host.get_tree().create_timer(0.3).timeout
	var shell := MenuShell.new()
	host.add_child(shell)
	await _frames(2)
	var settings := SettingsModal.new(shell)
	shell.open_dialog(settings)
	await host.get_tree().create_timer(0.4).timeout
	var row := _button(settings, "PRIVACY CHOICES")
	if check(row != null, "privacy choices row appears when the ad network requires it"):
		var consents := app.analytics_log.count(Analytics.AD_CONSENT)
		await _tap(row.get_global_rect().get_center())
		await host.get_tree().create_timer(0.3).timeout
		check(app.analytics_log.count(Analytics.AD_CONSENT) > consents, "it opens the network's privacy form and records the answer")
	shell.queue_free()
	await host.get_tree().create_timer(0.2).timeout
	fake.free()
	fresh_profile()
