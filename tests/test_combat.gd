extends TestSuite
## Readable enemy fire and the reworked Prism Lance and Plasma Mines.
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

func test_lance_aims_down_the_most_crowded_line() -> void:
	fresh_profile()
	var arena := _arena("laser", 1)
	var lance: Variant = arena.weapon_node("laser")
	# One Brute close by to the north; six in a row further east.
	var lone := _spawn(arena, "brute", 0.0, -160.0)
	var row: Array[int] = []
	for k in 6:
		row.append(arena.enemies.id[_spawn(arena, "brute", 220.0 + 60.0 * k, 0.0)])
	var lone_id := arena.enemies.id[lone]
	var charged := false
	var damaged_during_charge := 0.0
	for s in int(2.5 / DT):
		_pin(arena, lone_id, Vector2(0.0, -160.0), 1.0e6)
		for k in row.size():
			_pin(arena, row[k], Vector2(220.0 + 60.0 * k, 0.0), 1.0e6)
		arena.step(DT)
		if lance.is_charging():
			charged = true
			damaged_during_charge = maxf(damaged_during_charge, arena.combat.dealt_by_source[lance.src])
		if lance.is_firing():
			break
	check(charged, "it charges before firing")
	check_near(damaged_during_charge, 0.0, 0.001, "and does no damage while charging")
	check(lance.is_firing(), "then fires")
	check_near(wrapf(lance.beam_angles()[0], -PI, PI), 0.0, 0.2, "east, along the row of six, not at the nearer lone Brute")
	for s in 20:
		for k in row.size():
			_pin(arena, row[k], Vector2(220.0 + 60.0 * k, 0.0))
		_pin(arena, lone_id, Vector2(0.0, -160.0))
		arena.step(DT)
	var burned := 0
	for enemy_id in row:
		var i := arena.enemies.find_id(enemy_id)
		if i >= 0 and arena.enemies.hp[i] < 1.0e6:
			burned += 1
	check_eq(burned, 6, "it pierces: all six in the line were burned")
	var lone_i := arena.enemies.find_id(lone_id)
	check(lone_i >= 0 and arena.enemies.hp[lone_i] >= 1.0e6, "the Brute off the line was not touched")
	_free(arena)


func test_lance_extra_beams_take_other_lines() -> void:
	fresh_profile()
	var arena := _arena("laser", 5)
	var lance: Variant = arena.weapon_node("laser")
	for k in 4:
		_spawn(arena, "brute", 240.0 + 50.0 * k, 0.0)
		_spawn(arena, "brute", -240.0 - 50.0 * k, 0.0)
		_spawn(arena, "brute", 0.0, 240.0 + 50.0 * k)
	for s in int(3.0 / DT):
		arena.step(DT)
		if lance.is_firing():
			break
	var angles: PackedFloat32Array = lance.beam_angles()
	check_eq(angles.size(), 3, "three beams at level 5")
	var apart := true
	for p in angles.size():
		for q in range(p + 1, angles.size()):
			if absf(wrapf(angles[p] - angles[q], -PI, PI)) < 0.4:
				apart = false
	check(apart, "each on its own line (%s)" % str(angles))
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
	for weapon_id: String in ["laser", "mine"]:
		var single := [_single_target_dps(weapon_id, 1), _single_target_dps(weapon_id, 3), _single_target_dps(weapon_id, 5)]
		var crowd := [_crowd_dps(weapon_id, 1), _crowd_dps(weapon_id, 3), _crowd_dps(weapon_id, 5)]
		print("    [weapon] %s single %.0f / %.0f / %.0f   crowd %.0f / %.0f / %.0f" % [weapon_id, single[0], single[1], single[2], crowd[0], crowd[1], crowd[2]])
		check(single[0] > 0.0, "%s hurts a lone target that holds its ground (%.0f/s)" % [weapon_id, single[0]])
		check(single[1] > single[0] and single[2] > single[1], "%s: single-target damage rises at levels 3 and 5" % weapon_id)
		check(crowd[1] > crowd[0] and crowd[2] > crowd[1], "%s: crowd damage rises at levels 3 and 5" % weapon_id)
		check(crowd[0] > single[0] * 3.0, "%s is a crowd weapon first (crowd %.0f vs single %.0f)" % [weapon_id, crowd[0], single[0]])
	var pulse := _single_target_dps("pulse", 5)
	check(_single_target_dps("laser", 5) < pulse, "a maxed Lance does not out-damage a maxed Pulse Cannon on one target")


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
	for weapon_id: String in ["laser", "mine"]:
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


func test_lance_aiming_is_cheap_on_a_full_field() -> void:
	fresh_profile()
	var arena := _arena("laser", 5, 420)
	for k in 410:
		var angle := arena.rng.randf() * TAU
		_spawn(arena, "swarmer", cos(angle) * arena.rng.randf_range(100.0, 600.0), sin(angle) * arena.rng.randf_range(100.0, 600.0))
	var lance: Variant = arena.weapon_node("laser")
	var mark := Time.get_ticks_usec()
	for k in 50:
		lance._aim(620.0, 18.0)
	var per_aim := float(Time.get_ticks_usec() - mark) / 1000.0 / 50.0
	print("    [aim] %.2f ms per aim with %d enemies" % [per_aim, arena.enemies.count])
	# Once per firing cycle (about every two seconds); keep it far below a frame.
	check(per_aim < 2.0, "choosing the most crowded line costs %.2f ms with 410 enemies" % per_aim)
	_free(arena)
