extends TestSuite
## In-run notifications: one compact banner below the HUD, queued, gone in a
## few seconds, and never in the way of the fight or the player's thumb.

const DT := 1.0 / 30.0


func _arena() -> Arena:
	var config := RunConfig.for_testing(app.data, 71)
	config.autopilot = false
	config.base_mods = {"max_hp": 1000000.0}
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	arena.director.paused = true
	return arena


func _hud(arena: Arena) -> Hud:
	var hud := Hud.new(arena)
	host.add_child(hud)
	return hud


func _free(arena: Arena, hud: Hud) -> void:
	hud.queue_free()
	await wait_frames(2)
	host.remove_child(arena)
	arena.free()


## Runs the queue until it is empty; returns how long that took.
func _drain(banners: RunBanners, limit: float = 30.0) -> float:
	var waited := 0.0
	while (banners.is_showing() or banners.waiting() > 0) and waited < limit:
		banners.advance(DT)
		waited += DT
	return waited


func _ignore_all(node: Node, bad: Array) -> void:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		bad.append(node.name)
	for child in node.get_children():
		_ignore_all(child, bad)


func test_banner_sits_compactly_below_the_hud() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(3)
	var view := host.get_viewport().get_visible_rect()
	var longest := ""
	for synergy: Dictionary in app.data.synergies().values():
		if GameData.text(synergy, "desc").length() > longest.length():
			longest = GameData.text(synergy, "desc")
	hud._banners.notify_synergy("ABSOLUTE ZERO", longest)
	hud._banners.advance(0.0)
	await wait_frames(2)
	hud._banners.advance(RunBanners.FADE_IN + 0.01)
	await wait_frames(2)
	var banner := hud._banners.banner_rect()
	var top_row := hud._hp.get_global_rect()
	check(banner.position.y >= top_row.end.y, "below the health bar (%.0f vs %.0f)" % [banner.position.y, top_row.end.y])
	check(banner.end.y <= view.size.y * 0.3, "in the top of the screen, not the middle (ends at %.0f of %.0f)" % [banner.end.y, view.size.y])
	check(banner.size.y <= 120.0, "compact, even with the longest description (%.0f tall)" % banner.size.y)
	check(view.encloses(banner), "entirely on screen")
	var player_on_screen := view.size.y * 0.5
	check(banner.end.y < player_on_screen - 100.0, "well clear of the player")

	hud._on_boss_appeared("THE OVERSEER")
	await wait_frames(3)
	hud._banners.advance(0.01)
	await wait_frames(2)
	var boss_bar := hud._boss_box.get_global_rect()
	check(hud._banners.banner_rect().position.y >= boss_bar.end.y - 1.0, "and below the boss bar when there is one")
	await _free(arena, hud)


func test_banner_never_touches_input() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(3)
	hud._banners.notify_synergy("BULLET HELL", "Pulse Cannon fires 40% faster.")
	hud._banners.advance(0.5)
	await wait_frames(2)
	var bad: Array = []
	_ignore_all(hud._banners, bad)
	check_eq(bad, [], "no part of a banner catches touches")
	var at := hud._banners.banner_rect().get_center()
	check(hud._banners.is_showing(), "a banner is up")
	await wait_frames(1)
	touch_at(0, at, true)
	await wait_frames(2)
	drag_to(0, at + Vector2(0.0, 120.0))
	await wait_frames(2)
	check(hud.joystick.vector.length() > 0.2, "a thumb starting right on the banner still steers (%s)" % str(hud.joystick.vector))
	touch_at(0, at + Vector2(0.0, 120.0), false)
	await wait_frames(2)
	await _free(arena, hud)


func test_synergy_banner_is_gone_in_two_to_three_seconds() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(2)
	hud._banners.notify_synergy("TESLA STORM", "Arc Caster gains +3 jumps.")
	var took := _drain(hud._banners)
	check(took >= 2.0 and took <= 3.0, "on screen for %.2f s" % took)
	check(not hud._banners.is_showing(), "and then gone")
	await _free(arena, hud)


func test_notices_queue_one_at_a_time_and_merge() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(2)
	var banners := hud._banners
	banners.notify_synergy("TESLA STORM", "a")
	banners.notify_synergy("DEATH BLOSSOM", "b")
	banners.notify_synergy("TESLA STORM", "a")
	banners.notify_synergy("STEEL SWARM", "c")
	check_eq(banners.waiting(), 3, "the repeat is merged, not queued twice")
	var at_once := 0
	var seconds := 0.0
	while (banners.is_showing() or banners.waiting() > 0) and seconds < 30.0:
		banners.advance(DT)
		seconds += DT
		at_once = maxi(at_once, 1 if banners.is_showing() else 0)
	var titles: Array = banners.shown.map(func(n: Dictionary) -> String: return n.title)
	check_eq(titles, ["TESLA STORM", "DEATH BLOSSOM", "STEEL SWARM"], "all three shown, in order")
	check(seconds < 7.0, "with others waiting each is cut short (%.1f s for three)" % seconds)
	await _free(arena, hud)


func test_old_announcements_are_skipped_but_synergies_and_bosses_are_not() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(2)
	var banners := hud._banners
	banners.notify_synergy("FIRST", "x")
	banners.advance(DT)
	banners.notify_synergy("SECOND", "x")
	banners.notify("SWARM INCOMING", "", "warning")
	banners.notify_synergy("THIRD", "x")
	banners.notify_synergy("FOURTH", "x")
	banners.notify("WARNING  THE OVERSEER", "", "boss")
	_drain(banners)
	var titles: Array = banners.shown.map(func(n: Dictionary) -> String: return n.title)
	check(not titles.has("SWARM INCOMING"), "a surge warning that has gone stale is dropped (%s)" % str(titles))
	check_eq(titles.size(), 5, "every synergy and the boss warning were shown")
	check_eq(titles[0], "FIRST", "the banner on screen is not interrupted")
	check_eq(titles[1], "WARNING  THE OVERSEER", "the boss warning goes next")
	await _free(arena, hud)


func test_banners_wait_behind_upgrade_screens_and_never_stop_the_run() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(2)
	var banners := hud._banners
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	check_eq(arena.state, Arena.State.CHOOSING, "an upgrade screen is open")
	banners.notify_synergy("BULLET HELL", "earned by the card just picked")
	for k in 120:
		banners.advance(DT)
	check(not banners.is_showing(), "the banner does not play out behind the cards")
	check_eq(banners.waiting(), 1, "it waits")
	arena.choose(0)
	check_eq(arena.state, Arena.State.PLAYING, "play resumes")
	banners.advance(DT)
	check_eq(banners.current_title(), "BULLET HELL", "and it shows then")
	var before := arena.time
	for k in 30:
		arena.step(DT)
		banners.advance(DT)
	check_near(arena.time - before, 1.0, 0.01, "the fight runs at full speed under a banner")
	check_eq(arena.state, Arena.State.PLAYING, "and the run never waits for one")
	await _free(arena, hud)


func test_the_run_announcements_all_use_the_banner() -> void:
	fresh_profile()
	var arena := _arena()
	var hud := _hud(arena)
	await wait_frames(2)
	hud._banners.shown.clear()
	arena.announce("SWARM INCOMING", "warning")
	hud._banners.advance(DT)
	check_eq(hud._banners.current_title(), "SWARM INCOMING", "announcements arrive as banners")
	arena.synergy_activated.emit({"id": "x", "name": "CRYO-DETONATION", "desc": "d"})
	check_eq(hud._banners.waiting(), 1, "a synergy queues behind it rather than overlapping")
	await _free(arena, hud)
