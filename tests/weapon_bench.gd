class_name WeaponBench
extends RefCounted
## One weapon alone in a fixed scenario, for the balance tables (`--weapon-bench`)
## and the tests that hold them to account. Same seed, same fight.

const DT := 1.0 / 30.0


## Runs one bench scenario with only `weapon_id` at `level`. Returns
## {dps, kills, other_kills}. Scenario: "single", "swarm" (player still) or
## "kite". A `partner` weapon at level 5 fights alongside, for a weapon whose
## worth is what it does for others (Prism Lance); its kills are other_kills.
static func run(host: Node, app: AppRoot, weapon_id: String, level: int, scenario: String, seconds: float, run_seed: int = 77, path: String = "", partner: String = "") -> Dictionary:
	app.boot(MemorySaveBackend.new())
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.weapon_pool = [weapon_id]
	if not partner.is_empty():
		config.weapon_pool.append(partner)
	config.start_weapon = weapon_id
	config.max_enemies = 400
	# Sector 8 health and damage, so even the strongest weapon cannot clear
	# everything the bench sends and the top of the table still separates.
	config.tier = 8
	# No energy, so no level-ups: the build stays exactly one weapon at `level`.
	config.base_mods = {"max_hp": 100000000.0, "xp_gain_pct": -1.0}
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	arena.director.paused = true
	arena.grant_weapon(weapon_id, level)
	if not path.is_empty():
		arena.evolve_weapon(weapon_id, path)
	if not partner.is_empty():
		arena.grant_weapon(partner, 5)
	arena.enemies.clear()
	var src := arena.combat.source(weapon_id)
	var swarmer := arena.enemies.type_of("swarmer")
	var tank := arena.enemies.type_of("tank")
	var brute := arena.enemies.type_of("brute")
	var dummy_id := -1
	var boss_def := GameData.dict(GameData.dict(app.data.stages, "bosses"), GameData.text(GameData.dict(app.data.stages, "timeline"), "boss"))
	var boss_hp := GameData.num(boss_def, "hp", 16000.0) * float(app.campaign.scaling(config.tier).boss_hp)
	var kills_before := arena.combat.kills_by_source[src]
	var dealt_before := arena.combat.dealt_by_source[src]
	var steps := int(seconds / DT)
	for s in steps:
		while arena.state == Arena.State.CHOOSING:
			arena.choose(0)
		if scenario == "single":
			var i := arena.enemies.find_id(dummy_id) if dummy_id >= 0 else -1
			if i < 0:
				i = arena.enemies.spawn(tank, arena.player.x + 240.0, arena.player.y)
				dummy_id = arena.enemies.id[i]
				# Health is stored as 32-bit floats: at 1e9 a hit of 10 rounds away
				# to nothing, so use a million and top it up. It stands in for a
				# boss: flagged as one, with a Sector 8 boss's maximum health, so
				# a weapon that cuts a share of health (Prism Lance) cuts what it
				# would from a real boss.
				arena.enemies.max_hp[i] = boss_hp
				arena.enemies.hp[i] = 1.0e6
				arena.enemies.flags[i] |= EnemySystem.F_BOSS
			if arena.enemies.hp[i] < 5.0e5:
				arena.enemies.hp[i] = 1.0e6
			# Pinned in place: a target that stays put, like a boss mid-attack.
			arena.enemies.x[i] = arena.player.x + 240.0
			arena.enemies.y[i] = arena.player.y
		else:
			# A ring of 30 Swarmers and 12 Brutes every second and a half, from
			# 520 units out: more health than any single weapon can clear.
			if s % 45 == 0:
				for k in 42:
					var angle := TAU * float(k) / 42.0 + float(s) * 0.37 + float(run_seed)
					arena.enemies.spawn(brute if k % 7 < 2 else swarmer, arena.player.x + cos(angle) * 520.0, arena.player.y + sin(angle) * 520.0)
			if scenario == "kite":
				# A steady circle at three quarters of normal speed: what a player
				# leading a swarm around looks like.
				var t := float(s) * DT
				arena.move_input = Vector2(-sin(t * 0.6), cos(t * 0.6)) * 0.75
		arena.step(DT)
	var out := {"dps": (arena.combat.dealt_by_source[src] - dealt_before) / seconds, "kills": arena.combat.kills_by_source[src] - kills_before,
		"other_kills": arena.combat.kills - kills_before - (arena.combat.kills_by_source[src] - kills_before)}
	host.remove_child(arena)
	arena.free()
	return out
