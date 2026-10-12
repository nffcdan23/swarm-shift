extends TestSuite
## Runs the real simulation headless with the autopilot at the controls.
## These are integration tests: they exercise spawning, combat, upgrades, the
## boss and the end-of-run flow together, the way a player would.

const DT := 1.0 / 30.0


func _arena(config: RunConfig) -> Arena:
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	return arena


func _run(arena: Arena, seconds: float) -> void:
	var steps := int(seconds / DT)
	for i in steps:
		if arena.state == Arena.State.ENDED:
			return
		arena.step(DT)


func _free(arena: Arena) -> void:
	host.remove_child(arena)
	arena.free()


func _finite(arena: Arena) -> bool:
	if is_nan(arena.player.x) or is_nan(arena.player.y) or is_inf(arena.player.x) or is_inf(arena.player.y):
		return false
	for i in arena.enemies.count:
		if is_nan(arena.enemies.x[i]) or is_nan(arena.enemies.y[i]):
			return false
	return true


func test_opening_minute_plays() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 11))
	_run(arena, 60.0)
	check(arena.time >= 59.0 or arena.state == Arena.State.ENDED, "simulation advanced")
	check(arena.combat.kills > 10, "enemies are being killed (%d)" % arena.combat.kills)
	check(arena.level > 1, "player levelled up (level %d)" % arena.level)
	check(arena.director.spawned_total > 30, "director is spawning (%d)" % arena.director.spawned_total)
	check(_finite(arena), "no NaN positions")
	check(arena.enemies.count <= arena.enemies.capacity, "enemy count within capacity")
	check(app.analytics_log.count(Analytics.GAME_STARTED) == 1, "game_started was tracked")
	check(app.analytics_log.count(Analytics.UPGRADE_SELECTED) >= 1, "upgrade_selected was tracked")
	_free(arena)


func test_full_run_reaches_an_end() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 5))
	var ended: Array = []
	arena.run_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	_run(arena, 480.0)
	check(ended.size() == 1, "run_ended fired exactly once (%d)" % ended.size())
	if ended.size() == 1:
		var result: Dictionary = ended[0]
		check(bool(result.died) != bool(result.cleared), "run ended in exactly one of death or victory")
		check(float(result.time) > 20.0, "run lasted a sensible time (%.0fs)" % float(result.time))
		check(int(result.kills) > 0, "kills recorded")
		check(float(result.damage) > 0.0, "damage recorded")
		var summary := RunLedger.settle(app, result)
		check(int(summary.credits) >= 0, "ledger produced credits")
		check(int(summary.account_xp) > 0, "ledger produced account xp")
		check_eq(int(app.stats.value("runs")), 1, "run counted in lifetime stats")
	check(_finite(arena), "no NaN positions after a full run")
	_free(arena)


func test_same_seed_same_run() -> void:
	fresh_profile()
	var first := _arena(RunConfig.for_testing(app.data, 77))
	_run(first, 40.0)
	var a := [first.combat.kills, first.level, first.enemies.count, snappedf(first.player.x, 0.01)]
	_free(first)
	var second := _arena(RunConfig.for_testing(app.data, 77))
	_run(second, 40.0)
	var b := [second.combat.kills, second.level, second.enemies.count, snappedf(second.player.x, 0.01)]
	_free(second)
	check_eq(b, a, "identical seed reproduces the run exactly")


func test_every_weapon_deals_damage() -> void:
	fresh_profile()
	for weapon_id: String in app.data.weapon_defs():
		var config := RunConfig.for_testing(app.data, 21)
		config.start_weapon = weapon_id
		config.weapon_pool = [weapon_id]
		# Sturdy enough to survive the test window with a single weapon.
		config.base_mods = {"max_hp": 5000.0}
		var arena := _arena(config)
		arena.director.timeline_time = 90.0
		_run(arena, 30.0)
		var src := arena.combat.source(weapon_id)
		check(arena.combat.damage_by_source[src] > 0.0, "weapon '%s' dealt damage" % weapon_id)
		check(_finite(arena), "weapon '%s' leaves positions finite" % weapon_id)
		_free(arena)


func test_weapons_reach_max_level_cleanly() -> void:
	fresh_profile()
	var max_level := GameData.integer(app.data.weapons, "max_level", 5)
	for weapon_id: String in app.data.weapon_defs():
		var config := RunConfig.for_testing(app.data, 9)
		config.start_weapon = weapon_id
		config.base_mods = {"max_hp": 5000.0}
		var arena := _arena(config)
		arena.grant_weapon(weapon_id, max_level)
		arena.director.timeline_time = 150.0
		_run(arena, 12.0)
		check_eq(arena.build.weapon_level(weapon_id), max_level, "weapon '%s' is at max level" % weapon_id)
		check(arena.combat.damage_by_source[arena.combat.source(weapon_id)] > 0.0, "max-level '%s' dealt damage" % weapon_id)
		_free(arena)


func test_upgrade_offers_are_always_valid() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 3))
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	var weapon_slots := GameData.integer(app.data.run_cfg(), "weapon_slots", 4)
	var passive_slots := GameData.integer(app.data.run_cfg(), "passive_slots", 5)
	for round_index in 90:
		arena.level = 2 + round_index
		var offers := arena.upgrades.roll(3)
		check_eq(offers.size(), 3, "three offers on round %d" % round_index)
		var seen := {}
		for offer in offers:
			var key := "%s:%s" % [offer.kind, offer.id]
			check(not seen.has(key), "offers are distinct (%s)" % key)
			seen[key] = true
			if str(offer.kind) == UpgradeSystem.KIND_WEAPON:
				check(int(offer.level) <= weapon_max, "weapon offer within max level")
				check_eq(int(offer.level), arena.build.weapon_level(str(offer.id)) + 1, "weapon offer is the next level")
			if str(offer.kind) == UpgradeSystem.KIND_AUGMENT:
				check(not arena.build.augments.has(str(offer.id)), "augment not offered twice")
		arena.upgrades.apply(offers[arena.rng.randi_range(0, 2)])
		check(arena.build.weapon_order.size() <= weapon_slots, "weapon slots respected")
		check(arena.build.passive_order.size() <= passive_slots, "passive slots respected")
	# By now the build is saturated; the roller must still return a full hand.
	check_eq(arena.upgrades.roll(3).size(), 3, "a saturated build still gets three offers")
	_free(arena)


func test_passives_change_player_stats() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 3))
	var base_damage := arena.player.damage
	var base_hp := arena.player.max_hp
	arena.build.set_passive("amplifier", 3)
	arena.build.set_passive("plating", 2)
	arena.refresh_build()
	check_near(arena.player.damage, base_damage * 1.36, 0.001, "three Amplifiers add 36% damage")
	check_near(arena.player.max_hp, base_hp + 40.0, 0.001, "two Platings add 40 health")
	_free(arena)


func test_meta_and_core_mods_reach_the_run() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 100000, "test")
	app.meta.buy("m_hp")
	app.meta.buy("m_damage")
	var config := RunConfig.from_profile(app)
	config.autopilot = true
	var arena := _arena(config)
	check_near(arena.player.max_hp, 106.0, 0.001, "Hull Reinforcement raises max health in the run")
	check_near(arena.player.damage, 1.04, 0.001, "Weapon Calibration raises damage in the run")
	_free(arena)


func test_synergy_activates_and_applies() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 3))
	var events: Array = []
	arena.synergy_activated.connect(func(s: Dictionary) -> void: events.append(s))
	arena.grant_weapon("drone", 1)
	var blades := 0
	var base_blades := GameData.integer(GameData.dict(app.data.weapon("orbit"), "base"), "blades")
	arena.upgrades.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "orbit", "level": 1})
	check(arena.build.synergies.has("steel_swarm"), "drone + orbit activates STEEL SWARM")
	check_eq(events.size(), 1, "synergy_activated fired once")
	for weapon in arena.weapons:
		if weapon.id == "orbit":
			blades = int(weapon.stat("blades"))
	check_eq(blades, base_blades + 2, "synergy adds two Orbit Blades on top of the base count")
	arena.upgrades.apply({"kind": UpgradeSystem.KIND_PASSIVE, "id": "amplifier", "level": 1})
	check_eq(events.size(), 1, "an unrelated pick does not re-announce it")
	_free(arena)


func test_boss_fight_and_victory() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 8)
	config.base_mods = {"max_hp": 100000.0}
	var arena := _arena(config)
	var ended: Array = []
	arena.run_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	arena.director.timeline_time = arena.director.boss_time() - 0.5
	_run(arena, 2.0)
	check(arena.boss.active, "boss spawned at the boss time")
	check(arena.director.boss_active, "director stops the timeline for the fight")
	check(app.analytics_log.count(Analytics.BOSS_STARTED) == 1, "boss_started tracked")
	_run(arena, 25.0)
	check(arena.boss.hp_fraction() > 0.0, "boss is still alive and fighting")
	check(arena.bullets.count >= 0 and _finite(arena), "boss attacks keep the simulation sane")
	# Burn it down and make sure every phase is passed through on the way.
	var guard := 0
	while arena.boss.hp_fraction() > 0.0 and guard < 400:
		var idx := arena.enemies.find_id(arena.boss.enemy_id)
		if idx < 0:
			break
		arena.enemies.hurt(idx, arena.enemies.max_hp[idx] * 0.05)
		arena.step(DT)
		guard += 1
	check_eq(arena.combat.bosses_killed, 1, "boss was killed")
	check_eq(arena.boss.phase, 2, "boss reached its final phase before dying")
	_run(arena, 6.0)
	check_eq(ended.size(), 1, "run ended after the boss died")
	if ended.size() == 1:
		check(bool(ended[0].cleared), "sector is reported as cleared")
		check_eq(int(ended[0].bosses), 1, "result records the boss kill")
	_free(arena)


func test_endless_starts_a_new_cycle() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 8)
	config.mode = CampaignService.MODE_ENDLESS
	config.base_mods = {"max_hp": 100000.0}
	var arena := _arena(config)
	arena.director.timeline_time = arena.director.boss_time() - 0.5
	_run(arena, 2.0)
	check(arena.boss.active, "boss spawned in endless")
	var idx := arena.enemies.find_id(arena.boss.enemy_id)
	arena.enemies.hurt(idx, 100000000.0)
	_run(arena, 4.0)
	check_eq(arena.director.cycle, 1, "a new cycle began")
	check(not arena.director.boss_active, "timeline resumed")
	check(arena.state != Arena.State.ENDED, "endless run continues after the boss")
	check(arena.director.effective_tier() > 1.0, "the next cycle is harder")
	_free(arena)


func test_free_revive_then_death() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 4)
	config.base_mods = {"run.revives": 1.0}
	var arena := _arena(config)
	var ended: Array = []
	arena.run_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	_run(arena, 5.0)
	arena.player.invulnerable_for = 0.0
	arena.player.take_hit(100000.0, 0.0, 0.0)
	check(arena.player.alive, "free revive brought the player back")
	check_eq(arena.revives_used, 1, "revive was counted")
	check(arena.player.hp > 0.0, "revived with health")
	check_eq(ended.size(), 0, "run did not end on the first death")
	arena.player.invulnerable_for = 0.0
	arena.player.take_hit(100000.0, 0.0, 0.0)
	check_eq(ended.size(), 1, "second death ends the run")
	if ended.size() == 1:
		check(bool(ended[0].died), "result reports the death")
	_free(arena)


func test_abandon_keeps_earnings() -> void:
	fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 6))
	var ended: Array = []
	arena.run_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	_run(arena, 45.0)
	arena.abandon()
	arena.abandon()
	check_eq(ended.size(), 1, "abandon ends the run exactly once")
	if ended.size() == 1:
		check(bool(ended[0].abandoned), "result is flagged abandoned")
		check(int(RunLedger.compute(app, ended[0]).credits) >= 0, "abandoned run still has a payout")
	_free(arena)


func test_field_stays_within_budget() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 13)
	config.base_mods = {"max_hp": 1000000.0, "damage_pct": -0.9}
	var arena := _arena(config)
	# Late-run spawn rates with a player who cannot kill: the caps must hold.
	arena.director.timeline_time = 200.0
	_run(arena, 60.0)
	var max_enemies := GameData.integer(app.data.run_cfg(), "max_enemies", 420)
	check(arena.peak_enemies <= arena.enemies.capacity, "enemy storage never overflowed (%d)" % arena.peak_enemies)
	check(arena.peak_enemies >= max_enemies * 0.8, "the field actually filled up (%d)" % arena.peak_enemies)
	check(arena.pickups.count <= arena.pickups.capacity(), "pickup storage within capacity")
	check(arena.projectiles.count <= ProjectileSystem.CAPACITY, "projectile storage within capacity")
	check(_finite(arena), "positions stay finite under load")
	print("    [perf] %d enemies: %.2f ms per step (headless, includes draw buffer writes)" % [arena.enemies.count, arena.step_ms])
	_free(arena)
