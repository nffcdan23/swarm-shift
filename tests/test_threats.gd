extends TestSuite
## Difficulty that is not just bigger numbers: the enemies and set pieces added
## for later sectors, what each sector contains, and - for every one of them -
## that the danger is announced on screen in time to be avoided.

const DT := 1.0 / 60.0


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


## A run with a player who stands wherever the test puts them, and no swarm.
func _quiet(tier: int = 1, run_seed: int = 5) -> Arena:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.tier = tier
	config.start_weapon = "pulse"
	config.base_mods = {"damage_pct": -0.999}
	var arena := _arena(config)
	arena.director.boss_active = true      # holds the timeline: nothing spawns
	arena.enemies.clear()
	return arena


func _sector(tier: int, mode: String = CampaignService.MODE_SECTOR) -> Arena:
	var config := RunConfig.for_testing(app.data, 5)
	config.tier = tier
	config.mode = mode
	config.base_mods = {"max_hp": 100000000.0}
	return _arena(config)


func _track_enemies(arena: Arena) -> Array:
	var out: Array = []
	for track in arena.director._tracks:
		out.append(str(track.enemy))
	return out


func _event_types(arena: Arena) -> Array:
	var out: Array = []
	for event: Dictionary in arena.director._events:
		out.append(str(event.type))
	return out


# ------------------------------------------------------------------ sectors

func test_each_early_sector_adds_something_new() -> void:
	fresh_profile()
	var one := _sector(1)
	var two := _sector(2)
	var three := _sector(3)
	for basic: String in ["swarmer", "brute", "dasher", "splitter", "shooter", "tank"]:
		check(_track_enemies(one).has(basic), "Sector 1 has %ss" % basic)
	for later: String in ["weaver", "mortar", "bomber"]:
		check(not _track_enemies(one).has(later), "Sector 1 has no %ss - it is the beginner sector" % later)
	check(not _event_types(one).has("bombard"), "and no bombardments")
	check(_event_types(one).has("pack") and _event_types(one).has("pincer") and _event_types(one).has("line"),
		"but its later minutes do bring a pack, a pincer and a firing line")

	check(_track_enemies(two).has("weaver") and _track_enemies(two).has("mortar"), "Sector 2 adds Weavers and Mortars")
	check(not _track_enemies(two).has("bomber"), "but not Bombers yet")
	check(two.director._events.size() > one.director._events.size(), "and more set pieces (%d vs %d)" % [two.director._events.size(), one.director._events.size()])

	check(_track_enemies(three).has("bomber"), "Sector 3 adds Bombers")
	check(_event_types(three).has("bombard"), "and bombardments")
	check(three.director._events.size() > two.director._events.size(), "on top of everything from Sector 2")

	for tier in [1, 2, 3]:
		var brief := app.campaign.sector_brief(tier)
		check(not str(brief.name).is_empty() and not str(brief.brief).is_empty(), "Sector %d has a name and a briefing for the lobby" % tier)
		check((brief.mutators as Array).is_empty(), "Sector %d has no mutator" % tier)
	check_eq(app.campaign.sector_brief(2).new, ["Weaver", "Mortar"], "the Sector 2 briefing names its new enemies")
	_free(one)
	_free(two)
	_free(three)


func test_later_sectors_rotate_mutators() -> void:
	fresh_profile()
	var rotation := GameData.list(GameData.dict(app.data.stages, "sectors"), "rotation")
	check(rotation.size() >= 5, "there is a real rotation of mutators (%d)" % rotation.size())
	var previous := ""
	for tier in range(4, 10):
		var ids := app.campaign.mutator_ids(CampaignService.MODE_SECTOR, tier)
		check_eq(ids.size(), 1, "Sector %d has one mutator" % tier)
		check(ids[0] != previous, "and it differs from the sector before (%s)" % ids[0])
		previous = ids[0]
		var brief := app.campaign.sector_brief(tier)
		check_eq((brief.mutators as Array).size(), 1, "which the lobby can show")
		check(not str(brief.mutators[0].desc).is_empty(), "with a description")
	for tier in range(10, 21):
		var ids := app.campaign.mutator_ids(CampaignService.MODE_SECTOR, tier)
		check_eq(ids.size(), 2, "Sector %d has two mutators" % tier)
		check(ids[0] != ids[1], "and they are different ones (%s)" % str(ids))
	check(app.campaign.mutator_ids(CampaignService.MODE_ENDLESS, 1, 0).is_empty(), "Overdrive starts clean")
	check_eq(app.campaign.mutator_ids(CampaignService.MODE_ENDLESS, 1, 1).size(), 1, "and takes a mutator from its second cycle")

	# The mutators really change the run, not just its label.
	var plain := _sector(3)
	var blitz := _sector(4)
	plain.step(DT)
	blitz.step(DT)
	check_eq(blitz.director.mutator_ids(), ["blitz"] as Array[String], "Sector 4 runs BLITZ")
	check(blitz.enemies.speed_mult > plain.enemies.speed_mult * 1.1, "under which enemies are over 10%% faster (%.2f vs %.2f)" % [blitz.enemies.speed_mult, plain.enemies.speed_mult])
	_free(plain)
	_free(blitz)
	var artillery := _sector(5)
	check_eq(artillery.director.mutator_ids(), ["artillery"] as Array[String], "Sector 5 runs ARTILLERY")
	var mortar_mult := 1.0
	for track in artillery.director._tracks:
		if str(track.enemy) == "mortar":
			mortar_mult = float(track.mult)
	check(mortar_mult > 1.3, "which brings more Mortars (x%.1f)" % mortar_mult)
	check_eq(artillery.director._repeating.size(), 1, "and schedules repeating bombardments")
	artillery.director.timeline_time = float(artillery.director._repeating[0].next) + 0.1
	for i in 90:
		artillery.step(DT)
	check(artillery.director.bombarding() or artillery.hazards.count > 0, "one of which is under way a few seconds after its start time")
	_free(artillery)


func test_enemies_get_faster_late_in_a_run() -> void:
	fresh_profile()
	var arena := _sector(1)
	arena.step(DT)
	var early := arena.enemies.speed_mult
	arena.director.timeline_time = 200.0
	arena.step(DT)
	var mid := arena.enemies.speed_mult
	arena.director.timeline_time = 295.0
	arena.step(DT)
	var late := arena.enemies.speed_mult
	check_near(early, 1.0, 0.001, "the opening minutes run at normal speed")
	check(mid > early, "by 3:20 enemies have sped up (%.2f)" % mid)
	check(late > mid and late <= 1.25, "and again by the end, within reason (%.2f)" % late)
	_free(arena)


# --------------------------------------------------------------- set pieces

func test_set_pieces_arrive_from_the_edge_not_on_top_of_the_player() -> void:
	fresh_profile()
	for kind: String in ["pack", "pincer", "line"]:
		var arena := _quiet()
		arena.director.view_half = Vector2(410.0, 730.0)
		var announced: Array = []
		arena.announced.connect(func(text: String, _style: String) -> void: announced.append(text))
		var before := arena.enemies.count
		arena.director._fire({"type": kind, "enemy": "swarmer", "count": 12, "label": kind.to_upper()})
		arena.enemies._flush_spawns()
		var spawned := arena.enemies.count - before
		check_eq(spawned, 12, "%s: twelve enemies arrive" % kind)
		check_eq(announced, [kind.to_upper()], "%s: it is announced" % kind)
		var nearest := INF
		var angles: Array[float] = []
		for i in range(before, arena.enemies.count):
			var offset := Vector2(arena.enemies.x[i] - arena.player.x, arena.enemies.y[i] - arena.player.y)
			nearest = minf(nearest, offset.length())
			angles.append(offset.angle())
		check(nearest > 330.0, "%s: nothing appears near the player (closest %.0f)" % [kind, nearest])
		if kind == "pincer":
			var sides := 0
			var reference := angles[0]
			for angle in angles:
				if absf(angle_difference(angle, reference)) > PI * 0.5:
					sides += 1
			check(sides >= 4 and sides <= 8, "pincer: the group is split across opposite sides (%d of 12 opposite)" % sides)
		_free(arena)


## What a careful player does about blast circles: look at where each one will
## go off and head somewhere none of them will catch you. Returns the direction
## to move (zero to stay put), or NAN components if no direction is safe - the
## definition of unavoidable damage.
func _dodge(arena: Arena) -> Vector2:
	var here := Vector2(arena.player.x, arena.player.y)
	var speed := arena.player.move_speed * 0.92
	var margin := arena.player.radius * 0.5 + 8.0
	var options: Array[Vector2] = [Vector2.ZERO]
	for k in 16:
		options.append(Vector2.from_angle(TAU * float(k) / 16.0))
	for option in options:
		var safe := true
		for i in arena.hazards.count:
			var centre := Vector2(arena.hazards.x_of(i), arena.hazards.y_of(i))
			var there := here + option * speed * maxf(arena.hazards.time_left(i), 0.0)
			if there.distance_to(centre) < arena.hazards.radius_of(i) + margin:
				safe = false
				break
		if safe:
			return option
	return Vector2(NAN, NAN)


func test_a_bombardment_can_always_be_avoided() -> void:
	fresh_profile()
	var total_hits := 0
	var trapped := 0
	var shells := 0
	for run_seed in [3, 4, 5, 6, 7, 8, 9, 10]:
		var arena := _quiet(3, run_seed)
		var announced: Array = []
		arena.announced.connect(func(text: String, _style: String) -> void: announced.append(text))
		arena.director._fire({"type": "bombard", "label": "BOMBARDMENT", "count": 16})
		check_eq(announced, ["BOMBARDMENT"], "seed %d: the bombardment is announced" % run_seed)
		var hp := arena.player.hp
		var heading := Vector2.ZERO
		for i in int(12.0 / DT):
			var choice := _dodge(arena)
			if is_nan(choice.x):
				trapped += 1
			else:
				heading = choice
			arena.move_input = heading
			arena.step(DT)
		shells += arena.hazards.spawned_total
		# Every shell shows its blast circle for its whole fuse.
		check(arena.hazards.shortest_warning >= 1.0, "seed %d: every shell gave at least a second of warning (%.2f)" % [run_seed, arena.hazards.shortest_warning])
		if arena.player.hp < hp:
			total_hits += 1
		_free(arena)
	check_eq(shells, 16 * 8, "all the shells of eight bombardments landed")
	check_eq(trapped, 0, "at no moment was every direction about to be hit")
	check_eq(total_hits, 0, "and a player who heads for clear ground was never hit")


func test_standing_still_in_a_bombardment_does_hurt() -> void:
	fresh_profile()
	var arena := _quiet(3)
	arena.director._fire({"type": "bombard", "label": "BOMBARDMENT", "count": 6})
	var hp := arena.player.hp
	for i in int(6.0 / DT):
		arena.step(DT)
	check(arena.player.hp < hp, "the first shell is aimed at the player, so ignoring it costs health")
	_free(arena)


# ------------------------------------------------------------------ enemies

func test_mortar_shells_where_the_player_is_heading() -> void:
	fresh_profile()
	var arena := _quiet(2)
	var mortar := arena.enemies.spawn(arena.enemies.type_of("mortar"), arena.player.x + 420.0, arena.player.y)
	arena.enemies.timer[mortar] = 0.05
	check_eq(arena.enemies.ai[mortar], EnemySystem.AI_MORTAR, "the Mortar uses its own behaviour")
	arena.move_input = Vector2(0.0, 1.0)
	var fired_at := -1.0
	var wound_up := false
	var target := Vector2.ZERO
	var warning := 0.0
	var radius := 0.0
	var player_then := Vector2.ZERO
	for i in int(4.0 / DT):
		arena.step(DT)
		if arena.enemies.count > 0 and arena.enemies.state[0] == 1:
			wound_up = true
		if arena.hazards.count > 0 and fired_at < 0.0:
			fired_at = arena.time
			target = Vector2(arena.hazards.x_of(0), arena.hazards.y_of(0))
			warning = arena.hazards.time_left(0)
			radius = arena.hazards.radius_of(0)
			player_then = Vector2(arena.player.x, arena.player.y)
			break
	check(wound_up, "it glows before it fires")
	check(fired_at > 0.0, "it fires a shell")
	check(warning >= 1.0, "the shell takes over a second to land (%.2f s)" % warning)
	check(target.y > player_then.y + 30.0, "aimed ahead of the moving player (%.0f px ahead)" % (target.y - player_then.y))
	check(target.distance_to(player_then) < radius, "but close enough that carrying on would be hit")

	# Carry straight on and it lands on you; turn and it does not.
	var hp := arena.player.hp
	arena.move_input = Vector2(-1.0, 0.0)
	for i in int((warning + 0.2) / DT):
		arena.step(DT)
	check_eq(arena.player.hp, hp, "turning aside avoids it")
	_free(arena)

	arena = _quiet(2)
	mortar = arena.enemies.spawn(arena.enemies.type_of("mortar"), arena.player.x + 420.0, arena.player.y)
	arena.enemies.timer[mortar] = 0.05
	hp = arena.player.hp
	for i in int(3.0 / DT):
		arena.step(DT)
	check(arena.player.hp < hp, "standing still is hit")
	_free(arena)


func test_bomber_plants_itself_and_gives_time_to_leave() -> void:
	fresh_profile()
	var arena := _quiet(3)
	var bomber := arena.enemies.spawn(arena.enemies.type_of("bomber"), arena.player.x + 260.0, arena.player.y)
	check_eq(arena.enemies.ai[bomber], EnemySystem.AI_BOMBER, "the Bomber uses its own behaviour")
	var kills := arena.combat.kills
	var armed_at := -1.0
	var fuse := 0.0
	var radius := 0.0
	for i in int(5.0 / DT):
		arena.step(DT)
		if arena.hazards.count > 0 and armed_at < 0.0:
			armed_at = arena.time
			fuse = arena.hazards.time_left(0)
			radius = arena.hazards.radius_of(0)
			break
	check(armed_at > 0.0, "it runs in and arms next to the player")
	check(fuse >= 0.7, "its blast circle is on screen for the whole fuse (%.2f s)" % fuse)
	var escape_time := (radius + arena.player.radius) / arena.player.move_speed
	check(escape_time < fuse, "walking out of the circle takes less time than the fuse (%.2f s of %.2f s)" % [escape_time, fuse])
	var hp := arena.player.hp
	arena.move_input = Vector2(-1.0, 0.0)
	for i in int((fuse + 0.3) / DT):
		arena.step(DT)
	check_eq(arena.player.hp, hp, "a player who walks away is not hurt")
	check_eq(arena.enemies.count, 0, "the Bomber is gone after it goes off")
	check_eq(arena.combat.kills, kills, "and it does not count as a kill")
	check_eq(arena.pickups.count, 0, "or drop anything")
	_free(arena)

	arena = _quiet(3)
	arena.enemies.spawn(arena.enemies.type_of("bomber"), arena.player.x + 200.0, arena.player.y)
	hp = arena.player.hp
	for i in int(5.0 / DT):
		arena.step(DT)
	check(arena.player.hp < hp, "a player who stays put is")
	_free(arena)


func test_weaver_comes_in_from_the_side() -> void:
	fresh_profile()
	var arena := _quiet(2)
	var weaver := arena.enemies.spawn(arena.enemies.type_of("weaver"), arena.player.x + 280.0, arena.player.y)
	check_eq(arena.enemies.ai[weaver], EnemySystem.AI_WEAVER, "the Weaver uses its own behaviour")
	var start := Vector2(arena.enemies.x[0] - arena.player.x, arena.enemies.y[0] - arena.player.y)
	var swung := 0.0
	var closest := start.length()
	var hp := arena.player.hp
	for i in int(6.0 / DT):
		arena.step(DT)
		if arena.enemies.count == 0:
			break
		var offset := Vector2(arena.enemies.x[0] - arena.player.x, arena.enemies.y[0] - arena.player.y)
		swung = maxf(swung, absf(angle_difference(start.angle(), offset.angle())))
		closest = minf(closest, offset.length())
	check(swung > 0.6, "it swings round the player rather than running straight in (%.0f degrees)" % rad_to_deg(swung))
	check(closest < 60.0, "and still closes for the strike (closest %.0f)" % closest)
	check(arena.player.hp < hp, "which lands on a player who never moves")
	_free(arena)


func test_new_threats_survive_a_real_sector_three_run() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 9)
	config.tier = 3
	config.base_mods = {"max_hp": 100000000.0}
	var arena := _arena(config)
	var seen := {}
	var zones := 0
	var zone_count := 0
	for i in int(290.0 * 30.0):
		arena.step(1.0 / 30.0)
		if i % 15 == 0:
			for e in arena.enemies.count:
				seen[arena.enemies.type_ids[arena.enemies.type[e]]] = true
		if arena.hazards.count > zone_count:
			zones += arena.hazards.count - zone_count
		zone_count = arena.hazards.count
	for type_id: String in ["weaver", "mortar", "bomber", "swarmer", "dasher", "shooter"]:
		check(seen.has(type_id), "Sector 3 fielded %ss" % type_id)
	check(zones > 40, "the floor was dangerous: %d telegraphed blast zones" % zones)
	check(arena.hazards.shortest_warning >= HazardSystem.MIN_DELAY, "and none of them gave less than the minimum warning (%.2f s)" % arena.hazards.shortest_warning)
	check(arena.hazards.count <= HazardSystem.MAX, "within the hazard budget")
	check(arena.enemies.count <= arena.enemies.capacity, "and the enemy budget")
	check(arena.combat.kills > 500, "with the fight still working (%d kills)" % arena.combat.kills)
	_free(arena)
