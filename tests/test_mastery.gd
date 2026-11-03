extends TestSuite
## Weapon mastery and evolutions: earned by using a weapon, paid exactly once,
## impossible to farm, and every evolution a real choice.

const DT := 1.0 / 30.0


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


func _result(overrides: Dictionary = {}) -> Dictionary:
	var result := {
		"run_id": "m-1", "mode": CampaignService.MODE_SECTOR, "tier": 1, "effective_tier": 1.0, "core": "vanguard",
		"time": 330.0, "active_time": 330.0, "kills": 2500, "elites": 2, "bosses": 1, "level": 25, "level_ups": 24, "damage": 90000.0,
		"credits_picked": 300, "credit_gain": 1.0, "cleared": true, "died": false, "abandoned": false, "synergies": [], "revives": 0,
		"weapons": {"pulse": 5, "scatter": 3}, "passives": {}, "augments": [], "cycle": 0,
		"damage_by_source": {"pulse": 80000.0, "scatter": 10000.0}, "dealt_by_source": {"pulse": 80000.0, "scatter": 10000.0},
		"kills_by_source": {"pulse": 2200, "scatter": 300}, "evolved": {},
	}
	for key: String in overrides:
		result[key] = overrides[key]
	return result


func _rich() -> void:
	fresh_profile()
	app.account.add_xp(10000000, "test")
	app.economy.grant(Economy.CREDITS, 100000000, "test")


func _evolvable_config(run_seed: int, evolutions: Dictionary, slots: float = 1.0) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.evolutions = evolutions
	config.base_mods = {"max_hp": 1000000.0, "run.evolutions": slots}
	return config


# ---------------------------------------------------------------- earning XP

func test_xp_comes_from_damage_actually_landed() -> void:
	fresh_profile()
	var gains := app.mastery.preview(_result())
	check(int(gains.pulse) > int(gains.scatter), "more damage, more XP")
	check(int(gains.scatter) > 0, "but the smaller share still earns")
	check(float(gains.scatter) / float(gains.pulse) > 0.25, "a real part of it: square root of a 1:8 split, not 1:8")
	var unused := _result({"weapons": {"pulse": 5, "scatter": 3, "orbit": 1}})
	check(not app.mastery.preview(unused).has("orbit"), "a weapon that landed nothing earns nothing")


func test_a_run_with_no_real_fighting_earns_nothing() -> void:
	fresh_profile()
	var result := _result({"kills": 0, "bosses": 0, "cleared": false})
	check_near(app.mastery.run_budget(result), 0.0, 0.01, "no kills, no XP however long it lasted")
	check(app.mastery.run_budget(_result({"kills": 30, "bosses": 0, "cleared": false})) < app.mastery.run_budget(_result({"bosses": 0, "cleared": false})) * 0.2,
		"thirty kills in five minutes is barely anything")


func test_stretching_a_run_earns_nothing_extra() -> void:
	fresh_profile()
	var normal := app.mastery.run_budget(_result({"time": 360.0, "active_time": 360.0, "kills": 3000, "bosses": 2, "cleared": false}))
	var stretched := app.mastery.run_budget(_result({"time": 3600.0, "active_time": 3600.0, "kills": 30000, "bosses": 20, "cleared": false}))
	check_near(stretched, normal, 0.01, "an hour earns exactly what six minutes does")


func test_overdrive_earns_no_more_than_a_sector_of_the_same_length() -> void:
	fresh_profile()
	var sector := app.mastery.run_budget(_result({"tier": 1, "cleared": false, "bosses": 1}))
	var endless := app.mastery.run_budget(_result({"mode": CampaignService.MODE_ENDLESS, "tier": 1, "effective_tier": 16.0, "cleared": false, "bosses": 1}))
	check_near(endless, sector, 0.01, "no reward for depth beyond the budget")


func test_time_spent_not_moving_does_not_count() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 21)
	config.autopilot = false
	config.base_mods = {"max_hp": 1000000.0, "xp_gain_pct": -1.0}
	var arena := _arena(config)
	for s in int(30.0 / DT):
		arena.step(DT)
	check_near(arena.time, 30.0, 0.1, "thirty seconds passed")
	check_near(arena.idle_time, 24.0, 0.2, "all but the first six count as idle")
	var result := arena.build_result(false, false, true)
	check_near(float(result.active_time), 6.0, 0.2, "active time is what is left")
	var moved := arena.idle_time
	arena.move_input = Vector2(0.5, 0.0)
	for s in int(5.0 / DT):
		arena.step(DT)
	check_near(arena.idle_time, moved, 0.01, "moving stops the idle clock")
	arena.move_input = Vector2.ZERO
	for s in int(4.0 / DT):
		arena.step(DT)
	check_near(arena.idle_time, moved, 0.01, "and pausing to think for a few seconds does not start it")
	_free(arena)


func test_a_bot_that_plays_a_real_run_is_never_idle() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 22)
	config.base_mods = {"max_hp": 1000000.0}
	var arena := _arena(config)
	for s in int(60.0 / DT):
		arena.step(DT)
	check_near(arena.idle_time, 0.0, 0.5, "a player moving around is not idle")
	_free(arena)


func test_abandoning_early_cannot_be_used_to_farm() -> void:
	fresh_profile()
	var quick := app.mastery.run_budget(_result({"time": 8.0, "active_time": 8.0, "kills": 12, "bosses": 0, "cleared": false, "abandoned": true}))
	check(quick < 6.0, "a run thrown away after a few seconds is worth almost nothing (%.1f)" % quick)


func test_mastery_is_paid_exactly_once() -> void:
	fresh_profile()
	var result := _result()
	var first := RunLedger.settle(app, result)
	var xp := app.mastery.xp("pulse")
	check(xp > 0, "paid")
	check_eq((first.mastery as Array).size(), 2, "the summary lists both weapons")
	var again := RunLedger.settle(app, result)
	check(bool(again.duplicate), "a second settle is a duplicate")
	check_eq(app.mastery.xp("pulse"), xp, "and pays nothing")
	check_eq(app.mastery.record("pulse").runs, 1, "lifetime record counted once")


func test_an_interrupted_run_keeps_its_mastery() -> void:
	var backend := fresh_profile()
	RunLedger.checkpoint(app, _result({"run_id": "killed"}), true)
	var reopened := MemorySaveBackend.new()
	reopened.text = backend.text
	app.boot(reopened)
	check_eq(app.mastery.xp("pulse"), 0, "nothing paid yet")
	RunLedger.recover_pending(app)
	var xp := app.mastery.xp("pulse")
	check(xp > 0, "recovered at the next launch")
	check(RunLedger.recover_pending(app).is_empty(), "once")
	check_eq(app.mastery.xp("pulse"), xp, "and not again")


func test_ranks_and_the_top_of_the_track() -> void:
	fresh_profile()
	var mastery := app.mastery
	check_eq(mastery.rank("pulse"), 0, "starts unranked")
	check_eq(mastery.max_rank(), 5, "five ranks, not an endless climb")
	app.save.section("mastery")["pulse"] = {"xp": mastery.rank_xp(1)}
	check_eq(mastery.rank("pulse"), 1, "rank 1 at exactly its threshold")
	app.save.section("mastery")["pulse"] = {"xp": mastery.rank_xp(5) - 1}
	check_eq(mastery.rank("pulse"), 4, "one short of the top is not the top")
	check(not bool(mastery.progress("pulse").maxed), "not maxed")
	mastery.award(_result())
	check(mastery.is_maxed("pulse"), "a run takes it over the line")
	check_eq(mastery.xp("pulse"), mastery.rank_xp(5), "and it stops at the top")
	check_near(float(mastery.progress("pulse").fraction), 1.0, 0.001, "a full bar")
	var rows := mastery.award(_result({"weapons": {"pulse": 5}}))
	check_eq(int(rows[0].gained), 0, "nothing more is added")


func test_every_weapon_has_a_full_mastery_track() -> void:
	fresh_profile()
	for id: String in app.data.weapon_defs():
		check_eq(app.mastery.perks(id).size(), 2, "%s has two perks" % id)


func test_perks_reach_the_weapon_in_a_run() -> void:
	fresh_profile()
	app.save.section("mastery")["pulse"] = {"xp": app.mastery.rank_xp(4)}
	var config := RunConfig.from_profile(app)
	check_near(float(config.base_mods.get("w.pulse.pierce", 0.0)), 1.0, 0.001, "rank 4 perk is in the run's modifiers")
	check_near(float(config.base_mods.get("w.pulse.range_pct", 0.0)), 0.15, 0.001, "and rank 2's")
	var arena := _arena(config)
	check_eq(int(arena.weapon_node("pulse").stat("pierce")), 1, "the weapon has it")
	_free(arena)


func test_a_master_weapon_wears_a_finish_and_nothing_else_changes() -> void:
	fresh_profile()
	var plain := _arena(RunConfig.from_profile(app))
	var plain_color := plain.weapon_node("pulse").color
	var plain_damage := plain.weapon_node("pulse").stat("damage")
	_free(plain)
	app.save.section("mastery")["pulse"] = {"xp": app.mastery.rank_xp(app.mastery.max_rank())}
	check_eq(app.mastery.mastered_weapons(), ["pulse"], "mastered")
	var master := _arena(RunConfig.from_profile(app))
	check(master.weapon_node("pulse").color != plain_color, "its shots take on the finish")
	check_eq(master.weapon_node("pulse").stat("damage"), plain_damage, "with no extra damage from the finish")
	_free(master)


# ---------------------------------------------------------------- evolutions

func test_an_evolution_needs_lab_rank_and_credits() -> void:
	fresh_profile()
	var mastery := app.mastery
	check(not bool(mastery.evolution_info("pulse", "repeater").affordable), "nothing at the start")
	check(not mastery.unlock_evolution("pulse", "repeater"), "no lab, no rank, no Credits")
	app.account.add_xp(10000000, "test")
	app.economy.grant(Economy.CREDITS, 20000, "test")
	check(not mastery.unlock_evolution("pulse", "repeater"), "no lab yet")
	app.meta.buy("r_evo_lab")
	check(not mastery.unlock_evolution("pulse", "repeater"), "no rank yet")
	app.save.section("mastery")["pulse"] = {"xp": mastery.rank_xp(3)}
	var cost := int(mastery.evolution_info("pulse", "repeater").cost)
	var balance := app.economy.balance(Economy.CREDITS)
	check(mastery.unlock_evolution("pulse", "repeater"), "lab, rank and Credits")
	check_eq(app.economy.balance(Economy.CREDITS), balance - cost, "for exactly its price")
	check(not mastery.unlock_evolution("pulse", "repeater"), "not twice")
	check(not mastery.unlock_evolution("pulse", "breach"), "the second path needs rank 4")
	check_eq(mastery.owned_paths("pulse"), ["repeater"], "owned")
	check_eq(mastery.run_evolutions(), {"pulse": ["repeater"]}, "and on the table for a run")


func test_every_weapon_with_evolutions_has_two_for_different_jobs() -> void:
	fresh_profile()
	for id: String in app.data.weapon_defs():
		var table := app.mastery.evolution_table(id)
		if table.is_empty():
			continue
		check_eq(table.size(), 2, "%s has two paths" % id)
		var roles: Array = []
		for path: String in table:
			roles.append(GameData.text(table[path], "role"))
		check(roles[0] != roles[1], "%s's paths have different jobs (%s)" % [id, str(roles)])


func test_evolving_is_offered_at_the_final_level_and_not_before() -> void:
	fresh_profile()
	var arena := _arena(_evolvable_config(31, {"pulse": ["repeater", "breach"]}))
	arena.grant_weapon("pulse", 4)
	for offer in arena.upgrades.roll(3):
		check(str(offer.kind) != UpgradeSystem.KIND_EVOLUTION, "not at level 4")
	arena.grant_weapon("pulse", 5)
	var hand := arena.upgrades.roll(3)
	var paths: Array = []
	for offer in hand:
		if str(offer.kind) == UpgradeSystem.KIND_EVOLUTION:
			paths.append(str(offer.id))
	paths.sort()
	check_eq(paths, ["breach", "repeater"], "both paths side by side, always")
	check_eq(hand.size(), 3, "with one other card to choose instead")
	_free(arena)


func test_only_paths_the_player_owns_are_offered() -> void:
	fresh_profile()
	var arena := _arena(_evolvable_config(32, {"pulse": ["breach"]}))
	arena.grant_weapon("pulse", 5)
	var found: Array = []
	for offer in arena.upgrades.roll(3):
		if str(offer.kind) == UpgradeSystem.KIND_EVOLUTION:
			found.append(str(offer.id))
	check_eq(found, ["breach"], "the one owned, not the other")
	_free(arena)


func test_nothing_evolves_without_the_lab() -> void:
	fresh_profile()
	var arena := _arena(_evolvable_config(33, {"pulse": ["breach"]}, 0.0))
	arena.grant_weapon("pulse", 5)
	for offer in arena.upgrades.roll(3):
		check(str(offer.kind) != UpgradeSystem.KIND_EVOLUTION, "no slots, no card")
	_free(arena)


func test_taking_an_evolution_changes_the_weapon_and_closes_the_offer() -> void:
	fresh_profile()
	var arena := _arena(_evolvable_config(34, {"pulse": ["repeater", "breach"], "scatter": ["flak"]}))
	arena.grant_weapon("pulse", 5)
	arena.grant_weapon("scatter", 5)
	var weapon := arena.weapon_node("pulse")
	var cooldown := weapon.stat("cooldown")
	var offer := {}
	for candidate in arena.upgrades.roll(3):
		if str(candidate.id) == "repeater":
			offer = candidate
	check(arena.upgrades.apply(offer), "the card applies")
	check_eq(weapon.evolution, "repeater", "the weapon has evolved")
	check_eq(str(arena.build.evolved.get("pulse", "")), "repeater", "the build knows")
	check(weapon.stat("cooldown") < cooldown, "and it fires faster")
	for candidate in arena.upgrades.roll(3):
		check(str(candidate.kind) != UpgradeSystem.KIND_EVOLUTION, "one evolution per run without Twin Evolution")
	check(not arena.upgrades.is_valid(offer), "the old card cannot be replayed")
	check(not arena.upgrades.apply({"kind": UpgradeSystem.KIND_EVOLUTION, "id": "flak", "weapon": "scatter", "level": 1}), "and a stale second card is refused")
	check_eq(str(arena.build_result(false, false, false).evolved.get("pulse", "")), "repeater", "the result records it")
	_free(arena)


func test_twin_evolution_allows_a_second() -> void:
	fresh_profile()
	var arena := _arena(_evolvable_config(35, {"pulse": ["repeater"], "scatter": ["flak"]}, 2.0))
	arena.grant_weapon("pulse", 5)
	arena.grant_weapon("scatter", 5)
	var first := arena.upgrades.roll(3)
	var taken := {}
	for offer in first:
		if str(offer.kind) == UpgradeSystem.KIND_EVOLUTION:
			taken = offer
			break
	arena.upgrades.apply(taken)
	var second := {}
	for offer in arena.upgrades.roll(3):
		if str(offer.kind) == UpgradeSystem.KIND_EVOLUTION:
			second = offer
	check(not second.is_empty(), "the other weapon is offered")
	check(str(second.weapon) != str(taken.weapon), "not the one already evolved")
	check(arena.upgrades.apply(second), "and it applies")
	check_eq(arena.build.evolved.size(), 2, "two evolved weapons")
	_free(arena)


func test_every_evolution_runs_and_does_damage() -> void:
	fresh_profile()
	for weapon_id: String in app.data.weapon_defs():
		for path: String in app.mastery.evolution_table(weapon_id):
			var config := _evolvable_config(36, {weapon_id: [path]})
			config.start_weapon = weapon_id
			config.base_mods["xp_gain_pct"] = -1.0
			var arena := _arena(config)
			arena.director.paused = true
			arena.grant_weapon(weapon_id, 5)
			arena.evolve_weapon(weapon_id, path)
			arena.enemies.clear()
			var swarmer := arena.enemies.type_of("swarmer")
			var src := arena.combat.source(weapon_id)
			for s in int(5.0 / DT):
				if s % 20 == 0:
					for k in 12:
						var angle := TAU * float(k) / 12.0
						arena.enemies.spawn(swarmer, arena.player.x + cos(angle) * 180.0, arena.player.y + sin(angle) * 180.0)
				arena.step(DT)
			check(arena.combat.dealt_by_source[src] > 0.0, "%s %s deals damage" % [weapon_id, path])
			check_eq(arena.diag.upgrades_rejected, 0, "%s %s rejected nothing" % [weapon_id, path])
			_free(arena)


## The point of two paths: neither should be better at everything. Numbers from
## the same bench as the balance tables; Sector 8 health, averaged over a seed
## or two. Saturation is why "at least as good" allows a small margin.
func test_no_evolution_is_better_than_its_sibling_at_everything() -> void:
	for weapon_id: String in app.data.weapon_defs():
		var paths: Array = app.mastery.evolution_table(weapon_id).keys()
		if paths.size() != 2:
			continue
		var scores: Array[Dictionary] = []
		for path: String in paths:
			var row := {}
			for scenario: String in ["single", "swarm", "kite"]:
				row[scenario] = float(WeaponBench.run(host, app, weapon_id, 5, scenario, 20.0, 77, path).dps)
			scores.append(row)
		var a_wins := 0
		var b_wins := 0
		for scenario: String in ["single", "swarm", "kite"]:
			if float(scores[0][scenario]) > float(scores[1][scenario]) * 1.05:
				a_wins += 1
			if float(scores[1][scenario]) > float(scores[0][scenario]) * 1.05:
				b_wins += 1
		check(not (a_wins > 0 and b_wins == 0) or a_wins < 3, "%s: %s does not beat %s at everything %s" % [weapon_id, paths[0], paths[1], str(scores)])
		check(not (b_wins > 0 and a_wins == 0) or b_wins < 3, "%s: %s does not beat %s at everything %s" % [weapon_id, paths[1], paths[0], str(scores)])
	fresh_profile()


# --------------------------------------------------------------- new weapons

func test_railgun_hunts_the_toughest_enemy_not_the_nearest() -> void:
	fresh_profile()
	var config := _evolvable_config(41, {})
	config.start_weapon = "railgun"
	var arena := _arena(config)
	arena.director.paused = true
	arena.enemies.clear()
	var near := arena.enemies.spawn(arena.enemies.type_of("swarmer"), arena.player.x + 80.0, arena.player.y)
	var far := arena.enemies.spawn(arena.enemies.type_of("tank"), arena.player.x - 500.0, arena.player.y)
	var near_id := arena.enemies.id[near]
	var far_id := arena.enemies.id[far]
	var far_hp := arena.enemies.hp[far]
	var weapon := arena.weapon_node("railgun")
	for s in int(1.0 / DT):
		arena.enemies.x[arena.enemies.find_id(far_id)] = arena.player.x - 500.0
		arena.step(DT)
	check(weapon.get("fired") >= 1, "it fired")
	check(arena.enemies.hp[arena.enemies.find_id(far_id)] < far_hp, "at the Tank across the screen")
	check(arena.enemies.find_id(near_id) >= 0 and arena.enemies.hp[arena.enemies.find_id(near_id)] > 0.0, "ignoring the Swarmer beside the player")
	_free(arena)


func test_nanites_spread_when_a_host_dies() -> void:
	fresh_profile()
	var config := _evolvable_config(42, {})
	config.start_weapon = "nanite"
	var arena := _arena(config)
	arena.director.paused = true
	arena.enemies.clear()
	var type := arena.enemies.type_of("brute")
	var host_enemy := arena.enemies.spawn(type, arena.player.x + 200.0, arena.player.y)
	var neighbour := arena.enemies.spawn(type, arena.player.x + 260.0, arena.player.y)
	arena.enemies.infected[host_enemy] = 5.0
	var neighbour_id := arena.enemies.id[neighbour]
	arena.combat.hit(host_enemy, 1.0e7, 0, 0.0, 0.0, false)
	arena.step(DT)
	arena.step(DT)
	check(arena.enemies.infected[arena.enemies.find_id(neighbour_id)] > 0.0, "the neighbour caught it")
	_free(arena)


func test_infection_damage_does_not_depend_on_the_frame_rate() -> void:
	var totals: Array[float] = []
	for rate: float in [30.0, 60.0]:
		fresh_profile()
		var config := _evolvable_config(43, {})
		config.start_weapon = "nanite"
		var arena := _arena(config)
		arena.director.paused = true
		arena.enemies.clear()
		var weapon := arena.weapon_node("nanite")
		weapon._cd = 1000.0
		var tank := arena.enemies.spawn(arena.enemies.type_of("tank"), arena.player.x + 300.0, arena.player.y)
		arena.enemies.max_hp[tank] = 1.0e6
		arena.enemies.hp[tank] = 1.0e6
		arena.enemies.infected[tank] = 6.0
		for s in int(rate * 3.0):
			arena.enemies.x[0] = arena.player.x + 300.0
			arena.enemies.y[0] = arena.player.y
			arena.step(1.0 / rate)
		totals.append(1.0e6 - arena.enemies.hp[0])
		_free(arena)
	check(totals[0] > 0.0, "it does damage")
	check_near(totals[1] / totals[0], 1.0, 0.12, "the same at 30 and 60 steps a second, give or take one tick (%s)" % str(totals))


func test_bosses_are_worn_down_not_melted_by_nanites() -> void:
	fresh_profile()
	var config := _evolvable_config(44, {})
	config.start_weapon = "nanite"
	var arena := _arena(config)
	var weapon := arena.weapon_node("nanite")
	check(weapon.stat("share_cap") > 0.0, "a cap exists")
	check(weapon.stat("share_cap") + weapon.stat("damage") < 16000.0 * 0.01, "and one tick is well under 1% of the first boss")
	_free(arena)


func test_new_weapons_are_behind_research() -> void:
	_rich()
	check(not app.arsenal.is_owned(ArsenalService.WEAPONS, "railgun"), "locked at first")
	check(not app.arsenal.unlocked_weapons().has("nanite"), "and out of the pool")
	app.meta.buy("r_evo_lab")
	app.meta.buy("r_railgun")
	check(app.arsenal.is_owned(ArsenalService.WEAPONS, "railgun"), "research opens it")
	check(RunConfig.from_profile(app).weapon_pool.has("railgun"), "and it can be drawn in a run")


func test_flex_rack_lets_a_mastered_weapon_start() -> void:
	_rich()
	check_eq(app.arsenal.start_weapon(), "pulse", "the core's own by default")
	check(not app.arsenal.select_start_weapon("orbit"), "not without Flex Rack")
	app.meta.buy("r_flex_rack")
	check(not app.arsenal.select_start_weapon("orbit"), "not without Rank 1")
	app.save.section("mastery")["orbit"] = {"xp": app.mastery.rank_xp(1)}
	check(app.arsenal.select_start_weapon("orbit"), "with it, yes")
	check_eq(RunConfig.from_profile(app).start_weapon, "orbit", "the run starts with it")
	check(app.arsenal.select_start_weapon(""), "and back")
	check_eq(app.arsenal.start_weapon(), "pulse", "to the core's own")
	app.arsenal.grant(ArsenalService.WEAPONS, "laser", "test")
	app.save.section("mastery")["laser"] = {"xp": app.mastery.rank_xp(1)}
	check(not app.arsenal.select_start_weapon("laser"), "but never the Prism Lance, which cannot kill on its own")


# --------------------------------------------------------------- performance

## The enemy simulation has its own budget (see --bench): this holds the weapons
## to theirs, with a build far heavier than a run can normally hold.
func test_a_full_evolved_build_in_a_big_swarm_stays_fast() -> void:
	fresh_profile()
	var config := _evolvable_config(45, {})
	config.max_enemies = 420
	config.base_mods["xp_gain_pct"] = -1.0
	var arena := _arena(config)
	arena.director.paused = true
	arena.profile = true
	for weapon_id: String in ["orbit", "mine", "chain", "nanite", "singularity", "laser"]:
		arena.grant_weapon(weapon_id, 5)
	arena.evolve_weapon("orbit", "aegis")
	arena.evolve_weapon("mine", "stasis")
	arena.evolve_weapon("chain", "conductor")
	arena.evolve_weapon("laser", "sweep")
	var type := arena.enemies.type_of("swarmer")
	var steps := 0
	for s in 240:
		while arena.enemies.count < 400:
			var angle := randf() * TAU
			var i := arena.enemies.spawn(type, arena.player.x + cos(angle) * randf_range(100.0, 420.0), arena.player.y + sin(angle) * randf_range(100.0, 420.0))
			arena.enemies.hp[i] = 1.0e5
			arena.enemies.max_hp[i] = 1.0e5
		if s == 30:
			arena.profile_usec.fill(0)
		arena.step(DT)
		if s >= 30:
			steps += 1
	var ms := float(arena.profile_usec[2] + arena.profile_usec[4]) / float(steps) / 1000.0
	check(ms < 8.0, "six level 5 weapons among 400 enemies cost under 8 ms a step, headless, on this machine (%.2f ms)" % ms)
	_free(arena)
