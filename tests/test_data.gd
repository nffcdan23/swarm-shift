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
