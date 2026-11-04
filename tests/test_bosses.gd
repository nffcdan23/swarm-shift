extends TestSuite
## One boss per sector: twenty different bosses, each with its own look,
## attacks and phases, harder further in, every fight playable to the end, and
## a bounty and first-clear Crystals for beating them.

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


func _config(tier: int, run_seed: int = 61) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.tier = tier
	config.base_mods = {"max_hp": 1000000.0, "xp_gain_pct": -1.0}
	return config


func _bosses() -> Dictionary:
	return GameData.dict(app.data.stages, "bosses")


func _result(run_id: String, tier: int, cleared: bool, boss_ids: Array) -> Dictionary:
	return {"run_id": run_id, "mode": CampaignService.MODE_SECTOR, "tier": tier, "effective_tier": tier, "core": "default",
		"time": 320.0, "kills": 1500, "level": 30, "bosses": boss_ids.size(), "credits_picked": 500,
		"cleared": cleared, "died": not cleared, "abandoned": false, "boss_ids": boss_ids}


# ------------------------------------------------------------------- roster

func test_every_sector_has_its_own_boss() -> void:
	fresh_profile()
	var sectors := GameData.integer(app.data.stages, "sector_count", 20)
	var seen := {}
	var looks := {}
	for tier in range(1, sectors + 1):
		var id := app.campaign.boss_for(tier)
		check(_bosses().has(id), "sector %d has a boss in the data (%s)" % [tier, id])
		check(not seen.has(id), "sector %d's boss (%s) is not used by another sector" % [tier, id])
		seen[id] = tier
		var boss := app.campaign.boss_def(id)
		var look := GameData.dict(boss, "look")
		var key := "%s/%s/%s/%s" % [look.get("shell"), look.get("core"), look.get("ring"), boss.get("color")]
		check(not looks.has(key), "sector %d's boss looks unlike every other (%s)" % [tier, key])
		looks[key] = true
		check(not GameData.text(boss, "title").is_empty(), "%s has a title" % id)
	check_eq(seen.size(), sectors, "%d sectors, %d different bosses" % [sectors, sectors])
	check_eq(app.campaign.boss_for(20), "overseer", "the Overseer is the last of them")
	check_eq(app.campaign.boss_for(21), app.campaign.boss_for(1), "past the last sector the list wraps")


func test_later_bosses_are_harder() -> void:
	fresh_profile()
	var last_hp := 0.0
	var last_phases := 0
	var last_attacks := 0
	for tier in range(1, 21):
		var boss := app.campaign.boss_def(app.campaign.boss_for(tier))
		var hp := GameData.num(boss, "hp") * float(app.campaign.scaling(float(tier)).boss_hp)
		check(hp > last_hp, "Sector %d's boss has more health than Sector %d's (%d)" % [tier, tier - 1, int(hp)])
		last_hp = hp
		var phases := GameData.list(boss, "phases").size()
		check(phases >= last_phases, "and at least as many phases (%d)" % phases)
		last_phases = phases
		var attacks := GameData.dict(boss, "attacks").size()
		if tier % 5 == 1:
			# Each band of five starts again from a family's simplest member,
			# but never below the band before it.
			check(attacks >= 3, "Sector %d's boss has at least three attacks (%d)" % [tier, attacks])
		last_attacks = attacks
	check(last_phases >= 4, "the last bosses fight in four phases")
	check_eq(last_attacks, Boss.ATTACK_TYPES.size(), "and the Overseer knows every attack there is")
	var first := GameData.list(app.campaign.boss_def(app.campaign.boss_for(1)), "phases").size()
	check_eq(first, 2, "the first boss is a gentle two-phase fight")


func test_every_attack_type_is_used_by_some_boss() -> void:
	fresh_profile()
	var types := {}
	for id: String in _bosses():
		for key: String in GameData.dict(_bosses()[id], "attacks"):
			types[GameData.text(GameData.dict(GameData.dict(_bosses()[id], "attacks"), key), "type", key)] = true
	for kind: String in Boss.ATTACK_TYPES:
		check(types.has(kind), "some boss uses '%s'" % kind)


# -------------------------------------------------------------------- fights

## Fights a boss with an invulnerable player, burning its health down in steps
## so every phase gets time, and checks the fight stays sane throughout.
func _fight(tier: int) -> Dictionary:
	var arena := _arena(_config(tier, 60 + tier))
	arena.director.paused = true
	arena.player.invulnerable_for = 100000.0
	arena.spawn_boss(app.campaign.boss_for(tier), 1.0, 1.0)
	var boss := arena.boss
	var phases := GameData.list(app.campaign.boss_def(boss.boss_id), "phases")
	var problems := PackedStringArray()
	var peak_bullets := 0
	var peak_hazards := 0
	var shortest_warning := INF
	var seconds_per_phase := 32.0
	for p in phases.size():
		var idx := arena.enemies.find_id(boss.enemy_id)
		var above := GameData.num(phases[p], "hp_above")
		arena.enemies.hp[idx] = arena.enemies.max_hp[idx] * (above + 0.02)
		for s in int(seconds_per_phase / DT):
			arena.player.invulnerable_for = 100000.0
			# The player's weapons are firing too: hold the boss in this phase.
			idx = arena.enemies.find_id(boss.enemy_id)
			if idx >= 0:
				arena.enemies.hp[idx] = maxf(arena.enemies.hp[idx], arena.enemies.max_hp[idx] * (above + 0.02))
			arena.step(DT)
			peak_bullets = maxi(peak_bullets, arena.bullets.count)
			peak_hazards = maxi(peak_hazards, arena.hazards.count)
			if not (is_finite(boss.x) and is_finite(boss.y)):
				problems.append("position not finite")
				break
			if Vector2(boss.x, boss.y).distance_to(boss.centre) > boss.arena_radius + 1.0:
				problems.append("left its arena at %.1f s" % arena.time)
				break
		if boss.phase != p:
			problems.append("phase %d not reached (at %d)" % [p + 1, boss.phase])
	shortest_warning = arena.hazards.shortest_warning
	var used := boss.used.duplicate()
	_free(arena)
	return {"problems": problems, "used": used, "bullets": peak_bullets, "hazards": peak_hazards, "warning": shortest_warning,
		"phases": phases.size()}


func test_every_boss_fight_runs_every_attack_and_phase() -> void:
	fresh_profile()
	var capacity := 0
	var probe := _arena(_config(1))
	capacity = probe.bullets.capacity()
	_free(probe)
	for tier in range(1, 21):
		var id := app.campaign.boss_for(tier)
		var fight := _fight(tier)
		for problem: String in fight.problems:
			check(false, "%s: %s" % [id, problem])
		var attacks: Dictionary = GameData.dict(app.campaign.boss_def(id), "attacks")
		var unused := PackedStringArray()
		for key: String in attacks:
			if not (fight.used as Dictionary).has(key):
				unused.append(key)
		check(unused.is_empty(), "%s used every attack it has (unused: %s)" % [id, ", ".join(unused)])
		check(int(fight.bullets) < capacity, "%s never fills the bullet pool (peak %d of %d)" % [id, fight.bullets, capacity])
		check(float(fight.warning) >= 0.5 or float(fight.warning) == INF, "%s: every ground blast is warned at least 0.5 s ahead (%.2f)" % [id, fight.warning])


func test_new_attacks_are_telegraphed_and_aimed() -> void:
	fresh_profile()
	# Blink: the landing spot is marked before it arrives, and it lands there.
	var arena := _arena(_config(3))
	arena.director.paused = true
	arena.player.invulnerable_for = 100000.0
	arena.spawn_boss("phase_wraith", 1.0, 1.0)
	var boss := arena.boss
	var guard := 0
	while not boss.used.has("blink") and guard < 1800:
		arena.step(DT)
		guard += 1
	check(boss.used.has("blink"), "the Phase Wraith blinks")
	check(arena.hazards.count > 0, "its landing is marked on the ground first")
	var target: Vector2 = boss._blink_to
	check(Vector2(boss.x, boss.y).distance_to(target) > 1.0, "it has not moved yet while the mark fills")
	var start := Vector2(boss.x, boss.y)
	for s in int(1.5 / DT):
		arena.step(DT)
		if Vector2(boss.x, boss.y).distance_to(start) > 20.0:
			break
	check(Vector2(boss.x, boss.y).distance_to(target) < 3.0, "then it lands on the mark (%.1f away)" % Vector2(boss.x, boss.y).distance_to(target))
	_free(arena)

	# Fan: bullets are aimed at the player.
	arena = _arena(_config(4))
	arena.director.paused = true
	arena.player.invulnerable_for = 100000.0
	arena.spawn_boss("broodmother", 1.0, 1.0)
	boss = arena.boss
	guard = 0
	while boss._state != Boss.S.FAN and guard < 1800:
		arena.step(DT)
		guard += 1
	check_eq(boss._state, Boss.S.FAN, "the Broodmother winds up an aimed fan")
	arena.bullets.count = 0
	arena.step(DT)
	check(arena.bullets.count > 0, "and fires it")
	var to_player := Vector2(arena.player.x - boss.x, arena.player.y - boss.y).normalized()
	var mean := Vector2.ZERO
	for i in arena.bullets.count:
		mean += Vector2(arena.bullets.vx[i], arena.bullets.vy[i]).normalized()
	check(mean.normalized().dot(to_player) > 0.95, "centred on the player")
	_free(arena)

	# Spiral: a stream of bullets that turns.
	arena = _arena(_config(6))
	arena.director.paused = true
	arena.player.invulnerable_for = 100000.0
	arena.spawn_boss("lattice", 1.0, 1.0)
	boss = arena.boss
	guard = 0
	while boss._state != Boss.S.SPIRAL and guard < 1800:
		arena.step(DT)
		guard += 1
	check_eq(boss._state, Boss.S.SPIRAL, "the Lattice spins up a spiral")
	var before: float = boss._burst_angle
	var spawned := arena.bullets.spawned_total
	for s in int(1.0 / DT):
		arena.step(DT)
	check(arena.bullets.spawned_total - spawned >= 15, "which keeps firing (%d bullets a second)" % (arena.bullets.spawned_total - spawned))
	check(absf(boss._burst_angle - before) > 1.0, "and turns as it fires")
	_free(arena)


func test_each_sector_spawns_its_own_boss_and_overdrive_meets_them_in_order() -> void:
	fresh_profile()
	for tier in [1, 8, 20]:
		var arena := _arena(_config(tier))
		arena.director.timeline_time = arena.director.boss_time() - 0.2
		for s in 10:
			arena.step(DT)
		check(arena.boss.active, "Sector %d's boss arrives" % tier)
		check_eq(arena.boss.boss_id, app.campaign.boss_for(tier), "and it is Sector %d's own" % tier)
		check_eq(arena.boss.display_name, GameData.text(app.campaign.boss_def(app.campaign.boss_for(tier)), "name"), "with its name")
		check_eq(arena.boss.color, GameData.color(app.campaign.boss_def(app.campaign.boss_for(tier)), "color", Color.WHITE), "and its colour")
		var breaks := PackedFloat32Array()
		for phase: Dictionary in GameData.list(app.campaign.boss_def(app.campaign.boss_for(tier)), "phases"):
			if GameData.num(phase, "hp_above") > 0.0:
				breaks.append(GameData.num(phase, "hp_above"))
		check_eq(arena.boss.phase_marks(), breaks, "the health bar breaks where its own phases do")
		_free(arena)
	var config := _config(1)
	config.mode = CampaignService.MODE_ENDLESS
	var endless := _arena(config)
	check_eq(endless.director.boss_id(), app.campaign.boss_for(1), "Overdrive's first boss is Sector 1's")
	endless.director.begin_next_cycle()
	check_eq(endless.director.boss_id(), app.campaign.boss_for(2), "the next cycle brings Sector 2's")
	_free(endless)


# ------------------------------------------------------------------- rewards

func test_a_cleared_sector_pays_its_boss_bounty() -> void:
	fresh_profile()
	app.save.section("sectors")["highest_cleared"] = 10
	app.account.add_xp(100000000, "test")
	var lost := RunLedger.compute(app, _result("lost", 8, false, []))
	var won := RunLedger.compute(app, _result("won", 8, true, [app.campaign.boss_for(8)]))
	check_eq(int(lost.credits_boss), 0, "no bounty without beating the boss")
	var expected := int(round(float(app.campaign.boss_bounty(app.campaign.boss_for(8))) * float(app.campaign.scaling(8.0).reward)))
	check_eq(int(won.credits_boss), expected, "beating Sector 8's boss pays its bounty, scaled like the clear bonus (%d)" % expected)
	check_eq(str(won.boss_name), "THE RIFT WEAVER", "named after the boss")
	check(int(won.credits) >= int(won.credits_collected) + int(won.credits_survival) + int(won.credits_clear) + int(won.credits_boss),
		"and counted in the Credits total")
	var milestone := RunLedger.compute(app, _result("m", 10, true, [app.campaign.boss_for(10)]))
	var plain := RunLedger.compute(app, _result("p", 9, true, [app.campaign.boss_for(9)]))
	check(int(milestone.credits_boss) > int(plain.credits_boss) * 1.2, "every fifth sector's boss is worth more (%d vs %d)" % [milestone.credits_boss, plain.credits_boss])
	var finale := app.campaign.boss_bounty("overseer")
	for id: String in _bosses():
		check(app.campaign.boss_bounty(id) <= finale, "no bounty beats the Overseer's (%s)" % id)


func test_first_clear_crystals_come_from_the_boss_and_are_paid_once() -> void:
	fresh_profile()
	app.save.section("sectors")["highest_cleared"] = 4
	app.account.add_xp(100000000, "test")
	var before := app.economy.balance(Economy.CRYSTALS)
	var first := RunLedger.settle(app, _result("first5", 5, true, [app.campaign.boss_for(5)]))
	var expected := GameData.integer(app.campaign.boss_def(app.campaign.boss_for(5)), "first_clear_crystals")
	check_eq(int(first.crystals), expected, "the first clear of Sector 5 pays its boss's first-clear Crystals (%d)" % expected)
	check_eq(app.economy.balance(Economy.CRYSTALS), before + expected, "banked")
	var again := RunLedger.settle(app, _result("again5", 5, true, [app.campaign.boss_for(5)]))
	check_eq(int(again.crystals), 0, "a second clear pays no Crystals")
	check(int(again.credits_boss) > 0, "but the Credit bounty is paid every clear")
	var total := 0
	for id: String in _bosses():
		total += GameData.integer(_bosses()[id], "first_clear_crystals")
	check(total <= 400, "all the first-clear Crystals in the game add up to a fixed %d" % total)


func test_results_screen_shows_the_bounty() -> void:
	fresh_profile()
	app.save.section("sectors")["highest_cleared"] = 10
	app.account.add_xp(100000000, "test")
	var summary := RunLedger.settle(app, _result("shown", 8, true, [app.campaign.boss_for(8)]))
	var screen := ResultsScreen.new(_result("shown", 8, true, [app.campaign.boss_for(8)]), summary)
	host.add_child(screen)
	var texts := PackedStringArray()
	for node in screen.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	check(texts.has("The Rift Weaver bounty"), "a 'The Rift Weaver bounty' line is shown")
	check(texts.has("+%s" % Fmt.commas(int(summary.credits_boss))), "with its amount")
	host.remove_child(screen)
	screen.free()
