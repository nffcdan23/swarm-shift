extends TestSuite
## Upgrade cards: nothing maxed, owned or over its cap is ever offered or
## applied, and a hand is always dealt, even when the whole build is complete.

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


## A run a person is playing: no autopilot, cannot die, levels quickly.
func _player_config(run_seed: int) -> RunConfig:
	var config := RunConfig.for_testing(app.data, run_seed)
	config.autopilot = false
	config.base_mods = {"max_hp": 1000000.0, "xp_gain_pct": 4.0}
	return config


## Why `offer` should not be on the table for this build, or "" if it is fine.
func _offer_problem(arena: Arena, offer: Dictionary) -> String:
	var id := str(offer.id)
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	match str(offer.kind):
		UpgradeSystem.KIND_WEAPON:
			var have := arena.build.weapon_level(id)
			if have >= weapon_max:
				return "weapon %s offered at level %d although it is maxed (%d)" % [id, int(offer.level), have]
			if int(offer.level) != have + 1:
				return "weapon %s offered at level %d, owned at %d" % [id, int(offer.level), have]
		UpgradeSystem.KIND_PASSIVE:
			var have := arena.build.passive_level(id)
			var cap := GameData.integer(GameData.dict(app.data.passives(), id), "max_level", 5)
			if have >= cap:
				return "passive %s offered at level %d although it is maxed (%d/%d)" % [id, int(offer.level), have, cap]
			if int(offer.level) != have + 1:
				return "passive %s offered at level %d, owned at %d" % [id, int(offer.level), have]
		UpgradeSystem.KIND_AUGMENT:
			if arena.build.augments.has(id):
				return "augment %s offered although owned" % id
	return ""


## How many owned weapons and passives are at their cap.
func _maxed_count(arena: Arena) -> int:
	var n := 0
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	for id: String in arena.build.weapon_order:
		if arena.build.weapon_level(id) >= weapon_max:
			n += 1
	for id: String in arena.build.passive_order:
		if arena.build.passive_level(id) >= GameData.integer(GameData.dict(app.data.passives(), id), "max_level", 5):
			n += 1
	return n


func _hand_problems(arena: Arena) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for offer in arena.current_offers:
		var key := "%s:%s" % [offer.kind, offer.id]
		if seen.has(key) and str(offer.kind) in [UpgradeSystem.KIND_WEAPON, UpgradeSystem.KIND_PASSIVE, UpgradeSystem.KIND_AUGMENT]:
			problems.append("%s offered twice in one hand" % key)
		seen[key] = true
		var problem := _offer_problem(arena, offer)
		if not problem.is_empty():
			problems.append(problem)
	return problems


## Plays like a person: picks a random card, sometimes rerolls first, checks
## every hand dealt. Returns [problems, hands dealt].
func _play_checking_hands(run_seed: int, seconds: float) -> Array:
	var arena := _arena(_player_config(run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7919
	var problems := PackedStringArray()
	var hands := 0
	var maxed_hands := 0
	var steps := int(seconds / DT)
	for step in steps:
		if arena.state == Arena.State.ENDED:
			break
		var guard := 0
		while arena.state == Arena.State.CHOOSING and guard < 50:
			guard += 1
			hands += 1
			if _maxed_count(arena) > 0:
				maxed_hands += 1
			for problem in _hand_problems(arena):
				problems.append("t=%.1f L%d: %s" % [arena.time, arena.level, problem])
			if rng.randf() < 0.3 and arena.can_reroll():
				arena.reroll()
				continue
			arena.choose(rng.randi_range(0, arena.current_offers.size() - 1))
		arena.step(DT)
	_free(arena)
	return [problems, hands, maxed_hands]


func test_reproduce_no_maxed_card_is_ever_dealt() -> void:
	fresh_profile()
	var all_problems := PackedStringArray()
	var hands := 0
	var maxed_hands := 0
	for run_seed in [1, 2, 3, 4, 5, 6]:
		var result := _play_checking_hands(run_seed, 420.0)
		all_problems.append_array(result[0])
		hands += int(result[1])
		maxed_hands += int(result[2])
	for problem in all_problems.slice(0, 12):
		print("    [card] ", problem)
	check(hands > 100, "enough hands were dealt to mean something (%d)" % hands)
	check(maxed_hands >= 30, "many of them with something already maxed (%d)" % maxed_hands)
	check_eq(all_problems.size(), 0, "no maxed, owned or mis-levelled card in %d hands" % hands)


func _deal_many(arena: Arena, hands: int) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	for k in hands:
		seen.append_array(arena.upgrades.roll(3, k % 4 == 0))
	return seen


func test_maxed_weapons_are_never_offered() -> void:
	fresh_profile()
	var arena := _arena(_player_config(31))
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	arena.grant_weapon("pulse", weapon_max)
	arena.grant_weapon("scatter", weapon_max - 1)
	var pulse := 0
	var scatter_levels := {}
	for offer in _deal_many(arena, 300):
		if str(offer.kind) == UpgradeSystem.KIND_WEAPON and str(offer.id) == "pulse":
			pulse += 1
		if str(offer.kind) == UpgradeSystem.KIND_WEAPON and str(offer.id) == "scatter":
			scatter_levels[int(offer.level)] = true
	check_eq(pulse, 0, "a maxed weapon never appears in 300 hands, caches included")
	check_eq(scatter_levels.keys(), [weapon_max], "a weapon one short of max is offered only at its final level")
	arena.grant_weapon("scatter", weapon_max)
	var after := 0
	for offer in _deal_many(arena, 300):
		if str(offer.id) == "scatter":
			after += 1
	check_eq(after, 0, "and never again once that final level is taken")
	_free(arena)


func test_maxed_passives_are_never_offered() -> void:
	fresh_profile()
	var arena := _arena(_player_config(32))
	var maxed := {}
	for passive_id: String in ["amplifier", "fortune", "multishot"]:
		var cap := GameData.integer(GameData.dict(app.data.passives(), passive_id), "max_level", 5)
		arena.build.set_passive(passive_id, cap)
		maxed[passive_id] = cap
	arena.refresh_build()
	var offered := 0
	for offer in _deal_many(arena, 300):
		if str(offer.kind) == UpgradeSystem.KIND_PASSIVE and maxed.has(str(offer.id)):
			offered += 1
	check_eq(offered, 0, "passives at their own caps (5, 3 and 2) never appear")
	_free(arena)


func test_over_cap_and_stale_cards_are_rejected() -> void:
	fresh_profile()
	var arena := _arena(_player_config(33))
	var ups := arena.upgrades
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	arena.grant_weapon("pulse", weapon_max)
	check(not ups.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "pulse", "level": weapon_max + 1}), "a weapon past its cap is refused")
	check_eq(arena.build.weapon_level("pulse"), weapon_max, "and its level is unchanged")
	arena.grant_weapon("scatter", 2)
	check(not ups.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "scatter", "level": 2}), "a stale card for a level already owned is refused")
	check(not ups.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "scatter", "level": 4}), "skipping a level is refused")
	check(ups.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "scatter", "level": 3}), "the next level is accepted")
	arena.build.set_passive("fortune", 3)
	check(not ups.apply({"kind": UpgradeSystem.KIND_PASSIVE, "id": "fortune", "level": 4}), "a passive past its cap is refused")
	check_eq(arena.build.passive_level("fortune"), 3, "and stays at 3")
	arena.build.add_augment("volatile")
	check(not ups.apply({"kind": UpgradeSystem.KIND_AUGMENT, "id": "volatile", "level": 1}), "an augment already owned is refused")
	check(not ups.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "no_such_weapon", "level": 1}), "an unknown id is refused")
	for weapon_id: String in ["orbit", "nova"]:
		arena.grant_weapon(weapon_id, 1)
	check(not ups.apply({"kind": UpgradeSystem.KIND_WEAPON, "id": "chain", "level": 1}), "a fifth weapon with four slots full is refused")
	check_eq(arena.diag.upgrades_rejected, 7, "every refusal is counted")

	# Through the run: an invalid card on the table deals a fresh hand for the
	# same level instead of applying it or stranding the screen.
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	check_eq(arena.state, Arena.State.CHOOSING, "a level-up hand is on the table")
	var level_pending := arena.pending_choices()
	arena.current_offers[0] = {"kind": UpgradeSystem.KIND_WEAPON, "id": "pulse", "level": weapon_max + 1, "rarity": "epic"}
	var serial := arena.choice_serial
	arena.choose(0)
	check_eq(arena.state, Arena.State.CHOOSING, "the run is still waiting for a valid pick")
	check(arena.choice_serial > serial, "with a new hand")
	check_eq(arena.pending_choices(), level_pending, "and the level-up was not used up")
	check(_hand_problems(arena).is_empty(), "the new hand is valid")
	check_eq(arena.build.weapon_level("pulse"), weapon_max, "pulse is still at its cap")
	arena.choose(0)
	check_eq(arena.state, Arena.State.PLAYING, "a valid pick resumes play")
	_free(arena)


func test_everything_maxed_still_deals_a_fair_hand() -> void:
	fresh_profile()
	var arena := _arena(_player_config(34))
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	for weapon_id: String in ["pulse", "scatter", "orbit", "nova"]:
		arena.grant_weapon(weapon_id, weapon_max)
	var passive_ids: Array = app.data.passives().keys()
	for passive_id: String in passive_ids.slice(0, 5):
		arena.build.set_passive(passive_id, GameData.integer(GameData.dict(app.data.passives(), passive_id), "max_level", 5))
	for augment_id: String in app.data.augments():
		arena.build.add_augment(augment_id)
	arena.refresh_build()
	var hand := arena.upgrades.roll(3)
	check_eq(hand.size(), 3, "three cards are still dealt")
	var kinds := {}
	for offer in hand:
		kinds[str(offer.kind)] = true
	check_eq(kinds.size(), 3, "repair, salvage and purge, one each")
	for offer in hand:
		check(str(offer.kind) in [UpgradeSystem.KIND_HEAL, UpgradeSystem.KIND_CREDITS, UpgradeSystem.KIND_PURGE], "only fallback cards (%s)" % offer.kind)

	var crystals := app.economy.balance(Economy.CRYSTALS)
	var hands := 0
	var steps := int(60.0 / DT)
	for s in steps:
		while arena.state == Arena.State.CHOOSING:
			hands += 1
			check(not arena.current_offers.is_empty(), "never an empty hand")
			var salvage := -1
			for i in arena.current_offers.size():
				if str(arena.current_offers[i].kind) == UpgradeSystem.KIND_CREDITS:
					salvage = i
			arena.choose(salvage if salvage >= 0 else 0)
		arena.add_xp(arena.xp_needed * 0.05)
		arena.step(DT)
	check(hands >= 10, "levels keep coming and every hand is answerable (%d)" % hands)
	check_eq(arena.state, Arena.State.PLAYING, "no softlock")
	var salvage_each := GameData.integer(app.data.run_cfg(), "fallback_credits", 40)
	check(arena.credits <= float(hands * salvage_each) * arena.player.credit_gain + arena.pickups.collected_credits * arena.player.credit_gain + 0.01,
		"salvage pays only its fixed run Credits (%.0f)" % arena.credits)
	check_eq(app.economy.balance(Economy.CRYSTALS), crystals, "and never premium currency")
	_free(arena)


func test_pause_and_resume_during_a_choice() -> void:
	fresh_profile()
	var arena := _arena(_player_config(35))
	var hud := Hud.new(arena)
	host.add_child(hud)
	await wait_frames(2)
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	check_eq(arena.state, Arena.State.CHOOSING, "a hand is on the table")
	var serial := arena.choice_serial
	var hand := arena.current_offers.duplicate()
	for k in 20:
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		arena.set_paused(true)
		await wait_frames(1)
		hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		arena.set_paused(false)
		await wait_frames(1)
	check_eq(arena.state, Arena.State.CHOOSING, "losing and regaining focus 20 times leaves the choice open")
	check_eq(arena.choice_serial, serial, "with the same hand")
	check_eq(arena.current_offers, hand, "and the same cards")
	var overlay: LevelUpOverlay = null
	for child in hud.get_child(0).get_children():
		if child is LevelUpOverlay:
			overlay = child
	check(overlay != null and overlay.is_visible_in_tree() and overlay.serial == serial, "the cards are on screen for that hand")
	await wait_seconds(LevelUpOverlay.INPUT_GUARD + 0.1)
	arena.choose(0)
	check_eq(arena.state, Arena.State.PLAYING, "picking resumes play")
	arena.set_paused(true)
	check_eq(arena.state, Arena.State.PAUSED, "an ordinary pause still works afterwards")
	arena.set_paused(false)
	check_eq(arena.state, Arena.State.PLAYING, "and resumes")
	hud.queue_free()
	_free(arena)
	await wait_frames(2)


func test_final_upgrade_card_does_not_say_max_level() -> void:
	fresh_profile()
	var arena := _arena(_player_config(36))
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	arena.grant_weapon("scatter", weapon_max - 1)
	var final_offer: Dictionary = {}
	for k in 200:
		for offer in arena.upgrades.roll(3):
			if str(offer.id) == "scatter":
				final_offer = offer
		if not final_offer.is_empty():
			break
	if check(not final_offer.is_empty(), "the final Scatter Shot upgrade is offered"):
		var card := UpgradeCard.make(final_offer)
		check_eq(card._status_text(), "FINAL UPGRADE", "the card that completes an item says so")
		final_offer["level"] = 2
		final_offer["max_level"] = weapon_max
		var ordinary := UpgradeCard.make(final_offer)
		check_eq(ordinary._status_text(), "LEVEL 2", "an ordinary upgrade still shows its level")
		card.free()
		ordinary.free()
	_free(arena)
