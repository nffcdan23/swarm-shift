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
		await _wait(0.7)
		await _shot("02_menu_home")
		for tab: String in ["upgrades", "arsenal", "missions", "shop"]:
			menu.show_tab(tab)
			await _wait(0.6)
			await _shot("03_menu_%s" % tab)
		(menu.screen("missions") as MissionsScreen).show_achievements()
		menu.show_tab("missions")
		await _wait(0.6)
		await _shot("04_menu_achievements")
		menu.show_tab("home")
		await _wait(0.3)
		for entry: Array in [["settings", SettingsModal.new(menu)], ["profile", ProfileModal.new()], ["daily", DailyRewardModal.new(menu)]]:
			var dialog: Modal = entry[1]
			menu.open_dialog(dialog)
			await _wait(0.7)
			await _shot("05_dialog_%s" % str(entry[0]))
			dialog.close()
			await _wait(0.4)

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
	await _wait(4.2)
	await _shot("21_results")


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
