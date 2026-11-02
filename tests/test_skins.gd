extends TestSuite
## Skins are worth having, are looks and nothing else, and every one is reachable.

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


func test_every_skin_builds_all_its_layers() -> void:
	fresh_profile()
	for id: String in app.data.skins():
		var visual := CoreVisual.new()
		host.add_child(visual)
		visual.build(GameData.dict(app.data.skins(), id), Color.CYAN)
		visual.animate(0.5)
		visual.animate(0.5, 1.3)
		visual.set_flash(1.0)
		check(visual.get_child_count() >= 4, "%s has a stack of layers (%d)" % [id, visual.get_child_count()])
		check(visual.get_child_count() <= 24, "%s stays cheap to draw (%d sprites)" % [id, visual.get_child_count()])
		host.remove_child(visual)
		visual.free()


func test_the_headline_skins_are_more_than_a_colour_swap() -> void:
	fresh_profile()
	var seen_bodies: Array = []
	for id: String in ["void", "solar", "glacier", "quantum", "inferno"]:
		var def := GameData.dict(app.data.skins(), id)
		var look := GameData.dict(def, "visual")
		var body := GameData.text(look, "body")
		check(not body.is_empty(), "%s has its own silhouette" % id)
		check(not seen_bodies.has(body), "%s does not share one" % id)
		seen_bodies.append(body)
		check(look.has("aura"), "%s has an aura" % id)
		check(def.has("trail"), "%s has its own trail" % id)
		check(def.has("kill_tint"), "%s has its own kill effect" % id)
		check(def.has("weapon_tint"), "%s themes the weapons" % id)


func test_a_skin_changes_nothing_about_a_run() -> void:
	var outcomes: Array[String] = []
	for skin_id: String in ["default", "void", "solar", "quantum", "paragon"]:
		fresh_profile()
		var config := RunConfig.for_testing(app.data, 71)
		config.skin = skin_id
		config.skin_def = GameData.dict(app.data.skins(), skin_id)
		config.base_mods = {"max_hp": 100000.0}
		var arena := _arena(config)
		for s in int(90.0 / DT):
			arena.step(DT)
		outcomes.append("%d kills, %d level, %.1f damage, %.1f hp, %.2f,%.2f" % [arena.combat.kills, arena.level, arena.combat.total_damage, arena.player.hp, arena.player.x, arena.player.y])
		_free(arena)
	for outcome in outcomes:
		check_eq(outcome, outcomes[0], "the same seed plays out identically in every skin")


func test_no_skin_carries_a_gameplay_modifier() -> void:
	fresh_profile()
	for id: String in app.data.skins():
		var def := GameData.dict(app.data.skins(), id)
		check(not def.has("mods"), "%s has no modifiers" % id)
	app.arsenal.grant(ArsenalService.SKINS, "void", "test")
	var plain := RunConfig.from_profile(app).base_mods.duplicate()
	app.arsenal.select_skin("void")
	check_eq(RunConfig.from_profile(app).base_mods, plain, "and selecting one changes no modifier")


func test_enemy_fire_is_still_drawn_on_top_of_every_skin() -> void:
	fresh_profile()
	var config := RunConfig.for_testing(app.data, 72)
	config.skin = "solar"
	config.skin_def = GameData.dict(app.data.skins(), "solar")
	var arena := _arena(config)
	var gfx := arena.gfx
	check(gfx.hostile.get_index() > gfx.actors.get_index(), "the hostile layer comes after the actors, so it draws last")
	check_eq(arena.player.z_index, 0, "the player does not jump layers")
	check_eq(arena.player.radius, GameData.num(GameData.dict(app.data.game, "player"), "radius", 17.0), "and the hit radius is the game's, not the skin's")
	_free(arena)


## Enemy fire is a red shot with a white-hot centre. A skin that turns its own
## weapons or kill bursts that red would put a shot-shaped thing everywhere.
func test_no_skin_paints_the_battlefield_in_enemy_fire_red() -> void:
	fresh_profile()
	var hostile := Color(1.0, 0.36, 0.3)
	for id: String in app.data.skins():
		var def := GameData.dict(app.data.skins(), id)
		for key: String in ["weapon_tint", "kill_tint"]:
			if not def.has(key):
				continue
			var tint := GameData.color(def, key)
			var distance := absf(tint.h - hostile.h)
			distance = minf(distance, 1.0 - distance)
			check(distance > 0.05 or tint.s < 0.4, "%s's %s is well clear of enemy fire (hue distance %.3f)" % [id, key, distance])


func test_a_skin_keeps_the_factory_footprint() -> void:
	fresh_profile()
	for id: String in app.data.skins():
		var look := GameData.dict(GameData.dict(app.data.skins(), id), "visual")
		check(GameData.num(GameData.dict(look, "aura"), "scale", 1.0) <= 1.8, "%s's aura stays near the core" % id)
		check(GameData.num(GameData.dict(look, "plates"), "radius", 1.0) <= 1.5, "%s's plates stay near the core" % id)
		var alpha := GameData.num(GameData.dict(look, "glow"), "alpha", 0.55)
		check(alpha <= 0.75, "%s's glow does not wash out what is around it" % id)


func test_credit_skins_need_their_level_then_their_price() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 100000, "test")
	check(not app.arsenal.unlock(ArsenalService.SKINS, "glacier"), "not before Player Level 12")
	app.account.add_xp(10000, "test")
	check(app.account.level() >= 12, "levelled")
	var balance := app.economy.balance(Economy.CREDITS)
	check(app.arsenal.unlock(ArsenalService.SKINS, "glacier"), "bought")
	check_eq(app.economy.balance(Economy.CREDITS), balance - 12000, "for its price")
	check(app.arsenal.select_skin("glacier"), "selected")
	check_eq(app.arsenal.selected_skin(), "glacier", "kept")


func test_feat_skins_are_earned_and_cannot_be_bought() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 100000000, "test")
	check(not app.arsenal.is_owned(ArsenalService.SKINS, "paragon"), "not owned")
	check(not app.arsenal.unlock(ArsenalService.SKINS, "paragon"), "no amount of Credits buys it")
	for id: String in ["pulse", "scatter", "orbit"]:
		app.save.section("mastery")[id] = {"xp": app.mastery.rank_xp(app.mastery.max_rank())}
	check(app.arsenal.is_owned(ArsenalService.SKINS, "paragon"), "three Master ranks earn it")
	check(not app.arsenal.is_owned(ArsenalService.SKINS, "overseer"), "the other is still locked")
	app.save.section("sectors")["highest_cleared"] = 20
	check(app.arsenal.is_owned(ArsenalService.SKINS, "overseer"), "clearing Sector 20 earns it")


func test_paid_exclusives_stay_exclusive() -> void:
	fresh_profile()
	app.economy.grant(Economy.CREDITS, 100000000, "test")
	app.economy.grant(Economy.CRYSTALS, 1000000, "test")
	check(not app.arsenal.unlock(ArsenalService.SKINS, "aurum"), "Aurum still only comes from the Starter Pack")


func test_a_selected_skin_survives_a_restart() -> void:
	var backend := fresh_profile()
	app.arsenal.grant(ArsenalService.SKINS, "void", "test")
	app.arsenal.select_skin("void")
	app.save.flush()
	var reopened := MemorySaveBackend.new()
	reopened.text = backend.text
	app.boot(reopened)
	check_eq(app.arsenal.selected_skin(), "void", "kept")
	check(app.arsenal.is_owned(ArsenalService.SKINS, "void"), "and owned")
