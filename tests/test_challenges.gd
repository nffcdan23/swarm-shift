extends TestSuite
## Daily and Weekly Challenges: the schedule, the run they set up, rewards that
## pay once per period, and the clock check.

const DT := 1.0 / 30.0
const DAY := 86400


func _fresh(cleared: int = 12) -> ChallengeService:
	fresh_profile()
	app.save.section("sectors")["highest_cleared"] = cleared
	return app.challenges


func _result(c: Dictionary, cleared: bool, run_id: String, kills: int = 1500) -> Dictionary:
	return {
		"run_id": run_id, "mode": CampaignService.MODE_CHALLENGE, "tier": int(c.tier), "effective_tier": float(c.tier), "core": "vanguard",
		"time": 330.0 if cleared else 180.0, "kills": kills, "elites": 2, "bosses": 1 if cleared else 0, "level": 22, "level_ups": 21,
		"damage": 80000.0, "credits_picked": 500, "credit_gain": 1.0, "cleared": cleared, "died": not cleared, "abandoned": false,
		"synergies": [], "revives": 0, "weapons": {}, "passives": {}, "augments": [], "damage_by_source": {}, "cycle": 0,
		"threat": 0, "challenge_kind": str(c.kind), "challenge_id": str(c.id),
	}


# ----------------------------------------------------------------- schedule

func test_a_period_always_gives_the_same_challenge() -> void:
	var challenges := _fresh()
	for kind in ChallengeService.KINDS:
		var a := challenges.challenge(kind)
		var b := challenges.challenge(kind)
		check_eq([a.id, a.seed, a.tier, a.rules, a.weapons], [b.id, b.seed, b.tier, b.rules, b.weapons], "%s is stable within its period" % kind)
	# Thirty days in a row: varied, and each one valid.
	var seen := {}
	var today := challenges.period_index(ChallengeService.DAILY)
	for k in 30:
		var c := challenges.challenge(ChallengeService.DAILY, today + k)
		seen["%s|%s" % [str(c.rules), str(c.weapons)]] = true
		check(not (c.weapons as Array).is_empty(), "day %d has weapons" % k)
		check(not GameData.flag(app.data.weapon(str((c.weapons as Array)[0])), "support"), "and never starts with one that cannot kill")
		check_eq((c.rules as Array).size(), 1, "a daily has one rule")
	check(seen.size() >= 15, "thirty days bring at least fifteen different challenges (%d)" % seen.size())
	# Weeklies leave out the loadouts and rules marked for Dailies only.
	var cfg := GameData.dict(app.data.retention, "challenges")
	var daily_only: Array = []
	for entry: Dictionary in GameData.list(cfg, "loadouts"):
		if not GameData.flag(entry, "weekly", true):
			daily_only.append(GameData.text(entry, "name"))
	for rule_id: String in GameData.dict(cfg, "rules"):
		if not GameData.flag(GameData.dict(GameData.dict(cfg, "rules"), rule_id), "weekly", true):
			daily_only.append(rule_id)
	check(not daily_only.is_empty(), "some loadouts and rules are Daily-only")
	for k in 40:
		var week := challenges.challenge(ChallengeService.WEEKLY, k)
		check(not daily_only.has(str(week.loadout)), "week %d's weapons are fit for a Weekly (%s)" % [k, week.loadout])
		check((week.weapons as Array).size() >= 2, "and are two")
		for rule_id: String in week.rules:
			check(not daily_only.has(rule_id), "week %d's rules are fit for a Weekly (%s)" % [k, rule_id])
	var weekly := challenges.challenge(ChallengeService.WEEKLY)
	check_eq((weekly.rules as Array).size(), 2, "a weekly has two rules")
	check((weekly.rules as Array)[0] != (weekly.rules as Array)[1], "two different ones")
	check(int(weekly.threat) > 0 and (weekly.mutators as Array).has("t_patrols"), "and Threat on top")
	check(int((weekly.reward as Dictionary).crystals) > int((challenges.challenge(ChallengeService.DAILY).reward as Dictionary).crystals), "and pays more")


func test_the_schedule_does_not_depend_on_the_engine_hash() -> void:
	check_eq(ChallengeService.stable_hash(""), 2166136261, "FNV-1a of nothing")
	check_eq(ChallengeService.stable_hash("a"), 0xe40c292c, "FNV-1a of 'a'")


func test_periods_turn_over_in_utc_and_count_down() -> void:
	var challenges := _fresh()
	var day := challenges.period_index(ChallengeService.DAILY)
	var left := challenges.seconds_left(ChallengeService.DAILY)
	check(left > 0 and left <= DAY, "a day has 0-24 hours left (%d s)" % left)
	app.clock.offset_seconds += left + 1
	check_eq(challenges.period_index(ChallengeService.DAILY), day + 1, "and then the next day begins")
	check(challenges.seconds_left(ChallengeService.WEEKLY) <= 7 * DAY, "a week has at most 7 days left")
	# Weeks begin on Monday 00:00 UTC: 5 January 1970 was a Monday.
	check_eq(challenges.period_index(ChallengeService.WEEKLY, 4 * DAY), 0, "Monday 5 January 1970 starts week 0")
	check_eq(challenges.period_index(ChallengeService.WEEKLY, 4 * DAY - 1), -1, "the Sunday before is the week before")


func test_the_sector_never_outruns_the_campaign() -> void:
	var challenges := _fresh(3)
	for k in 20:
		var c := challenges.challenge(ChallengeService.WEEKLY, k)
		check(int(c.tier) <= 4, "a weekly for a player at Sector 3 is at most Sector 4 (%d)" % int(c.tier))
	check(not _fresh(2).unlocked(), "challenges open with Sector 3, like Overdrive")


# ---------------------------------------------------------------------- run

func test_the_run_is_set_up_from_the_challenge() -> void:
	var challenges := _fresh()
	challenges.select(ChallengeService.WEEKLY)
	var c := challenges.challenge(ChallengeService.WEEKLY)
	var config := RunConfig.from_profile(app, CampaignService.MODE_CHALLENGE)
	check_eq(config.mode, CampaignService.MODE_CHALLENGE, "a challenge run")
	check_eq(config.tier, int(c.tier), "in its sector")
	check_eq(config.rng_seed, int(c.seed), "on its fixed seed")
	check_eq(config.start_weapon, str((c.weapons as Array)[0]), "starting with its first weapon")
	check_eq(Array(config.weapon_pool), Array(c.weapons), "and offered only its weapons")
	for id: String in c.mutators:
		check(config.extra_mutators.has(id), "with %s" % id)
	check_eq(config.challenge_id, str(c.id), "tagged with its period")

	config.autopilot = true
	config.autopilot_skill = 0.7
	var arena := Arena.new()
	arena.manual_stepping = true
	host.add_child(arena)
	arena.setup(app, config)
	arena.start()
	for s in int(25.0 / DT):
		while arena.state == Arena.State.CHOOSING:
			arena.choose(0)
		arena.step(DT)
	for weapon_id: String in arena.build.weapons:
		check((c.weapons as Array).has(weapon_id), "only its weapons were used (%s)" % weapon_id)
	var result := arena.build_result(false, true, false)
	check_eq(str(result.challenge_id), str(c.id), "the result names the challenge")
	host.remove_child(arena)
	arena.free()


func test_a_challenge_never_counts_as_a_sector_clear() -> void:
	var challenges := _fresh(3)
	var c := challenges.challenge(ChallengeService.DAILY)
	var summary := RunLedger.settle(app, _result(c, true, "no-unlock"))
	check_eq(app.campaign.highest_cleared(), 3, "the campaign does not move")
	check(not bool(summary.first_clear) and int(summary.crystals) == 0, "and no sector first-clear Crystals")


# ------------------------------------------------------------------ rewards

func test_the_reward_pays_once_per_period() -> void:
	var challenges := _fresh()
	# At the top Player Level, so no level-up Crystals muddy the count.
	app.account.add_xp(100000000, "test")
	var c := challenges.challenge(ChallengeService.DAILY)
	var crystals := app.economy.balance(Economy.CRYSTALS)
	var lost := RunLedger.settle(app, _result(c, false, "d-lost"))
	check(not bool((lost.challenge as Dictionary).claimed_now), "a loss pays no challenge reward")
	var won := RunLedger.settle(app, _result(c, true, "d-won"))
	check(bool((won.challenge as Dictionary).claimed_now), "a clear does")
	check_eq(app.economy.balance(Economy.CRYSTALS), crystals + int((c.reward as Dictionary).crystals), "its Crystals banked")
	check_eq(app.stats.value("daily_challenges_done"), 1.0, "counted")
	var again := RunLedger.settle(app, _result(c, true, "d-again"))
	check(not bool((again.challenge as Dictionary).claimed_now), "a second clear the same day pays nothing more")
	check_eq(app.economy.balance(Economy.CRYSTALS), crystals + int((c.reward as Dictionary).crystals), "not one Crystal")
	check(challenges.challenge(ChallengeService.DAILY).claimed, "the lobby shows it collected")
	check_eq(int(challenges.best(str(c.id)).kills), 1500, "and the best result is kept")
	check(not app.leaderboards.submitted.is_empty(), "each result was offered to the leaderboard seam")
	check_eq(str(app.leaderboards.submitted[-1].board), str(c.leaderboard), "on the daily board")

	app.clock.offset_seconds += DAY
	var tomorrow := challenges.challenge(ChallengeService.DAILY)
	check(not bool(tomorrow.claimed), "tomorrow is a new challenge")
	check(bool(RunLedger.settle(app, _result(tomorrow, true, "d-tomorrow")).challenge.claimed_now), "with its own reward")


func test_a_run_that_crosses_midnight_still_pays() -> void:
	var challenges := _fresh()
	var c := challenges.challenge(ChallengeService.DAILY)
	app.clock.offset_seconds += challenges.seconds_left(ChallengeService.DAILY) + 60
	check(bool(RunLedger.settle(app, _result(c, true, "late")).challenge.claimed_now), "yesterday's challenge, finished a minute after midnight, pays")
	var old := challenges.challenge(ChallengeService.DAILY, challenges.period_index(ChallengeService.DAILY) - 3)
	check(not bool(RunLedger.settle(app, _result(old, true, "stale")).challenge.claimed_now), "one from three days ago does not")


func test_turning_the_clock_back_pauses_challenges() -> void:
	var challenges := _fresh()
	check(challenges.can_play(), "playable now")
	# Forward three days and play: that much is the player's to take.
	app.clock.offset_seconds += 3 * DAY
	check(challenges.can_play(), "playable with the clock moved forward")
	# Then back to today: challenges wait until real time catches up.
	app.clock.offset_seconds -= 3 * DAY
	check(not challenges.clock_ok(), "the clock is now behind what was seen")
	check(not challenges.can_play(), "so challenges cannot start")
	check_eq(challenges.open_count(), 0, "nor show as waiting")
	var c := challenges.challenge(ChallengeService.DAILY)
	check(not bool(RunLedger.settle(app, _result(c, true, "rewound")).challenge.claimed_now), "and a clear pays nothing")
	# A small correction (daylight saving, a manual fix) is fine.
	app.clock.offset_seconds += 3 * DAY - 3600
	check(challenges.clock_ok(), "within an hour of the latest time seen, challenges work again")


func test_old_saves_start_with_no_challenge_history() -> void:
	var backend := MemorySaveBackend.new()
	backend.text = FileAccess.get_file_as_string("res://tests/fixtures/profile_v1_endgame_before_research.save")
	app.boot(backend)
	check((app.save.section("challenges").get("claimed", []) as Array).is_empty(), "nothing claimed")
	check(app.challenges.clock_ok(), "and the clock is trusted")
	if app.campaign.highest_cleared() >= app.challenges.unlock_sector():
		check_eq(app.challenges.open_count(), 2, "both of today's challenges are waiting")
	fresh_profile()
