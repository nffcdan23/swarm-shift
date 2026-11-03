extends TestSuite
## Research, doctrines, awakenings, the economy around them, and the move from
## version 1 profiles.

const ENDGAME_V1 := "res://tests/fixtures/profile_v1_endgame_before_research.save"
const PLAYTEST_V1 := "res://tests/fixtures/profile_v1_before_playtest_update.save"
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


func _rich() -> void:
	fresh_profile()
	app.account.add_xp(10000000, "test")
	app.economy.grant(Economy.CREDITS, 100000000, "test")


func _boot_fixture(path: String) -> MemorySaveBackend:
	var backend := MemorySaveBackend.new()
	backend.text = FileAccess.get_file_as_string(path)
	app.boot(backend)
	return backend


# ------------------------------------------------------------ save migration

func test_an_endgame_v1_save_keeps_every_scrap_of_progress() -> void:
	check(FileAccess.file_exists(ENDGAME_V1), "the end-game version 1 fixture is present")
	var before: Dictionary = JSON.parse_string(str((JSON.parse_string(FileAccess.get_file_as_string(ENDGAME_V1)) as Dictionary).body))
	check_eq(int(before.version), 1, "the fixture really is version 1")
	_boot_fixture(ENDGAME_V1)
	check(not app.save.is_new_profile, "recognised, not replaced")
	check(app.save.integrity_ok, "its checksum verifies")
	check_eq(int(app.save.state.version), SaveMigrations.CURRENT_VERSION, "and it is now the current version")
	check_eq(app.account.level(), int(before.account.level), "Player Level kept")
	check_eq(app.economy.balance(Economy.CREDITS), int(before.currencies.credits), "Credits kept")
	check_eq(app.economy.balance(Economy.CRYSTALS), int(before.currencies.crystals), "Crystals kept")
	var levels: Dictionary = before.meta_upgrades
	for id: String in levels:
		check_eq(app.meta.level(id), int(levels[id]), "%s keeps its level" % id)
	for category: String in before.unlocks:
		for id: String in before.unlocks[category]:
			check(app.arsenal.is_owned(category, id), "%s %s is still owned" % [category, id])
	check_eq(app.arsenal.selected_core(), "tempest", "selected core kept")
	check_eq(app.arsenal.selected_skin(), "amethyst", "selected skin kept")
	check_eq(app.campaign.highest_cleared(), 12, "sector progress kept")
	check_near(app.campaign.endless_best(), 1520.5, 0.01, "Overdrive best kept")
	check_eq(app.save.section("purchases").get("entitlements"), ["starter_pack"], "purchases kept")


func test_veterans_get_a_head_start_in_mastery() -> void:
	_boot_fixture(ENDGAME_V1)
	check_eq(app.mastery.rank("chain"), 2, "96 runs earn Rank 2 on a weapon they own")
	check_eq(app.mastery.xp("chain"), SaveMigrations.VETERAN_XP_CAP, "capped")
	check_eq(app.mastery.rank("pulse"), 2, "and on the starter weapons")
	check_eq(app.mastery.xp("railgun"), 0, "not on a weapon that did not exist")
	check_eq(app.meta.total_levels(), 97, "the old upgrades are all there")
	check(app.meta.total_max_levels() > 97, "and there is now more to research")
	check(not app.meta.any_affordable() == false, "with Credits that finally have somewhere to go")


func test_a_light_v1_save_gets_a_proportionate_start() -> void:
	_boot_fixture(PLAYTEST_V1)
	var runs := float((app.save.section("stats") as Dictionary).get("runs", 0.0))
	check_eq(app.mastery.xp("pulse"), mini(int(runs * SaveMigrations.VETERAN_XP_PER_RUN), SaveMigrations.VETERAN_XP_CAP), "XP follows the runs played")


func test_a_migrated_save_round_trips_and_does_not_migrate_twice() -> void:
	var backend := _boot_fixture(ENDGAME_V1)
	app.save.section("mastery")["chain"] = {"xp": 900, "kills": 5, "damage": 10.0, "runs": 2}
	app.save.flush()
	var text := backend.text
	var again := MemorySaveBackend.new()
	again.text = text
	app.boot(again)
	check_eq(int(app.save.state.version), SaveMigrations.CURRENT_VERSION, "still the current version")
	check_eq(app.mastery.xp("chain"), 900, "the head start is not applied a second time")


func test_a_run_in_progress_in_a_v1_save_is_still_paid_once() -> void:
	_boot_fixture(ENDGAME_V1)
	var credits := app.economy.balance(Economy.CREDITS)
	var summary := RunLedger.recover_pending(app)
	check(not summary.is_empty(), "the interrupted run is recovered")
	check(app.economy.balance(Economy.CREDITS) > credits, "and paid")
	check(app.mastery.xp("chain") > SaveMigrations.VETERAN_XP_CAP, "with Mastery from its old-format damage table")
	check(RunLedger.recover_pending(app).is_empty(), "and only once")


func test_new_profiles_start_on_the_current_version() -> void:
	fresh_profile()
	check_eq(int(app.save.state.version), SaveMigrations.CURRENT_VERSION, "version")
	check_eq(app.meta.active_doctrine(), "", "no doctrine")
	check_eq(app.mastery.xp("pulse"), 0, "no mastery")


# ------------------------------------------------------------------ research

func test_research_needs_its_level_and_prerequisites() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 1000000, "test")
	check(not app.meta.buy("r_siege"), "Player Level gate holds")
	app.account.add_xp(200000, "test")
	check(app.account.level() >= 9, "levelled past the gate")
	check(not app.meta.is_unlocked("r_siege"), "still locked by its prerequisite")
	check_eq(str(app.meta.missing_requirements("r_siege")[0].id), "m_damage", "and says which")
	check_eq(int(app.meta.missing_requirements("r_siege")[0].level), 3, "and what level")
	check(not app.meta.buy("r_siege"), "cannot be bought")
	app.meta.buy_many("m_damage", 3)
	check(app.meta.is_unlocked("r_siege"), "open once the prerequisite is met")
	check(app.meta.buy("r_siege"), "and can be bought")


func test_every_one_off_is_bought_once() -> void:
	_rich()
	check(app.meta.buy("r_evo_lab"), "bought")
	var credits := app.economy.balance(Economy.CREDITS)
	check(not app.meta.buy("r_evo_lab"), "not twice")
	check_eq(app.economy.balance(Economy.CREDITS), credits, "and the second attempt costs nothing")


func test_doctrines_only_count_while_selected() -> void:
	_rich()
	app.meta.buy("d_glass")
	check(app.meta.buy("d_bulwark"), "two doctrines owned")
	check_near(app.meta.mod_total("damage_pct"), 0.0, 0.001, "neither applies until selected")
	var config := RunConfig.from_profile(app)
	check(not config.base_mods.has("max_hp_pct"), "not in a run either")
	check(app.meta.select_doctrine("d_glass"), "select one")
	check_near(float(RunConfig.from_profile(app).base_mods.get("damage_pct", 0.0)), 0.3, 0.001, "its gain applies")
	check_near(float(RunConfig.from_profile(app).base_mods.get("max_hp_pct", 0.0)), -0.3, 0.001, "and so does its cost")
	check(app.meta.select_doctrine("d_bulwark"), "swap")
	check_near(float(RunConfig.from_profile(app).base_mods.get("damage_pct", 0.0)), -0.2, 0.001, "only one at a time")
	check(app.meta.select_doctrine(""), "clear")
	check_eq(app.meta.active_doctrine(), "", "cleared")
	check(not app.meta.select_doctrine("d_scavenger"), "an unowned doctrine cannot be selected")
	check(not app.meta.select_doctrine("m_damage"), "and neither can something that is not a doctrine")


func test_specialist_doctrine_really_means_two_weapons() -> void:
	_rich()
	app.meta.buy("d_specialist")
	app.meta.select_doctrine("d_specialist")
	var config := RunConfig.for_testing(app.data, 11)
	app.meta.collect_mods(config.base_mods)
	config.autopilot = false
	var arena := _arena(config)
	arena.grant_weapon("scatter", 1)
	check_eq(arena.build.weapon_order.size(), 2, "two weapons owned")
	for offer in arena.upgrades.roll(8):
		check(not (str(offer.kind) == UpgradeSystem.KIND_WEAPON and bool(offer.is_new)), "no third weapon is offered (%s)" % str(offer.id))
	_free(arena)


func test_fifth_hardpoint_and_auxiliary_bay_add_slots() -> void:
	var config := RunConfig.for_testing(app.data, 12)
	config.autopilot = false
	config.base_mods = {"run.weapon_slots": 1.0, "run.passive_slots": 1.0}
	fresh_profile()
	var arena := _arena(config)
	for weapon_id: String in ["scatter", "orbit", "nova"]:
		arena.grant_weapon(weapon_id, 1)
	var offered_new := false
	for attempt in 30:
		for offer in arena.upgrades.roll(3):
			offered_new = offered_new or (str(offer.kind) == UpgradeSystem.KIND_WEAPON and bool(offer.is_new))
	check(offered_new, "a fifth weapon can be offered")
	_free(arena)


func test_priority_signal_deals_a_fourth_card() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 13)
	config.autopilot = false
	config.base_mods = {"run.extra_choices": 1.0}
	var arena := _arena(config)
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	check_eq(arena.current_offers.size(), 4, "four cards")
	arena.reroll()
	check_eq(arena.current_offers.size(), 4, "still four after a reroll")
	_free(arena)


func test_awakening_gives_the_selected_core_its_augment() -> void:
	_rich()
	check(app.meta.buy("a_vanguard"), "Vanguard is owned by default")
	check(not app.meta.buy("a_tempest"), "an awakening needs its core")
	app.arsenal.grant(ArsenalService.CORES, "tempest", "test")
	check(app.meta.buy("a_tempest"), "once owned it can be researched")
	var config := RunConfig.from_profile(app)
	check_eq(config.start_augments, ["reactive"], "Vanguard starts with Reactive Shell")
	var arena := _arena(config)
	check(arena.build.augments.has("reactive"), "from the first second")
	check(arena.build.enabled("fx.reactive"), "and it works")
	for offer in arena.upgrades.roll(12):
		check(str(offer.id) != "reactive", "and it is not offered again")
	_free(arena)
	app.arsenal.select_core("tempest")
	check_eq(RunConfig.from_profile(app).start_augments, ["storm_crit"], "each core has its own")
	# Striker's was Seeker Rounds until that augment was removed.
	app.arsenal.grant(ArsenalService.CORES, "striker", "test")
	check(app.meta.buy("a_striker"), "Striker Awakening can be researched")
	app.arsenal.select_core("striker")
	config = RunConfig.from_profile(app)
	check_eq(config.start_augments, ["explosive_rounds"], "Striker starts with Explosive Rounds")
	arena = _arena(config)
	check(arena.build.enabled("fx.explosive"), "and it works from the first second")
	_free(arena)
	check(not app.data.augments().has("seeker"), "Seeker Rounds is gone from the augment pool")
	var seen: Array[String] = []
	for id: String in app.meta.ids():
		if GameData.text(app.meta.def(id), "kind") == "awakening":
			var augment := GameData.text(app.meta.def(id), "augment")
			check(not seen.has(augment), "%s gives an augment no other core starts with (%s)" % [id, augment])
			seen.append(augment)


func test_boss_damage_only_applies_to_bosses_and_elites() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 14)
	config.autopilot = false
	config.base_mods = {"boss_damage_pct": 0.3, "crit_chance": -1.0}
	var arena := _arena(config)
	arena.director.paused = true
	arena.enemies.clear()
	var type := arena.enemies.type_of("tank")
	var plain := arena.enemies.spawn(type, 200.0, 0.0)
	var elite := arena.enemies.spawn(type, -200.0, 0.0, true)
	var plain_before := arena.enemies.hp[plain]
	var elite_before := arena.enemies.hp[elite]
	arena.combat.hit(plain, 10.0, 0, 0.0, 0.0, false)
	arena.combat.hit(elite, 10.0, 0, 0.0, 0.0, false)
	check_near(plain_before - arena.enemies.hp[plain], 10.0, 0.01, "an ordinary enemy takes the normal hit")
	check_near(elite_before - arena.enemies.hp[elite], 13.0, 0.01, "an elite takes 30% more")
	_free(arena)


func test_executioner_finishes_the_weak_but_never_elites() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 15)
	config.autopilot = false
	config.base_mods = {"fx.execute": 0.1}
	var arena := _arena(config)
	arena.director.paused = true
	arena.enemies.clear()
	var type := arena.enemies.type_of("brute")
	var weak := arena.enemies.spawn(type, 200.0, 0.0)
	var elite := arena.enemies.spawn(type, -200.0, 0.0, true)
	arena.enemies.hp[weak] = arena.enemies.max_hp[weak] * 0.12
	arena.enemies.hp[elite] = arena.enemies.max_hp[elite] * 0.12
	var kills := arena.combat.kills
	arena.combat.hit(weak, arena.enemies.max_hp[weak] * 0.05, 0, 0.0, 0.0, false)
	check_eq(arena.combat.kills, kills + 1, "a hit that leaves it under 10% kills it")
	arena.combat.hit(elite, arena.enemies.max_hp[elite] * 0.05, 0, 0.0, 0.0, false)
	check_eq(arena.combat.kills, kills + 1, "an elite is not executed")
	_free(arena)


func test_last_stand_triggers_once() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 16)
	config.autopilot = false
	config.base_mods = {"fx.last_stand": 1.0}
	var arena := _arena(config)
	var player := arena.player
	player.hp = player.max_hp * 0.3
	player.take_hit(player.max_hp * 0.1, 0.0, 0.0)
	check(player.invulnerable_for > 1.5, "falling under 25% buys two seconds")
	player.invulnerable_for = 0.0
	player.hp = player.max_hp * 0.2
	player.take_hit(1.0, 0.0, 0.0)
	check(player.invulnerable_for < 1.0, "but only once per run")
	_free(arena)


func test_kinetic_buffer_absorbs_a_hit_then_recharges() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 17)
	config.autopilot = false
	config.base_mods = {"fx.buffer": 25.0}
	var arena := _arena(config)
	arena.director.paused = true
	var player := arena.player
	var health := player.hp
	check(not player.take_hit(20.0, 0.0, 0.0), "the first hit is absorbed")
	check_eq(player.hp, health, "no health lost")
	player.invulnerable_for = 0.0
	check(player.take_hit(20.0, 0.0, 0.0), "the next one lands")
	player.invulnerable_for = 0.0
	for s in int(26.0 / DT):
		player.invulnerable_for = 0.0
		arena.enemies.clear()
		arena.step(DT)
	health = player.hp
	check(not player.take_hit(20.0, 0.0, 0.0), "after 25 seconds it is back")
	check_eq(player.hp, health, "and absorbs again")
	_free(arena)


func test_ballistics_suite_adds_pierce_to_projectiles_only() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 18)
	config.autopilot = false
	config.base_mods = {"extra_pierce": 1.0}
	var arena := _arena(config)
	arena.director.paused = true
	var spawn_at := arena.enemies.spawn(arena.enemies.type_of("tank"), arena.player.x + 200.0, arena.player.y)
	check(spawn_at >= 0, "a target")
	for s in 40:
		arena.step(DT)
		if arena.projectiles.count > 0:
			break
	check(arena.projectiles.count > 0, "a bolt is in the air")
	if arena.projectiles.count > 0:
		check_eq(arena.projectiles.pierce[0], 1, "with one more pierce than level 1 has")
	_free(arena)


func test_mission_uplink_adds_a_daily_mission() -> void:
	_rich()
	var before: Array = app.save.section("missions").get("list", [])
	check_eq(before.size(), 3, "three by default")
	app.meta.buy("r_missions")
	app.save.section("missions")["day"] = -1
	app.missions.refresh()
	var after: Array = app.save.section("missions").get("list", [])
	check_eq(after.size(), 4, "four from the next day")


func test_bounty_network_pays_more_for_clearing() -> void:
	_rich()
	var result := {"run_id": "b", "mode": "sector", "tier": 3, "effective_tier": 3.0, "time": 300.0, "kills": 900, "cleared": true, "credit_gain": 1.0, "credits_picked": 0, "weapons": {}}
	var plain := int(RunLedger.compute(app, result).credits_clear)
	app.meta.buy_many("m_credits", 2)
	app.meta.buy("r_bounty")
	check_near(float(RunLedger.compute(app, result).credits_clear), float(plain) * 1.25, 2.0, "+25% per level on the clear bonus")
	result["cleared"] = false
	check_eq(int(RunLedger.compute(app, result).credits_clear), 0, "and nothing for not clearing")


# ------------------------------------------------------------------- economy

func test_overdrive_cannot_out_earn_the_campaign() -> void:
	fresh_profile()
	var deep := {"run_id": "o", "mode": "endless", "tier": 1, "effective_tier": 16.0, "time": 1200.0, "kills": 14000, "level": 40, "bosses": 3, "cleared": false, "credit_gain": 1.0, "credits_picked": 2000, "weapons": {}}
	app.save.section("sectors")["highest_cleared"] = 3
	var early := RunLedger.compute(app, deep)
	app.save.section("sectors")["highest_cleared"] = 20
	var late := RunLedger.compute(app, deep)
	check(int(early.credits) < int(late.credits), "pay follows what the player has cleared (%d vs %d)" % [int(early.credits), int(late.credits)])
	check(int(early.account_xp) < int(late.account_xp), "and so does Player XP")
	check_near(app.campaign.reward_tier(CampaignService.MODE_SECTOR, 9.0), 9.0, 0.001, "a sector pays its own tier")


func test_credits_have_somewhere_to_go_for_a_long_time() -> void:
	fresh_profile()
	var research := 0
	for id: String in app.meta.ids():
		for step in app.meta.max_level(id):
			research += app.meta.cost_at(id, step)
	var evolutions := 0
	for weapon_id: String in app.data.weapon_defs():
		for path: String in app.mastery.evolution_table(weapon_id):
			evolutions += GameData.integer(app.mastery.evolution_def(weapon_id, path), "cost")
	var skins := 0
	for id: String in app.data.skins():
		var unlock := GameData.dict(app.data.skins()[id], "unlock")
		if GameData.text(unlock, "type") == "level":
			skins += GameData.integer(unlock, "cost")
	check(research > 400000, "research is a long-term goal (%d Credits)" % research)
	check(evolutions > 100000, "evolutions are a real sink (%d Credits)" % evolutions)
	check(skins > 100000, "skins absorb Credits as well (%d Credits)" % skins)


func test_no_new_currency_appears() -> void:
	fresh_profile()
	check_eq(app.save.section("currencies").keys().size(), 2, "Credits and Crystals, and nothing else")
	for id: String in app.meta.ids():
		check(not app.meta.def(id).has("crystals"), "%s is not priced in Crystals" % id)


# --------------------------------------------------------------------- goals

func test_goals_exist_at_three_distances_for_a_new_player() -> void:
	fresh_profile()
	check(not app.goals.short_term().is_empty(), "something to buy")
	check(not app.goals.medium_term().is_empty(), "a weapon to rank up")
	check(not app.goals.long_term().is_empty(), "something big to aim for")


func test_the_long_goal_becomes_an_evolution_when_one_is_earned() -> void:
	_rich()
	app.meta.buy("r_evo_lab")
	app.save.section("mastery")["pulse"] = {"xp": 900, "kills": 0, "damage": 0.0, "runs": 1}
	var goal := app.goals.long_term()
	check_eq(str(goal.title), "EVOLVE: Storm Repeater", "the earned evolution is named")
	check(bool(goal.ready), "and marked ready when affordable")
	app.mastery.unlock_evolution("pulse", "repeater")
	check(str(app.goals.long_term().title) != "EVOLVE: Storm Repeater", "and it moves on once bought")


func test_a_finished_player_is_told_so_rather_than_left_blank() -> void:
	_rich()
	for core_id: String in app.data.cores():
		app.arsenal.grant(ArsenalService.CORES, core_id, "test")
	for pass_number in 3:
		for id: String in app.meta.ids():
			app.meta.buy_many(id, 999)
	check(app.goals.short_term().is_empty(), "nothing left to research")
	for id: String in app.data.weapon_defs():
		app.save.section("mastery")[id] = {"xp": 99999, "kills": 0, "damage": 0.0, "runs": 1}
	check(app.goals.medium_term().is_empty(), "nothing left to master")
