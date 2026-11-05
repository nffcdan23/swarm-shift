extends TestSuite
## Readable enemy fire, the spinning Prism Lance and Plasma Mines.
## Weapon numbers come from `godot --headless --path . -- --weapon-bench`;
## these tests pin the behaviour that makes those numbers possible.

const DT := 1.0 / 30.0
const FIXTURE := "res://tests/fixtures/profile_v1_before_playtest_update.save"


func _arena(weapon_id: String = "pulse", level: int = 1, enemies: int = 0) -> Arena:
	var config := RunConfig.for_testing(app.data, 61)
	config.autopilot = false
	config.weapon_pool = [weapon_id]
	config.start_weapon = weapon_id
	config.max_enemies = maxi(enemies + 60, 420)
	config.base_mods = {"max_hp": 100000000.0, "xp_gain_pct": -1.0}
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	arena.director.paused = true
	arena.enemies.clear()
	arena.grant_weapon(weapon_id, level)
	return arena


func _free(arena: Arena) -> void:
	host.remove_child(arena)
	arena.free()


func _spawn(arena: Arena, type_id: String, dx: float, dy: float) -> int:
	return arena.enemies.spawn(arena.enemies.type_of(type_id), arena.player.x + dx, arena.player.y + dy)


## Pins enemy `index_id` (by id) in place and tops up its health.
func _pin(arena: Arena, enemy_id: int, at: Vector2, hp: float = -1.0) -> void:
	var i := arena.enemies.find_id(enemy_id)
	if i < 0:
		return
	arena.enemies.x[i] = arena.player.x + at.x
	arena.enemies.y[i] = arena.player.y + at.y
	if hp > 0.0:
		arena.enemies.hp[i] = hp
		arena.enemies.max_hp[i] = hp


func _instances_at(batch: SpriteBatch, at: Vector2, within: float) -> int:
	var n := 0
	for k in batch.count:
		var o := k * 16
		if Vector2(batch.buf[o + 3], batch.buf[o + 7]).distance_to(at) <= within:
			n += 1
	return n


# ------------------------------------------------------------ enemy fire

func test_enemy_fire_is_drawn_on_top_of_everything() -> void:
	fresh_profile()
	var arena := _arena()
	var gfx := arena.gfx
	var order := gfx.get_children()
	var hostile := order.find(gfx.hostile)
	check(hostile >= 0, "there is a hostile-fire layer")
	for layer: Node in [gfx.ground, gfx.ground_glow, gfx.telegraphs, gfx.zones, gfx.pickups, gfx.enemies, gfx.actors, gfx.shots, gfx.bullets, gfx.particles, gfx.beams, gfx.rings, gfx.numbers]:
		check(order.find(layer) < hostile, "%s is drawn below enemy fire" % layer.name)
	var shader := (gfx.hostile.material as ShaderMaterial).shader
	check(shader.resource_path.ends_with("sprite_mix.gdshader"), "with normal blending, so it shows over bright and dark alike")
	check(gfx.hostile.capacity >= arena.bullets.capacity() + 40, "with room for every bullet plus firing cues (%d)" % gfx.hostile.capacity)
	check(gfx.cell("hostile") != gfx.cell("bullet"), "using its own sprite, not the old additive dot")
	_free(arena)


func test_enemy_fire_looks_exactly_as_big_as_it_hits() -> void:
	fresh_profile()
	var arena := _arena()
	var bullets := arena.bullets
	check_near(bullets.draw_size(), bullets.hit_radius() * 4.0, 0.001, "the red body (half the sprite) is the hit radius")
	# Collision itself is unchanged: radius 8 plus 80% of the player's radius.
	var reach := bullets.hit_radius() + arena.player.radius * 0.8
	var hp := arena.player.hp
	bullets.spawn(arena.player.x + reach + 3.0, arena.player.y, 0.0, 0.0, 10.0)
	arena.step(DT)
	check_near(arena.player.hp, hp, 0.001, "a shot just outside the hit circle does not hit")
	bullets.clear()
	arena.player.invulnerable_for = 0.0
	bullets.spawn(arena.player.x + reach - 2.0, arena.player.y, 0.0, 0.0, 10.0)
	arena.step(DT)
	check(arena.player.hp < hp, "one just inside does")
	_free(arena)


func test_enemy_fire_stays_visible_in_a_dense_fight() -> void:
	fresh_profile()
	var arena := _arena("pulse", 5, 400)
	for weapon_id: String in ["scatter", "missile", "nova"]:
		arena.grant_weapon(weapon_id, 5)
	arena.build.add_augment("volatile")
	arena.refresh_build()
	for k in 400:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(90.0, 600.0)
		arena.enemies.spawn(arena.enemies.type_of(["swarmer", "brute", "shooter"][k % 3]), arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)
	var src := arena.combat.source("test")
	for k in 40:
		arena.combat.blast(arena.player.x + arena.rng.randf_range(-400.0, 400.0), arena.player.y + arena.rng.randf_range(-400.0, 400.0), 120.0, 1.0e6, src, Color.WHITE)
	arena.player.invulnerable_for = 1000.0
	var worst_missing := 0
	var checked := 0
	for s in 90:
		# Keep the crowd up and a stream of shots in the air through the whole fight.
		while arena.enemies.count < 300:
			var spot := arena.rng.randf() * TAU
			arena.enemies.spawn(arena.enemies.type_of("brute"), arena.player.x + cos(spot) * 500.0, arena.player.y + sin(spot) * 500.0)
		for k in 3:
			var angle := arena.rng.randf() * TAU
			arena.bullets.spawn(arena.player.x + cos(angle) * 380.0, arena.player.y + sin(angle) * 380.0, -cos(angle) * 250.0, -sin(angle) * 250.0, 1.0)
		arena.step(DT)
		var missing := 0
		for b in arena.bullets.count:
			checked += 1
			if _instances_at(arena.gfx.hostile, Vector2(arena.bullets.x[b], arena.bullets.y[b]), 0.5) == 0:
				missing += 1
		worst_missing = maxi(worst_missing, missing)
	check(checked > 1000, "plenty of shots were checked (%d)" % checked)
	check_eq(worst_missing, 0, "every shot in the air is drawn on the top layer, every frame, mid-explosions")
	check(arena.enemies.count >= 250 and arena.combat.kills > 100, "with the swarm still there and dying (%d kills)" % arena.combat.kills)
	_free(arena)


func test_shooters_show_a_cue_before_they_fire() -> void:
	fresh_profile()
	var arena := _arena()
	arena.player.invulnerable_for = 1000.0
	var shooter := _spawn(arena, "shooter", 320.0, 0.0)
	var shooter_id := arena.enemies.id[shooter]
	var cue_seen_at := -1.0
	var fired_at := -1.0
	for s in int(6.0 / DT):
		_pin(arena, shooter_id, Vector2(320.0, 0.0))
		var before := arena.bullets.spawned_total
		arena.step(DT)
		var i := arena.enemies.find_id(shooter_id)
		if i >= 0 and cue_seen_at < 0.0 and _instances_at(arena.gfx.hostile, Vector2(arena.enemies.x[i], arena.enemies.y[i]), arena.enemies.radius[i] + 4.0) > 0:
			cue_seen_at = arena.time
		if arena.bullets.spawned_total > before:
			fired_at = arena.time
			break
	check(fired_at > 0.0, "the Shooter fired")
	check(cue_seen_at > 0.0 and cue_seen_at < fired_at, "a cue appeared at its muzzle first (%.2f s before the shot)" % (fired_at - cue_seen_at))
	_free(arena)


# ------------------------------------------------------------ Prism Lance

func test_lance_bursts_spin_and_cut_without_killing() -> void:
	fresh_profile()
	var arena := _arena("laser", 1)
	var lance: Variant = arena.weapon_node("laser")
	# Eight Brutes in a ring, held in place: one burst of two opposite spokes
	# turns far enough to sweep the whole circle.
	var ring: Array[int] = []
	for k in 8:
		var angle := TAU * float(k) / 8.0
		ring.append(arena.enemies.id[_spawn(arena, "brute", cos(angle) * 180.0, sin(angle) * 180.0)])
	var start: float = lance.beam_angles()[0]
	var top := arena.enemies.max_hp[arena.enemies.find_id(ring[0])]
	var charged := false
	var cut_while_charging := 0.0
	for s in int(1.5 / DT):
		for k in ring.size():
			var angle := TAU * float(k) / 8.0
			_pin(arena, ring[k], Vector2(cos(angle) * 180.0, sin(angle) * 180.0))
		arena.step(DT)
		if lance.is_charging():
			charged = true
			cut_while_charging = maxf(cut_while_charging, arena.combat.dealt_by_source[lance.src])
	check(charged, "it charges first")
	check_near(cut_while_charging, 0.0, 0.001, "and cuts nothing while charging")
	check(lance.is_firing(), "then fires")
	check(absf(wrapf(lance.beam_angles()[0] - start, -PI, PI)) > 0.5, "the spokes turned")
	var cut := 0
	for enemy_id in ring:
		var i := arena.enemies.find_id(enemy_id)
		check(i >= 0 and arena.enemies.hp[i] > 0.0, "a burst kills nothing at full health")
		if i >= 0 and arena.enemies.hp[i] <= top * 0.72:
			cut += 1
	check_eq(cut, 8, "every Brute in the ring lost at least 28% of its health in one burst")
	# It is a burst, not a permanent ring: it switches off, then fires again.
	var off := false
	for s in int(5.0 / DT):
		for k in ring.size():
			var angle := TAU * float(k) / 8.0
			_pin(arena, ring[k], Vector2(cos(angle) * 180.0, sin(angle) * 180.0))
		arena.step(DT)
		if not lance.is_firing() and not lance.is_charging():
			off = true
	check(off, "the spokes switch off between bursts")
	check_eq(lance.bursts, 2, "and come back for a second burst within five seconds")
	_free(arena)


func test_a_cut_stops_at_the_floor() -> void:
	fresh_profile()
	var arena := _arena("laser", 1)
	var i := _spawn(arena, "tank", 2000.0, 0.0)
	var top := arena.enemies.max_hp[i]
	arena.combat.cut(i, 0.3, 0.15, 0)
	check_near(arena.enemies.hp[i], top * 0.7, 0.01, "30% off a full-health Tank")
	arena.combat.cut(i, 0.3, 0.15, 0)
	arena.combat.cut(i, 0.3, 0.15, 0)
	check_near(arena.enemies.hp[i], top * 0.15, 0.01, "three cuts leave it at the 15% floor")
	arena.combat.cut(i, 0.3, 0.15, 0)
	check_near(arena.enemies.hp[i], top * 0.15, 0.01, "and more cuts take nothing further")
	_free(arena)


func test_after_the_lance_any_weapon_finishes_a_tank() -> void:
	fresh_profile()
	var arena := _arena("laser", 3)
	var tank := arena.enemies.id[_spawn(arena, "tank", 200.0, 0.0)]
	var top := arena.enemies.max_hp[arena.enemies.find_id(tank)]
	for s in int(6.0 / DT):
		_pin(arena, tank, Vector2(200.0, 0.0))
		arena.step(DT)
	var i := arena.enemies.find_id(tank)
	check(i >= 0, "six seconds of the Lance alone have not killed a Tank")
	check(i >= 0 and absf(arena.enemies.hp[i] - top * 0.12) < 0.5, "but cut it to its 12%% floor (%.0f of %.0f)" % [arena.enemies.hp[i] if i >= 0 else 0.0, top])
	# One Scatter Shot volley at level 1: five pellets of its base damage.
	var pellet := GameData.num(GameData.dict(app.data.weapon("scatter"), "base"), "damage")
	for k in 5:
		if i >= 0 and arena.enemies.hp[i] > 0.0:
			arena.combat.hit(i, pellet, 0, 0.0, 0.0, false)
	check(i >= 0 and arena.enemies.hp[i] <= 0.0, "and one starter volley finishes it")
	_free(arena)


func test_bosses_take_smaller_cuts_and_elites_full_ones() -> void:
	fresh_profile()
	var arena := _arena("laser", 5)
	var boss := _spawn(arena, "tank", 150.0, 0.0)
	arena.enemies.flags[boss] |= EnemySystem.F_BOSS
	# A real boss's health: the Lance's small ordinary hit barely shows on it.
	arena.enemies.max_hp[boss] = 16000.0
	arena.enemies.hp[boss] = 16000.0
	var boss_id := arena.enemies.id[boss]
	for s in int(20.0 / DT):
		_pin(arena, boss_id, Vector2(150.0, 0.0))
		arena.step(DT)
	var b := arena.enemies.find_id(boss_id)
	var share := arena.enemies.hp[b] / arena.enemies.max_hp[b] if b >= 0 else 0.0
	check(share >= 0.5, "twenty seconds of a maxed Lance leave a boss at half health or more (%.2f)" % share)
	check(share < 0.99, "though it does cut it")
	_free(arena)
	# An elite takes the full cut, like an ordinary Brute: big enemies are what
	# the Lance is for.
	arena = _arena("laser", 1)
	var elite := _spawn(arena, "brute", 180.0, 0.0)
	arena.enemies.flags[elite] |= EnemySystem.F_ELITE
	var plain := _spawn(arena, "brute", -180.0, 0.0)
	var elite_id := arena.enemies.id[elite]
	var plain_id := arena.enemies.id[plain]
	for s in int(1.6 / DT):
		_pin(arena, elite_id, Vector2(180.0, 0.0))
		_pin(arena, plain_id, Vector2(-180.0, 0.0))
		arena.step(DT)
	var e := arena.enemies.find_id(elite_id)
	var p := arena.enemies.find_id(plain_id)
	check(e >= 0 and p >= 0 and arena.enemies.hp[e] / arena.enemies.max_hp[e] < 0.72,
		"an elite loses as big a share as an ordinary enemy (%.2f)" % (arena.enemies.hp[e] / arena.enemies.max_hp[e] if e >= 0 else 1.0))
	_free(arena)


func test_lance_extra_beams_are_evenly_spaced() -> void:
	fresh_profile()
	var arena := _arena("laser", 5)
	var lance: Variant = arena.weapon_node("laser")
	var angles: PackedFloat32Array = lance.beam_angles()
	check_eq(angles.size(), 4, "four spokes at level 5")
	for k in angles.size():
		check_near(absf(wrapf(angles[(k + 1) % angles.size()] - angles[k], -PI, PI)), PI / 2.0, 0.01, "a quarter turn apart")
	arena.evolve_weapon("laser", "sweep")
	check_eq(lance.beam_angles().size(), 6, "six on the Prism Wheel")
	_free(arena)


func _single_target_dps(weapon_id: String, level: int) -> float:
	var arena := _arena(weapon_id, level)
	var tank := arena.enemies.id[_spawn(arena, "tank", 240.0, 0.0)]
	var src: int = arena.weapon_node(weapon_id).src
	for s in int(12.0 / DT):
		_pin(arena, tank, Vector2(240.0, 0.0), 1.0e6 if s == 0 else -1.0)
		var i := arena.enemies.find_id(tank)
		if i >= 0 and arena.enemies.hp[i] < 5.0e5:
			arena.enemies.hp[i] = 1.0e6
		arena.step(DT)
	var dps := arena.combat.dealt_by_source[src] / 12.0
	_free(arena)
	return dps


func _crowd_dps(weapon_id: String, level: int) -> float:
	var arena := _arena(weapon_id, level, 300)
	var src: int = arena.weapon_node(weapon_id).src
	for s in int(10.0 / DT):
		if s % 30 == 0:
			for k in 30:
				var angle := TAU * float(k) / 30.0 + float(s)
				_spawn(arena, "brute" if k % 3 == 0 else "swarmer", cos(angle) * 480.0, sin(angle) * 480.0)
		arena.step(DT)
	var dps := arena.combat.dealt_by_source[src] / 10.0
	_free(arena)
	return dps


func test_every_lance_and_mine_level_is_an_upgrade() -> void:
	fresh_profile()
	for weapon_id: String in ["mine"]:
		var single := [_single_target_dps(weapon_id, 1), _single_target_dps(weapon_id, 3), _single_target_dps(weapon_id, 5)]
		var crowd := [_crowd_dps(weapon_id, 1), _crowd_dps(weapon_id, 3), _crowd_dps(weapon_id, 5)]
		print("    [weapon] %s single %.0f / %.0f / %.0f   crowd %.0f / %.0f / %.0f" % [weapon_id, single[0], single[1], single[2], crowd[0], crowd[1], crowd[2]])
		check(single[0] > 0.0, "%s hurts a lone target that holds its ground (%.0f/s)" % [weapon_id, single[0]])
		check(single[1] > single[0] and single[2] > single[1], "%s: single-target damage rises at levels 3 and 5" % weapon_id)
		check(crowd[1] > crowd[0] and crowd[2] > crowd[1], "%s: crowd damage rises at levels 3 and 5" % weapon_id)
		check(crowd[0] > single[0] * 3.0, "%s is a crowd weapon first (crowd %.0f vs single %.0f)" % [weapon_id, crowd[0], single[0]])
	# The Lance cuts a share of health, so a dummy with a million of it says
	# nothing; a crowd of real enemies does.
	var lance := [_crowd_dps("laser", 1), _crowd_dps("laser", 3), _crowd_dps("laser", 5)]
	print("    [weapon] laser crowd %.0f / %.0f / %.0f" % [lance[0], lance[1], lance[2]])
	check(lance[1] > lance[0] and lance[2] > lance[1], "laser: crowd damage rises at levels 3 and 5")


# ------------------------------------------------------------ Plasma Mines

func test_mines_deploy_while_moving_and_wait_to_arm() -> void:
	fresh_profile()
	var arena := _arena("mine", 1)
	var mines: Variant = arena.weapon_node("mine")
	arena.move_input = Vector2(1.0, 0.0)
	for s in int(4.0 / DT):
		arena.step(DT)
	check(mines.placed >= 3, "mines keep coming while the player runs (%d in 4 s)" % mines.placed)
	check_eq(mines.detonated, 0, "with nothing near, none go off")
	var behind := 0
	for k in mines.mine_count():
		if mines.mine_position(k).x < arena.player.x - 20.0:
			behind += 1
	check(behind >= mines.mine_count() - 1, "they are left along the trail (%d of %d behind)" % [behind, mines.mine_count()])
	arena.move_input = Vector2.ZERO
	_free(arena)


func test_mines_are_lobbed_at_a_threat_and_go_off_on_contact() -> void:
	fresh_profile()
	var arena := _arena("mine", 1)
	var mines: Variant = arena.weapon_node("mine")
	var target := arena.enemies.id[_spawn(arena, "tank", 200.0, 0.0)]
	var landed := Vector2.INF
	for s in int(2.0 / DT):
		_pin(arena, target, Vector2(200.0, 0.0), 1.0e6)
		arena.step(DT)
		if mines.mine_count() > 0:
			landed = mines.mine_position(0) - Vector2(arena.player.x, arena.player.y)
			break
	check(landed.x > 60.0 and absf(landed.y) < 5.0, "the first mine is lobbed towards the enemy (%s)" % str(landed))
	var src: int = mines.src
	for s in int(3.0 / DT):
		_pin(arena, target, Vector2(200.0, 0.0))
		arena.step(DT)
	check(mines.detonated >= 1, "an enemy standing on the minefield sets mines off (%d)" % mines.detonated)
	check(arena.combat.dealt_by_source[src] > 0.0, "and they damage it")
	_free(arena)


func test_mine_trigger_radius_and_arming() -> void:
	fresh_profile()
	var arena := _arena("mine", 1)
	var mines: Variant = arena.weapon_node("mine")
	arena.step(DT)
	check_eq(mines.mine_count(), 1, "a mine at the player's feet")
	var at: Vector2 = mines.mine_position(0)
	var trigger: float = mines.trigger_radius()
	# Outside the trigger radius: stays put even once armed.
	var outside := _spawn(arena, "tank", at.x - arena.player.x + trigger + 45.0, at.y - arena.player.y)
	var outside_id := arena.enemies.id[outside]
	for s in 12:
		_pin(arena, outside_id, at - Vector2(arena.player.x, arena.player.y) + Vector2(trigger + 45.0, 0.0), 1.0e6)
		arena.step(DT)
	check(mines.is_armed(0), "the mine has armed")
	check_eq(mines.detonated, 0, "an enemy just outside the trigger radius does not set it off")
	_pin(arena, outside_id, at - Vector2(arena.player.x, arena.player.y) + Vector2(trigger - 10.0, 0.0))
	arena.step(DT)
	check_eq(mines.detonated, 1, "stepping inside does, at once")
	_free(arena)


func test_mine_level_four_blasts_slow_enemies() -> void:
	fresh_profile()
	var arena := _arena("mine", 4)
	var mines: Variant = arena.weapon_node("mine")
	var brute := arena.enemies.id[_spawn(arena, "tank", 150.0, 0.0)]
	for s in int(3.0 / DT):
		_pin(arena, brute, Vector2(150.0, 0.0), 1.0e6)
		arena.step(DT)
		if mines.detonated > 0:
			break
	arena.step(DT)
	var i := arena.enemies.find_id(brute)
	check(mines.detonated > 0 and i >= 0 and arena.enemies.is_cold(i), "the blast leaves it chilled")
	_free(arena)


# ------------------------------------------------------------ attribution, load, saves

func test_damage_and_kills_are_credited_to_the_weapon() -> void:
	fresh_profile()
	for weapon_id: String in ["mine"]:
		var arena := _arena(weapon_id, 3, 120)
		for k in 120:
			var angle := TAU * float(k) / 120.0
			_spawn(arena, "swarmer", cos(angle) * (150.0 + float(k % 5) * 60.0), sin(angle) * (150.0 + float(k % 5) * 60.0))
		for s in int(8.0 / DT):
			arena.step(DT)
		var src: int = arena.weapon_node(weapon_id).src
		check(arena.combat.kills > 0, "%s killed (%d)" % [weapon_id, arena.combat.kills])
		check_eq(arena.combat.kills_by_source[src], arena.combat.kills, "%s: every kill is credited to it" % weapon_id)
		check(arena.combat.dealt_by_source[src] <= arena.combat.damage_by_source[src] + 0.01, "%s: landed damage never exceeds raw damage" % weapon_id)
		_free(arena)


func test_the_lance_alone_never_kills() -> void:
	fresh_profile()
	var arena := _arena("laser", 5, 120)
	for k in 120:
		var angle := TAU * float(k) / 120.0
		_spawn(arena, "swarmer", cos(angle) * (100.0 + float(k % 5) * 50.0), sin(angle) * (100.0 + float(k % 5) * 50.0))
	for s in int(8.0 / DT):
		arena.step(DT)
	var src: int = arena.weapon_node("laser").src
	check(arena.combat.dealt_by_source[src] > 0.0, "it cut them (%.0f health)" % arena.combat.dealt_by_source[src])
	check_eq(arena.combat.kills, 0, "but killed none")
	var lowest := 1.0
	for i in arena.enemies.count:
		lowest = minf(lowest, arena.enemies.hp[i] / arena.enemies.max_hp[i])
	check(lowest >= 0.12 - 0.001, "none below the 12%% floor (lowest %.3f)" % lowest)
	_free(arena)


func test_lance_and_mines_on_a_crowded_field_stay_fast() -> void:
	fresh_profile()
	var arena := _arena("laser", 5, 420)
	arena.grant_weapon("mine", 5)
	arena.player.invulnerable_for = 1000.0
	var worst := 0.0
	var total := 0.0
	var steps := int(10.0 / DT)
	for s in steps:
		while arena.enemies.count < 400:
			var angle := arena.rng.randf() * TAU
			_spawn(arena, "swarmer", cos(angle) * arena.rng.randf_range(150.0, 620.0), sin(angle) * arena.rng.randf_range(150.0, 620.0))
		var mark := Time.get_ticks_usec()
		arena.step(DT)
		var ms := float(Time.get_ticks_usec() - mark) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	print("    [load] Lance 5 + Mines 5 among 400 enemies: %.2f ms per step, worst %.1f ms" % [total / steps, worst])
	check(total / steps < 8.0, "average step stays well inside a frame (%.2f ms)" % (total / steps))
	_free(arena)


func test_old_saves_with_these_weapons_still_load_and_play() -> void:
	var backend := MemorySaveBackend.new()
	backend.text = FileAccess.get_file_as_string(FIXTURE)
	app.boot(backend)
	check(not app.save.is_new_profile, "the pre-update save still loads")
	for weapon_id: String in ["mine", "laser"]:
		app.arsenal.grant(ArsenalService.WEAPONS, weapon_id, "test")
	app.save.flush()
	var reloaded := MemorySaveBackend.new()
	reloaded.text = backend.text
	app.boot(reloaded)
	check(app.arsenal.is_owned(ArsenalService.WEAPONS, "mine") and app.arsenal.is_owned(ArsenalService.WEAPONS, "laser"), "unlocked Mines and Lance survive a save and reload")
	var config := RunConfig.from_profile(app, CampaignService.MODE_SECTOR)
	config.autopilot = true
	config.weapon_pool = ["laser", "mine", config.start_weapon]
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	arena.grant_weapon("laser", 5)
	arena.grant_weapon("mine", 5)
	for s in int(20.0 / DT):
		arena.step(DT)
	check(arena.combat.kills > 0 and is_finite(arena.player.x), "a run from that profile plays with both (%d kills)" % arena.combat.kills)
	_free(arena)


# ------------------------------------------------- railgun and scatter aim

## Steps until the Railgun has fired once (or `seconds` pass), holding the
## given enemies in place.
func _until_fired(arena: Arena, gun: Weapon, pins: Dictionary, seconds: float = 4.0) -> void:
	var before: int = gun.fired
	for s in int(seconds / DT):
		for enemy_id: int in pins:
			_pin(arena, enemy_id, pins[enemy_id])
		arena.step(DT)
		if gun.fired > before:
			return


func test_railgun_goes_for_the_big_enemy_not_the_swarm() -> void:
	fresh_profile()
	var arena := _arena("railgun", 1)
	var gun := arena.weapon_node("railgun")
	var pins := {}
	for k in 4:
		var near := _spawn(arena, "swarmer", -140.0, -60.0 + 40.0 * k)
		pins[arena.enemies.id[near]] = Vector2(-140.0, -60.0 + 40.0 * k)
	var tank := arena.enemies.id[_spawn(arena, "tank", 0.0, 520.0)]
	pins[tank] = Vector2(0.0, 520.0)
	_pin(arena, tank, Vector2(0.0, 520.0), 5000.0)
	_until_fired(arena, gun, pins)
	check_eq(gun.fired, 1, "the Railgun fired")
	var t := arena.enemies.find_id(tank)
	check(t >= 0 and arena.enemies.hp[t] < 5000.0, "at the Tank, though four swarmers were closer")
	var swarmers_left := 0
	for enemy_id: int in pins:
		if enemy_id != tank and arena.enemies.find_id(enemy_id) >= 0:
			swarmers_left += 1
	check_eq(swarmers_left, 4, "and none of its shot went into the swarmers on the other side")
	_free(arena)


func test_railgun_hits_bosses_hardest() -> void:
	fresh_profile()
	var arena := _arena("railgun", 1)
	var gun := arena.weapon_node("railgun")
	var tank := arena.enemies.id[_spawn(arena, "tank", 300.0, 0.0)]
	_pin(arena, tank, Vector2(300.0, 0.0), 1.0e5)
	var i := arena.enemies.find_id(tank)
	arena.enemies.flags[i] |= EnemySystem.F_BOSS
	_until_fired(arena, gun, {tank: Vector2(300.0, 0.0)})
	i = arena.enemies.find_id(tank)
	var base := GameData.dict(app.data.weapon("railgun"), "base")
	var expected := GameData.num(base, "damage") * GameData.num(base, "boss_mult")
	check(GameData.num(base, "boss_mult") > 1.0, "the Railgun carries a bonus against bosses")
	# Crits can only add to the hit.
	check(i >= 0 and 1.0e5 - arena.enemies.hp[i] >= expected - 1.0,
		"a boss takes the bonus on the Railgun's hit (%.0f, at least %.0f)" % [1.0e5 - arena.enemies.hp[i] if i >= 0 else 0.0, expected])
	_free(arena)


func test_railgun_swings_to_a_new_mark_when_its_target_dies_mid_charge() -> void:
	fresh_profile()
	var arena := _arena("railgun", 1)
	var gun := arena.weapon_node("railgun")
	var first := arena.enemies.id[_spawn(arena, "tank", 300.0, 0.0)]
	var second := arena.enemies.id[_spawn(arena, "tank", -300.0, 0.0)]
	_pin(arena, first, Vector2(300.0, 0.0), 6000.0)
	_pin(arena, second, Vector2(-300.0, 0.0), 4000.0)
	var pins := {first: Vector2(300.0, 0.0), second: Vector2(-300.0, 0.0)}
	for s in 30:
		_pin(arena, first, pins[first])
		_pin(arena, second, pins[second])
		arena.step(DT)
		if gun.is_charging():
			break
	check(gun.is_charging(), "the Railgun started charging")
	check_eq(gun._marks[0], first, "on the healthier Tank")
	# Another weapon finishes it while the shot charges.
	var f := arena.enemies.find_id(first)
	arena.combat.hit(f, 1.0e6, 0, 0.0, 0.0, false)
	pins.erase(first)
	_until_fired(arena, gun, pins)
	check_eq(gun.fired, 1, "the shot still went off")
	var s2 := arena.enemies.find_id(second)
	check(s2 >= 0 and arena.enemies.hp[s2] < 4000.0, "into the other Tank, not where the dead one stood")
	_free(arena)


func test_railgun_calls_off_a_shot_with_nothing_left_to_hit() -> void:
	fresh_profile()
	var arena := _arena("railgun", 1)
	var gun := arena.weapon_node("railgun")
	var tank := arena.enemies.id[_spawn(arena, "tank", 300.0, 0.0)]
	_pin(arena, tank, Vector2(300.0, 0.0), 6000.0)
	for s in 30:
		_pin(arena, tank, Vector2(300.0, 0.0))
		arena.step(DT)
		if gun.is_charging():
			break
	check(gun.is_charging(), "the Railgun started charging")
	arena.combat.hit(arena.enemies.find_id(tank), 1.0e6, 0, 0.0, 0.0, false)
	arena.step(DT)
	arena.step(DT)
	check(not gun.is_charging(), "with its only target dead, the charge stops")
	check_eq(gun.fired, 0, "no shot is wasted on empty space")
	check_eq(gun.called_off, 1, "it was called off")
	# The next target is shot straight away, not after a full cooldown.
	var next := arena.enemies.id[_spawn(arena, "tank", 0.0, 300.0)]
	_pin(arena, next, Vector2(0.0, 300.0), 6000.0)
	var started := false
	for s in 3:
		_pin(arena, next, Vector2(0.0, 300.0))
		arena.step(DT)
		started = started or gun.is_charging()
	check(started, "and is ready for the next one at once")
	_free(arena)


func test_railgun_with_no_big_enemies_fires_down_the_crowded_lane() -> void:
	fresh_profile()
	var arena := _arena("railgun", 1)
	var gun := arena.weapon_node("railgun")
	var pins := {}
	var lane: Array[int] = []
	# One swarmer close by on its own, and a line of six further out.
	var lone := arena.enemies.id[_spawn(arena, "swarmer", -120.0, 0.0)]
	pins[lone] = Vector2(-120.0, 0.0)
	for k in 6:
		var at := Vector2(0.0, 180.0 + 60.0 * k)
		var enemy_id := arena.enemies.id[_spawn(arena, "swarmer", at.x, at.y)]
		pins[enemy_id] = at
		lane.append(enemy_id)
	_until_fired(arena, gun, pins)
	check_eq(gun.fired, 1, "the Railgun still fires at small enemies")
	var hit := 0
	for enemy_id in lane:
		var i := arena.enemies.find_id(enemy_id)
		if i < 0 or arena.enemies.hp[i] < arena.enemies.max_hp[i]:
			hit += 1
	check_eq(hit, 6, "down the line of six, not at the nearest one")
	check(arena.enemies.find_id(lone) >= 0, "and the lone swarmer was left for other weapons")
	_free(arena)


## A lone enemy close to the player on one side, a pack further out on the other.
func _lone_and_pack(arena: Arena) -> void:
	var lone := arena.enemies.id[_spawn(arena, "swarmer", 0.0, -110.0)]
	_pin(arena, lone, Vector2(0.0, -110.0), 1.0e5)
	for k in 7:
		var angle := -0.3 + 0.1 * k
		var at := Vector2(cos(angle), sin(angle)) * (220.0 + 20.0 * (k % 3))
		var enemy_id := arena.enemies.id[_spawn(arena, "swarmer", at.x, at.y)]
		_pin(arena, enemy_id, at, 1.0e5)


func test_scatter_shot_aims_at_the_pack_and_pulse_at_the_nearest() -> void:
	fresh_profile()
	var arena := _arena("scatter", 1)
	_lone_and_pack(arena)
	arena.step(DT)
	var aim := arena.player.aim_angle
	check(absf(wrapf(aim, -PI, PI)) < 0.3, "Scatter Shot points its cone at the pack of seven (aim %.2f rad)" % aim)
	_free(arena)
	arena = _arena("pulse", 1)
	_lone_and_pack(arena)
	arena.step(DT)
	check(absf(wrapf(arena.player.aim_angle + PI * 0.5, -PI, PI)) < 0.1,
		"the Pulse Cannon still shoots the nearest enemy (aim %.2f rad)" % arena.player.aim_angle)
	_free(arena)


func test_scatter_cone_centres_on_the_pack() -> void:
	fresh_profile()
	var arena := _arena("scatter", 1)
	var gun := arena.weapon_node("scatter")
	# A pack straddling straight left, where the angles wrap round.
	for k in 5:
		var angle := PI - 0.2 + 0.1 * k
		_spawn(arena, "swarmer", cos(angle) * 200.0, sin(angle) * 200.0)
	_spawn(arena, "swarmer", 0.0, 150.0)
	# Positions only reach the lookup grid once a step runs it.
	arena.enemies._rebuild_grid(arena.player.x, arena.player.y)
	var aim: float = gun.group_aim(arena.player.x, arena.player.y, 400.0, 0.0)
	check(absf(wrapf(aim - PI, -PI, PI)) < 0.12, "the cone centres on a pack across the wrap (aim %.2f rad)" % aim)
	_free(arena)
