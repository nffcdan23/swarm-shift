extends TestSuite
## Energy and Credits on the floor: every reward an enemy drops is accounted
## for, a drop near the action is visible near the action even when the field
## is full, and merging never creates or destroys value.

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


## A run that stands still and cannot die, so tests decide what happens.
func _still_config(run_seed: int) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.base_mods = {"max_hp": 1000000.0}
	return config


func _soft_cap() -> int:
	return GameData.integer(app.data.run_cfg(), "max_pickups", 340)


func _credit_cap() -> int:
	return GameData.integer(app.data.run_cfg(), "max_credit_pickups", 70)


## Pickups of `wanted_kind` within `radius` of (cx, cy): [count, total value].
func _near(arena: Arena, cx: float, cy: float, radius: float, wanted_kind: int) -> Array:
	var n := 0
	var total := 0.0
	var p := arena.pickups
	for i in p.count:
		if p.kind[i] == wanted_kind and Vector2(p.x[i] - cx, p.y[i] - cy).length() <= radius:
			n += 1
			total += p.value[i]
	return [n, total]


## Fills the field the way a long run does: gems left behind far from where
## the player now is.
func _litter_far_away(arena: Arena, amount: int, drop_kind: int) -> void:
	var p := arena.pickups
	for k in amount:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(2200.0, 4200.0)
		var sx := arena.player.x + cos(angle) * dist
		var sy := arena.player.y + sin(angle) * dist
		if drop_kind == PickupSystem.KIND_XP:
			p.drop_xp(sx, sy, 2.0)
		else:
			p.drop(drop_kind, sx, sy, 3.0)


## Kills `amount` swarmers in a ring `radius` from the player, in one step.
## Returns the energy they carried.
func _kill_ring(arena: Arena, amount: int, radius: float, elite: bool = false) -> float:
	var energy := 0.0
	var type_idx := arena.enemies.type_of("swarmer")
	var ids: Array[int] = []
	for k in amount:
		var angle := TAU * float(k) / float(amount)
		var i := arena.enemies.spawn(type_idx, arena.player.x + cos(angle) * radius, arena.player.y + sin(angle) * radius, elite, "")
		if i >= 0:
			energy += arena.enemies.xp[i]
			ids.append(i)
	for i in ids:
		arena.enemies.hurt(i, 1.0e9)
	arena.step(DT)
	return energy


func test_reproduce_drops_vanish_when_the_field_is_full() -> void:
	fresh_profile()
	var arena := _arena(_still_config(3))
	arena.step(DT)
	_litter_far_away(arena, _soft_cap(), PickupSystem.KIND_XP)
	check(arena.pickups.count >= _soft_cap(), "field saturated with left-behind energy (%d)" % arena.pickups.count)
	var energy := _kill_ring(arena, 20, 160.0)
	var near := _near(arena, arena.player.x, arena.player.y, 320.0, PickupSystem.KIND_XP)
	check(int(near[0]) >= 1, "energy from 20 kills next to the player is visible next to the player (%d gems)" % int(near[0]))
	check_near(float(near[1]), energy, 0.01, "and holds all of it")
	_free(arena)


func test_reproduce_credits_vanish_when_the_credit_cap_is_reached() -> void:
	fresh_profile()
	var arena := _arena(_still_config(4))
	arena.step(DT)
	_litter_far_away(arena, _credit_cap(), PickupSystem.KIND_CREDIT)
	var elite_credits := GameData.num(GameData.dict(app.data.enemies, "elite"), "credit_value", 25.0)
	_kill_ring(arena, 1, 160.0, true)
	var near := _near(arena, arena.player.x, arena.player.y, 320.0, PickupSystem.KIND_CREDIT)
	check(int(near[0]) >= 1, "an elite's Credits appear where it died (%d piles)" % int(near[0]))
	check(float(near[1]) >= elite_credits - 0.01, "holding at least its %d Credits (%.1f)" % [int(elite_credits), float(near[1])])
	_free(arena)


## Not a pass/fail test: how often the field fills up in ordinary play.
func test_probe_saturation_in_play() -> void:
	for setup: Array in [[1, CampaignService.MODE_SECTOR, 300.0], [3, CampaignService.MODE_SECTOR, 300.0], [1, CampaignService.MODE_ENDLESS, 600.0]]:
		fresh_profile()
		var config := RunConfig.for_testing(app.data, 21)
		config.tier = int(setup[0])
		config.mode = str(setup[1])
		config.base_mods = {"max_hp": 1000000.0}
		var arena := _arena(config)
		var steps_full := 0
		var peak := 0
		var steps := int(float(setup[2]) / DT)
		for s in steps:
			if arena.state == Arena.State.ENDED:
				break
			arena.step(DT)
			peak = maxi(peak, arena.pickups.count)
			if arena.pickups.count >= _soft_cap():
				steps_full += 1
		print("    [probe] %s tier %d, %d s: peak %d pickups, field full %.0f%% of the time, %d merges" % [setup[1], setup[0], int(arena.time), peak, 100.0 * steps_full / maxf(steps, 1), arena.diag.pickups_merged])
		_free(arena)
	check(true, "probe ran")
