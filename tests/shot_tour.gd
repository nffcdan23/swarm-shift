extends Node
## Screenshot tour. Drives the real game through every screen and saves a PNG
## of each, so a visual change can be reviewed without playing through by hand.
##
##   godot --path . --resolution 540x1170 -- --shots=/absolute/output/folder
##   ... --shots=/folder --only=run        only shots whose name contains "run"
##
## Needs a window (not --headless): it captures what is actually rendered.
## Uses the in-memory profile, so it never touches a real save.

const DT := 1.0 / 30.0

var _dir := ""
var _only := ""
var _main: Node
var _count := 0


func _ready() -> void:
	_dir = App.cli_text("shots", "user://shots")
	_only = App.cli_text("only")
	_main = get_parent()
	DirAccess.make_dir_recursive_absolute(_dir)
	await _run()
	print("Shot tour: %d screenshots in %s" % [_count, _dir])
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	if not _only.is_empty() and not shot_name.contains(_only):
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_dir, shot_name])
	_count += 1


func _wants(group: String) -> bool:
	return _only.is_empty() or group.contains(_only) or _only.contains(group)


func _run() -> void:
	var menu: MenuShell = _main.menu
	await _wait(1.0)
	if _wants("menu"):
		await _shot("01_menu_home_new_player")

		# A profile part-way through, so every state of every screen is visible.
		App.account.add_xp(2600, "tour")
		App.economy.grant(Economy.CREDITS, 3200, "tour")
		App.economy.grant(Economy.CRYSTALS, 140, "tour")
		App.meta.buy("m_damage")
		App.meta.buy("m_damage")
		App.meta.buy("m_hp")
		App.arsenal.unlock(ArsenalService.WEAPONS, "chain")
		App.campaign.record_run(CampaignService.MODE_SECTOR, 1, true, 312.0)
		App.campaign.record_run(CampaignService.MODE_SECTOR, 2, true, 298.0)
		App.campaign.record_run(CampaignService.MODE_SECTOR, 3, true, 305.0)
		App.stats.add("kills", 4200.0)
		App.stats.add("runs", 9.0)
		App.missions.apply_run({"kills": 620, "time": 310, "bosses": 1, "level_ups": 24, "level": 25, "damage": 61000, "credits": 340, "elites": 4, "runs": 1})
		menu.set_active(true)
		# Let the "Player Level" toasts from the grants above clear first.
		await _wait(3.6)
		await _shot("02_menu_home")
		# A later sector: its mutator is named before the run is started.
		App.campaign.select(4)
		menu.refresh_current()
		await _wait(0.4)
		await _shot("02_menu_home_sector_4")
		App.campaign.select(1)
		for tab: String in ["upgrades", "arsenal", "missions", "shop"]:
			menu.show_tab(tab)
			await _wait(0.6)
			await _shot("03_menu_%s" % tab)
		menu.show_tab("upgrades")
		var upgrades := menu.screen("upgrades") as UpgradesScreen
		upgrades._quantity.select(1)
		upgrades._on_quantity(1)
		await _wait(0.5)
		await _shot("03_menu_upgrades_x5")
		upgrades._quantity.select(0)
		upgrades._on_quantity(0)
		(menu.screen("missions") as MissionsScreen).show_achievements()
		menu.show_tab("missions")
		await _wait(0.6)
		await _shot("04_menu_achievements")
		menu.show_tab("home")
		await _wait(0.3)
		for entry: Array in [["settings", SettingsModal.new(menu)], ["licences", LicencesModal.new()], ["profile", ProfileModal.new()], ["daily", DailyRewardModal.new(menu)]]:
			var dialog: Modal = entry[1]
			menu.open_dialog(dialog)
			await _wait(0.7)
			await _shot("05_dialog_%s" % str(entry[0]))
			dialog.close()
			await _wait(0.4)

	if _wants("sector"):
		await _sector_three()
	if _wants("combat"):
		await _combat_readability()
	if not (_wants("run") or _wants("boss") or _wants("levelup") or _wants("results") or _wants("pause")):
		return
	App.cli["autoplay"] = "1"
	App.cli["seed"] = "4"
	App.campaign.select(1)
	_main.start_run(CampaignService.MODE_SECTOR)
	await _wait(1.2)
	var arena: Arena = _main.arena
	var hud: Hud = _main.hud
	arena.ad_revives_left = 0
	arena.free_revives_left = 0
	await _shot("10_run_start")

	await _advance(arena, 18.0)
	await _shot("11_run_early")
	await _advance(arena, 75.0)
	await _shot("12_run_one_minute")

	# Level-up choice, shown as a player would see it.
	var bot := arena.autopilot
	arena.autopilot = null
	arena.add_xp(arena.xp_needed + 1.0)
	await _wait(1.3)
	await _shot("13_levelup")
	if arena.state == Arena.State.CHOOSING:
		arena.choose(0)
	arena.autopilot = bot
	await _wait(0.3)

	await _advance(arena, 170.0)
	await _shot("14_run_mid")
	hud.open_pause()
	await _wait(0.8)
	await _shot("15_pause")
	hud._pause._show_confirm()
	await _wait(0.4)
	await _shot("15_pause_end_run")
	hud.handle_back()
	await _wait(0.2)
	hud.handle_back()
	await _wait(0.4)

	await _advance(arena, 250.0)
	await _shot("16_run_late")

	# Every weapon at once (ignoring the slot limit) to review their visuals.
	for weapon_id: String in App.data.weapon_defs():
		arena.grant_weapon(weapon_id, 4)
	await _advance(arena, arena.time + 7.0)
	await _shot("16_all_weapons")
	await _advance(arena, arena.time + 2.5)
	await _shot("16_all_weapons_b")

	arena.player.hp = arena.player.max_hp
	arena.director.timeline_time = maxf(arena.director.timeline_time, arena.director.boss_time() - 7.0)
	await _wait(1.6)
	await _shot("17_boss_warning")
	await _advance(arena, arena.time + 9.0)
	arena.player.hp = arena.player.max_hp
	await _shot("18_boss_fight")
	await _advance(arena, arena.time + 6.0)
	arena.player.hp = arena.player.max_hp
	await _shot("19_boss_attack")

	arena.autopilot = null
	arena.player.invulnerable_for = 0.0
	arena.player.take_hit(1000000.0, arena.player.x, arena.player.y)
	await _wait(0.5)
	await _shot("20_death")
	await _wait(3.2)
	await _shot("21_results_collecting")
	await _wait(6.0)
	await _shot("21_results")


## Sector 3 adds Weavers, Mortars, Bombers and bombardments: show them.
func _sector_three() -> void:
	App.cli["autoplay"] = "1"
	App.cli["seed"] = "9"
	App.campaign.record_run(CampaignService.MODE_SECTOR, 1, true, 312.0)
	App.campaign.record_run(CampaignService.MODE_SECTOR, 2, true, 298.0)
	App.campaign.select(3)
	_main.start_run(CampaignService.MODE_SECTOR)
	await _wait(1.2)
	var arena: Arena = _main.arena
	for weapon_id: String in ["pulse", "orbit", "nova"]:
		arena.grant_weapon(weapon_id, 3)
	await _advance(arena, 4.0)
	await _shot("30_sector_3_start")
	await _advance(arena, 141.5)
	await _shot("31_sector_3_bombardment")
	await _advance(arena, 150.0)
	await _shot("32_sector_3_mid")
	await _advance(arena, 205.0)
	await _shot("33_sector_3_mortars")
	await _advance(arena, 264.5)
	await _shot("34_sector_3_bombers")
	_main._teardown_run()
	_main.menu.set_active(true)
	await _wait(0.5)
	App.campaign.select(1)


## Readability under load: enemy fire through a crowd and explosions, then the
## Prism Lance and Plasma Mines working a swarm.
func _combat_readability() -> void:
	App.cli["seed"] = "12"
	App.campaign.select(1)
	_main.start_run(CampaignService.MODE_SECTOR)
	await _wait(1.2)
	var arena: Arena = _main.arena
	arena.autopilot = null
	arena.director.paused = true
	arena.player.invulnerable_for = 1000.0
	for weapon_id: String in ["pulse", "scatter", "missile"]:
		arena.grant_weapon(weapon_id, 5)
	arena.build.add_augment("volatile")
	arena.refresh_build()
	var types := ["swarmer", "brute", "shooter", "swarmer", "splitter"]
	for k in 320:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(120.0, 640.0)
		arena.enemies.spawn(arena.enemies.type_of(types[k % types.size()]), arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)
	var src := arena.combat.source("tour")
	for s in 24:
		for k in 2:
			var angle := arena.rng.randf() * TAU
			arena.bullets.spawn(arena.player.x + cos(angle) * 420.0, arena.player.y + sin(angle) * 420.0, -cos(angle) * 250.0, -sin(angle) * 250.0, 1.0)
		if s % 6 == 0:
			arena.combat.blast(arena.player.x + arena.rng.randf_range(-260.0, 260.0), arena.player.y + arena.rng.randf_range(-260.0, 260.0), 130.0, 1.0e6, src, Color.WHITE)
		arena.step(DT)
	for k in 6:
		await get_tree().process_frame
	await _shot("35_combat_enemy_fire_in_a_crowd")
	_main._teardown_run()
	await _wait(0.3)
	_main.start_run(CampaignService.MODE_SECTOR)
	await _wait(1.2)
	arena = _main.arena
	arena.autopilot = null
	arena.director.paused = true
	arena.player.invulnerable_for = 1000.0
	arena.grant_weapon("laser", 5)
	arena.grant_weapon("mine", 5)
	# After the grants, which recompute the player's stats: no level-up screens.
	arena.player.xp_gain = 0.0
	for k in 260:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(160.0, 600.0)
		arena.enemies.spawn(arena.enemies.type_of("swarmer" if k % 4 else "brute"), arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)
	for s in 75:
		arena.move_input = Vector2(cos(float(s) * 0.05), sin(float(s) * 0.05)) * 0.6
		arena.step(DT)
		if arena.weapon_node("laser").is_firing() and s > 50:
			break
	for k in 4:
		await get_tree().process_frame
	await _shot("36_combat_lance_and_mines")
	arena.move_input = Vector2.ZERO
	_main._teardown_run()
	_main.menu.set_active(true)
	await _wait(0.5)


## Runs the simulation flat out until `target` seconds of run time, then lets a
## few real frames render so effects are mid-flight in the capture.
func _advance(arena: Arena, target: float) -> void:
	var guard := 0
	while arena.time < target and arena.state != Arena.State.ENDED and guard < 40000:
		if arena.state == Arena.State.PLAYING:
			# Keep the bot alive: the tour ends the run itself, on cue.
			arena.player.hp = maxf(arena.player.hp, arena.player.max_hp * 0.6)
			arena.step(DT)
		else:
			await get_tree().process_frame
		guard += 1
		if guard % 240 == 0:
			await get_tree().process_frame
	await _wait(0.5)
