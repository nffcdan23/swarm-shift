extends TestSuite
## Sanity checks on the JSON tables: they load, cross-references resolve, and
## the curves the economy depends on behave.


func test_tables_load() -> void:
	var data := GameData.new()
	check(data.load_all(), "data files failed to load: " + ", ".join(data.errors))
	for file in GameData.FILES:
		var table: Dictionary = data.get(file)
		check(not table.is_empty(), "table '%s' is empty" % file)


func test_references_resolve() -> void:
	var problems := app.data.validate()
	for problem in problems:
		check(false, problem)
	check(true, "validated")


func test_curve_interpolation() -> void:
	var points := [[0, 1.0], [60, 2.0], [120, 4.0]]
	check_near(GameData.curve(points, -5.0), 1.0, 0.001, "clamps below first key")
	check_near(GameData.curve(points, 30.0), 1.5, 0.001, "interpolates first segment")
	check_near(GameData.curve(points, 90.0), 3.0, 0.001, "interpolates second segment")
	check_near(GameData.curve(points, 999.0), 4.0, 0.001, "clamps above last key")


func test_overrides_merge_deeply() -> void:
	var data := GameData.new()
	data.load_all()
	var before := GameData.num(GameData.dict(data.enemy_types(), "brute"), "hp")
	data.apply_overrides({"enemies": {"types": {"swarmer": {"hp": 123}}}})
	check_near(GameData.num(GameData.dict(data.enemy_types(), "swarmer"), "hp"), 123.0, 0.001, "override applied")
	check_near(GameData.num(GameData.dict(data.enemy_types(), "brute"), "hp"), before, 0.001, "siblings untouched")
	check(GameData.dict(data.enemy_types(), "swarmer").has("speed"), "unrelated keys survive the merge")


func test_meta_costs_increase() -> void:
	fresh_profile()
	for id: String in app.meta.ids():
		check(app.meta.cost(id) > 0, "upgrade '%s' has a positive first cost" % id)
		check(app.meta.max_level(id) >= 1, "upgrade '%s' has at least one level" % id)


func test_account_curve_is_monotonic() -> void:
	fresh_profile()
	var previous := 0
	for level in range(1, app.account.max_level()):
		var needed := app.account.xp_needed(level)
		check(needed > previous, "xp needed rises at level %d" % level)
		previous = needed


func test_every_account_level_pays_something() -> void:
	fresh_profile()
	for level in range(2, 31):
		var rewards := app.account.level_rewards(level)
		check(int(rewards.credits) > 0, "level %d pays credits" % level)


func test_weapon_levels_have_descriptions() -> void:
	for id: String in app.data.weapon_defs():
		var levels := GameData.list(app.data.weapon(id), "levels")
		for i in levels.size():
			var level: Dictionary = levels[i]
			check(not GameData.text(level, "desc").is_empty(), "weapon '%s' level %d has a description" % [id, i + 1])


## "Avoid unavoidable damage": every blast in the tables gives enough warning
## for a player moving at base speed to walk from its centre to safety, with a
## margin for reacting to it.
func test_every_blast_can_be_outrun_from_its_centre() -> void:
	var player := GameData.dict(app.data.game, "player")
	var speed := GameData.num(GameData.dict(player, "base_stats"), "move_speed", 250.0)
	var body := GameData.num(player, "radius", 17.0)
	var reaction := 0.25
	var blasts: Array[Array] = []
	var types := app.data.enemy_types()
	var lob := GameData.dict(GameData.dict(types, "mortar"), "lob")
	blasts.append(["Mortar shell", GameData.num(lob, "blast_radius"), GameData.num(lob, "flight")])
	var bomb := GameData.dict(GameData.dict(types, "bomber"), "bomb")
	blasts.append(["Bomber", GameData.num(bomb, "blast_radius"), GameData.num(bomb, "fuse")])
	var volatile := GameData.dict(GameData.dict(GameData.dict(app.data.enemies, "elite"), "affixes"), "volatile")
	blasts.append(["Volatile elite", GameData.num(volatile, "death_blast_radius"), GameData.num(volatile, "death_blast_delay")])
	var bombard := GameData.dict(GameData.dict(app.data.stages, "timeline"), "bombard")
	blasts.append(["Bombardment shell", GameData.num(bombard, "radius"), GameData.num(bombard, "delay")])
	for boss_id: String in GameData.dict(app.data.stages, "bosses"):
		var zones := GameData.dict(GameData.dict(GameData.dict(app.data.stages, "bosses")[boss_id], "attacks"), "zones")
		if not zones.is_empty():
			blasts.append(["%s ground blast" % boss_id, GameData.num(zones, "radius"), GameData.num(zones, "telegraph")])
	for entry in blasts:
		var radius := float(entry[1])
		var warning := float(entry[2])
		var needed := (radius + body) / speed + reaction
		check(warning >= HazardSystem.MIN_DELAY, "%s gives at least the minimum warning (%.2f s)" % [str(entry[0]), warning])
		check(warning >= needed, "%s: %.2f s of warning covers the %.2f s needed to react and walk out" % [str(entry[0]), warning, needed])
	for type_id: String in ["dasher"]:
		var dash := GameData.dict(GameData.dict(types, type_id), "dash")
		check(GameData.num(dash, "telegraph") >= 0.4, "%s shows its lane before charging (%.2f s)" % [type_id, GameData.num(dash, "telegraph")])


func test_upgrade_table_is_well_formed() -> void:
	fresh_profile()
	var total := 0
	for id: String in app.meta.ids():
		var levels := app.meta.max_level(id)
		for step in levels:
			total += app.meta.cost_at(id, step)
		var gate := app.meta.unlock_level(id)
		check(gate >= 0 and gate <= 30, "upgrade '%s' unlocks at a reachable Player Level (%d)" % [id, gate])
	check(total > 50000 and total < 400000, "buying everything is a long-term goal, not an impossible one (%d Credits)" % total)
	var first_buys := 0
	for id: String in app.meta.ids():
		if app.meta.unlock_level(id) <= 1 and app.meta.cost_at(id, 0) <= 250:
			first_buys += 1
	check(first_buys >= 6, "a new player has several upgrades within reach of a first run or two (%d)" % first_buys)
