extends TestSuite
## Threat levels: the ladder, what each modifier does, rewards that pay once,
## and the heaviest stacks staying fair and fast.

const DT := 1.0 / 30.0
const ENDGAME_V1 := "res://tests/fixtures/profile_v1_endgame_before_research.save"
const PLAYTEST_V1 := "res://tests/fixtures/profile_v1_before_playtest_update.save"


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


func _cleared_to(sector: int) -> void:
	app.save.section("sectors")["highest_cleared"] = sector


func _config(mutators: Array[String], tier: int = 5) -> RunConfig:
	var config := RunConfig.for_testing(app.data, 51)
	config.autopilot = false
	config.tier = tier
	config.extra_mutators = mutators
	config.base_mods = {"max_hp": 5000.0, "xp_gain_pct": -1.0}
	return config


func _result(run_id: String, tier: int, threat: int, cleared: bool) -> Dictionary:
	return {
		"run_id": run_id, "mode": CampaignService.MODE_SECTOR, "tier": tier, "effective_tier": float(tier), "core": "vanguard",
		"time": 330.0, "kills": 2000, "elites": 3, "bosses": 1 if cleared else 0, "level": 25, "level_ups": 24, "damage": 90000.0,
		"credits_picked": 600, "credit_gain": 1.0, "cleared": cleared, "died": not cleared, "abandoned": false,
		"synergies": [], "revives": 0, "weapons": {"pulse": 5}, "passives": {}, "augments": [], "damage_by_source": {"pulse": 90000.0},
		"cycle": 0, "threat": threat, "challenge_kind": "", "challenge_id": "",
	}


# ------------------------------------------------------------------ ladder

func test_threat_stays_out_of_the_way_until_the_campaign_reaches_it() -> void:
	fresh_profile()
	var campaign := app.campaign
	check(not campaign.threat_available(), "a new player sees no Threat")
	_cleared_to(3)
	check(not campaign.threat_available(), "nor at Sector 3")
	check_eq(campaign.selected_threat(), 0, "and every run is an ordinary sector")
	_cleared_to(4)
	check(campaign.threat_available(), "Threat 1 opens with Sector 4 cleared, long before Sector 20")
	check_eq(campaign.max_threat(2), 1, "a cleared sector can be played at Threat 1")
	check_eq(campaign.max_threat(5), 0, "a sector not yet cleared cannot")
	check_eq(RunConfig.from_profile(app).threat, 0, "the default run is still Threat 0")


func test_each_sector_climbs_its_own_ladder_one_level_at_a_time() -> void:
	fresh_profile()
	var campaign := app.campaign
	_cleared_to(20)
	for level in range(1, 11):
		check_eq(campaign.max_threat(7), level, "Sector 7 offers Threat %d next" % level)
		campaign.record_run(CampaignService.MODE_SECTOR, 7, true, 320.0, level)
	check_eq(campaign.threat_cleared(7), 10, "cleared all ten")
	check_eq(campaign.max_threat(7), 10, "and the ladder tops out at ten")
	check_eq(campaign.max_threat(8), 1, "another sector starts its own ladder at 1")
	campaign.record_run(CampaignService.MODE_SECTOR, 8, false, 200.0, 1)
	check_eq(campaign.threat_cleared(8), 0, "a loss climbs nothing")


func test_higher_levels_open_as_the_campaign_advances() -> void:
	fresh_profile()
	var campaign := app.campaign
	_cleared_to(9)
	for level in range(1, 4):
		campaign.record_run(CampaignService.MODE_SECTOR, 2, true, 320.0, level)
	check_eq(campaign.max_threat(2), 3, "Threat 4 waits for Sector 10")
	_cleared_to(10)
	check_eq(campaign.max_threat(2), 4, "and opens with it")
	var last := 0
	for level in range(1, campaign.threat_max() + 1):
		check(campaign.threat_unlock_sector(level) >= last, "levels open in order")
		last = campaign.threat_unlock_sector(level)
	check(campaign.threat_unlock_sector(1) < campaign.sector_count(), "the first level opens well before the last sector")


func test_the_lobby_selection_is_always_a_level_the_sector_allows() -> void:
	fresh_profile()
	var campaign := app.campaign
	_cleared_to(12)
	campaign.select(6)
	campaign.select_threat(5)
	check_eq(campaign.selected_threat(), 1, "a sector with no Threat clears offers only 1")
	campaign.record_run(CampaignService.MODE_SECTOR, 6, true, 320.0, 1)
	campaign.select_threat(2)
	check_eq(campaign.selected_threat(), 2, "after a clear, 2")
	campaign.select(7)
	check_eq(campaign.selected_threat(), 1, "another sector clamps the choice to its own ladder")
	var config := RunConfig.from_profile(app)
	check_eq(config.threat, 1, "the run carries it")
	check_eq(config.extra_mutators, campaign.threat_mutators(1), "with its modifier")


# ---------------------------------------------------------------- modifiers

func test_levels_stack_and_each_names_a_real_modifier() -> void:
	fresh_profile()
	var campaign := app.campaign
	var seen: Array[String] = []
	for level in range(1, campaign.threat_max() + 1):
		var stack := campaign.threat_mutators(level)
		check_eq(stack.size(), level, "Threat %d carries %d modifiers" % [level, level])
		var id := campaign.threat_mutator(level)
		check(not seen.has(id), "Threat %d adds something new (%s)" % [level, id])
		seen.append(id)
		var def := campaign.mutator_def(id)
		check(not GameData.text(def, "desc").is_empty(), "%s says what it does" % id)
		# Not just more health: anything that only touches health or numbers
		# across the board would fail one of these.
		check(not def.has("hp") and not def.has("spawn") and not def.has("speed"), "%s is a rule, not a stat multiplier" % id)


func test_each_modifier_does_what_it_says() -> void:
	fresh_profile()
	# Quick Shots: faster enemy shots that reach no further.
	var arena := _arena(_config(["t_quick_shots"]))
	arena.director.paused = true
	arena.bullets.spawn(0.0, 0.0, 100.0, 0.0, 5.0)
	check_near(arena.bullets.vx[0], 120.0, 0.01, "Quick Shots: shots fly 20% faster")
	check_near(arena.bullets.vx[0] * arena.bullets.life[0], 100.0 * (arena.bullets.life[0] * 1.2), 0.5, "and expire sooner, so their reach is unchanged")
	_free(arena)

	# Scarce Repairs: half healing, regeneration included.
	arena = _arena(_config(["t_scarce_repairs"]))
	arena.director.paused = true
	arena.player.hp = 100.0
	arena.player.heal(20.0)
	check_near(arena.player.hp, 110.0, 0.01, "Scarce Repairs: a heal of 20 restores 10")
	_free(arena)

	# Brood Elites: every elite also spawns Swarmers, whatever else it is.
	arena = _arena(_config(["t_brood_elites"]))
	arena.director.paused = true
	var elite := arena.enemies.spawn(arena.enemies.type_of("brute"), 300.0, 0.0, true, "swift")
	check((arena.enemies.flags[elite] & EnemySystem.F_SPAWNER) != 0, "Brood Elites: a Swift elite is also a Broodmother")
	var same := arena.enemies.spawn(arena.enemies.type_of("brute"), -300.0, 0.0, true, "spawner")
	check((arena.enemies.flags[same] & EnemySystem.F_SPAWNER) != 0, "and a Broodmother stays one")
	_free(arena)

	# No Second Chances: no revives of any kind, whatever research says.
	var config := _config(["t_no_second_chances"])
	config.base_mods["run.revives"] = 1.0
	arena = _arena(config)
	check_eq(arena.free_revives_left, 0, "No Second Chances: no free revive")
	check_eq(arena.ad_revives_left, 0, "and no ad revive")
	check_near(arena.player.heal_mult, 0.5, 0.001, "and healing halved")
	_free(arena)

	# Scatter Fire: Shooters fire three at once.
	arena = _arena(_config(["t_scatter_fire"]))
	arena.director.paused = true
	arena.enemies.clear()
	arena.enemies.spawn(arena.enemies.type_of("shooter"), arena.player.x + 260.0, arena.player.y)
	for s in int(6.0 / DT):
		arena.step(DT)
		if arena.bullets.spawned_total >= 3:
			break
	check_eq(arena.bullets.spawned_total % 3, 0, "Scatter Fire: a Shooter's shots come in threes (%d)" % arena.bullets.spawned_total)
	check(arena.bullets.spawned_total >= 3, "and it fired")
	_free(arena)

	# Final Protocol: tougher elites.
	arena = _arena(_config([]))
	arena.director.paused = true
	var plain_hp := arena.enemies.max_hp[arena.enemies.spawn(arena.enemies.type_of("brute"), 300.0, 0.0, true, "swift")]
	_free(arena)
	arena = _arena(_config(["t_final_protocol"]))
	arena.director.paused = true
	var tough_hp := arena.enemies.max_hp[arena.enemies.spawn(arena.enemies.type_of("brute"), 300.0, 0.0, true, "swift")]
	check_near(tough_hp / plain_hp, 1.5, 0.01, "Final Protocol: elites have 50% more health")
	_free(arena)


func test_set_piece_modifiers_repeat_with_warning() -> void:
	fresh_profile()
	for id: String in ["t_patrols", "t_crossfire", "t_hunters"]:
		var arena := _arena(_config([id], 12))
		var labels: Array[String] = []
		arena.announced.connect(func(text: String, _kind: String) -> void: labels.append(text))
		arena.director.timeline_time = 60.0
		arena.player.invulnerable_for = 1000.0
		var spawned_before := arena.director.spawned_total
		for s in int(70.0 / DT):
			arena.step(DT)
		check(arena.director.spawned_total > spawned_before, "%s brings enemies" % id)
		var expected := {"t_patrols": "ELITE", "t_crossfire": "CROSSFIRE", "t_hunters": "HUNTER PACK"}
		var warned := false
		for text in labels:
			if text.contains(str(expected[id])):
				warned = true
		check(warned, "%s is announced when it arrives (%s)" % [id, ", ".join(PackedStringArray(labels.slice(0, 6)))])
		# Threat is risk, not loot: what it brings drops nothing, so it cannot
		# make a run easier by handing out levels and elite caches.
		var bare := 0
		for i in arena.enemies.count:
			if (arena.enemies.flags[i] & EnemySystem.F_NO_DROPS) != 0:
				bare += 1
		check(bare > 0, "%s's enemies drop nothing (%d on the field)" % [id, bare])
		_free(arena)


func test_boss_modifiers() -> void:
	fresh_profile()
	var arena := _arena(_config(["t_wrath"]))
	arena.director.paused = true
	arena.spawn_boss("overseer", 1.0, 1.0)
	check_eq(arena.boss.phase, 1, "Overseer's Wrath: the boss opens in its second phase")
	_free(arena)
	arena = _arena(_config(["t_wrath", "t_final_protocol"]))
	arena.director.paused = true
	arena.spawn_boss("overseer", 1.0, 1.0)
	check_eq(arena.boss._phases.size(), 4, "Final Protocol: a fourth phase")
	var i := arena.enemies.find_id(arena.boss.enemy_id)
	arena.enemies.hp[i] = arena.enemies.max_hp[i] * 0.1
	arena.player.invulnerable_for = 1000.0
	for s in 10:
		arena.step(DT)
	check_eq(arena.boss.phase, 3, "reached below 20%% health")
	_free(arena)
	# The phase list in the data is never changed by a run.
	check_eq(GameData.list(GameData.dict(GameData.dict(app.data.stages, "bosses"), "overseer"), "phases").size(), 3, "the boss data keeps its three phases")


# ------------------------------------------------------------------ rewards

func test_threat_pays_more_and_its_first_clears_pay_once() -> void:
	fresh_profile()
	_cleared_to(10)
	# At the top Player Level, so no level-up Crystals muddy the count.
	app.account.add_xp(100000000, "test")
	var plain := RunLedger.compute(app, _result("x", 5, 0, true))
	var hard := RunLedger.compute(app, _result("y", 5, 3, true))
	check(int(hard.credits) > int(plain.credits), "Threat 3 pays more Credits (%d vs %d)" % [hard.credits, plain.credits])
	check(int(hard.account_xp) > int(plain.account_xp), "and more Player XP")
	check_eq(int(hard.crystals), 0, "no ordinary first-clear Crystals for a sector already cleared")

	var crystals := app.economy.balance(Economy.CRYSTALS)
	var first := RunLedger.settle(app, _result("t1-a", 5, 1, true))
	check(bool(first.threat_first_clear), "the first Threat 1 clear of Sector 5 is a first clear")
	check(int(first.threat_first_credits) > 0, "it pays a Credit bonus")
	check_eq(int(first.threat_crystals), 5, "and the Threat 1 milestone: 5 Crystals")
	check_eq(app.economy.balance(Economy.CRYSTALS), crystals + 5, "banked")
	var again := RunLedger.settle(app, _result("t1-b", 5, 1, true))
	check(not bool(again.threat_first_clear) and int(again.threat_first_credits) == 0, "clearing it again pays no first-clear bonus")
	var other := RunLedger.settle(app, _result("t1-c", 6, 1, true))
	check(int(other.threat_first_credits) > 0, "another sector's first Threat 1 clear pays its Credits")
	check_eq(int(other.threat_crystals), 0, "but the Crystal milestone was paid once, for the level")
	check_eq(app.economy.balance(Economy.CRYSTALS), crystals + 5, "so no more Crystals")
	check_eq(app.campaign.highest_cleared(), 10, "Threat clears never move the campaign")


func test_premium_currency_from_threat_has_a_ceiling() -> void:
	fresh_profile()
	_cleared_to(20)
	app.account.add_xp(100000000, "test")
	var total := 0
	for level in range(1, app.campaign.threat_max() + 1):
		for sector in [3, 9, 15]:
			var summary := RunLedger.settle(app, _result("cap-%d-%d" % [level, sector], sector, level, true))
			total += int(summary.threat_crystals) + int(summary.crystals)
	var ceiling := 0
	for level in range(1, app.campaign.threat_max() + 1):
		ceiling += GameData.integer(GameData.dict(app.data.stages, "threat"), "milestone_crystals", 5) * level
	check_eq(total, ceiling, "every Crystal Threat pays, across three full ladders, is the one-off milestones (%d)" % ceiling)
	var later := RunLedger.settle(app, _result("cap-again", 3, 10, true))
	check_eq(int(later.threat_crystals) + int(later.crystals), 0, "and replaying pays none")


func test_threat_and_cosmetics_and_achievements() -> void:
	fresh_profile()
	_cleared_to(20)
	check(not app.arsenal.is_owned(ArsenalService.SKINS, "hazard"), "Hazard is locked")
	for level in range(1, 6):
		app.campaign.record_run(CampaignService.MODE_SECTOR, 4, true, 300.0, level)
	check(app.arsenal.is_owned(ArsenalService.SKINS, "hazard"), "Threat 5 earns Hazard")
	check(not app.arsenal.is_owned(ArsenalService.SKINS, "apex"), "Apex waits for Threat 10")
	check(not app.arsenal.unlock(ArsenalService.SKINS, "apex"), "and cannot be bought")
	var claimable := 0
	for entry in app.achievements.all():
		if str(entry.id) in ["threat_1", "threat_5"] and bool(entry.get("complete", false)):
			claimable += 1
	check_eq(claimable, 2, "Threat 1 and 5 achievements are complete")


# --------------------------------------------------------------- fairness

## The worst stacks the game can produce: Threat 10 on top of each late
## sector's own two mutators. A strong bot must still be able to survive, the
## field must stay within its caps, and steps must stay cheap.
func test_the_heaviest_stacks_stay_fair_and_fast() -> void:
	fresh_profile()
	var worst := 0.0
	var total := 0.0
	var steps := 0
	var fastest_shot := 0.0
	var peak := 0
	var cap := 0
	for tier in [11, 14, 17, 20]:
		var config := RunConfig.for_testing(app.data, 70 + tier)
		config.tier = tier
		config.autopilot_skill = 0.85
		config.extra_mutators = app.campaign.threat_mutators(10)
		config.base_mods = {"max_hp_pct": 2.0, "damage_pct": 2.0, "xp_gain_pct": 1.0}
		var arena := _arena(config)
		arena.director.timeline_time = 150.0
		for s in int(40.0 / DT):
			while arena.state == Arena.State.CHOOSING:
				arena.choose(0)
			var mark := Time.get_ticks_usec()
			arena.step(DT)
			var ms := float(Time.get_ticks_usec() - mark) / 1000.0
			total += ms
			steps += 1
			worst = maxf(worst, ms)
			peak = maxi(peak, arena.enemies.count)
			cap = arena.max_enemy_count()
			for k in arena.bullets.count:
				fastest_shot = maxf(fastest_shot, Vector2(arena.bullets.vx[k], arena.bullets.vy[k]).length())
			if arena.state == Arena.State.ENDED or arena.state == Arena.State.DOWNED:
				break
		check(is_finite(arena.player.x), "Sector %d at Threat 10 ran" % tier)
		_free(arena)
	print("    [threat 10] %.2f ms per step, worst %.1f ms, fastest enemy shot %.0f, peak field %d (cap %d)" % [total / float(steps), worst, fastest_shot, peak, cap])
	# Set pieces may push past the soft cap the timeline respects, but never
	# past the pool the arena allocates.
	check(peak <= cap + 110, "the field never outgrows the arena's pool (%d)" % peak)
	check(total / float(steps) < 6.0, "Threat 10 stacks average under 6 ms a step (%.2f)" % (total / float(steps)))
	# Shooters fire at 250 at most; Quick Shots makes that 300. Anything faster
	# would leave no time to react.
	check(fastest_shot <= 310.0, "no enemy shot outruns what a player can dodge (%.0f)" % fastest_shot)


# ------------------------------------------------------------------- saves

func test_old_saves_gain_threat_without_losing_anything() -> void:
	for path: String in [ENDGAME_V1, PLAYTEST_V1]:
		var backend := MemorySaveBackend.new()
		backend.text = FileAccess.get_file_as_string(path)
		app.boot(backend)
		var before := app.campaign.highest_cleared()
		check(app.save.state.has("threat") and app.save.state.has("challenges"), "%s gains the new sections" % path.get_file())
		check_eq(app.campaign.highest_threat_cleared(), 0, "with no Threat progress")
		check_eq(app.campaign.highest_cleared(), before, "and its campaign intact")
		if before >= 4:
			check(app.campaign.max_threat(1) >= 1, "a veteran can start the ladder straight away")
	fresh_profile()
