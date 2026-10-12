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
##   godot --headless --path . -- --bench
##       worst-case load scenarios with a per-system time breakdown.
##
## Use it to answer "is sector 3 beatable at 30% meta?" before a playtest does.

const DT := 1.0 / 30.0


func _ready() -> void:
	await get_tree().process_frame
	if App.cli.has("bench"):
		_bench()
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
	var next_mark := 30.0
	var last_kills := 0
	var last_damage := 0.0
	var alive_sum := 0.0
	var alive_samples := 0
	while arena.state != Arena.State.ENDED and arena.time < limit:
		arena.step(DT)
		alive_sum += float(arena.enemies.count)
		alive_samples += 1
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
	remove_child(arena)
	arena.free()
	return out


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
