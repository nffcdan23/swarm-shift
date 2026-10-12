extends TestSuite
## Profile, economy, progression, retention and monetisation rules.
## Every test starts from a fresh in-memory profile.


func test_save_round_trip() -> void:
	var backend := fresh_profile()
	check(app.save.is_new_profile, "first boot creates a profile")
	app.economy.grant(Economy.CREDITS, 250, "test")
	app.save.flush()
	app.boot(backend)
	check(not app.save.is_new_profile, "second boot loads the existing profile")
	check_eq(app.economy.balance(Economy.CREDITS), 250, "credits survive a reload")
	check(app.save.integrity_ok, "checksum matches an untouched save")


func test_save_detects_tampering() -> void:
	var backend := fresh_profile()
	app.economy.grant(Economy.CREDITS, 10, "test")
	app.save.flush()
	backend.text = backend.text.replace("\\\"credits\\\":10", "\\\"credits\\\":999999")
	app.boot(backend)
	check_eq(app.economy.balance(Economy.CREDITS), 999999, "edited value is what was read")
	check(not app.save.integrity_ok, "edit is flagged by the checksum")


func test_save_survives_garbage() -> void:
	var backend := MemorySaveBackend.new()
	backend.text = "{ this is not json"
	app.boot(backend)
	check(app.save.is_new_profile, "corrupt save falls back to a new profile instead of crashing")
	check_eq(app.account.level(), 1, "new profile starts at level 1")


func test_migration_fills_defaults_and_keeps_unknown_keys() -> void:
	var migrated := SaveMigrations.migrate({"version": 1, "currencies": {"credits": 7}, "from_the_future": 42})
	check_eq(int(migrated.currencies.credits), 7, "existing values are kept")
	check_eq(int(migrated.currencies.crystals), 0, "missing nested keys get defaults")
	check(migrated.has("settings"), "missing sections get defaults")
	check_eq(int(migrated.from_the_future), 42, "unknown keys are preserved")
	check_eq(int(migrated.version), SaveMigrations.CURRENT_VERSION, "version is stamped")


func test_save_is_debounced() -> void:
	var backend := fresh_profile()
	var writes := backend.writes
	app.economy.grant(Economy.CREDITS, 1, "test")
	app.economy.grant(Economy.CREDITS, 1, "test")
	app.save.tick(0.5)
	check_eq(backend.writes, writes, "no write before the debounce window")
	app.save.tick(SaveService.DEBOUNCE_SECONDS)
	check_eq(backend.writes, writes + 1, "one write for a burst of changes")


func test_economy_rules() -> void:
	fresh_profile()
	check(not app.economy.spend(Economy.CREDITS, 50, "test"), "cannot spend what you do not have")
	app.economy.grant(Economy.CREDITS, 100, "test")
	check(app.economy.spend(Economy.CREDITS, 60, "test"), "can spend within balance")
	check_eq(app.economy.balance(Economy.CREDITS), 40, "balance after spend")
	app.economy.grant(Economy.CREDITS, -500, "test")
	check_eq(app.economy.balance(Economy.CREDITS), 40, "negative grants are ignored")
	check(not app.economy.spend(Economy.CREDITS, -5, "test"), "negative spends are rejected")
	check_eq(int(app.stats.value("credits_earned")), 100, "earned credits are tracked")
	check(app.analytics_log.count(Analytics.CURRENCY_EARNED) >= 1, "earning is logged")
	check(app.analytics_log.count(Analytics.CURRENCY_SPENT) >= 1, "spending is logged")


func test_account_levels_and_rewards() -> void:
	fresh_profile()
	var needed := app.account.xp_needed(1)
	var gained := app.account.add_xp(needed - 1, "test")
	check(gained.is_empty(), "one short of the threshold does not level")
	gained = app.account.add_xp(1, "test")
	check_eq(gained.size(), 1, "reaching the threshold levels once")
	check_eq(app.account.level(), 2, "now level 2")
	check_eq(app.account.xp(), 0, "xp carries over from zero")
	check(app.economy.balance(Economy.CREDITS) > 0, "level-up paid credits")
	var big := app.account.add_xp(100000, "test")
	check(big.size() > 5, "a large grant can cross many levels")
	check(app.economy.balance(Economy.CRYSTALS) > 0, "milestone levels paid crystals")


func test_account_level_cap() -> void:
	fresh_profile()
	app.account.add_xp(2000000000, "test")
	check_eq(app.account.level(), app.account.max_level(), "level stops at the cap")
	check(app.account.add_xp(500, "test").is_empty(), "no more levels after the cap")


func test_meta_upgrades() -> void:
	fresh_profile()
	var first_cost := app.meta.cost("m_damage")
	check(not app.meta.buy("m_damage"), "cannot buy without credits")
	app.economy.grant(Economy.CREDITS, 1000000, "test")
	check(app.meta.buy("m_damage"), "can buy with credits")
	check_eq(app.meta.level("m_damage"), 1, "level went up")
	check(app.meta.cost("m_damage") > first_cost, "next level costs more")
	var mods := {}
	app.meta.collect_mods(mods)
	check_near(float(mods.get("damage_pct", 0.0)), 0.04, 0.0001, "one level contributes its mod once")
	while app.meta.buy("m_damage"):
		pass
	check(app.meta.is_maxed("m_damage"), "can be bought up to the cap")
	check_eq(app.meta.cost("m_damage"), 0, "maxed upgrade has no cost")
	check(not app.meta.buy("m_damage"), "cannot exceed the cap")


func test_arsenal_gates() -> void:
	fresh_profile()
	check(app.arsenal.is_owned(ArsenalService.WEAPONS, "pulse"), "default weapon is owned")
	check(not app.arsenal.is_owned(ArsenalService.WEAPONS, "missile"), "gated weapon starts locked")
	app.economy.grant(Economy.CREDITS, 100000, "test")
	check(not app.arsenal.unlock(ArsenalService.WEAPONS, "missile"), "credits alone do not bypass the level gate")
	app.account.add_xp(5000, "test")
	check(app.arsenal.unlock(ArsenalService.WEAPONS, "missile"), "unlocks once the level gate is met")
	check(app.arsenal.is_owned(ArsenalService.WEAPONS, "missile"), "weapon is now owned")
	check(not app.arsenal.unlock(ArsenalService.WEAPONS, "missile"), "cannot unlock twice")
	check(not app.arsenal.select_core("bastion"), "cannot select a locked core")
	check_eq(app.arsenal.selected_core(), "vanguard", "selection falls back to the default core")


func test_missions_roll_and_reset() -> void:
	fresh_profile()
	var first := app.missions.active()
	check_eq(first.size(), 3, "three missions per day")
	app.missions.refresh()
	check_eq(app.missions.active()[0].id, first[0].id, "same day keeps the same missions")
	var ids := {}
	for mission in first:
		ids[mission.id] = true
	check_eq(ids.size(), 3, "missions are distinct")
	app.clock.offset_seconds += 86400
	app.missions.refresh()
	check_eq(app.missions.active().size(), 3, "a new day rolls a new set")
	check_eq(float(app.missions.active()[0].progress), 0.0, "new set starts at zero")
	app.clock.offset_seconds -= 3 * 86400
	var before: String = str(app.missions.active()[0].id)
	app.missions.refresh()
	check_eq(app.missions.active()[0].id, before, "turning the clock back does not re-roll")


func test_missions_progress_and_claim() -> void:
	fresh_profile()
	var huge := {"kills": 99999, "time": 99999, "bosses": 99, "level_ups": 999, "level": 99, "damage": 9999999, "credits": 99999, "elites": 99, "runs": 99}
	app.missions.apply_run(huge)
	app.missions.notify_event("meta_purchases", 5.0)
	var credits_before := app.economy.balance(Economy.CREDITS)
	for mission in app.missions.active():
		check(bool(mission.complete), "mission '%s' completes" % mission.id)
		check(not app.missions.claim(str(mission.id)).is_empty(), "mission '%s' can be claimed" % mission.id)
		check(app.missions.claim(str(mission.id)).is_empty(), "mission '%s' cannot be claimed twice" % mission.id)
	check(app.economy.balance(Economy.CREDITS) > credits_before, "claims paid credits")
	check(not app.missions.claim_bonus().is_empty(), "all-complete bonus can be claimed")
	check(app.missions.claim_bonus().is_empty(), "bonus cannot be claimed twice")
	check_eq(app.missions.claimable_count(), 0, "nothing left to claim")


func test_achievements_claim_once() -> void:
	fresh_profile()
	check_eq(app.achievements.claimable_count(), 0, "nothing claimable on a new profile")
	app.stats.add("kills", 1500.0)
	check(app.achievements.claimable_count() >= 2, "kill achievements became claimable")
	check(app.achievements.poll_newly_completed().size() >= 2, "newly completed achievements are announced")
	check(app.achievements.poll_newly_completed().is_empty(), "each is announced only once")
	check(app.achievements.claim("first_blood") > 0, "claim pays crystals")
	check_eq(app.achievements.claim("first_blood"), 0, "cannot claim twice")
	check_eq(app.achievements.claim("kills_100k"), 0, "cannot claim an incomplete achievement")


func test_daily_reward_once_per_day() -> void:
	fresh_profile()
	check(app.daily.can_claim(), "claimable on first day")
	check(not app.daily.claim().is_empty(), "claim pays out")
	check(not app.daily.can_claim(), "not claimable again the same day")
	check(app.daily.claim().is_empty(), "second claim pays nothing")
	app.clock.offset_seconds += 86400
	check(app.daily.can_claim(), "claimable the next day")
	check_eq(app.daily.current_index(), 1, "calendar advanced one slot")
	app.clock.offset_seconds += 5 * 86400
	check_eq(app.daily.current_index(), 1, "missing days does not reset the calendar")
	var doubled := app.daily.claim(2)
	var base: Dictionary = app.daily.cycle()[1]
	check_eq(int(doubled.credits), int(base.credits) * 2, "ad-doubled claim pays double")


func test_interstitial_policy() -> void:
	fresh_profile()
	check(not app.ads.should_show_interstitial(), "never on a brand-new profile")
	app.stats.add("runs", 5.0)
	app.ads.note_run_finished()
	check(not app.ads.should_show_interstitial(), "not until enough runs have passed since the last one")
	app.ads.note_run_finished()
	check(app.ads.should_show_interstitial(), "allowed once every cap is satisfied")
	check(await app.ads.maybe_show_interstitial("test"), "interstitial is shown")
	check(not app.ads.should_show_interstitial(), "frequency cap applies straight after")
	app.ads.note_run_finished()
	app.ads.note_run_finished()
	check(not app.ads.should_show_interstitial(), "minimum interval still blocks it")
	app.clock.offset_seconds += 600
	check(app.ads.should_show_interstitial(), "allowed again after the interval")
	check(await app.ads.show_rewarded(AdsService.DOUBLE_REWARDS), "rewarded ad completes")
	check(not app.ads.should_show_interstitial(), "no interstitial after a rewarded ad in the same flow")
	app.ads.note_run_finished()
	check(app.ads.should_show_interstitial(), "a new flow clears that")
	check(await app.store.purchase("remove_ads"), "remove ads can be bought")
	check(not app.ads.should_show_interstitial(), "remove ads stops interstitials")
	check(app.ads.rewarded_available(AdsService.REVIVE), "rewarded ads remain available after remove ads")


func test_rewarded_shop_credits_daily_cap() -> void:
	fresh_profile()
	var cap := app.ads.shop_credit_ads_left()
	check(cap > 0, "there is a daily allowance")
	for i in cap:
		check(await app.ads.claim_shop_credits() > 0, "allowed claim %d pays" % (i + 1))
	check_eq(await app.ads.claim_shop_credits(), 0, "claim beyond the cap pays nothing")
	check_eq(app.economy.balance(Economy.CREDITS), cap * app.ads.shop_credit_reward(), "exactly the capped amount was paid")
	app.clock.offset_seconds += 86400
	check_eq(app.ads.shop_credit_ads_left(), cap, "allowance resets the next day")


func test_declined_rewarded_ad_pays_nothing() -> void:
	fresh_profile()
	(app.ads.provider as MockAdProvider).auto_complete = false
	check(not await app.ads.show_rewarded(AdsService.REVIVE), "an abandoned ad reports no reward")
	check_eq(app.analytics_log.count(Analytics.REWARDED_AD_COMPLETED), 0, "no completion is logged")


func test_store_purchases() -> void:
	fresh_profile()
	check(await app.store.purchase("starter_pack"), "starter pack purchase succeeds")
	check_eq(app.economy.balance(Economy.CRYSTALS), 300, "starter pack crystals granted")
	check_eq(app.economy.balance(Economy.CREDITS), 5000, "starter pack credits granted")
	check(app.arsenal.is_owned(ArsenalService.SKINS, "aurum"), "starter pack skin granted")
	check(not await app.store.purchase("starter_pack"), "a non-consumable cannot be bought twice")
	check_eq(app.economy.balance(Economy.CRYSTALS), 300, "second attempt granted nothing")
	check(await app.store.purchase("crystals_s"), "consumable purchase succeeds")
	check(await app.store.purchase("crystals_s"), "consumables can be bought repeatedly")
	check_eq(app.economy.balance(Economy.CRYSTALS), 540, "consumables stack")
	check(not await app.store.purchase("no_such_product"), "unknown product is rejected")
	check_eq(app.analytics_log.count(Analytics.PURCHASE_COMPLETED), 3, "completed purchases are logged")


func test_store_cancel_and_restore() -> void:
	fresh_profile()
	var provider := app.store.provider as MockStoreProvider
	provider.auto_approve = false
	check(not await app.store.purchase("remove_ads"), "a cancelled purchase fails cleanly")
	check(not app.store.has_entitlement("remove_ads"), "nothing granted on cancel")
	provider.auto_approve = true
	check(await app.store.purchase("starter_pack"), "purchase succeeds")
	var crystals := app.economy.balance(Economy.CRYSTALS)
	# Simulate a reinstall: entitlements gone locally, the store still knows.
	app.save.section("purchases")["entitlements"] = []
	check(not app.store.is_owned("starter_pack"), "entitlement lost locally")
	check_eq(await app.store.restore(), 1, "restore brings it back")
	check(app.store.is_owned("starter_pack"), "entitlement restored")
	check_eq(app.economy.balance(Economy.CRYSTALS), crystals, "restore does not pay currency twice")


func test_run_ledger_pays_out_once_and_unlocks() -> void:
	fresh_profile()
	var result := {
		"mode": CampaignService.MODE_SECTOR, "tier": 1, "core": "vanguard", "time": 320.0,
		"kills": 900, "elites": 4, "bosses": 1, "level": 24, "level_ups": 23, "damage": 80000.0,
		"credits_picked": 200, "credit_gain": 1.0, "cleared": true, "died": false, "abandoned": false,
		"synergies": ["tesla_storm"], "revives": 0,
	}
	var preview := RunLedger.compute(app, result)
	check(int(preview.credits) > 200, "bonus credits are added to pickups")
	check(bool(preview.first_clear), "first clear is recognised")
	var summary := RunLedger.settle(app, result)
	check_eq(app.economy.balance(Economy.CREDITS) >= int(summary.credits), true, "credits were paid")
	check_eq(app.campaign.highest_cleared(), 1, "sector 1 recorded as cleared")
	check_eq(app.campaign.selected(), 2, "selector moves on to sector 2")
	check(app.account.level() > 1, "account levelled up")
	check_eq(int(app.stats.value("kills")), 900, "kills recorded")
	check_eq(int(app.stats.value("synergies_found")), 1, "synergy recorded")
	check(app.economy.balance(Economy.CRYSTALS) >= 10, "first clear paid crystals")
	var again := RunLedger.compute(app, result)
	check(not bool(again.first_clear), "the same sector is not a first clear twice")
	var credits := app.economy.balance(Economy.CREDITS)
	check_eq(RunLedger.double_credits(app, summary), int(summary.credits), "doubling pays the run credits again")
	check_eq(RunLedger.double_credits(app, summary), 0, "doubling only works once")
	check_eq(app.economy.balance(Economy.CREDITS), credits + int(summary.credits), "balance reflects one doubling")


func test_endless_unlock_and_scaling() -> void:
	fresh_profile()
	check(not app.campaign.endless_unlocked(), "endless starts locked")
	for tier in range(1, 4):
		app.campaign.record_run(CampaignService.MODE_SECTOR, tier, true, 300.0)
	check(app.campaign.endless_unlocked(), "endless unlocks after the configured sector")
	var low := app.campaign.scaling(1.0)
	var high := app.campaign.scaling(6.0)
	check_near(float(low.hp), 1.0, 0.0001, "sector 1 is the baseline")
	check(float(high.hp) > float(low.hp), "enemy health scales with sector")
	check(float(high.reward) > float(low.reward), "rewards scale with sector")
	check(float(app.campaign.scaling(500.0).speed) <= 1.3001, "speed scaling is capped")
