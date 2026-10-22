extends TestSuite
## AdMobAdProvider and its consent flow, driven through AdsService against a
## scripted stand-in for the native bridge (tests/fakes/fake_admob_bridge.gd).
## The real bridge is exercised on a phone with `tools/ios_deploy.sh --admob-check`.

var _fakes: Array[FakeAdMobBridge] = []


## A fresh profile and an AdsService on AdMob over `fake`. `tuning` overrides
## the `admob` block of monetization.json for this test.
func _ads(fake: FakeAdMobBridge, tuning: Dictionary = {}) -> AdsService:
	fresh_profile()
	var cfg: Dictionary = app.data.monetization["admob"]
	cfg.merge(tuning, true)
	_fakes.append(fake)
	return AdsService.new(app, AdMobAdProvider.new(fake))


func _settle() -> void:
	await wait_seconds(0.25)


func _cleanup() -> void:
	await wait_seconds(0.1)
	for fake in _fakes:
		fake.free()
	_fakes.clear()


func test_signal_race() -> void:
	var fake := FakeAdMobBridge.new()
	fake.call_deferred("emit_signal", "started")
	check_eq(await SignalRace.first(fake, ["started"], 1.0), ["started"], "a signal without arguments is told apart from a timeout")
	fake.call_deferred("emit_signal", "rewarded_failed_to_load", "no fill")
	check_eq(await SignalRace.first(fake, ["rewarded_loaded", "rewarded_failed_to_load"], 1.0), ["rewarded_failed_to_load", "no fill"], "the first signal wins, with its argument")
	check_eq(await SignalRace.first(fake, ["rewarded_loaded"], 0.15), [], "nothing fired: empty")
	check_eq(fake.get_signal_connection_list("rewarded_loaded").size(), 0, "no connection is left behind")
	fake.free()


func test_starts_at_launch_when_no_consent_is_needed() -> void:
	var fake := FakeAdMobBridge.new()
	var ads := _ads(fake)
	await _settle()
	check_eq(fake.updates, 1, "consent checked once at launch")
	check_eq(fake.forms, 0, "no form where none is needed")
	check_eq(fake.starts, 1, "SDK started")
	check(fake.is_rewarded_loaded() and fake.is_interstitial_loaded(), "one rewarded and one interstitial ad preloaded")
	check(ads.rewarded_available(AdsService.REVIVE), "rewarded offers appear")
	check_eq(fake.max_rating, "G", "ad content capped at the configured rating")
	check_eq(fake.age_treatment, 0, "age treatment left unspecified")
	check(app.analytics_log.count(Analytics.AD_CONSENT) >= 1, "consent outcome reported to analytics")
	await _cleanup()


func test_consent_form_waits_for_a_quiet_moment_after_the_first_run() -> void:
	var fake := FakeAdMobBridge.new()
	fake.status = 1
	fake.can_request = false
	var ads := _ads(fake)
	await _settle()
	check_eq(fake.starts, 0, "nothing starts before consent")
	check_eq(fake.rewarded_loads + fake.interstitial_loads, 0, "no ad is requested before consent")
	check(not ads.rewarded_available(AdsService.REVIVE), "rewarded offers stay hidden")
	await ads.between_runs()
	check_eq(fake.forms, 0, "no form before the first run is finished")
	app.stats.add("runs", 1.0)
	await ads.between_runs()
	check_eq(fake.forms, 1, "form shown at the first quiet moment after a run")
	await _settle()
	check_eq(fake.starts, 1, "SDK starts once consent allows it")
	check(ads.rewarded_available(AdsService.REVIVE), "rewarded offers appear after consent")
	await ads.between_runs()
	check_eq(fake.forms, 1, "never shown twice in one session")
	await _cleanup()


func test_refused_consent_requests_nothing() -> void:
	var fake := FakeAdMobBridge.new()
	fake.status = 1
	fake.can_request = false
	fake.can_request_after_form = false
	var ads := _ads(fake)
	await _settle()
	app.stats.add("runs", 1.0)
	await ads.between_runs()
	await _settle()
	check_eq(fake.starts, 0, "SDK not started")
	check_eq(fake.rewarded_loads + fake.interstitial_loads, 0, "no ad requested")
	check(not ads.rewarded_available(AdsService.DOUBLE_REWARDS), "no rewarded offers")
	app.stats.add("runs", 5.0)
	app.ads = ads
	ads.note_run_finished()
	ads.note_run_finished()
	check(not await ads.maybe_show_interstitial("test"), "no interstitial")
	await _cleanup()


func test_rewarded_pays_only_on_the_reward_callback() -> void:
	var fake := FakeAdMobBridge.new()
	var ads := _ads(fake, {"show_timeout_sec": 0.4, "reward_grace_sec": 0.3})
	await _settle()
	var silenced_during: Array = []
	ads.ad_opened.connect(func() -> void: silenced_during.append(app.audio.is_silenced()))

	check(await ads.show_rewarded(AdsService.DOUBLE_REWARDS), "watched to the end: earned")
	check_eq(silenced_during, [true], "game audio silenced while the ad is up")
	check(not app.audio.is_silenced(), "and restored afterwards")
	await _settle()
	check(fake.is_rewarded_loaded(), "the next rewarded ad is loaded straight away")

	fake.show_mode = "earn_late"
	check(await ads.show_rewarded(AdsService.REVIVE), "a reward arriving just after the close still counts")
	await _settle()
	fake.show_mode = "no_reward"
	check(not await ads.show_rewarded(AdsService.REVIVE), "closed early: nothing earned")
	await _settle()
	fake.show_mode = "fail"
	check(not await ads.show_rewarded(AdsService.REVIVE), "failed to show: nothing earned")
	await _settle()
	fake.show_mode = "hang"
	check(not await ads.show_rewarded(AdsService.REVIVE), "no answer from the SDK: times out with nothing earned")
	check(not ads.is_showing(), "and the ads service is free again")
	check(not app.audio.is_silenced(), "with sound back")
	await _cleanup()


func test_interstitial_shows_and_reloads() -> void:
	var fake := FakeAdMobBridge.new()
	var ads := _ads(fake)
	await _settle()
	app.stats.add("runs", 5.0)
	app.ads = ads
	ads.note_run_finished()
	ads.note_run_finished()
	check(await ads.maybe_show_interstitial("test"), "interstitial shown between runs")
	check_eq(fake.interstitial_shows, 1, "exactly once")
	await _settle()
	check(fake.is_interstitial_loaded(), "the next one is loaded")
	await _cleanup()


func test_failed_loads_retry_with_backoff() -> void:
	var fake := FakeAdMobBridge.new()
	fake.fill = false
	var ads := _ads(fake, {"retry_seconds": [0.1, 0.2]})
	await wait_seconds(0.9)
	check(fake.rewarded_loads >= 3, "no fill is retried (%d attempts)" % fake.rewarded_loads)
	check(fake.rewarded_loads <= 6, "but not in a tight loop (%d attempts)" % fake.rewarded_loads)
	check(not ads.rewarded_available(AdsService.REVIVE), "offers hidden while nothing is loaded")
	fake.fill = true
	await wait_seconds(0.5)
	check(ads.rewarded_available(AdsService.REVIVE), "offers return once an ad loads")
	await _cleanup()


func test_remove_ads_stops_interstitial_loading() -> void:
	var fake := FakeAdMobBridge.new()
	fresh_profile()
	check(await app.store.purchase("remove_ads"), "remove ads bought")
	_fakes.append(fake)
	var ads := AdsService.new(app, AdMobAdProvider.new(fake))
	await _settle()
	check_eq(fake.interstitial_loads, 0, "no interstitial is even requested")
	check(fake.is_rewarded_loaded(), "optional rewarded ads still load")
	check(ads.rewarded_available(AdsService.REVIVE), "and are offered")
	await _cleanup()


func test_unsupported_bridge_does_nothing() -> void:
	var fake := FakeAdMobBridge.new()
	fake.supported = false
	var ads := _ads(fake)
	await _settle()
	check_eq(fake.updates + fake.starts + fake.rewarded_loads, 0, "the stub is never driven")
	check(not ads.rewarded_available(AdsService.REVIVE), "no offers")
	await ads.between_runs()
	check_eq(fake.forms, 0, "no form")
	check(not ads.privacy_options_required(), "no privacy options")
	await _cleanup()


func test_privacy_options_follow_the_sdk() -> void:
	var fake := FakeAdMobBridge.new()
	fake.privacy_required = true
	var ads := _ads(fake)
	await _settle()
	check(ads.privacy_options_required(), "entry point required when UMP says so")
	await ads.show_privacy_options()
	check(app.analytics_log.count(Analytics.AD_CONSENT) >= 2, "the new answer is reported")
	await _cleanup()


func test_desktop_and_tests_keep_the_mock() -> void:
	fresh_profile()
	check(app.ads.provider is MockAdProvider, "automated runs use the mock provider")
