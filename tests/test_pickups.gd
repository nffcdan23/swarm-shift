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


## Energy: everything dropped is either collected (after the gain multiplier)
## or still on the floor. Credits: the same, before the Credits multiplier.
func _ledger(arena: Arena, label: String) -> void:
	var p := arena.pickups
	check_near(p.collected_energy + p.field_xp(), p.dropped_xp, p.dropped_xp * 0.0005 + 0.01,
		"%s: energy accounted for (dropped %.1f, collected %.1f, on the floor %.1f)" % [label, p.dropped_xp, p.collected_energy, p.field_xp()])
	check_near(p.collected_credits + p.field_credits(), p.dropped_credits, p.dropped_credits * 0.0005 + 0.01,
		"%s: Credits accounted for (dropped %.1f, collected %.1f, on the floor %.1f)" % [label, p.dropped_credits, p.collected_credits, p.field_credits()])
	check_near(arena.credits, p.collected_credits * arena.player.credit_gain, 0.01, "%s: the run holds exactly the Credits collected" % label)


func _special_count(arena: Arena) -> int:
	var n := 0
	for i in arena.pickups.count:
		if arena.pickups.kind[i] >= PickupSystem.KIND_REPAIR:
			n += 1
	return n


## Pulls everything to the player and steps until the floor is clear.
func _collect_everything(arena: Arena) -> void:
	for k in 600:
		arena.pickups.magnetise_all()
		while arena.state == Arena.State.CHOOSING:
			arena.choose(0)
		arena.step(DT)
		if arena.pickups.field_xp() + arena.pickups.field_credits() <= 0.0:
			return


func test_hundreds_of_deaths_in_one_step_keep_every_reward() -> void:
	fresh_profile()
	var config := _still_config(5)
	config.max_enemies = 1000
	var arena := _arena(config)
	arena.step(DT)
	for wave: int in [200, 500, 900]:
		var energy_before := arena.pickups.dropped_xp
		var energy := _kill_ring(arena, wave, 260.0)
		check_near(arena.pickups.dropped_xp - energy_before, energy, 0.01, "%d deaths at once: every one dropped its energy" % wave)
		check(arena.pickups.count <= arena.pickups.capacity(), "the field never exceeds its capacity (%d)" % arena.pickups.count)
		var near := _near(arena, arena.player.x, arena.player.y, 600.0, PickupSystem.KIND_XP)
		check(int(near[0]) > 0, "%d deaths at once: crystals are visible where they died (%d)" % [wave, int(near[0])])
		_ledger(arena, "%d deaths" % wave)
		while arena.state == Arena.State.CHOOSING:
			arena.choose(0)
	_free(arena)


func test_saturation_merges_far_pickups_and_keeps_kinds_apart() -> void:
	fresh_profile()
	var arena := _arena(_still_config(6))
	arena.step(DT)
	arena.pickups.drop(PickupSystem.KIND_CACHE, arena.player.x + 3000.0, arena.player.y, 1.0)
	arena.pickups.drop(PickupSystem.KIND_REPAIR, arena.player.x - 3000.0, arena.player.y, 1.0)
	_litter_far_away(arena, 60, PickupSystem.KIND_CREDIT)
	_litter_far_away(arena, _soft_cap() * 2, PickupSystem.KIND_XP)
	var credits_before := arena.pickups.field_credits()
	check(arena.pickups.count < _soft_cap(), "a full field is thinned out below its cap (%d)" % arena.pickups.count)
	check(arena.diag.pickups_merged > 0, "by merging (%d merges)" % arena.diag.pickups_merged)
	check_near(arena.pickups.field_xp(), float(_soft_cap() * 2) * 2.0, 0.01, "no energy created or destroyed by merging")
	check_near(arena.pickups.field_credits(), credits_before, 0.01, "energy never merges into Credits or back")
	check_eq(_special_count(arena), 2, "a cache and a repair cell are never merged away")
	_litter_far_away(arena, _credit_cap() * 3, PickupSystem.KIND_CREDIT)
	var piles := 0
	for i in arena.pickups.count:
		if arena.pickups.kind[i] == PickupSystem.KIND_CREDIT:
			piles += 1
	check(piles <= _credit_cap(), "Credit piles stay within their own cap (%d)" % piles)
	check_near(arena.pickups.field_credits(), float(60 + _credit_cap() * 3) * 3.0, 0.01, "and every Credit is still there")
	var biggest := 0.0
	for i in arena.pickups.count:
		if arena.pickups.kind[i] == PickupSystem.KIND_XP:
			biggest = maxf(biggest, arena.pickups.value[i])
	check(biggest > 2.0, "merged crystals carry the sum of their parts (largest %.0f)" % biggest)
	_ledger(arena, "after merging")
	_free(arena)


func test_merged_pickups_pay_exactly_when_collected() -> void:
	fresh_profile()
	var arena := _arena(_still_config(7))
	arena.step(DT)
	_litter_far_away(arena, _soft_cap() * 3, PickupSystem.KIND_XP)
	_litter_far_away(arena, _credit_cap() * 3, PickupSystem.KIND_CREDIT)
	_kill_ring(arena, 120, 200.0, false)
	_kill_ring(arena, 3, 200.0, true)
	check(arena.diag.pickups_merged > 0, "merging happened (%d)" % arena.diag.pickups_merged)
	_collect_everything(arena)
	# The run keeps going while everything is pulled in, so compare with the
	# totals at the end rather than a snapshot from before.
	var energy := arena.pickups.dropped_xp
	var coins := arena.pickups.dropped_credits
	check_near(arena.pickups.field_xp() + arena.pickups.field_credits(), 0.0, 0.001, "the floor is clear")
	check_near(arena.pickups.collected_energy, energy, energy * 0.0005 + 0.01, "every point of energy was paid, once")
	check_near(arena.pickups.collected_credits, coins, 0.01, "every Credit was paid, once")
	_ledger(arena, "after collecting")
	_free(arena)


func test_simultaneous_explosions_keep_the_ledger() -> void:
	fresh_profile()
	var config := _still_config(8)
	config.max_enemies = 600
	var arena := _arena(config)
	arena.build.add_augment("volatile")
	arena.refresh_build()
	arena.step(DT)
	_litter_far_away(arena, _soft_cap(), PickupSystem.KIND_XP)
	var type_idx := arena.enemies.type_of("swarmer")
	var carried := 0.0
	for k in 600:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(80.0, 560.0)
		var i := arena.enemies.spawn(type_idx, arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)
		if i >= 0:
			carried += arena.enemies.xp[i]
	var energy_before := arena.pickups.dropped_xp
	var kills_before := arena.combat.kills
	var src := arena.combat.source("test")
	for k in 200:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf() * 560.0
		arena.combat.blast(arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist, 140.0, 1.0e6, src, Color.WHITE)
	var worst := 0.0
	for s in 240:
		while arena.state == Arena.State.CHOOSING:
			arena.choose(0)
		var mark := Time.get_ticks_usec()
		arena.step(DT)
		worst = maxf(worst, float(Time.get_ticks_usec() - mark) / 1000.0)
		if arena.combat.pending_blasts() == 0 and arena.enemies.count == 0:
			break
	var killed := arena.combat.kills - kills_before
	check(killed >= 500, "200 explosions and their chain reaction killed the crowd (%d)" % killed)
	check(arena.pickups.dropped_xp - energy_before >= carried * 0.8, "and the energy of the dead hit the floor")
	_ledger(arena, "explosions")
	var near := _near(arena, arena.player.x, arena.player.y, 700.0, PickupSystem.KIND_XP)
	check(int(near[0]) > 0, "visible where the fight was (%d crystals)" % int(near[0]))
	print("    [load] 200 explosions on a full field: %d kills, worst step %.1f ms, %d merges" % [killed, worst, arena.diag.pickups_merged])
	_free(arena)


func test_long_heavy_run_keeps_rewards_visible_and_accounted() -> void:
	for setup: Array in [[3, CampaignService.MODE_SECTOR, 300.0], [1, CampaignService.MODE_ENDLESS, 600.0]]:
		fresh_profile()
		var config := RunConfig.for_testing(app.data, 21)
		config.tier = int(setup[0])
		config.mode = str(setup[1])
		config.base_mods = {"max_hp": 1000000.0}
		var arena := _arena(config)
		var steps := int(float(setup[2]) / DT)
		var full_steps := 0
		var peak := 0
		var worst := 0.0
		var total_ms := 0.0
		var hidden := 0
		var kills_seen := 0
		for s in steps:
			if arena.state == Arena.State.ENDED:
				break
			var kills_before := arena.combat.kills
			var mark := Time.get_ticks_usec()
			arena.step(DT)
			var ms := float(Time.get_ticks_usec() - mark) / 1000.0
			worst = maxf(worst, ms)
			total_ms += ms
			peak = maxi(peak, arena.pickups.count)
			if arena.pickups.count >= _soft_cap():
				full_steps += 1
			# Every step with kills should leave something on the floor near the player.
			if arena.combat.kills > kills_before and s % 15 == 0:
				kills_seen += 1
				if int(_near(arena, arena.player.x, arena.player.y, 900.0, PickupSystem.KIND_XP)[0]) == 0:
					hidden += 1
		var label := "%s tier %d" % [setup[1], setup[0]]
		check(peak <= arena.pickups.capacity(), "%s: never over capacity (peak %d)" % [label, peak])
		check(hidden <= kills_seen / 20, "%s: kills near the player leave visible crystals (%d of %d sampled steps had none)" % [label, hidden, kills_seen])
		_ledger(arena, label)
		print("    [load] %s, %d s: %.2f ms per step, worst %.1f ms, peak %d pickups, full %.0f%% of the time, %d merges" % [
			label, int(arena.time), total_ms / maxf(steps, 1), worst, peak, 100.0 * full_steps / maxf(steps, 1), arena.diag.pickups_merged])
		_free(arena)

