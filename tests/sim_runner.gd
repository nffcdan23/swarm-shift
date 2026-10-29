class_name SimRunner
extends Node
## Balance and performance tooling. Plays whole runs with the autopilot, far
## faster than real time, and prints what happened.
##
##   godot --headless --path . -- --sim=20
##       20 runs of sector 1 with no permanent upgrades.
##   godot --headless --path . -- --sim=20 --sector=4 --meta=0.5 --skill=0.8
##       sector 4, half of every permanent upgrade bought, a stronger pilot.
##   godot --headless --path . -- --sim=5 --mode=endless --limit=1200
##   godot --headless --path . -- --sim=1 --timeline
##       also prints a line every 30 simulated seconds for the first run.
##   godot --headless --path . -- --sim=30 --sector=2 --pressure
##       also prints, minute by minute and averaged over the runs, how hard the
##       sector pushes: hits taken, enemies alive, their speed, and how many
##       charges, shots and blast zones the player had to deal with.
##   godot --headless --path . -- --bench
##       worst-case load scenarios with a per-system time breakdown.
##   godot --headless --path . -- --weapons=8 --sector=3 --meta=0.2
##       each weapon on its own: 8 runs per weapon where it is the only weapon
##       the run can have (passives and augments as usual), then a table of
##       damage per second, kills, survival and clears. Add --immortal to
##       measure raw output over --limit seconds without anyone dying.
##   godot --headless --path . -- --weapon-bench
##       each weapon alone at levels 1, 3 and 5, twenty seconds in each of
##       three fixed scenarios: one tough target (a boss stand-in), a swarm
##       closing on a player who stands still, and the same swarm chasing a
##       player who keeps moving. Prints damage per second and kills. Same
##       seeds every time, so before/after numbers compare directly. Enemies
##       have Sector 8 health so strong weapons do not run out of targets.
##       --only=laser,mine limits the weapons; --seconds=N changes the length.
##   godot --headless --path . -- --campaign=8 --skill=0.6
##       a free player's campaign on one profile: play the highest unlocked
##       sector, bank the real payout, unlock weapons, trade free Crystals for
##       Credits and buy the cheapest permanent upgrade, until N attempts have
##       been made at the target sector (--attempts, default 6). Nothing is
##       bought with money and no ads are watched.
##
## Use it to answer "is sector 3 beatable at 30% meta?" before a playtest does.

const DT := 1.0 / 30.0


func _ready() -> void:
	await get_tree().process_frame
	if App.cli.has("bench"):
		_bench()
	elif App.cli.has("weapon-bench"):
		_weapon_bench()
	elif App.cli.has("weapons"):
		_weapons()
	elif App.cli.has("campaign"):
		_campaign()
	else:
		_sim()
	get_tree().quit()


func _meta_mods(fraction: float) -> Dictionary:
	var mods: Dictionary = {}
	var table := App.data.meta_upgrades()
	for id: String in table:
		var def: Dictionary = table[id]
		var owned := int(round(GameData.num(def, "max_level", 1.0) * fraction))
		var per_level := GameData.dict(def, "mods")
		for key: String in per_level:
			mods[key] = float(mods.get(key, 0.0)) + float(per_level[key]) * float(owned)
	return mods


func _play(config: RunConfig, limit: float, traced: bool = false) -> Dictionary:
	var arena := Arena.new()
	arena.manual_stepping = true
	add_child(arena)
	arena.setup(App, config)
	arena.start()
	var out: Dictionary = {}
	arena.run_ended.connect(func(result: Dictionary) -> void: out["result"] = result)
	var wall := Time.get_ticks_msec()
	var minutes: Array[Dictionary] = []
	var minute_end := 60.0
	var m_hits := 0
	var m_damage := 0.0
	var m_dashes := 0
	var m_shots := 0
	var m_zones := 0
	var m_alive := 0.0
	var m_speed := 0.0
	var m_steps := 0
	var next_mark := 30.0
	var last_kills := 0
	var last_damage := 0.0
	var alive_sum := 0.0
	var alive_samples := 0
	while arena.state != Arena.State.ENDED and arena.time < limit:
		arena.step(DT)
		alive_sum += float(arena.enemies.count)
		alive_samples += 1
		m_alive += float(arena.enemies.count)
		m_speed += arena.enemies.speed_mult
		m_steps += 1
		if arena.time >= minute_end or arena.state == Arena.State.ENDED:
			# One row per minute of the run; a part-minute counts if the run ended in it.
			minutes.append({
				"hits": arena.player.hits_taken - m_hits,
				"damage": (arena.player.damage_taken - m_damage) / maxf(arena.player.max_hp, 1.0),
				"dashes": arena.enemies.dashes_total - m_dashes, "shots": arena.bullets.spawned_total - m_shots,
				"zones": arena.hazards.spawned_total - m_zones,
				"alive": m_alive / float(maxi(m_steps, 1)), "speed": m_speed / float(maxi(m_steps, 1)),
				"survived": arena.state != Arena.State.ENDED or bool(out.get("result", {}).get("cleared", false)),
			})
			m_hits = arena.player.hits_taken
			m_damage = arena.player.damage_taken
			m_dashes = arena.enemies.dashes_total
			m_shots = arena.bullets.spawned_total
			m_zones = arena.hazards.spawned_total
			m_alive = 0.0
			m_speed = 0.0
			m_steps = 0
			minute_end += 60.0
		if traced and arena.time >= next_mark:
			print("    %5s  lvl %2d  hp %3d%%  alive %3d (avg %3.0f)  kills/s %4.1f  dps %5.0f  hp_mult %.2f  weapons %s" % [
				Fmt.time_mmss(arena.time), arena.level, int(arena.player.hp_fraction() * 100.0), arena.enemies.count,
				alive_sum / float(maxi(alive_samples, 1)), float(arena.combat.kills - last_kills) / 30.0,
				(arena.combat.total_damage - last_damage) / 30.0, arena.enemies.hp_mult, str(arena.build.weapons)])
			next_mark += 30.0
			last_kills = arena.combat.kills
			last_damage = arena.combat.total_damage
			alive_sum = 0.0
			alive_samples = 0
	if not out.has("result"):
		out["result"] = arena.build_result(false, false, false)
	out["wall_ms"] = Time.get_ticks_msec() - wall
	out["peak"] = arena.peak_enemies
	out["step_ms"] = arena.step_ms
	out["worst_ms"] = arena.step_ms_worst
	out["steps"] = arena.step_count
	out["profile"] = arena.profile_usec.duplicate()
	out["boss_hp"] = arena.boss.hp_fraction() if arena.boss.active else -1.0
	out["hp"] = arena.player.hp_fraction()
	out["diag"] = arena.diag
	out["minutes"] = minutes
	remove_child(arena)
	arena.free()
	return out


## Runs one bench scenario with only `weapon_id` at `level`. Returns
## {dps, kills}. Scenario: "single", "swarm" (player still) or "kite".
func bench_weapon(weapon_id: String, level: int, scenario: String, seconds: float, run_seed: int = 77) -> Dictionary:
	App.boot(MemorySaveBackend.new())
	var config := RunConfig.for_testing(App.data, run_seed)
	config.autopilot = false
	config.weapon_pool = [weapon_id]
	config.start_weapon = weapon_id
	config.max_enemies = 400
	# Sector 8 health and damage, so even the strongest weapon cannot clear
	# everything the bench sends and the top of the table still separates.
	config.tier = 8
	# No energy, so no level-ups: the build stays exactly one weapon at `level`.
	config.base_mods = {"max_hp": 100000000.0, "xp_gain_pct": -1.0}
	var arena := Arena.new()
	arena.manual_stepping = true
	add_child(arena)
	arena.setup(App, config)
	arena.start()
	arena.director.paused = true
	arena.grant_weapon(weapon_id, level)
	arena.enemies.clear()
	var src := arena.combat.source(weapon_id)
	var swarmer := arena.enemies.type_of("swarmer")
	var tank := arena.enemies.type_of("tank")
	var brute := arena.enemies.type_of("brute")
	var dummy_id := -1
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
				# to nothing, so use a million and top it up.
				arena.enemies.max_hp[i] = 1.0e6
				arena.enemies.hp[i] = 1.0e6
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
	remove_child(arena)
	arena.free()
	return out


func _weapon_bench() -> void:
	var seconds := float(App.cli_text("seconds", "20"))
	var only := App.cli_text("only")
	print("\n=== WEAPON BENCH  %d s per scenario, one weapon, no passives ===" % int(seconds))
	print("  weapon          lvl   single dps   swarm dps  kills   kite dps  kills")
	var ids: Array = App.data.weapon_defs().keys()
	for weapon_id: String in ids:
		if not only.is_empty() and not only.split(",").has(weapon_id):
			continue
		for level: int in [1, 3, 5]:
			# Averaged over three seeds: one twenty-second fight is too chaotic.
			var row := {"single": 0.0, "swarm": 0.0, "swarm_kills": 0.0, "kite": 0.0, "kite_kills": 0.0}
			for run_seed: int in [77, 78, 79]:
				var single := bench_weapon(weapon_id, level, "single", seconds, run_seed)
				var swarm := bench_weapon(weapon_id, level, "swarm", seconds, run_seed)
				var kite := bench_weapon(weapon_id, level, "kite", seconds, run_seed)
				row.single += float(single.dps) / 3.0
				row.swarm += float(swarm.dps) / 3.0
				row.swarm_kills += float(swarm.kills) / 3.0
				row.kite += float(kite.dps) / 3.0
				row.kite_kills += float(kite.kills) / 3.0
			print("  %-14s  %3d   %10.0f   %9.0f  %5.0f   %8.0f  %5.0f" % [GameData.text(App.data.weapon(weapon_id), "name"), level,
				row.single, row.swarm, row.swarm_kills, row.kite, row.kite_kills])


## One weapon at a time: the run can only ever own that weapon, so its damage,
## kills and survival can be compared like for like.
func _weapons() -> void:
	var runs := maxi(App.cli_int("weapons", 6), 1)
	var sector := App.cli_int("sector", 3)
	var meta := float(App.cli_text("meta", "0.2"))
	var skill := float(App.cli_text("skill", "0.7"))
	var limit := float(App.cli_text("limit", "330"))
	var immortal := App.cli.has("immortal")
	var only := App.cli_text("only")
	print("\n=== WEAPONS  sector=%d meta=%.0f%% skill=%.2f runs=%d%s ===" % [sector, meta * 100.0, skill, runs, "  immortal, %d s" % int(limit) if immortal else ""])
	print("  weapon         dps   kills   survived  boss  clear   (median level %s)" % "")
	var ids: Array = App.data.weapon_defs().keys()
	for weapon_id: String in ids:
		if not only.is_empty() and not only.split(",").has(weapon_id):
			continue
		var dps := 0.0
		var kills := 0.0
		var times: Array[float] = []
		var bosses := 0
		var clears := 0
		var level_sum := 0.0
		for i in runs:
			App.boot(MemorySaveBackend.new())
			var config := RunConfig.for_testing(App.data, 100 + i)
			config.tier = sector
			config.autopilot_skill = skill
			config.weapon_pool = [weapon_id]
			config.start_weapon = weapon_id
			config.base_mods = _meta_mods(meta)
			if immortal:
				config.base_mods["max_hp"] = 100000000.0
			var out := _play(config, limit)
			var r: Dictionary = out.result
			var seconds := maxf(float(r.time), 1.0)
			var by_source: Dictionary = r.damage_by_source
			dps += float(by_source.get(weapon_id, 0.0)) / seconds
			kills += float(r.kills)
			times.append(seconds)
			level_sum += float((r.weapons as Dictionary).get(weapon_id, 0))
			if int(r.bosses) > 0 or float(out.boss_hp) >= 0.0:
				bosses += 1
			if bool(r.cleared):
				clears += 1
		times.sort()
		var n := float(runs)
		print("  %-13s %5.0f  %6.0f   %7s  %3d%%  %3d%%   weapon level %.1f" % [GameData.text(App.data.weapon(weapon_id), "name"), dps / n, kills / n,
			Fmt.time_mmss(times[times.size() / 2]), int(100.0 * bosses / n), int(100.0 * clears / n), level_sum / n])


## Spends like a careful free player: weapon unlocks first, then Crystals
## traded for Credits, then the cheapest upgrade level on offer, repeatedly.
func _spend_free() -> void:
	for weapon_id: String in App.arsenal.defs(ArsenalService.WEAPONS):
		App.arsenal.unlock(ArsenalService.WEAPONS, weapon_id)
	for offer: Dictionary in GameData.list(App.data.monetization, "exchange"):
		var price := GameData.integer(offer, "crystals")
		while price > 0 and App.economy.spend(Economy.CRYSTALS, price, "exchange"):
			App.economy.grant(Economy.CREDITS, GameData.integer(offer, "credits"), "exchange")
	while true:
		var cheapest := ""
		var cheapest_cost := 0
		for id: String in App.meta.ids():
			if App.meta.can_buy(id) and (cheapest.is_empty() or App.meta.cost(id) < cheapest_cost):
				cheapest = id
				cheapest_cost = App.meta.cost(id)
		if cheapest.is_empty() or not App.meta.buy(cheapest):
			return


func _campaign() -> void:
	var target := App.cli_int("campaign", 8)
	var attempts := App.cli_int("attempts", 6)
	var skill := float(App.cli_text("skill", "0.6"))
	var cap := App.cli_int("max_runs", 160)
	App.boot(MemorySaveBackend.new())
	print("\n=== CAMPAIGN  free player to sector %d, skill %.2f, %d attempts there ===" % [target, skill, attempts])
	print("  run  sector  result   time   credits  banked  upgrades  player lvl")
	var at_target := 0
	var target_clears := 0
	var first_at_target := {}
	var per_sector: Dictionary = {}
	for run in cap:
		var sector := mini(App.campaign.max_selectable(), target)
		App.campaign.select(sector)
		var config := RunConfig.from_profile(App, CampaignService.MODE_SECTOR)
		config.autopilot = true
		config.autopilot_skill = skill
		config.rng_seed = 1000 + run
		var share := float(App.meta.total_levels()) / float(maxi(App.meta.total_max_levels(), 1))
		if sector == target and first_at_target.is_empty():
			first_at_target = {"run": run + 1, "share": share, "level": App.account.level()}
		var out := _play(config, 900.0)
		var r: Dictionary = out.result
		var summary := RunLedger.settle(App, r)
		var row: Dictionary = per_sector.get(sector, {"runs": 0, "clears": 0})
		row.runs = int(row.runs) + 1
		if bool(r.cleared):
			row.clears = int(row.clears) + 1
		per_sector[sector] = row
		print("  %3d  %4d    %-6s  %5s  %6d  %7d    %3.0f%%     %3d" % [run + 1, sector, "CLEAR" if bool(r.cleared) else "died",
			Fmt.time_mmss(float(r.time)), int(summary.get("credits", 0)), App.economy.balance(Economy.CREDITS), share * 100.0, App.account.level()])
		_spend_free()
		if sector == target:
			at_target += 1
			if bool(r.cleared):
				target_clears += 1
			if at_target >= attempts:
				break
	print("  ---")
	for sector: int in per_sector:
		var row: Dictionary = per_sector[sector]
		print("  sector %2d: %2d runs, %2d clears" % [sector, int(row.runs), int(row.clears)])
	if first_at_target.is_empty():
		print("  never reached sector %d in %d runs" % [target, cap])
	else:
		print("  reached sector %d on run %d with %.0f%% of all upgrade levels (Player Level %d); cleared it %d of %d attempts" % [
			target, int(first_at_target.run), float(first_at_target.share) * 100.0, int(first_at_target.level), target_clears, at_target])


func _sim() -> void:
	var runs := maxi(App.cli_int("sim", 10), 1)
	var sector := App.cli_int("sector", 1)
	var meta := float(App.cli_text("meta", "0"))
	var skill := float(App.cli_text("skill", "0.7"))
	var mode := App.cli_text("mode", CampaignService.MODE_SECTOR)
	var limit := float(App.cli_text("limit", "900"))
	var first_seed := App.cli_int("seed", 1)
	var core := App.cli_text("core", "vanguard")

	print("\n=== SIM  mode=%s sector=%d meta=%.0f%% skill=%.2f core=%s runs=%d ===" % [mode, sector, meta * 100.0, skill, core, runs])
	print("  seed   time  result   lvl  kills  elite  peak  dps    weapons")
	var times: Array[float] = []
	var levels := 0.0
	var clears := 0
	var kills := 0.0
	var boss_reached := 0
	var weapon_damage: Dictionary = {}
	var weapon_picks: Dictionary = {}
	var credits := 0.0
	var credits_cleared := 0.0
	var player_xp := 0.0
	var pressure: Array[Dictionary] = []
	var choices := 0
	var quick_choices := 0
	var runs_with_quick := 0
	var recoveries := 0
	var share_sum: Dictionary = {}
	var share_runs: Dictionary = {}
	for i in runs:
		App.boot(MemorySaveBackend.new())
		var config := RunConfig.for_testing(App.data, first_seed + i)
		config.mode = mode
		config.tier = sector
		config.autopilot_skill = skill
		config.core = core
		var core_def := GameData.dict(App.data.cores(), core)
		config.start_weapon = GameData.text(core_def, "start_weapon", "pulse")
		config.base_mods = _meta_mods(meta)
		var core_mods := GameData.dict(core_def, "mods")
		for key: String in core_mods:
			config.base_mods[key] = float(config.base_mods.get(key, 0.0)) + float(core_mods[key])
		var out := _play(config, limit, App.cli.has("timeline") and i == 0)
		var r: Dictionary = out.result
		var seconds := float(r.time)
		var outcome := "CLEAR" if bool(r.cleared) else ("died" if bool(r.died) else "limit")
		if bool(r.cleared):
			clears += 1
		if int(r.bosses) > 0 or float(out.boss_hp) >= 0.0:
			boss_reached += 1
		times.append(seconds)
		var payout := RunLedger.compute(App, r)
		credits += float(payout.credits)
		player_xp += float(payout.account_xp)
		if bool(r.cleared):
			credits_cleared += float(payout.credits)
		var per_minute: Array = out.minutes
		for m in per_minute.size():
			if m >= pressure.size():
				pressure.append({"runs": 0, "hits": 0.0, "damage": 0.0, "dashes": 0.0, "shots": 0.0, "zones": 0.0, "alive": 0.0, "speed": 0.0, "survived": 0})
			var row: Dictionary = per_minute[m]
			var total: Dictionary = pressure[m]
			total.runs = int(total.runs) + 1
			for key: String in ["hits", "damage", "dashes", "shots", "zones", "alive", "speed"]:
				total[key] = float(total[key]) + float(row[key])
			if bool(row.survived):
				total.survived = int(total.survived) + 1
		var diag: RunDiagnostics = out.diag
		choices += diag.choices
		quick_choices += diag.quick_choices
		recoveries += diag.hud_recoveries + diag.blasts_dropped
		if diag.quick_choices > 0:
			runs_with_quick += 1
		levels += float(r.level)
		kills += float(r.kills)
		var loadout := ""
		var owned: Dictionary = r.weapons
		for weapon_id: String in owned:
			loadout += "%s%d " % [weapon_id.substr(0, 4), int(owned[weapon_id])]
			weapon_picks[weapon_id] = int(weapon_picks.get(weapon_id, 0)) + 1
		var by_source: Dictionary = r.damage_by_source
		for source_name: String in by_source:
			weapon_damage[source_name] = float(weapon_damage.get(source_name, 0.0)) + float(by_source[source_name])
			# Share of that run's damage, so late pickups are not unfairly diluted.
			share_sum[source_name] = float(share_sum.get(source_name, 0.0)) + float(by_source[source_name]) / maxf(float(r.damage), 1.0)
			share_runs[source_name] = int(share_runs.get(source_name, 0)) + 1
		print("  %4d  %5s  %-6s  %3d  %5d  %5d  %4d  %5.0f  %s%s" % [first_seed + i, Fmt.time_mmss(seconds), outcome, int(r.level), int(r.kills),
			int(r.elites), int(out.peak), float(r.damage) / maxf(seconds, 1.0), loadout,
			("  [boss at %d%%]" % int(float(out.boss_hp) * 100.0)) if float(out.boss_hp) >= 0.0 and not bool(r.cleared) else ""])
	times.sort()
	print("  ---")
	@warning_ignore("integer_division")
	var median := times[times.size() / 2]
	print("  clear rate %d/%d (%.0f%%)   reached boss %d/%d   median time %s   avg level %.1f   avg kills %.0f" % [
		clears, runs, 100.0 * float(clears) / float(runs), boss_reached, runs, Fmt.time_mmss(median), levels / float(runs), kills / float(runs)])
	print("  payout per run: %.0f Credits, %.0f Player XP   (cleared runs: %.0f Credits)   [no Credit or XP upgrades applied]" % [
		credits / float(runs), player_xp / float(runs), credits_cleared / float(maxi(clears, 1))])
	# How often an upgrade screen opens while the previous one would still be
	# fading out. Each of these froze the game before the playtest-1 fix.
	print("  upgrade screens %d, of which %d (%.1f%%) opened within %.2fs of the previous one closing - in %d of %d runs   safety valves used: %d" % [
		choices, quick_choices, 100.0 * float(quick_choices) / float(maxi(choices, 1)), RunDiagnostics.QUICK_WINDOW, runs_with_quick, runs, recoveries])
	if App.cli.has("pressure"):
		print("  pressure by minute (averages over the runs still alive at its start; the boss arrives at 5:00)")
		print("    minute   runs  survived   hits  health lost   enemies  speed   charges  shots  blast zones")
		for m in pressure.size():
			var row: Dictionary = pressure[m]
			var n := float(maxi(int(row.runs), 1))
			print("    %d:00-%d:00  %3d   %5.0f%%   %5.1f   %8.0f%%   %7.0f   x%.2f   %6.1f  %5.1f   %8.1f" % [
				m, m + 1, int(row.runs), 100.0 * float(row.survived) / n, float(row.hits) / n, 100.0 * float(row.damage) / n,
				float(row.alive) / n, float(row.speed) / n, float(row.dashes) / n, float(row.shots) / n, float(row.zones) / n])
	var total := 0.0
	for source_name: String in weapon_damage:
		total += float(weapon_damage[source_name])
	var names := weapon_damage.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(weapon_damage[a]) > float(weapon_damage[b]))
	print("  source          overall   in runs that had it   runs")
	for source_name: String in names:
		print("    %-14s %5.1f%%   %5.1f%%               %d" % [source_name, 100.0 * float(weapon_damage[source_name]) / maxf(total, 1.0),
			100.0 * float(share_sum[source_name]) / float(maxi(int(share_runs[source_name]), 1)), int(share_runs[source_name])])


func _bench() -> void:
	print("\n=== BENCH (headless: simulation + draw-buffer writes, no GPU) ===")
	App.boot(MemorySaveBackend.new())

	# 1. A full field the player cannot thin out: enemy update cost in isolation.
	var crowd := RunConfig.for_testing(App.data, 3)
	crowd.base_mods = {"max_hp": 10000000.0, "damage_pct": -0.95}
	_report("full field, weak player", crowd, 200.0, 45.0)

	# 2. A maxed, absurd build mid-swarm: projectiles, blasts and kill chains.
	var storm := RunConfig.for_testing(App.data, 3)
	storm.base_mods = {"max_hp": 10000000.0, "extra_projectiles": 2.0, "fire_rate_pct": 1.0, "area_pct": 0.5,
		"fx.volatile": 1.0, "fx.volatile_damage": 14.0, "fx.volatile_radius": 82.0,
		"fx.split": 1.0, "fx.explosive": 1.0, "fx.explosive_radius": 48.0, "fx.explosive_damage_pct": 0.45,
		"fx.storm": 1.0, "fx.storm_damage": 10.0, "fx.storm_arcs": 4.0, "crit_chance": 0.4}
	_report("maxed build, late swarm", storm, 240.0, 45.0, ["pulse", "scatter", "orbit", "chain", "missile", "nova", "laser", "mine", "drone", "singularity"])


func _report(title: String, config: RunConfig, start_time: float, seconds: float, arsenal: Array = []) -> void:
	var arena := Arena.new()
	arena.manual_stepping = true
	arena.profile = true
	add_child(arena)
	arena.setup(App, config)
	arena.start()
	var max_level := GameData.integer(App.data.weapons, "max_level", 5)
	for weapon_id: String in arsenal:
		arena.grant_weapon(weapon_id, max_level)
	arena.director.timeline_time = start_time
	var steps := int(seconds / DT)
	var wall := Time.get_ticks_usec()
	for i in steps:
		arena.step(DT)
	var total_ms := float(Time.get_ticks_usec() - wall) / 1000.0
	print("\n  %s" % title)
	print("    %d steps, avg %.2f ms, worst %.2f ms   |   enemies now %d (peak %d), projectiles %d, pickups %d, kills %d" % [
		steps, total_ms / float(steps), arena.step_ms_worst, arena.enemies.count, arena.peak_enemies, arena.projectiles.count, arena.pickups.count, arena.combat.kills])
	for s in Arena.PROFILE_SECTIONS.size():
		print("      %-24s %6.3f ms" % [Arena.PROFILE_SECTIONS[s], float(arena.profile_usec[s]) / 1000.0 / float(steps)])
	print("    60 fps budget is 16.6 ms; a mid-range phone runs GDScript roughly 3-4x slower than this Mac.")
	remove_child(arena)
	arena.free()
