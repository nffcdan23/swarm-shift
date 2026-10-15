extends TestSuite
## The two levelling systems, Credits and permanent upgrades: what a run pays,
## that it is paid exactly once, that it survives a restart or a killed app,
## and that a profile saved by the build before this work still loads intact.

const FIXTURE := "res://tests/fixtures/profile_v1_before_playtest_update.save"
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


## A plausible finished run, shaped like Arena.build_result().
func _result(run_id: String, overrides: Dictionary = {}) -> Dictionary:
	var result := {
		"run_id": run_id, "mode": CampaignService.MODE_SECTOR, "tier": 1, "effective_tier": 1.0, "core": "vanguard",
		"time": 178.0, "kills": 1035, "elites": 2, "bosses": 0, "level": 16, "level_ups": 15, "damage": 52000.0,
		"credits_picked": 180, "credit_gain": 1.0, "cleared": false, "died": true, "abandoned": false,
		"synergies": [], "revives": 0, "weapons": {"pulse": 3}, "passives": {}, "augments": [], "damage_by_source": {"pulse": 52000.0}, "cycle": 0,
	}
	for key: String in overrides:
		result[key] = overrides[key]
	return result


# ------------------------------------------------------------ existing saves

func test_a_save_from_before_this_update_loads_intact() -> void:
	check(FileAccess.file_exists(FIXTURE), "the pre-update save fixture is present")
	var backend := MemorySaveBackend.new()
	backend.text = FileAccess.get_file_as_string(FIXTURE)
	app.boot(backend)
	check(not app.save.is_new_profile, "the old save is recognised, not replaced")
	check(app.save.integrity_ok, "its checksum still verifies")
	check_eq(app.account.level(), 8, "Player Level kept")
	check_eq(app.account.xp(), 80, "Player XP kept")
	check_eq(app.economy.balance(Economy.CREDITS), 4460, "Credits kept")
	check_eq(app.economy.balance(Economy.CRYSTALS), 370, "Crystals kept")
	var owned := {"m_damage": 3, "m_hp": 2, "m_crit": 1, "m_credits": 1, "m_reroll": 1}
	for id: String in owned:
		check_eq(app.meta.level(id), int(owned[id]), "upgrade %s kept at its level" % id)
		check(app.meta.is_unlocked(id), "upgrade %s is still usable" % id)
	check_eq(app.meta.total_levels(), 8, "no upgrade levels appeared or vanished")
	for id: String in ["m_firerate", "m_critdmg", "m_account_xp"]:
		check_eq(app.meta.level(id), 0, "new upgrade %s starts at zero" % id)
	check(app.arsenal.is_owned(ArsenalService.WEAPONS, "chain") and app.arsenal.is_owned(ArsenalService.WEAPONS, "missile"), "unlocked weapons kept")
	check(app.arsenal.is_owned(ArsenalService.CORES, "striker"), "unlocked core kept")
	check_eq(app.arsenal.selected_core(), "striker", "selected core kept")
	check_eq(app.arsenal.selected_skin(), "ember", "selected skin kept")
	check_eq(app.campaign.highest_cleared(), 2, "sector progress kept")
	check_near(app.campaign.best_time(1), 312.5, 0.01, "best times kept")
	check_eq(int(app.stats.value("kills")), 5321, "lifetime kills kept")
	check_eq(int(app.stats.value("runs")), 14, "lifetime runs kept")
	check_eq(int(app.stats.value("highest_run_level")), 27, "highest Run Level kept")
	check((app.save.state.get("synergies", []) as Array).has("tesla_storm"), "discovered synergies kept")
	check((app.save.section("achievements").get("claimed", []) as Array).has("first_blood"), "claimed achievements stay claimed")
	check_near(app.settings.number(SettingsService.MUSIC, 1.0), 0.4, 0.001, "settings kept")
	check(not app.settings.enabled(SettingsService.HAPTICS), "haptics preference kept")
	check((app.save.section("purchases").get("entitlements", []) as Array).has("remove_ads"), "purchases kept")

	# New sections are added underneath, with defaults.
	check(app.save.state.has("runs"), "the run ledger section was added")
	check(RunLedger.pending(app).is_empty(), "with nothing pending")
	check_eq(int(app.save.state.version), SaveMigrations.CURRENT_VERSION, "no schema bump was needed")

	# Its upgrades still reach a run, and it survives being saved by this build.
	var mods: Dictionary = {}
	app.meta.collect_mods(mods)
	check_near(float(mods.get("damage_pct", 0.0)), 0.12, 0.0001, "three levels of damage still count")
	var credits_before := app.economy.balance(Economy.CREDITS)
	var summary := RunLedger.settle(app, _result("old-save-run"))
	check(int(summary.credits) > 0 and int(summary.account_xp) > 0, "a run pays out on the old profile")
	app.save.flush()
	app.boot(backend)
	check(app.save.integrity_ok, "re-saved by this build and reloaded cleanly")
	check_eq(app.economy.balance(Economy.CREDITS) - credits_before, int(summary.credits) + _level_credits(summary), "the payout persisted")
	check_eq(app.meta.total_levels(), 8, "upgrade levels unchanged after the round trip")


func _level_credits(summary: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in summary.get("level_ups", []):
		total += int((entry.rewards as Dictionary).get("credits", 0))
	return total


# --------------------------------------------------------- the Player Level

func test_player_xp_comes_from_every_listed_source() -> void:
	fresh_profile()
	var died := RunLedger.compute(app, _result("a"))
	var parts: Dictionary = died.xp_parts
	check(int(parts.time) > 0, "time survived pays Player XP (%d)" % int(parts.time))
	check(int(parts.kills) > 0, "enemies defeated pay Player XP (%d)" % int(parts.kills))
	check(int(parts.level) > 0, "Run Level reached pays Player XP (%d)" % int(parts.level))
	check_eq(int(parts.bosses), 0, "no boss, no boss XP")
	check_eq(int(parts.clear), 0, "no clear, no sector XP")
	check_eq(int(died.account_xp), int(parts.time) + int(parts.kills) + int(parts.level), "the parts add up to the total")

	var cleared := RunLedger.compute(app, _result("b", {"cleared": true, "died": false, "bosses": 1, "time": 320.0}))
	check(int(cleared.xp_parts.bosses) > 0, "a boss pays Player XP")
	check(int(cleared.xp_parts.clear) > 0, "a cleared sector pays Player XP")
	check(int(cleared.account_xp) > int(died.account_xp), "a clear is worth more than a death")

	# Missions and achievements pay it too.
	var before := app.account.xp() + app.account.level() * 100000
	app.economy.grant_bundle({"account_xp": 40}, "mission")
	check(app.account.xp() + app.account.level() * 100000 > before, "a mission reward adds Player XP")
	app.stats.add("kills", 1.0)
	before = app.account.xp() + app.account.level() * 100000
	check(app.achievements.claim("first_blood") > 0, "an achievement can be claimed")
	check(app.account.xp() + app.account.level() * 100000 > before, "claiming it adds Player XP")
	check_eq(app.achievements.claim("first_blood"), 0, "and only once")


func test_player_level_is_permanent_and_run_level_is_not() -> void:
	var backend := fresh_profile()
	var summary := RunLedger.settle(app, _result("first"))
	check(app.account.level() >= 2, "a three-minute run lifts a new player past level 1 (level %d)" % app.account.level())
	check_eq(int(summary.level_before), 1, "the summary remembers where the bar started")
	check_eq(int(summary.level_after), app.account.level(), "and where it ended")
	check((summary.level_ups as Array).size() == app.account.level() - 1, "one entry per level gained")
	var level := app.account.level()
	var xp := app.account.xp()

	# Kill the app, start it again: the Player Level is exactly where it was.
	app.boot(backend)
	check_eq(app.account.level(), level, "Player Level survives a restart")
	check_eq(app.account.xp(), xp, "Player XP survives a restart")

	# A new run starts its own Run Level at 1 whatever the Player Level is.
	var arena := _arena(RunConfig.from_profile(app))
	check_eq(arena.level, 1, "every run starts at Run Level 1")
	arena.add_xp(arena.xp_needed * 3.0)
	check(arena.level > 1, "green energy raises the Run Level")
	check_eq(app.account.level(), level, "and leaves the Player Level alone")
	_free(arena)
	var second := _arena(RunConfig.from_profile(app))
	check_eq(second.level, 1, "the next run starts at Run Level 1 again")
	_free(second)


func test_player_levels_unlock_content() -> void:
	fresh_profile()
	check(not app.meta.is_unlocked("m_firerate"), "Rapid Cyclers is locked at Player Level 1")
	app.economy.grant(Economy.CREDITS, 100000, "test")
	check(not app.meta.buy("m_firerate"), "and cannot be bought, however rich")
	var ahead := app.account.next_unlock()
	check_eq(int(ahead.level), 2, "the next unlock is at Player Level 2")
	check((ahead.names as Array).size() >= 2, "and names what it opens (%s)" % str(ahead.names))
	var road := app.account.roadmap(20)
	check(road.size() >= 6, "the roadmap lists the unlocks ahead (%d steps)" % road.size())
	var last := 1
	for step in road:
		check(int(step.level) > last, "roadmap is in level order")
		last = int(step.level)
		check(not (step.names as Array).is_empty(), "every step unlocks something")

	app.account.add_xp(app.account.xp_needed(1) + app.account.xp_needed(2), "test")
	check_eq(app.account.level(), 3, "two levels gained")
	check(app.meta.is_unlocked("m_firerate"), "Rapid Cyclers opens at Player Level 3")
	check(app.meta.buy("m_firerate"), "and can now be bought")
	check(bool(app.arsenal.unlock_info(ArsenalService.WEAPONS, "missile").level_met), "Seeker Missiles are available at Player Level 3")
	check(not bool(app.arsenal.unlock_info(ArsenalService.WEAPONS, "singularity").level_met), "Singularity is still gated")
	var rewards := app.account.level_rewards(3)
	check((rewards.unlocks as Array).has("Rapid Cyclers"), "the level-3 reward names the upgrade it opens")


# ------------------------------------------------------------------ banking

func test_a_run_is_banked_exactly_once() -> void:
	fresh_profile()
	var result := _result("run-1")
	var first := RunLedger.settle(app, result)
	check(not bool(first.duplicate), "the first settlement is the real one")
	var credits := app.economy.balance(Economy.CREDITS)
	var level := app.account.level()
	var xp := app.account.xp()
	var runs := int(app.stats.value("runs"))
	check(credits > 0, "Credits were banked (%d)" % credits)
	check_eq(int(first.credits), int(first.credits_collected) + int(first.credits_survival) + int(first.credits_clear), "the Credit parts add up")

	for attempt in 3:
		var again := RunLedger.settle(app, result)
		check(bool(again.duplicate), "attempt %d to claim it again is recognised" % (attempt + 2))
		check_eq(int(again.credits), int(first.credits), "and reports the same amount")
	check_eq(app.economy.balance(Economy.CREDITS), credits, "no extra Credits")
	check_eq(app.account.level(), level, "no extra levels")
	check_eq(app.account.xp(), xp, "no extra Player XP")
	check_eq(int(app.stats.value("runs")), runs, "the run is counted once")

	# The rewarded-ad doubling is once per run too.
	check_eq(RunLedger.double_credits(app, first), int(first.credits), "doubling pays the run's Credits again")
	check_eq(RunLedger.double_credits(app, first), 0, "but not twice")
	check_eq(RunLedger.double_credits(app, RunLedger.settle(app, result)), 0, "nor through a second copy of the summary")
	check_eq(app.economy.balance(Economy.CREDITS), credits + int(first.credits), "exactly one doubling was paid")

	var other := RunLedger.settle(app, _result("run-2"))
	check(not bool(other.duplicate), "a different run pays normally")
	check(app.economy.balance(Economy.CREDITS) > credits + int(first.credits), "and its Credits arrive")


func test_death_completion_and_leaving_all_bank() -> void:
	for outcome: String in ["died", "cleared", "abandoned"]:
		var backend := fresh_profile()
		var result := _result("run-" + outcome, {
			"died": outcome == "died", "cleared": outcome == "cleared", "abandoned": outcome == "abandoned",
			"bosses": 1 if outcome == "cleared" else 0})
		var preview := RunLedger.compute(app, result)
		var summary := RunLedger.settle(app, result)
		check_eq(int(summary.credits), int(preview.credits), "%s: banks what the preview promised" % outcome)
		check(int(summary.credits) >= 180, "%s: everything picked up in the run is kept (%d)" % [outcome, int(summary.credits)])
		check_eq(app.economy.balance(Economy.CREDITS), int(summary.credits) + _level_credits(summary), "%s: the balance is the payout" % outcome)
		app.boot(backend)
		check_eq(app.economy.balance(Economy.CREDITS), int(summary.credits) + _level_credits(summary), "%s: and it is still there after a restart" % outcome)
		check(RunLedger.is_settled(app, "run-" + outcome), "%s: the run is remembered as paid after a restart" % outcome)
		check(bool(RunLedger.settle(app, result).duplicate), "%s: so it cannot be claimed again after a restart" % outcome)
	fresh_profile()
	var died := RunLedger.compute(app, _result("x"))
	var left := RunLedger.compute(app, _result("x", {"died": false, "abandoned": true}))
	check_eq(int(left.credits), int(died.credits), "leaving a run early pays the same Credits as dying at that moment")
	check_eq(int(left.account_xp), int(died.account_xp), "and the same Player XP")


func test_an_interrupted_run_is_recovered_at_next_launch() -> void:
	var backend := fresh_profile()
	var arena := _arena(RunConfig.for_testing(app.data, 12))
	for i in int(60.0 / DT):
		arena.step(DT)
	check(arena.combat.kills > 20, "a run is under way (%d kills)" % arena.combat.kills)
	arena.add_credits(40.0)
	var snapshot := arena.build_result(false, false, true)
	RunLedger.checkpoint(app, snapshot, true)
	check(not RunLedger.pending(app).is_empty(), "the run in progress is checkpointed")
	check_eq(app.economy.balance(Economy.CREDITS), 0, "a checkpoint pays nothing by itself")
	_free(arena)

	# The app is killed here - no results screen, no settle - and launched again.
	app.boot(backend)
	check(not RunLedger.pending(app).is_empty(), "the checkpoint survived the kill")
	var recovered := RunLedger.recover_pending(app)
	check(bool(recovered.get("recovered", false)), "the next launch recovers the run")
	check(int(recovered.credits) >= 40, "its Credits are banked (%d)" % int(recovered.credits))
	check(int(recovered.account_xp) > 0, "its Player XP is banked (%d)" % int(recovered.account_xp))
	check_eq(app.economy.balance(Economy.CREDITS), int(recovered.credits) + _level_credits(recovered), "the balance shows it")
	check_eq(int(app.stats.value("runs")), 1, "and it counts as a run")
	check(RunLedger.pending(app).is_empty(), "nothing is left pending")
	check(RunLedger.recover_pending(app).is_empty(), "so it cannot be recovered twice")
	app.boot(backend)
	check(RunLedger.recover_pending(app).is_empty(), "not even after another restart")

	# A run that does finish normally leaves nothing to recover.
	RunLedger.checkpoint(app, _result("finishes"), true)
	var credits := app.economy.balance(Economy.CREDITS)
	var summary := RunLedger.settle(app, _result("finishes"))
	check(RunLedger.pending(app).is_empty(), "settling a run clears its checkpoint")
	RunLedger.checkpoint(app, _result("finishes"), true)
	check(RunLedger.pending(app).is_empty(), "and a late checkpoint for a paid run is ignored")
	check(RunLedger.recover_pending(app).is_empty(), "so nothing is paid a second time")
	check_eq(app.economy.balance(Economy.CREDITS), credits + int(summary.credits) + _level_credits(summary), "the finished run was paid once")


# ------------------------------------------------------------------ credits

func test_enemies_drop_gold_credits_and_green_energy() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 44)
	config.autopilot = false
	var arena := _arena(config)
	# Kill a field of each enemy type far from the player: nothing is collected.
	var far_x := arena.player.x + 4000.0
	var expected := 0.0
	var dropped_xp := 0.0
	for type_id: String in ["swarmer", "brute", "dasher", "shooter", "splitter", "tank", "weaver", "mortar", "bomber"]:
		var def := GameData.dict(app.data.enemy_types(), type_id)
		for k in 300:
			var i := arena.enemies.spawn(arena.enemies.type_of(type_id), far_x + float(k % 30) * 40.0, arena.player.y + float(k / 30) * 40.0)
			dropped_xp += arena.enemies.xp[i]
			arena.enemies.hurt(i, 1.0e9)
			if k % 60 == 59:
				arena.enemies.sweep()
		arena.enemies.sweep()
		expected += 300.0 * GameData.num(def, "credit_chance") * GameData.num(def, "credit_value")
	var on_field := arena.pickups.field_credits()
	check(expected > 500.0, "the table asks for a meaningful number of Credits (%.0f)" % expected)
	check(absf(on_field - expected) < expected * 0.25, "enemies dropped about what the table says (%.0f of %.0f)" % [on_field, expected])
	check_near(arena.pickups.dropped_xp, dropped_xp, 1.0, "and every one dropped its energy")

	var kinds := {}
	var cells := {}
	for i in arena.pickups.count:
		kinds[arena.pickups.kind[i]] = int(kinds.get(arena.pickups.kind[i], 0)) + 1
		cells[arena.pickups.kind[i]] = arena.pickups.cell[i] if arena.pickups.kind[i] == PickupSystem.KIND_CREDIT else cells.get(arena.pickups.kind[i], -1.0)
	check(int(kinds.get(PickupSystem.KIND_CREDIT, 0)) > 0, "Credit pickups are on the field")
	check(int(kinds.get(PickupSystem.KIND_XP, 0)) > 0, "energy crystals are on the field")
	var credit_cell := arena.gfx.cell("credit")
	for gem: String in ["gem_s", "gem_m", "gem_l"]:
		check(arena.gfx.cell(gem) != credit_cell, "%s uses different art from a Credit" % gem)
	check_eq(float(cells[PickupSystem.KIND_CREDIT]), credit_cell, "Credits use the gold coin sprite")
	_free(arena)


func test_collected_credits_reach_the_bank() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 1000, "test")
	app.meta.buy("m_credits")
	var start := app.economy.balance(Economy.CREDITS)
	var config := RunConfig.from_profile(app)
	var arena := _arena(config)
	check_near(arena.player.credit_gain, 1.06, 0.0001, "Salvage Protocol raises Credits earned in the run")
	var level := arena.level
	for k in 20:
		arena.pickups.drop(PickupSystem.KIND_CREDIT, arena.player.x + 30.0, arena.player.y, 5.0)
	for i in 30:
		arena.step(DT)
	check_near(arena.credits, 106.0, 0.01, "twenty 5-Credit pickups were collected, with the bonus")
	check_eq(arena.level, level, "collecting Credits does not move the Run Level")
	check_near(arena.pickups.collected_xp, 0.0, 0.001, "nor count as energy")
	arena.abandon()
	var result := arena.build_result(false, false, true)
	check_eq(int(result.credits_picked), 106, "the result carries the Credits collected")
	var summary := RunLedger.settle(app, result)
	check_eq(int(summary.credits_collected), 106, "the ledger banks all of them")
	check_eq(app.economy.balance(Economy.CREDITS), start + int(summary.credits) + _level_credits(summary), "and they are in the balance")
	_free(arena)


# ------------------------------------------------------- permanent upgrades

func test_upgrades_cover_every_category_and_stat() -> void:
	fresh_profile()
	check_eq(app.meta.categories(), ["offence", "defence", "utility", "economy"], "four categories, in order")
	var wanted := {
		"offence": ["damage_pct", "fire_rate_pct", "crit_chance", "crit_mult"],
		"defence": ["max_hp_pct", "armor", "regen"],
		"utility": ["move_speed_pct", "pickup_radius_pct", "xp_gain_pct"],
		"economy": ["credit_gain_pct", "account_xp_pct"],
	}
	for category: String in wanted:
		var found: Array = []
		for id in app.meta.ids_in(category):
			found.append_array(GameData.dict(app.meta.def(id), "mods").keys())
		for key: String in wanted[category]:
			check(found.has(key), "%s has an upgrade for %s" % [category.to_upper(), key])
	var seen := 0
	for category: String in app.meta.categories():
		seen += app.meta.ids_in(category).size()
	check_eq(seen, app.meta.ids().size(), "every upgrade belongs to a category")

	for id: String in app.meta.ids():
		var def := app.meta.def(id)
		check(not GameData.text(def, "name").is_empty(), "%s has a name" % id)
		check(not GameData.text(def, "desc").is_empty(), "%s has a description" % id)
		check(not app.meta.stat_label(id).is_empty(), "%s names the stat it changes" % id)
		check_eq(GameData.dict(def, "mods").size(), 1, "%s changes exactly one thing" % id)
		check(app.meta.max_level(id) >= 1, "%s has a maximum level" % id)
		check_eq(app.meta.effect_text(id, 0), "+0%" if GameData.text(def, "format") == "percent" else "+0", "%s shows no effect at level 0" % id)
		check(app.meta.effect_text(id, 1) != app.meta.effect_text(id, 0), "%s shows what the next level gives (%s)" % [id, app.meta.effect_text(id, 1)])
		var previous := 0
		for step in app.meta.max_level(id):
			var price := app.meta.cost_at(id, step)
			check(price >= previous and price > 0, "%s: level %d costs at least as much as the one before (%d)" % [id, step + 1, price])
			previous = price
	check_eq(app.meta.effect_text("m_damage", 3), "+12%", "three levels of +4% damage read as +12%")
	check_eq(app.meta.effect_text("m_regen", 2), "+0.4", "two levels of +0.2 regeneration read as +0.4")
	check_eq(app.meta.effect_text("m_armor", 3), "+3", "three armour reads as +3")


func test_buying_one_or_many_upgrade_levels() -> void:
	var backend := fresh_profile()
	check(not app.meta.buy("m_damage"), "cannot buy with no Credits")
	check_eq(app.meta.affordable_count("m_damage", 5), 0, "nothing is affordable")
	var first := app.meta.cost("m_damage")
	app.economy.grant(Economy.CREDITS, first, "test")
	check(app.meta.buy("m_damage"), "one level bought for exactly its price")
	check_eq(app.economy.balance(Economy.CREDITS), 0, "the price was taken")
	check_eq(app.meta.level("m_damage"), 1, "the level went up")
	check(app.meta.cost("m_damage") > first, "the next level costs more")

	# Five at once: all or as many as the balance covers, charged exactly.
	var five := app.meta.cost_for("m_damage", 5)
	var manual := 0
	for step in range(1, 6):
		manual += app.meta.cost_at("m_damage", step)
	check_eq(five, manual, "the price of five levels is the sum of each")
	app.economy.grant(Economy.CREDITS, five + 7, "test")
	check_eq(app.meta.affordable_count("m_damage", 5), 5, "five are affordable")
	check_eq(app.meta.buy_many("m_damage", 5), 5, "five bought in one go")
	check_eq(app.meta.level("m_damage"), 6, "now level 6")
	check_eq(app.economy.balance(Economy.CREDITS), 7, "charged exactly the sum")

	var two := app.meta.cost_for("m_damage", 2)
	app.economy.grant(Economy.CREDITS, two - 7 + 3, "test")
	check_eq(app.meta.buy_many("m_damage", 99), 2, "MAX buys only what the balance covers")
	check_eq(app.meta.level("m_damage"), 8, "now level 8")
	check_eq(app.economy.balance(Economy.CREDITS), 3, "and never overspends")

	app.economy.grant(Economy.CREDITS, 10000000, "test")
	check_eq(app.meta.buy_many("m_damage", 99), 2, "MAX stops at the cap")
	check(app.meta.is_maxed("m_damage"), "the upgrade is maxed")
	check_eq(app.meta.cost("m_damage"), 0, "a maxed upgrade has no price")
	check_eq(app.meta.buy_many("m_damage", 5), 0, "and cannot be bought again")
	var balance := app.economy.balance(Economy.CREDITS)
	check(not app.meta.buy("m_damage"), "a single purchase is refused too")
	check_eq(app.economy.balance(Economy.CREDITS), balance, "and costs nothing")

	app.save.flush()
	app.boot(backend)
	check_eq(app.meta.level("m_damage"), 10, "upgrade levels survive a restart")
	check_eq(app.economy.balance(Economy.CREDITS), balance, "and so does the balance")
	check_eq(int(app.stats.value("meta_purchases")), 10, "each level counted as a purchase")


func test_new_upgrades_change_the_run_and_the_payout() -> void:
	fresh_profile()
	app.account.add_xp(200000, "test")
	app.economy.grant(Economy.CREDITS, 10000000, "test")
	var plain := RunLedger.compute(app, _result("x"))
	check_eq(app.meta.buy_many("m_firerate", 5), 5, "five levels of attack speed")
	check_eq(app.meta.buy_many("m_critdmg", 4), 4, "four levels of critical damage")
	check_eq(app.meta.buy_many("m_account_xp", 10), 10, "ten levels of Player XP earned")
	var arena := _arena(RunConfig.from_profile(app))
	check_near(arena.player.fire_rate, 1.15, 0.0001, "attack speed reaches the run (+15%)")
	check_near(arena.player.crit_mult, 1.8, 0.0001, "critical damage reaches the run (1.6 -> 1.8)")
	_free(arena)
	var boosted := RunLedger.compute(app, _result("x"))
	check_near(float(boosted.account_xp), float(plain.account_xp) * 1.5, 3.0, "Player XP earned is half as much again (%d vs %d)" % [int(boosted.account_xp), int(plain.account_xp)])
	check_eq(int(boosted.credits), int(plain.credits), "and Credits are untouched by it")


func test_the_lobby_always_has_a_next_upgrade_to_aim_for() -> void:
	fresh_profile()
	var goal := app.meta.next_goal()
	check(not str(goal.id).is_empty(), "a new player is shown a first upgrade (%s)" % str(goal.get("name", "")))
	check_near(float(goal.progress), 0.0, 0.001, "with no progress towards it yet")
	check(app.meta.is_unlocked(str(goal.id)), "and it is one they are allowed to buy")
	app.economy.grant(Economy.CREDITS, int(goal.cost) / 2, "test")
	check_near(float(app.meta.next_goal().progress), 0.5, 0.02, "half its price is half the bar")
	app.economy.grant(Economy.CREDITS, int(goal.cost), "test")
	check(bool(app.meta.next_goal().affordable), "enough Credits marks it ready")
	app.account.add_xp(10000000, "test")
	app.economy.grant(Economy.CREDITS, 100000000, "test")
	for id: String in app.meta.ids():
		app.meta.buy_many(id, 999)
	check_eq(app.meta.total_levels(), app.meta.total_max_levels(), "everything can be bought out")
	check(str(app.meta.next_goal().id).is_empty(), "and then there is no next goal")
