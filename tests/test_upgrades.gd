extends TestSuite
## Upgrade cards: nothing maxed, owned or over its cap is ever offered or
## applied, and a hand is always dealt, even when the whole build is complete.

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


## A run a person is playing: no autopilot, cannot die, levels quickly.
func _player_config(run_seed: int) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.base_mods = {"max_hp": 1000000.0, "xp_gain_pct": 4.0}
	return config


## Why `offer` should not be on the table for this build, or "" if it is fine.
func _offer_problem(arena: Arena, offer: Dictionary) -> String:
	var id := str(offer.id)
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	match str(offer.kind):
		UpgradeSystem.KIND_WEAPON:
			var have := arena.build.weapon_level(id)
			if have >= weapon_max:
				return "weapon %s offered at level %d although it is maxed (%d)" % [id, int(offer.level), have]
			if int(offer.level) != have + 1:
				return "weapon %s offered at level %d, owned at %d" % [id, int(offer.level), have]
		UpgradeSystem.KIND_PASSIVE:
			var have := arena.build.passive_level(id)
			var cap := GameData.integer(GameData.dict(app.data.passives(), id), "max_level", 5)
			if have >= cap:
				return "passive %s offered at level %d although it is maxed (%d/%d)" % [id, int(offer.level), have, cap]
			if int(offer.level) != have + 1:
				return "passive %s offered at level %d, owned at %d" % [id, int(offer.level), have]
		UpgradeSystem.KIND_AUGMENT:
			if arena.build.augments.has(id):
				return "augment %s offered although owned" % id
	return ""


## How many owned weapons and passives are at their cap.
func _maxed_count(arena: Arena) -> int:
	var n := 0
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	for id: String in arena.build.weapon_order:
		if arena.build.weapon_level(id) >= weapon_max:
			n += 1
	for id: String in arena.build.passive_order:
		if arena.build.passive_level(id) >= GameData.integer(GameData.dict(app.data.passives(), id), "max_level", 5):
			n += 1
	return n


func _hand_problems(arena: Arena) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for offer in arena.current_offers:
		var key := "%s:%s" % [offer.kind, offer.id]
		if seen.has(key) and str(offer.kind) in [UpgradeSystem.KIND_WEAPON, UpgradeSystem.KIND_PASSIVE, UpgradeSystem.KIND_AUGMENT]:
			problems.append("%s offered twice in one hand" % key)
		seen[key] = true
		var problem := _offer_problem(arena, offer)
		if not problem.is_empty():
			problems.append(problem)
	return problems


## Plays like a person: picks a random card, sometimes rerolls first, checks
## every hand dealt. Returns [problems, hands dealt].
func _play_checking_hands(run_seed: int, seconds: float) -> Array:
	var arena := _arena(_player_config(run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7919
	var problems := PackedStringArray()
	var hands := 0
	var maxed_hands := 0
	var steps := int(seconds / DT)
	for step in steps:
		if arena.state == Arena.State.ENDED:
			break
		var guard := 0
		while arena.state == Arena.State.CHOOSING and guard < 50:
			guard += 1
			hands += 1
			if _maxed_count(arena) > 0:
				maxed_hands += 1
			for problem in _hand_problems(arena):
				problems.append("t=%.1f L%d: %s" % [arena.time, arena.level, problem])
			if rng.randf() < 0.3 and arena.can_reroll():
				arena.reroll()
				continue
			arena.choose(rng.randi_range(0, arena.current_offers.size() - 1))
		arena.step(DT)
	_free(arena)
	return [problems, hands, maxed_hands]


func test_reproduce_no_maxed_card_is_ever_dealt() -> void:
	fresh_profile()
	var all_problems := PackedStringArray()
	var hands := 0
	var maxed_hands := 0
	for run_seed in [1, 2, 3, 4, 5, 6]:
		var result := _play_checking_hands(run_seed, 420.0)
		all_problems.append_array(result[0])
		hands += int(result[1])
		maxed_hands += int(result[2])
	for problem in all_problems.slice(0, 12):
		print("    [card] ", problem)
	check(hands > 100, "enough hands were dealt to mean something (%d)" % hands)
	check(maxed_hands >= 30, "many of them with something already maxed (%d)" % maxed_hands)
	check_eq(all_problems.size(), 0, "no maxed, owned or mis-levelled card in %d hands" % hands)
