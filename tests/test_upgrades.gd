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



## Plays a run as a person would, rerolling now and then, and counts cards that
## were on the hand just closed (picked away or rerolled) turning up again.
func _play_counting_returns(run_seed: int, seconds: float) -> Array:
	var arena := _arena(_player_config(run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 104729
	var returns := PackedStringArray()
	var hands := 0
	var late_hands := 0
	var passed := {}
	for step in int(seconds / DT):
		if arena.state == Arena.State.ENDED:
			break
		var guard := 0
		while arena.state == Arena.State.CHOOSING and guard < 50:
			guard += 1
			hands += 1
			if arena.build.weapon_order.size() >= 4:
				late_hands += 1
			for offer in arena.current_offers:
				if passed.has(UpgradeSystem.offer_key(offer)) and str(offer.kind) in [UpgradeSystem.KIND_WEAPON, UpgradeSystem.KIND_PASSIVE, UpgradeSystem.KIND_AUGMENT]:
					returns.append("L%d %s" % [arena.level, UpgradeSystem.offer_key(offer)])
			passed.clear()
			if rng.randf() < 0.25 and arena.can_reroll():
				for offer in arena.current_offers:
					passed[UpgradeSystem.offer_key(offer)] = true
				arena.reroll()
				continue
			var pick := rng.randi_range(0, arena.current_offers.size() - 1)
			for i in arena.current_offers.size():
				if i != pick:
					passed[UpgradeSystem.offer_key(arena.current_offers[i])] = true
			arena.choose(pick)
		arena.step(DT)
	_free(arena)
	return [returns, hands, late_hands]


## Playtest feedback (build 8): late in a run, the two cards passed on at one
## level-up came straight back at the next, level after level.
func test_passed_cards_do_not_come_straight_back() -> void:
	fresh_profile()
	var returns := PackedStringArray()
	var hands := 0
	var late_hands := 0
	for run_seed in [41, 42, 43, 44, 45, 46]:
		var result := _play_counting_returns(run_seed, 600.0)
		returns.append_array(result[0])
		hands += int(result[1])
		late_hands += int(result[2])
	for line in returns.slice(0, 10):
		print("    [returned] ", line)
	check(hands > 200, "enough hands to mean something (%d)" % hands)
	check(late_hands > 80, "many with every weapon slot full, where the pool is small (%d)" % late_hands)
	check_eq(returns.size(), 0, "no passed or rerolled-away card is dealt in the very next hand (%d hands)" % hands)


func test_a_reroll_deals_a_different_hand() -> void:
	fresh_profile()
	var arena := _arena(_player_config(47))
	arena.rerolls_left = 20
	arena.add_xp(arena.xp_needed + 1.0)
	arena.step(DT)
	check_eq(arena.state, Arena.State.CHOOSING, "a hand is on the table")
	for k in 20:
		var before := {}
		for offer in arena.current_offers:
			before[UpgradeSystem.offer_key(offer)] = true
		check(arena.reroll(), "reroll %d is allowed" % k)
		var again := 0
		for offer in arena.current_offers:
			if before.has(UpgradeSystem.offer_key(offer)):
				again += 1
		check_eq(again, 0, "reroll %d shares no card with the hand it replaced" % k)
		check(_hand_problems(arena).is_empty(), "and is a valid hand")
	_free(arena)


## Build almost complete: two weapons one level short, everything else maxed.
func _nearly_done(arena: Arena) -> void:
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	for weapon_id: String in ["pulse", "scatter", "orbit", "nova"]:
		arena.grant_weapon(weapon_id, weapon_max - (1 if weapon_id in ["pulse", "scatter"] else 0))
	var passive_ids: Array = app.data.passives().keys()
	for passive_id: String in passive_ids.slice(0, 5):
		arena.build.set_passive(passive_id, GameData.integer(GameData.dict(app.data.passives(), passive_id), "max_level", 5))
	for augment_id: String in app.data.augments():
		arena.build.add_augment(augment_id)
	arena.build.evolved["orbit"] = "x"
	arena.build.evolved["nova"] = "x"
	arena.refresh_build()


func _ids(hand: Array[Dictionary]) -> Array:
	var ids := []
	for offer in hand:
		ids.append(str(offer.id))
	ids.sort()
	return ids


func test_last_cards_left_rest_one_hand_then_return() -> void:
	fresh_profile()
	var arena := _arena(_player_config(48))
	_nearly_done(arena)
	var ups := arena.upgrades
	var hand := ups.roll(3)
	var real := 0
	var filler := -1
	for i in hand.size():
		if str(hand[i].kind) == UpgradeSystem.KIND_WEAPON:
			real += 1
		else:
			filler = i
	check_eq(real, 2, "the only two upgrades left are both dealt: %s" % [_ids(hand)])
	ups.note_hand(hand, filler)
	var next := ups.roll(3)
	for offer in next:
		check(str(offer.kind) in [UpgradeSystem.KIND_HEAL, UpgradeSystem.KIND_CREDITS, UpgradeSystem.KIND_PURGE],
			"right after passing them, the hand is fallback cards (%s)" % offer.id)
	ups.note_hand(next, 0)
	var after := ups.roll(3)
	var back := 0
	for offer in after:
		if str(offer.kind) == UpgradeSystem.KIND_WEAPON:
			back += 1
	check_eq(back, 2, "a hand later they are back, rather than gone for good")
	_free(arena)


func test_passing_fades_a_card_and_taking_it_resets() -> void:
	fresh_profile()
	var arena := _arena(_player_config(49))
	var ups := arena.upgrades
	var card := {"kind": UpgradeSystem.KIND_PASSIVE, "id": "amplifier", "level": 1}
	var other := {"kind": UpgradeSystem.KIND_PASSIVE, "id": "fortune", "level": 1}
	var counts_before := 0
	for offer in _deal_many(arena, 600):
		if str(offer.id) == "amplifier":
			counts_before += 1
	for k in 3:
		ups.note_hand([card, other], 1)
	check_eq(ups.passes(card), 3, "three passes are remembered")
	check_eq(ups.passes(other), 0, "the card taken is not counted as passed")
	check(ups.is_resting(card), "the card passed last sits out the next hand")
	ups.roll(3)
	check(not ups.is_resting(card), "for one hand only")
	var counts_after := 0
	for offer in _deal_many(arena, 600):
		if str(offer.id) == "amplifier":
			counts_after += 1
	print("    amplifier in 600 hands: %d fresh, %d after three passes" % [counts_before, counts_after])
	check(counts_after < counts_before * 0.5, "a card passed three times turns up far less often")
	check(counts_after > 0, "but still turns up")
	ups.note_hand([card], 0)
	check_eq(ups.passes(card), 0, "taking it clears the record")
	_free(arena)


func test_evolutions_are_never_held_back() -> void:
	fresh_profile()
	var config := _player_config(50)
	config.evolutions = {"pulse": ["repeater", "breach"]}
	config.base_mods["run.evolutions"] = 1.0
	var arena := _arena(config)
	var weapon_max := GameData.integer(app.data.weapons, "max_level", 5)
	arena.grant_weapon("pulse", weapon_max)
	var ups := arena.upgrades
	var hand := ups.roll(3)
	var evolutions := 0
	var other := -1
	for i in hand.size():
		if str(hand[i].kind) == UpgradeSystem.KIND_EVOLUTION:
			evolutions += 1
		else:
			other = i
	check(evolutions > 0, "a weapon at max offers its evolution")
	ups.note_hand(hand, other)
	var again := 0
	for offer in ups.roll(3):
		if str(offer.kind) == UpgradeSystem.KIND_EVOLUTION:
			again += 1
	check_eq(again, evolutions, "passed on once, the evolution is still offered next hand")
	_free(arena)



## Playtest (build 8): "there are new weapons, but my mate has not come across
## them in two runs". Reaching a Player Level only puts a weapon on sale; once
## bought, it must turn up in runs.
func test_a_bought_weapon_turns_up_in_runs() -> void:
	fresh_profile()
	app.account.add_xp(app.account.xp_needed(1) + 1, "test")
	check(app.account.level() >= 2, "Player Level 2 reached")
	check(not RunConfig.from_profile(app, CampaignService.MODE_SECTOR).weapon_pool.has("chain"),
		"Arc Caster is on sale, not in runs, until it is bought")
	var for_sale := app.arsenal.weapons_for_sale()
	check(not for_sale.is_empty() and str(for_sale[0].id) == "chain", "the Arsenal lists it for sale")
	app.economy.grant(Economy.CREDITS, 400, "test")
	check(app.arsenal.unlock(ArsenalService.WEAPONS, "chain"), "it can be bought")
	check(app.arsenal.weapons_for_sale().is_empty(), "and is no longer for sale")
	var offered_runs := 0
	var runs := 10
	for run_seed in range(runs):
		var config := RunConfig.from_profile(app, CampaignService.MODE_SECTOR)
		config.rng_seed = 500 + run_seed
		config.autopilot = false
		config.base_mods = {"max_hp": 1000000.0}
		check(config.weapon_pool.has("chain"), "a bought weapon is in the run's pool")
		var arena := _arena(config)
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed
		var offered := false
		for step in int(240.0 / DT):
			if arena.state == Arena.State.ENDED or offered:
				break
			var guard := 0
			while arena.state == Arena.State.CHOOSING and guard < 50:
				guard += 1
				for offer in arena.current_offers:
					offered = offered or str(offer.id) == "chain"
				arena.choose(rng.randi_range(0, arena.current_offers.size() - 1))
			arena.step(DT)
		if offered:
			offered_runs += 1
		_free(arena)
	check(offered_runs >= 9, "Arc Caster is offered in nearly every run once bought (%d of %d)" % [offered_runs, runs])



## A player who has played a while: the four starters well used.
func _seasoned_starters() -> void:
	for id: String in ["pulse", "scatter", "orbit", "nova"]:
		app.save.section("mastery")[id] = {"xp": 2000}


## Playtest (build 8, follow-up): a weapon bought in the Arsenal did not always
## turn up in the run. The newest one not yet used is now always the first
## weapon card, and unused weapons come up more than well-worn ones.
func test_a_newly_bought_weapon_is_the_first_weapon_card() -> void:
	fresh_profile()
	_seasoned_starters()
	for id: String in ["chain", "missile"]:
		app.arsenal.grant(ArsenalService.WEAPONS, id, "test")
	check_eq(app.arsenal.featured_weapon(), "missile", "the most recent purchase not yet used is featured")
	for run_seed in range(10):
		var config := RunConfig.from_profile(app, CampaignService.MODE_SECTOR)
		config.rng_seed = 900 + run_seed
		config.autopilot = false
		config.base_mods = {"max_hp": 1000000.0}
		check_eq(config.featured_weapon, "missile", "run %d features it" % run_seed)
		var arena := _arena(config)
		# The first hand that offers any new weapon (a hand is shuffled, and
		# can hold more than one).
		var first_weapon_hand: Array = []
		for step in int(120.0 / DT):
			if not first_weapon_hand.is_empty():
				break
			while arena.state == Arena.State.CHOOSING:
				var weapons: Array = []
				for offer in arena.current_offers:
					if str(offer.kind) == UpgradeSystem.KIND_WEAPON and bool(offer.is_new):
						weapons.append(str(offer.id))
				if first_weapon_hand.is_empty():
					first_weapon_hand = weapons
				arena.choose(0)
			arena.step(DT)
		check(first_weapon_hand.has("missile"), "run %d: the first hand with a weapon offers the new purchase (%s)" % [run_seed, first_weapon_hand])
		_free(arena)
	# Used once (it earned Mastery XP), the next newest unused one takes over.
	app.save.section("mastery")["missile"] = {"xp": 40}
	check_eq(app.arsenal.featured_weapon(), "chain", "once used, the previous purchase is featured")
	app.save.section("mastery")["chain"] = {"xp": 40}
	check_eq(app.arsenal.featured_weapon(), "", "and with everything used, none is")
	check_eq(RunConfig.from_profile(app, CampaignService.MODE_SECTOR).featured_weapon, "", "so runs feature nothing")


func test_untried_weapons_come_up_more_and_early_hands_offer_one() -> void:
	fresh_profile()
	_seasoned_starters()
	app.arsenal.grant(ArsenalService.WEAPONS, "chain", "test")
	var config := RunConfig.from_profile(app, CampaignService.MODE_SECTOR)
	check(float(config.weapon_interest.get("chain", 1.0)) > float(config.weapon_interest.get("scatter", 1.0)),
		"an unused weapon is weighted above a well-used starter")
	config.rng_seed = 77
	config.autopilot = false
	config.featured_weapon = ""
	config.base_mods = {"max_hp": 1000000.0}
	var arena := _arena(config)
	arena.level = 5
	var chain := 0
	var scatter := 0
	for k in 600:
		for offer in arena.upgrades.roll(3):
			if str(offer.id) == "chain":
				chain += 1
			elif str(offer.id) == "scatter":
				scatter += 1
	check(chain > scatter * 2, "over 600 hands the unused Arc Caster comes up far more than Scatter Shot (%d vs %d)" % [chain, scatter])
	var without := 0
	for k in 200:
		var has_weapon := false
		for offer in arena.upgrades.roll(3):
			has_weapon = has_weapon or (str(offer.kind) == UpgradeSystem.KIND_WEAPON and bool(offer.is_new))
		if not has_weapon:
			without += 1
	check_eq(without, 0, "until the build has a second weapon, every hand offers one")
	for id: String in ["chain", "scatter", "orbit"]:
		arena.grant_weapon(id, 1)
	var full_hands_with_new := 0
	for k in 200:
		for offer in arena.upgrades.roll(3):
			if str(offer.kind) == UpgradeSystem.KIND_WEAPON and bool(offer.is_new):
				full_hands_with_new += 1
	check_eq(full_hands_with_new, 0, "with every slot full, no new weapon is offered")
	_free(arena)



func test_the_railgun_is_a_rare_find() -> void:
	fresh_profile()
	check_eq(GameData.text(app.data.weapon("railgun"), "rarity"), "epic", "the Railgun is marked epic")
	var config := RunConfig.for_testing(app.data, 5)
	config.autopilot = false
	config.weapon_pool = ["pulse", "scatter", "railgun"]
	config.start_weapon = "pulse"
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	var weights := {}
	for offer: Dictionary in arena.upgrades._candidates(false):
		if str(offer.kind) == UpgradeSystem.KIND_WEAPON and bool(offer.is_new):
			weights[str(offer.id)] = [str(offer.rarity), float(offer.weight)]
	check(weights.has("railgun") and weights.has("scatter"), "both are on offer as new weapons")
	if weights.has("railgun") and weights.has("scatter"):
		check_eq(weights.railgun[0], "epic", "the Railgun's card is epic")
		check_eq(weights.scatter[0], "rare", "an ordinary new weapon's card is still rare")
		check(float(weights.railgun[1]) < float(weights.scatter[1]) * 0.6,
			"and it turns up far less often (%.2f against %.2f)" % [weights.railgun[1], weights.scatter[1]])
	host.remove_child(arena)
	arena.free()
