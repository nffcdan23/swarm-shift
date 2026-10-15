extends TestSuite
## Freeze, deadlock and overload tests.
##
## The first group replays the freeze from the first device playtest (see
## docs/playtest-1/): the HUD and the run disagreeing about whether an upgrade
## screen is open. The second group pushes the simulation far past what the
## director would ever ask of it and checks that it stays bounded.

const DT := 1.0 / 60.0


func _arena(config: RunConfig, manual: bool = true) -> Arena:
	var arena := Arena.new()
	arena.manual_stepping = manual
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	return arena


func _player_config(run_seed: int) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	return config


func _hud(arena: Arena) -> Hud:
	var hud := Hud.new(arena)
	host.add_child(hud)
	return hud


func _overlay(hud: Hud) -> LevelUpOverlay:
	for child in hud.get_child(0).get_children():
		if child is LevelUpOverlay:
			return child
	return null


func _free(arena: Arena, hud: Hud = null) -> void:
	if hud != null:
		hud.queue_free()
	host.remove_child(arena)
	arena.free()
	await wait_frames(1)


## True while the run is waiting for an upgrade choice the player cannot see.
func _stranded(arena: Arena, overlay: LevelUpOverlay) -> bool:
	return arena.state == Arena.State.CHOOSING and (not overlay.is_visible_in_tree() or overlay.modulate.a < 0.5)


## Taps the first card until the hand on the table has been answered. Returns
## false if nothing the player can do gets the run past it.
func _pick_first_card(arena: Arena, overlay: LevelUpOverlay, limit: float = 3.0) -> bool:
	var hand := arena.choice_serial
	var waited := 0.0
	while waited < limit:
		if arena.state != Arena.State.CHOOSING or arena.choice_serial != hand:
			return true
		if overlay.is_visible_in_tree() and overlay.card_count() > 0:
			await tap_at(overlay.card(0).get_global_rect().get_center())
		await wait_seconds(0.1)
		waited += 0.1
	return arena.state != Arena.State.CHOOSING or arena.choice_serial != hand


## A finger on the glass, sent through the engine's own input path so that its
## touch-to-mouse emulation takes part exactly as it does on a phone.
func _finger(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = down
	event.position = host.get_viewport().get_final_transform() * at
	Input.parse_input_event(event)


func _finger_drag(index: int, from: Vector2, to: Vector2) -> void:
	var xform := host.get_viewport().get_final_transform()
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = xform * to
	event.relative = xform.basis_xform(to - from)
	Input.parse_input_event(event)


func _last_pick() -> String:
	var found := ""
	for record in app.analytics_log.recent:
		if record.event == Analytics.UPGRADE_SELECTED:
			found = "%s:%s" % [record.props.kind, record.props.id]
	return found


func _offer_key(offer: Dictionary) -> String:
	return "%s:%s" % [offer.kind, offer.id]


# ------------------------------------------------------------ playtest freeze

## The last two events in the device log of the frozen run were
##     upgrade_selected {cache: true, time: 178.154}
##     player_level_up  {level: 16,   time: 178.188}
## - an elite cache reward was picked and, one simulation step later, the
## elite's energy levelled the player up. This is that sequence.
func test_level_up_one_step_after_a_cache_pick_is_shown() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	check(overlay != null, "HUD owns the upgrade overlay")

	arena.open_cache()
	arena.step(DT)
	check_eq(arena.state, Arena.State.CHOOSING, "an elite cache asks for a choice")
	check(await _pick_first_card(arena, overlay), "tapping a card takes the cache reward")
	check_eq(arena.state, Arena.State.PLAYING, "and play resumes")

	# One step later the rest of the elite's drop arrives.
	arena.add_xp(arena.xp_needed - arena.xp + 1.0)
	arena.step(1.0 / 30.0)
	check_eq(arena.state, Arena.State.CHOOSING, "the level-up asks for a choice")
	var frozen_at := arena.time

	await wait_seconds(0.6)
	check_eq(arena.state, Arena.State.CHOOSING, "the run is still waiting for that choice")
	check(not _stranded(arena, overlay), "the level-up screen is on screen while the run waits for it")
	check(overlay.modulate.a > 0.99, "and it is fully opaque (alpha %.2f)" % overlay.modulate.a)

	# Whatever the screen shows, the player must have a way forward.
	hud.open_pause()
	var can_pause := arena.state == Arena.State.PAUSED
	if can_pause:
		hud.handle_back()
		await wait_seconds(0.3)
	var picked := await _pick_first_card(arena, overlay)
	check(picked, "the player can make the choice")
	if picked:
		for i in 10:
			arena.step(DT)
		check(arena.time > frozen_at, "and the run carries on afterwards")
		check_eq(arena.diag.hud_recoveries, 0, "without the HUD's safety net having to step in")
		check_eq(arena.diag.quick_choices, 1, "the run recorded the back-to-back choice")
	else:
		print("    [freeze] run stuck at t=%.3f in state CHOOSING: overlay visible=%s alpha=%.2f, pause available=%s" % [
			arena.time, str(overlay.is_visible_in_tree()), overlay.modulate.a, str(can_pause)])
	await _free(arena, hud)


## The same thing without scripting the order: an elite dies next to a player
## whose energy bar is nearly full, in real time, and the drop (a cache, a
## large energy gem and Credits, all from the same spot) is vacuumed in.
func test_elite_drop_never_strands_the_upgrade_screen() -> void:
	var stranded_seeds: Array[int] = []
	var double_choices := 0
	var recoveries := 0
	for run_seed: int in [3, 7, 11, 19, 23, 42]:
		fresh_profile()
		var config := _player_config(run_seed)
		config.base_mods = {"max_hp": 1000000.0}
		var arena := _arena(config, false)
		var hud := _hud(arena)
		await wait_frames(2)
		var overlay := _overlay(hud)
		arena.level = 15
		arena.xp_needed = arena._xp_for(15)
		arena.xp = arena.xp_needed - 2.0
		var elite := arena.enemies.spawn(arena.enemies.type_of("brute"), arena.player.x + 50.0, arena.player.y, true, "")
		arena.enemies.hurt(elite, 1.0e9)

		var choices := 0
		var was_choosing := false
		var stuck := 0.0
		var elapsed := 0.0
		while elapsed < 6.0 and stuck < 0.6:
			var choosing := arena.state == Arena.State.CHOOSING
			if choosing and not was_choosing:
				choices += 1
			was_choosing = choosing
			if _stranded(arena, overlay):
				stuck += 0.05
			elif choosing and not overlay.card_count() == 0:
				stuck = 0.0
				await tap_at(overlay.card(0).get_global_rect().get_center())
			if choices >= 2 and not choosing:
				break
			await wait_seconds(0.05)
			elapsed += 0.05
		if choices >= 2:
			double_choices += 1
		recoveries += arena.diag.hud_recoveries
		if stuck >= 0.6:
			stranded_seeds.append(run_seed)
			print("    [freeze] seed %d: stuck at t=%.3f, level %d, upgrade screen hidden" % [run_seed, arena.time, arena.level])
		await _free(arena, hud)
	check(double_choices >= 3, "the scenario really does produce back-to-back choices (%d of 6 runs)" % double_choices)
	check(stranded_seeds.is_empty(), "no run was left waiting on a hidden upgrade screen (stuck seeds: %s)" % str(stranded_seeds))
	check_eq(recoveries, 0, "and the HUD's safety net never had to step in")


## A reroll tapped in the instant after a card was chosen must not swap the
## hand under the choice.
func test_reroll_after_a_pick_keeps_the_chosen_card() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	arena.rerolls_left = 3
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	await wait_seconds(LevelUpOverlay.INPUT_GUARD + 0.3)
	check_eq(arena.state, Arena.State.CHOOSING, "level-up is waiting")
	var wanted := _offer_key(arena.current_offers[0])
	await tap_at(overlay.card(0).get_global_rect().get_center())
	# The pick is confirmed; now hammer the reroll button before play resumes.
	app.analytics_log.recent.clear()
	await tap_at(overlay._reroll.get_global_rect().get_center())
	await wait_seconds(0.6)
	check_eq(arena.state, Arena.State.PLAYING, "the run resumed")
	check_eq(_last_pick(), wanted, "the card that was tapped is the one that was applied")
	check_eq(arena.rerolls_left, 3, "and the late reroll was not spent")
	await _free(arena, hud)


# ------------------------------------------------------------ HUD safety net

## Sabotage: hide the upgrade screen behind the HUD's back. The reconciler has
## to notice within a frame and put it back.
func test_hud_restores_an_upgrade_screen_that_went_missing() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	await wait_frames(2)
	check(overlay.is_open(), "the level-up screen opened")
	overlay.visible = false
	overlay.serial = 0
	await wait_frames(3)
	check(overlay.is_open() and overlay.is_visible_in_tree(), "a hidden upgrade screen is put back")
	check_eq(overlay.serial, arena.choice_serial, "showing the hand the run is waiting on")
	check_eq(arena.diag.hud_recoveries, 1, "the recovery is counted once")
	check_eq(app.analytics_log.count(Analytics.HUD_RECOVERED), 1, "and reported through analytics")
	check(await _pick_first_card(arena, overlay), "the restored screen can be answered")
	check_eq(arena.state, Arena.State.PLAYING, "and the run resumes")
	await _free(arena, hud)


func test_hud_restores_a_pause_with_no_menu() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	arena.set_paused(true)
	await wait_frames(3)
	check(hud._pause_open(), "a paused run always has a pause menu on screen")
	check(hud.handle_back(), "back is handled by that menu")
	check_eq(arena.state, Arena.State.PLAYING, "and it resumes the run")
	# Pausing again while the old menu is still animating away must work.
	hud.open_pause()
	check_eq(arena.state, Arena.State.PAUSED, "pause works again at once")
	check(hud._pause_open(), "with a fresh menu")
	hud.handle_back()
	await wait_seconds(0.3)
	var menus := 0
	for child in hud.get_child(0).get_children():
		if child is PauseOverlay:
			menus += 1
	check_eq(menus, 0, "no pause menu is left behind")
	await _free(arena, hud)


func test_losing_focus_never_strands_the_run() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check_eq(arena.state, Arena.State.PAUSED, "leaving the app mid-fight pauses")
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await wait_frames(2)
	check(hud._pause_open(), "with the pause menu up")
	hud.handle_back()
	await wait_seconds(0.25)
	check_eq(arena.state, Arena.State.PLAYING, "and resumes from it")

	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	await wait_frames(2)
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await wait_frames(2)
	check_eq(arena.state, Arena.State.CHOOSING, "leaving during a level-up keeps the choice")
	check(overlay.is_open(), "and its screen is still there on return")
	check(await _pick_first_card(arena, overlay), "and still answerable")
	check_eq(arena.diag.hud_recoveries, 0, "none of this needed the safety net")
	await _free(arena, hud)


# ------------------------------------------------------------------ fingers

## One thumb steering, the other hand tapping: the tap has to count, and the
## thumb that never left the glass has to still be steering afterwards.
func test_second_finger_picks_a_card_while_the_thumb_steers() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	var thumb := host.get_viewport().get_visible_rect().get_center() + Vector2(0.0, 260.0)
	_finger(0, thumb, true)
	_finger_drag(0, thumb, thumb + Vector2(Joystick.RADIUS, 0.0))
	await wait_frames(3)
	check_near(arena.move_input.x, 1.0, 0.01, "the thumb steers right")
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "the engine sees that thumb as a held mouse button")

	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	await wait_frames(2)
	check_eq(arena.state, Arena.State.CHOOSING, "level-up is waiting")
	check_eq(arena.move_input, Vector2.ZERO, "steering is ignored while choosing")
	await wait_seconds(LevelUpOverlay.INPUT_GUARD + 0.25)
	check(overlay.is_armed(), "the cards become tappable although the thumb never lifted")

	var wanted := _offer_key(arena.current_offers[1])
	var at := overlay.card(1).get_global_rect().get_center()
	var converted := TouchTaps.converted
	app.analytics_log.recent.clear()
	_finger(1, at, true)
	await wait_frames(2)
	_finger(1, at, false)
	await wait_seconds(LevelUpOverlay.PICK_HOLD + 0.3)
	check_eq(TouchTaps.converted, converted + 1, "the second finger's tap became a click")
	check_eq(arena.state, Arena.State.PLAYING, "a tap from the other hand picks the card")
	check_eq(_last_pick(), wanted, "and it is the card that was tapped")
	await wait_frames(2)
	check_near(arena.move_input.x, 1.0, 0.01, "the thumb that never moved is still steering")
	_finger(0, thumb + Vector2(Joystick.RADIUS, 0.0), false)
	await wait_frames(2)
	check_eq(arena.move_input, Vector2.ZERO, "and lifting it stops")
	await _free(arena, hud)


func test_second_finger_can_pause_while_the_thumb_steers() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var view := host.get_viewport().get_visible_rect()
	var thumb := view.get_center() + Vector2(0.0, 260.0)
	_finger(0, thumb, true)
	_finger_drag(0, thumb, thumb + Vector2(0.0, -Joystick.RADIUS))
	await wait_frames(2)
	check_near(arena.move_input.y, -1.0, 0.01, "the thumb steers up")
	var pause_at := Vector2(view.end.x - 44.0, 64.0)
	_finger(1, pause_at, true)
	await wait_frames(1)
	_finger(1, pause_at, false)
	await wait_frames(3)
	check_eq(arena.state, Arena.State.PAUSED, "the other hand can reach PAUSE")
	hud.handle_back()
	await wait_seconds(0.25)
	check_eq(arena.state, Arena.State.PLAYING, "resumed")
	await wait_frames(2)
	check_near(arena.move_input.y, -1.0, 0.01, "still steering up after the pause")
	# A slow press or a swipe by the second finger is not a tap.
	var converted := TouchTaps.converted
	_finger(1, pause_at, true)
	_finger_drag(1, pause_at, pause_at + Vector2(-200.0, 0.0))
	await wait_frames(1)
	_finger(1, pause_at + Vector2(-200.0, 0.0), false)
	await wait_frames(3)
	check_eq(TouchTaps.converted, converted, "a swipe by the second finger is not turned into a click")
	_finger(0, thumb, false)
	await wait_frames(2)
	await _free(arena, hud)


# ----------------------------------------------------------- level-up queue

func test_energy_grants_are_validated_and_bounded() -> void:
	fresh_profile()
	var arena := _arena(_player_config(5))
	var before := arena.level
	arena.add_xp(INF)
	arena.add_xp(NAN)
	arena.add_xp(-25.0)
	arena.add_xp(0.0)
	check_eq(arena.level, before, "nonsense amounts change nothing")
	check_eq(arena.diag.xp_rejected, 4, "and are counted")
	arena.add_xp(1.0e12)
	check_eq(arena.level, before + Arena.MAX_LEVELS_PER_GRANT, "one grant gives a bounded number of levels")
	check(arena.xp < arena.xp_needed and arena.xp >= 0.0, "leaving the bar in a valid state")
	check_eq(arena.pending_choices(), Arena.MAX_LEVELS_PER_GRANT, "each level is queued as a choice")
	await _free(arena)


## A screen-wide vacuum of energy: many levels land in single steps. Every one
## must get its own hand of cards, in order, with none skipped or repeated.
func test_rapid_energy_collection_queues_every_level() -> void:
	fresh_profile()
	var arena := _arena(_player_config(5))
	var started := arena.level
	for k in 300:
		arena.pickups.drop_xp(arena.player.x, arena.player.y, 40.0)
	arena.open_cache()
	arena.open_cache()
	var hands := 0
	var caches := 0
	var seen: Dictionary = {}
	var steps := 0
	while steps < 3000 and (arena.pickups.count > 0 or arena.state == Arena.State.CHOOSING or arena.pending_choices() > 0):
		if arena.state == Arena.State.CHOOSING:
			hands += 1
			if arena.choosing_cache:
				caches += 1
			check(not seen.has(arena.choice_serial), "hand %d is new" % arena.choice_serial)
			seen[arena.choice_serial] = true
			check_eq(arena.current_offers.size(), 3, "three cards in hand %d" % hands)
			arena.choose(arena.rng.randi_range(0, 2))
		else:
			arena.step(DT)
			steps += 1
	var gained := arena.level - started
	check(gained >= 30, "the vacuum gave many levels (%d)" % gained)
	check(arena.diag.levels_in_one_step >= 2, "several in a single step (%d)" % arena.diag.levels_in_one_step)
	check_eq(hands, gained + 2, "one hand per level plus the two caches")
	check_eq(caches, 2, "both caches were opened")
	check_eq(arena.state, Arena.State.PLAYING, "and the run is playing again")
	check_eq(arena.pending_choices(), 0, "with nothing left owing")
	check_near(arena.pickups.collected_xp, arena.pickups.dropped_xp * arena.player.xp_gain, arena.pickups.dropped_xp * 0.2 + 1.0,
		"the energy collected matches the energy dropped")
	await _free(arena)


func test_queued_choices_are_shown_one_after_another() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	# Three levels and an elite cache, all in the same step.
	var grant := 0.0
	for extra in 3:
		grant += arena._xp_for(arena.level + extra)
	arena.add_xp(grant - arena.xp + 1.0)
	arena.open_cache()
	arena.step(DT)
	var titles: Array[String] = []
	for hand in 4:
		await wait_frames(2)
		check_eq(arena.state, Arena.State.CHOOSING, "hand %d is waiting" % (hand + 1))
		check(overlay.is_open() and overlay.serial == arena.choice_serial, "and it is the one on screen")
		titles.append(overlay._title.text)
		check(await _pick_first_card(arena, overlay), "hand %d can be answered" % (hand + 1))
	check_eq(titles[0], "ELITE CACHE", "the cache is offered first")
	var top := arena.level
	check_eq(titles.slice(1), ["RUN LEVEL %d" % (top - 2), "RUN LEVEL %d" % (top - 1), "RUN LEVEL %d" % top],
		"then each level in turn, headed by its own number")
	await wait_seconds(0.4)
	check_eq(arena.state, Arena.State.PLAYING, "then play resumes")
	check(not overlay.visible, "and the screen has gone")
	check_eq(arena.diag.hud_recoveries, 0, "with no recovery needed")
	await _free(arena, hud)


# --------------------------------------------------------------- overload

const ALL_WEAPONS: Array[String] = ["pulse", "scatter", "orbit", "nova", "chain", "missile", "mine", "drone", "laser", "singularity"]
const MIXED_TYPES: Array[String] = ["swarmer", "swarmer", "swarmer", "swarmer", "brute", "dasher", "shooter", "splitter"]


## A player who cannot die and cannot kill: the field fills and stays full.
func _wall_config(run_seed: int, cap: int) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.max_enemies = cap
	config.base_mods = {"max_hp": 100000000.0, "damage_pct": -0.97}
	return config


## Every weapon at max level, every passive, every augment: the build that
## produces the longest kill chains the rules allow.
func _everything_build(arena: Arena) -> void:
	var max_level := GameData.integer(app.data.weapons, "max_level", 5)
	for weapon_id in ALL_WEAPONS:
		arena.grant_weapon(weapon_id, max_level)
	for passive_id: String in app.data.passives():
		arena.build.set_passive(passive_id, GameData.integer(app.data.passives()[passive_id], "max_level", 5))
	for augment_id: String in app.data.augments():
		arena.build.add_augment(augment_id)
	arena.build.refresh_synergies()
	arena.refresh_build()


func _fill(arena: Arena, total: int, reach: float = 620.0) -> void:
	for k in total:
		var angle := arena.rng.randf() * TAU
		var dist := reach * (0.3 + 0.7 * sqrt(arena.rng.randf()))
		arena.enemies.spawn(arena.enemies.type_of(MIXED_TYPES[k % MIXED_TYPES.size()]),
			arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)


func _bounded(arena: Arena, label: String) -> void:
	check(arena.enemies.count <= arena.enemies.capacity, "%s: enemies within storage (%d)" % [label, arena.enemies.count])
	check(arena.projectiles.count <= ProjectileSystem.CAPACITY, "%s: projectiles within storage (%d)" % [label, arena.projectiles.count])
	check(arena.pickups.count <= arena.pickups.capacity(), "%s: pickups within storage (%d)" % [label, arena.pickups.count])
	check(arena.combat.pending_blasts() <= arena.combat.max_queued_blasts, "%s: explosion queue within its cap (%d)" % [label, arena.combat.pending_blasts()])
	var finite := is_finite(arena.player.x) and is_finite(arena.player.y) and is_finite(arena.xp) and is_finite(arena.player.hp)
	for i in arena.enemies.count:
		if not (is_finite(arena.enemies.x[i]) and is_finite(arena.enemies.y[i]) and is_finite(arena.enemies.hp[i])):
			finite = false
			break
	check(finite, "%s: every position and health value is a finite number" % label)


## Steps the run and returns [average ms per step, worst ms, step index of the worst].
func _timed(arena: Arena, seconds: float, dt: float = 1.0 / 30.0) -> Array[float]:
	var steps := int(seconds / dt)
	var worst := 0.0
	var worst_at := 0
	var started := Time.get_ticks_usec()
	var done := 0
	for i in steps:
		if arena.state == Arena.State.ENDED:
			break
		var mark := Time.get_ticks_usec()
		arena.step(dt)
		var cost := float(Time.get_ticks_usec() - mark) / 1000.0
		if cost > worst:
			worst = cost
			worst_at = i
		done += 1
	return [float(Time.get_ticks_usec() - started) / 1000.0 / float(maxi(done, 1)), worst, float(worst_at)]


func test_500_enemies() -> void:
	fresh_profile()
	var arena := _arena(_wall_config(13, 500))
	arena.director.timeline_time = 230.0
	_fill(arena, 500)
	var cost := _timed(arena, 20.0)
	check(arena.peak_enemies >= 500, "five hundred enemies were alive at once (%d)" % arena.peak_enemies)
	_bounded(arena, "500 enemies")
	check(cost[0] < 12.0, "a step stays affordable (%.2f ms average on this machine)" % cost[0])
	print("    [load] 500-enemy wall: %.2f ms per step, worst %.1f ms (step %d), %d alive at the end" % [cost[0], cost[1], int(cost[2]), arena.enemies.count])
	await _free(arena)


func test_1000_enemies() -> void:
	fresh_profile()
	# More than twice what the shipped game will ever spawn (420).
	var arena := _arena(_wall_config(14, 1000))
	arena.director.timeline_time = 230.0
	_fill(arena, 1000, 760.0)
	var cost := _timed(arena, 15.0)
	check(arena.peak_enemies >= 1000, "a thousand enemies were alive at once (%d)" % arena.peak_enemies)
	_bounded(arena, "1000 enemies")
	check(cost[0] < 25.0, "a step stays affordable (%.2f ms average on this machine)" % cost[0])
	print("    [load] 1000-enemy wall: %.2f ms per step, worst %.1f ms (step %d)" % [cost[0], cost[1], int(cost[2])])
	await _free(arena)

	# The same crowd against the strongest build there is: mass kills, drops,
	# splitters and every chain effect at once.
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 15)
	config.max_enemies = 1000
	config.base_mods = {"max_hp": 100000000.0}
	arena = _arena(config)
	arena.director.timeline_time = 230.0
	_everything_build(arena)
	_fill(arena, 1000, 760.0)
	cost = _timed(arena, 20.0)
	_bounded(arena, "1000 enemies vs everything")
	check(arena.combat.kills > 1000, "the build chewed through the crowd (%d kills)" % arena.combat.kills)
	check(cost[0] < 25.0, "a step stays affordable under mass kills (%.2f ms average)" % cost[0])
	print("    [load] 1000 enemies vs max build: %.2f ms per step, worst %.1f ms, %d kills, %s" % [
		cost[0], cost[1], arena.combat.kills, arena.diag.summary()])
	await _free(arena)


func test_hundreds_of_simultaneous_explosions() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 16)
	config.max_enemies = 500
	config.base_mods = {"max_hp": 100000000.0}
	var arena := _arena(config)
	arena.build.add_augment("volatile")
	arena.refresh_build()
	_fill(arena, 500, 520.0)
	arena.step(1.0 / 30.0)
	var src := arena.combat.source("test")
	for k in 300:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf() * 520.0
		arena.combat.blast(arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist, 120.0, 400.0, src, Color.WHITE)
	check_eq(arena.combat.pending_blasts(), 300, "three hundred explosions are queued at once")
	var kills_before := arena.combat.kills
	var steps := 0
	var worst := 0.0
	var most_resolved := 0
	while arena.combat.pending_blasts() > 0 and steps < 900:
		var mark := Time.get_ticks_usec()
		var resolved_before := arena.combat.blasts_resolved
		arena.step(1.0 / 60.0)
		worst = maxf(worst, float(Time.get_ticks_usec() - mark) / 1000.0)
		most_resolved = maxi(most_resolved, arena.combat.blasts_resolved - resolved_before)
		steps += 1
	check(steps < 900, "the queue drains (%d steps)" % steps)
	check(most_resolved <= Combat.MAX_BLASTS_PER_STEP, "no step resolves more than its budget (%d)" % most_resolved)
	check(arena.combat.kills - kills_before > 300, "the chain reaction did its work (%d kills)" % (arena.combat.kills - kills_before))
	check_eq(arena.diag.blasts_dropped, 0, "nothing had to be discarded")
	_bounded(arena, "300 explosions")
	print("    [load] 300 explosions + chain: drained in %d steps, worst step %.1f ms, queue peak %d" % [steps, worst, arena.diag.blast_queue_peak])

	# Far past the backstop: the surplus is dropped, never allowed to pile up.
	for k in arena.combat.max_queued_blasts * 3:
		arena.combat.blast(arena.player.x, arena.player.y, 60.0, 1.0, src, Color.WHITE)
	check_eq(arena.combat.pending_blasts(), arena.combat.max_queued_blasts, "the queue stops at its cap")
	check(arena.diag.blasts_dropped >= arena.combat.max_queued_blasts * 2, "and counts what it turned away")
	steps = 0
	while arena.combat.pending_blasts() > 0 and steps < 900:
		arena.step(1.0 / 60.0)
		steps += 1
	check(steps < 900, "and still drains")
	await _free(arena)


func test_chain_reaction_build_for_a_minute() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 17)
	config.max_enemies = 500
	config.base_mods = {"max_hp": 100000000.0}
	var arena := _arena(config)
	_everything_build(arena)
	arena.director.timeline_time = 200.0
	_fill(arena, 500)
	var cost := _timed(arena, 60.0)
	_bounded(arena, "chain build")
	check(arena.combat.kills > 1200, "well over a thousand chained kills (%d)" % arena.combat.kills)
	check(arena.state != Arena.State.CHOOSING, "no choice is left hanging")
	var gain := arena.player.xp_gain
	var accounted := arena.pickups.collected_xp / gain + arena.pickups.field_xp()
	check_near(accounted, arena.pickups.dropped_xp, arena.pickups.dropped_xp * 0.01 + 1.0,
		"every point of energy dropped is either collected or still on the field")
	check(cost[0] < 16.0, "a step stays affordable (%.2f ms average)" % cost[0])
	print("    [load] everything build, 500 cap, 60 s: %.2f ms per step, worst %.1f ms, %d kills, level %d\n           %s" % [
		cost[0], cost[1], arena.combat.kills, arena.level, arena.diag.summary()])
	await _free(arena)


func test_full_field_keeps_caches_and_credits() -> void:
	fresh_profile()
	var arena := _arena(_player_config(18))
	# Park the drops far from the player so nothing is collected.
	var far_x := arena.player.x + 5000.0
	var cap := arena.pickups.capacity()
	for k in cap + 50:
		arena.pickups.drop_xp(far_x, arena.player.y, 3.0)
	for k in 200:
		arena.pickups.drop(PickupSystem.KIND_CREDIT, far_x, arena.player.y, 2.0)
	check(arena.pickups.count <= cap, "the field never exceeds its storage (%d of %d)" % [arena.pickups.count, cap])
	check_near(arena.pickups.field_credits() + arena.credits, 400.0, 0.01, "all 400 Credits are still there")
	check_near(arena.pickups.field_xp(), float(cap + 50) * 3.0, 0.5, "and all the energy")
	for k in 40:
		arena.pickups.drop(PickupSystem.KIND_CACHE, far_x, arena.player.y)
	var caches := 0
	for i in arena.pickups.count:
		if arena.pickups.kind[i] == PickupSystem.KIND_CACHE:
			caches += 1
	check_eq(caches + arena.pending_choices(), 40, "every elite cache survives a full field")
	check(arena.pickups.count <= cap, "still within storage")
	check_near(arena.pickups.field_xp() + arena.pickups.collected_xp, float(cap + 50) * 3.0, 0.5, "and no energy was destroyed to make room")
	check(arena.diag.pickups_merged > 0, "the merges are counted (%d)" % arena.diag.pickups_merged)
	await _free(arena)


## Pause, resume, level up and pause again, as fast as the HUD allows, in the
## middle of a heavy fight running in real time.
func test_pausing_during_heavy_combat() -> void:
	fresh_profile()
	var config := _player_config(19)
	config.base_mods = {"max_hp": 100000000.0}
	var arena := _arena(config, false)
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	_everything_build(arena)
	arena.director.timeline_time = 200.0
	_fill(arena, 300)
	var pauses := 0
	var hands := 0
	var paused_drift := 0.0
	for round_index in 60:
		match arena.state:
			Arena.State.CHOOSING:
				if await _pick_first_card(arena, overlay):
					hands += 1
			Arena.State.PLAYING:
				hud.open_pause()
				if arena.state == Arena.State.PAUSED:
					pauses += 1
					var frozen := arena.time
					await wait_frames(2)
					paused_drift += absf(arena.time - frozen)
					hud.handle_back()
			Arena.State.PAUSED:
				hud.handle_back()
		await wait_frames(1 + round_index % 4)
	await wait_seconds(0.4)
	if arena.state == Arena.State.CHOOSING:
		await _pick_first_card(arena, overlay)
	check(pauses >= 15, "the fight was paused many times (%d)" % pauses)
	check_eq(paused_drift, 0.0, "the simulation never advanced while paused")
	check(arena.time > 0.2, "and did advance in between (%.2fs)" % arena.time)
	check(arena.combat.kills > 50, "with real combat going on (%d kills, %d level-ups answered)" % [arena.combat.kills, hands])
	var menus := 0
	for child in hud.get_child(0).get_children():
		if child is PauseOverlay and not (child as PauseOverlay).is_closing():
			menus += 1
	check_eq(menus, 1 if arena.state == Arena.State.PAUSED else 0, "no stray pause menu is left on screen")
	check_eq(arena.diag.hud_recoveries, 0, "and the safety net was never needed")
	_bounded(arena, "pause storm")
	await _free(arena, hud)


func test_boss_arrives_on_a_full_field() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 20)
	# Every weapon and every chain effect, at a sliver of the damage so that
	# the boss survives long enough to use its whole repertoire.
	config.base_mods = {"max_hp": 100000000.0, "damage_pct": -0.95}
	var arena := _arena(config)
	var ended: Array = []
	arena.run_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	var max_level := GameData.integer(app.data.weapons, "max_level", 5)
	for weapon_id in ALL_WEAPONS:
		arena.grant_weapon(weapon_id, max_level)
	for augment_id: String in ["volatile", "storm_crit", "shatter", "split_rounds", "explosive_rounds", "barrage", "reactive"]:
		arena.build.add_augment(augment_id)
	arena.refresh_build()
	_fill(arena, 400)
	arena.director.timeline_time = arena.director.boss_time() - 1.0
	# The boss's arrival wave kills the whole field in a few steps: hundreds of
	# deaths, drops and chain explosions, then a vacuum of all their energy.
	var cost := _timed(arena, 8.0)
	check(arena.boss.active, "the boss arrived")
	_bounded(arena, "boss arrival")
	check(arena.diag.levels_in_one_step >= 1, "the vacuum levelled the player (%d levels in one step at most)" % arena.diag.levels_in_one_step)
	var fight := _timed(arena, 12.0)
	_bounded(arena, "boss fight")
	check(arena.boss.active and arena.state != Arena.State.ENDED, "the fight is under way")
	check(arena.bullets.count > 0 or arena.hazards.count > 0 or arena.boss.hp_fraction() < 1.0, "and the boss is attacking")
	var guard := 0
	while arena.boss.hp_fraction() > 0.0 and guard < 600:
		var idx := arena.enemies.find_id(arena.boss.enemy_id)
		if idx < 0:
			break
		arena.enemies.hurt(idx, arena.enemies.max_hp[idx] * 0.05)
		arena.step(1.0 / 30.0)
		guard += 1
	_timed(arena, 6.0)
	check_eq(ended.size(), 1, "the run ended exactly once after the boss died")
	if ended.size() == 1:
		check(bool(ended[0].cleared), "as a clear")
	print("    [load] boss on a 400-enemy field: arrival %.2f ms per step (worst %.1f), fight %.2f ms (worst %.1f)" % [cost[0], cost[1], fight[0], fight[1]])
	await _free(arena)


## An Overdrive session far longer than a normal run: storage, the explosion
## queue, memory and step cost must all stay flat. `--soak=<minutes>` sets the
## simulated length (default 10).
func test_long_session_stays_flat() -> void:
	fresh_profile()
	var minutes := float(app.cli_text("soak", "10"))
	var config := RunConfig.for_testing(app.data, 21)
	config.mode = CampaignService.MODE_ENDLESS
	config.base_mods = {"max_hp": 100000000.0}
	var arena := _arena(config)
	var first := _timed(arena, 120.0)
	var memory_start := OS.get_static_memory_usage()
	var objects_start := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var worst := first[1]
	var slowest_minute := first[0]
	var minute := 2
	while float(minute) < minutes and arena.state != Arena.State.ENDED:
		var cost := _timed(arena, 60.0)
		slowest_minute = maxf(slowest_minute, cost[0])
		worst = maxf(worst, cost[1])
		minute += 1
		_bounded(arena, "minute %d" % minute)
	var grown_mb := float(OS.get_static_memory_usage() - memory_start) / 1048576.0
	var objects_grown := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_start
	check(arena.time >= minutes * 60.0 - 1.0, "the session ran its full length (%.0f s)" % arena.time)
	check(arena.director.cycle >= int(minutes / 6.0), "through several boss cycles (%d)" % arena.director.cycle)
	check(grown_mb < 24.0, "memory stays flat (%.1f MB growth after the first two minutes)" % grown_mb)
	check(objects_grown < 1500, "no objects pile up (%d more than after two minutes)" % objects_grown)
	check(slowest_minute < 12.0, "step cost stays affordable (slowest minute averaged %.2f ms)" % slowest_minute)
	print("    [soak] %.0f simulated minutes of Overdrive: cycle %d, level %d, %d kills, slowest minute %.2f ms per step, worst step %.1f ms, memory %+.1f MB, objects %+d\n           %s" % [
		arena.time / 60.0, arena.director.cycle, arena.level, arena.combat.kills, slowest_minute, worst, grown_mb, objects_grown, arena.diag.summary()])
	await _free(arena)


## Sabotage of a different kind: a card is tapped but the pick never reaches
## the run. The cards must not stay locked for ever.
func test_hud_deals_again_if_a_pick_is_lost() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var hud := _hud(arena)
	await wait_frames(2)
	var overlay := _overlay(hud)
	overlay.picked.disconnect(hud._on_card_picked)
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	await wait_seconds(LevelUpOverlay.INPUT_GUARD + 0.2)
	await tap_at(overlay.card(0).get_global_rect().get_center())
	await wait_seconds(0.5)
	check(overlay.is_resolved() and arena.state == Arena.State.CHOOSING, "the tap was taken but the run never heard about it")
	await wait_seconds(LevelUpOverlay.PICK_HOLD + 1.0)
	check(not overlay.is_resolved(), "the HUD notices and deals the hand again")
	check_eq(arena.diag.hud_recoveries, 1, "counting it as a recovery")
	overlay.picked.connect(hud._on_card_picked)
	check(await _pick_first_card(arena, overlay), "and this time the pick goes through")
	check_eq(arena.state, Arena.State.PLAYING, "so the run resumes")
	await _free(arena, hud)
