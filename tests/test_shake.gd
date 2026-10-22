extends TestSuite
## Camera shake: ordinary explosions never shake, a chain reaction shakes once
## and gently, nothing can keep the camera moving, and the big moments still
## land. Amounts are 0..1 of the configured maximum offset, before the player's
## Screen Shake setting.

const DT := 1.0 / 30.0
## Below this the camera moves less than about a pixel at the Normal setting.
const STILL := 0.05


func _arena(config: RunConfig) -> Arena:
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	return arena


func _free(arena: Arena) -> void:
	host.remove_child(arena)
	arena.free()


func _amount(arena: Arena) -> float:
	return arena.fx.shake_amount()


## A crowd of `amount` enemies around the player, all set to explode on death.
func _volatile_crowd(amount: int, run_seed: int) -> Arena:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.max_enemies = amount + 50
	config.base_mods = {"max_hp": 100000000.0}
	var arena := _arena(config)
	arena.build.add_augment("volatile")
	arena.refresh_build()
	var type_idx := arena.enemies.type_of("swarmer")
	for k in amount:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(60.0, 620.0)
		arena.enemies.spawn(type_idx, arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)
	arena.step(DT)
	return arena


## Steps `seconds`, answering any upgrade screen, and describes the shake.
## `every_step` (optional) runs before each step - to keep feeding a chain.
func _watch(arena: Arena, seconds: float, every_step: Callable = Callable()) -> Dictionary:
	var steps := int(seconds / DT)
	var moving := 0
	var longest := 0
	var run := 0
	var peak := 0.0
	var starts := 0
	var was_moving := false
	for s in steps:
		while arena.state == Arena.State.CHOOSING:
			arena.choose(0)
		if every_step.is_valid():
			every_step.call(s)
		arena.step(DT)
		var amount := _amount(arena)
		peak = maxf(peak, amount)
		var is_moving := amount > STILL
		if is_moving:
			moving += 1
			run += 1
			longest = maxi(longest, run)
			if not was_moving:
				starts += 1
		else:
			run = 0
		was_moving = is_moving
	return {"moving": float(moving) / float(steps), "longest": float(longest) * DT, "peak": peak, "starts": starts}


func test_sustained_chain_reaction_keeps_the_camera_readable() -> void:
	fresh_profile()
	var arena := _volatile_crowd(500, 41)
	var src := arena.combat.source("test")
	for k in 40:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf() * 600.0
		arena.combat.blast(arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist, 120.0, 1.0e6, src, Color.WHITE)
	var kills_before := arena.combat.kills
	var seen := _watch(arena, 10.0)
	var killed := arena.combat.kills - kills_before
	print("    [shake] 500-enemy chain: %d kills, %d explosions; camera moving %.0f%% of the time, longest %.2f s, peak %.2f, %d separate shakes" % [
		killed, arena.combat.blasts_resolved, seen.moving * 100.0, seen.longest, seen.peak, seen.starts])
	check(killed >= 400, "the chain reaction still does its work (%d kills)" % killed)
	check(seen.starts <= 1, "at most one shake for the whole chain (%d)" % seen.starts)
	check(seen.longest <= 0.6, "no shake lasts longer than 0.6 s (%.2f s)" % seen.longest)
	check(seen.peak <= 0.35, "and it is subtle (peak %.2f of the maximum)" % seen.peak)
	check(seen.moving <= 0.1, "the camera is still for at least 90%% of the chain (moving %.0f%%)" % (seen.moving * 100.0))
	_free(arena)


func test_waves_of_chain_reactions_never_keep_the_camera_moving() -> void:
	fresh_profile()
	var arena := _volatile_crowd(200, 42)
	var src := arena.combat.source("test")
	var type_idx := arena.enemies.type_of("swarmer")
	# A fresh crowd of 60 every half second, set off at once: twenty waves.
	var feed := func(s: int) -> void:
		if s % 15 != 0:
			return
		for k in 60:
			var angle := arena.rng.randf() * TAU
			var dist := arena.rng.randf_range(60.0, 600.0)
			arena.enemies.spawn(type_idx, arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)
		arena.combat.blast(arena.player.x + 200.0, arena.player.y, 160.0, 1.0e6, src, Color.WHITE)
	var kills_before := arena.combat.kills
	var resolved_before := arena.combat.blasts_resolved
	var seen := _watch(arena, 10.0, feed)
	var killed := arena.combat.kills - kills_before
	print("    [shake] 20 waves in 10 s: %d kills, %d explosions; camera moving %.0f%% of the time, longest %.2f s, peak %.2f, %d separate shakes" % [
		killed, arena.combat.blasts_resolved - resolved_before, seen.moving * 100.0, seen.longest, seen.peak, seen.starts])
	check(killed >= 1000, "a thousand or more enemies exploded (%d)" % killed)
	check(seen.longest <= 0.6, "no shake lasts longer than 0.6 s (%.2f s)" % seen.longest)
	check(seen.peak <= 0.35, "every shake is subtle (peak %.2f)" % seen.peak)
	check(seen.moving <= 0.15, "the camera is still at least 85%% of the time (moving %.0f%%)" % (seen.moving * 100.0))
	_free(arena)


func test_single_explosions_and_routine_fire_never_shake() -> void:
	fresh_profile()
	var arena := _volatile_crowd(0, 43)
	var src := arena.combat.source("test")
	for k in 6:
		arena.combat.blast(arena.player.x + 300.0, arena.player.y, 140.0, 10.0, src, Color.WHITE)
		_watch(arena, 0.5)
	check_eq(arena.fx.shakes_started, 0, "six separate explosions, half a second apart: no shake")
	for weapon_id: String in ["scatter", "nova", "pulse"]:
		arena.grant_weapon(weapon_id, 5)
	# Only weapons and plain deaths here: being hit, and a chain of exploding
	# enemies, are separate and intended shakes.
	arena.player.invulnerable_for = 1000.0
	arena.build.augments.erase("volatile")
	arena.refresh_build()
	var type_idx := arena.enemies.type_of("brute")
	for k in 40:
		arena.enemies.spawn(type_idx, arena.player.x + 150.0 + float(k % 8) * 20.0, arena.player.y + float(k / 8) * 30.0)
	var seen := _watch(arena, 4.0)
	check(arena.combat.kills > 0, "the weapons fired and killed (%d)" % arena.combat.kills)
	check_eq(seen.starts, 0, "routine weapon fire and big-enemy deaths do not shake")
	_free(arena)


func test_repeated_requests_cannot_extend_a_shake() -> void:
	fresh_profile()
	var arena := _volatile_crowd(0, 44)
	var fx := arena.fx
	var longest := 0.0
	var run := 0.0
	var accepted := 0
	for s in int(3.0 / DT):
		for k in 5:
			if fx.shake(FxSystem.Shake.MEDIUM):
				accepted += 1
		arena.step(DT)
		run = run + DT if fx.shake_amount() > 0.0 else 0.0
		longest = maxf(longest, run)
	check(accepted <= 4, "five medium requests every step for 3 s start at most 4 shakes (%d)" % accepted)
	check(longest <= 0.31, "and none ran longer than one medium shake (%.2f s)" % longest)
	check(fx.shake_amount() <= 0.3 + 0.001, "strength never stacks past the tier")
	# A weaker request never replaces a stronger one; a stronger one does.
	_watch(arena, 2.0)
	check(fx.shake(FxSystem.Shake.HEAVY), "a heavy shake starts")
	check(not fx.shake(FxSystem.Shake.LIGHT), "a light one cannot interrupt it")
	check(not fx.shake(FxSystem.Shake.HEAVY), "nor can another heavy one restart it")
	check(fx.shake(FxSystem.Shake.EPIC), "an epic one takes over")
	check_near(fx.shake_amount(), 1.0, 0.001, "at full strength, never more")
	_free(arena)


func test_big_moments_still_shake_during_a_chain() -> void:
	fresh_profile()
	var arena := _volatile_crowd(400, 45)
	var src := arena.combat.source("test")
	arena.combat.blast(arena.player.x + 100.0, arena.player.y, 200.0, 1.0e6, src, Color.WHITE)
	_watch(arena, 0.6)
	check(arena.fx.in_chain(), "a chain reaction is under way")
	_watch(arena, 1.0)
	check(arena.fx.shake(FxSystem.Shake.EPIC), "a boss defeat in the middle of it still shakes")
	check(arena.fx.shake_amount() > 0.9, "noticeably (%.2f)" % arena.fx.shake_amount())
	_free(arena)

	fresh_profile()
	arena = _volatile_crowd(0, 46)
	arena.combat.detonate_bomb()
	check(arena.fx.shake_amount() >= 0.5, "the bomb is a heavy shake (%.2f)" % arena.fx.shake_amount())
	_watch(arena, 1.0)
	arena.on_boss_phase(1)
	check(arena.fx.shake_amount() >= 0.5, "so is a boss phase change (%.2f)" % arena.fx.shake_amount())
	_watch(arena, 1.0)
	arena.on_player_hit(arena.player.max_hp * 0.25, arena.player.x, arena.player.y)
	check_near(arena.fx.shake_amount(), 0.3, 0.001, "a big hit is a medium shake")
	_watch(arena, 1.0)
	arena.on_player_hit(1.0, arena.player.x, arena.player.y)
	check(arena.fx.shake_amount() < 0.25, "chip damage only a light one (%.2f)" % arena.fx.shake_amount())
	_free(arena)


func test_screen_shake_setting() -> void:
	fresh_profile()
	check_eq(SettingsService.initial_shake_level(1.0, true), SettingsService.SHAKE_LOW, "a phone starts on Low")
	check_eq(SettingsService.initial_shake_level(1.0, false), SettingsService.SHAKE_NORMAL, "a computer on Normal")
	check_eq(SettingsService.initial_shake_level(null, true), SettingsService.SHAKE_LOW, "a new profile on a phone: Low")
	check_eq(SettingsService.initial_shake_level(0.0, false), SettingsService.SHAKE_OFF, "the old slider all the way down becomes Off")
	check_eq(SettingsService.initial_shake_level(0.45, false), SettingsService.SHAKE_LOW, "part way becomes Low")
	var expected := SettingsService.SHAKE_LOW if OS.has_feature("mobile") else SettingsService.SHAKE_NORMAL
	check_eq(app.settings.shake_level(), expected, "a fresh profile gets the platform default")
	for level: String in SettingsService.SHAKE_LEVELS:
		app.settings.set_value(SettingsService.SHAKE_LEVEL, level)
		var arena := _volatile_crowd(0, 47)
		arena.fx.shake(FxSystem.Shake.EPIC)
		arena._update_camera(DT)
		var offset := arena.camera.offset.length()
		var limit := GameData.num(GameData.dict(app.data.game, "feel"), "shake_max_offset", 22.0) * app.settings.shake_scale() * sqrt(2.0)
		if level == SettingsService.SHAKE_OFF:
			check_near(offset, 0.0, 0.0001, "Off: the camera never moves, even for an epic shake")
		else:
			check(offset <= limit + 0.001, "%s: offset %.1f within its cap %.1f" % [level, offset, limit])
		_free(arena)
	check_near(app.settings.shake_scale(), 1.0, 0.001, "Normal is full strength")
	app.settings.set_value(SettingsService.SHAKE_LEVEL, SettingsService.SHAKE_LOW)
	check_near(app.settings.shake_scale(), 0.5, 0.001, "Low is half")


func test_settings_dialog_offers_off_low_normal() -> void:
	fresh_profile()
	var shell := MenuShell.new()
	host.add_child(shell)
	await wait_frames(2)
	var settings := SettingsModal.new(shell)
	shell.open_dialog(settings)
	await wait_seconds(0.4)
	var choice := settings.find_child("ShakeLevel", true, false) as SegmentedControl
	if check(choice != null, "Settings has the Screen Shake choice"):
		check_eq(SettingsService.SHAKE_LEVELS[choice.selected], app.settings.shake_level(), "showing the current level")
		check(host.get_viewport().get_visible_rect().encloses(choice.get_global_rect()), "on screen")
		choice._on_pressed(0)
		check_eq(app.settings.shake_level(), SettingsService.SHAKE_OFF, "choosing OFF saves it")
		choice._on_pressed(2)
		check_eq(app.settings.shake_level(), SettingsService.SHAKE_NORMAL, "choosing NORMAL saves it")
	shell.queue_free()
	await wait_frames(2)
