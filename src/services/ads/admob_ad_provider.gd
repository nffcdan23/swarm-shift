class_name AdMobAdProvider
extends AdProvider
## Google AdMob through the native bridge (native/admob, the `AdMob`
## singleton), with Google's consent flow (UMP) in front of it.
##
## Consent. Google requires the consent status to be checked at every launch.
## If the player has already answered, or lives where no answer is needed, ads
## start straight away. Otherwise the consent form - followed by Apple's
## tracking prompt where AdMob is set up for it - waits for a quiet moment
## between runs once the player has finished `consent_form_after_runs` runs, so
## the first thing a new player meets is the game, not a form. Until consent
## allows ad requests, nothing is requested and every ad offer stays hidden.
##
## Loading. One rewarded and one interstitial ad are kept loaded (no
## interstitial once Remove Ads is owned). A failed load - no fill, no network -
## is retried after a growing delay (`retry_seconds`).
##
## Showing. A rewarded ad pays only on the SDK's reward callback; closing it
## early, a failure to show or a timeout all return false.
##
## The ad units come from `admob` in monetization.json and are Google's demo
## units: test ads only until C2's real units are signed off.

## Values match the bridge's CONSENT_* constants (and UMPConsentStatus).
const CONSENT_REQUIRED := 1
const REWARDED := "rewarded"
const INTERSTITIAL := "interstitial"
const AGE_TREATMENTS := {"unspecified": 0, "child": 1, "teen": 2}

var _app: AppRoot
var _bridge: Object
var _cfg: Dictionary
var _consent_checked := false
var _form_shown := false
var _started := false
var _failures := {REWARDED: 0, INTERSTITIAL: 0}
var _retry_waiting := {REWARDED: false, INTERSTITIAL: false}


## `bridge` is Engine.get_singleton("AdMob"), or a stand-in with the same
## methods and signals (tests/fakes/fake_admob_bridge.gd).
func _init(bridge: Object) -> void:
	_bridge = bridge


func initialize(app: AppRoot) -> void:
	_app = app
	_cfg = GameData.dict(app.data.monetization, "admob")
	if not _supported():
		return
	_bridge.set_max_ad_content_rating(GameData.text(_cfg, "max_ad_content_rating", "G"))
	_bridge.set_age_treatment(int(AGE_TREATMENTS.get(GameData.text(_cfg, "age_treatment", "unspecified"), 0)))
	_bridge.rewarded_loaded.connect(_on_loaded.bind(REWARDED))
	_bridge.interstitial_loaded.connect(_on_loaded.bind(INTERSTITIAL))
	_bridge.rewarded_failed_to_load.connect(_on_load_failed.bind(REWARDED))
	_bridge.interstitial_failed_to_load.connect(_on_load_failed.bind(INTERSTITIAL))
	# Development: `--consent-reset` forgets the stored answer so the form shows again.
	if app.cli.has("consent-reset"):
		_bridge.consent_reset()
	_check_consent()


func describe() -> String:
	return "admob " + str(_bridge.get_sdk_version()) if _supported() else "admob (unavailable)"


# ------------------------------------------------------------------ consent

func _check_consent() -> void:
	_bridge.consent_request_update(0, PackedStringArray(), false)
	await SignalRace.first(_bridge, ["consent_info_updated"], float(GameData.num(_cfg, "consent_timeout_sec", 30.0)))
	# On an error or a timeout UMP keeps the previous session's answer, so the
	# status below is still the right one to act on.
	_consent_checked = true
	_after_consent("launch")


func _after_consent(moment: String) -> void:
	_app.analytics.track(Analytics.AD_CONSENT, {
		"moment": moment,
		"status": int(_bridge.consent_get_status()),
		"can_request_ads": bool(_bridge.consent_can_request_ads()),
		"tracking": int(_bridge.get_tracking_status()),
	})
	if _bridge.consent_can_request_ads():
		_start()


func needs_consent_form() -> bool:
	return _supported() and _consent_checked and not _form_shown \
		and int(_bridge.consent_get_status()) == CONSENT_REQUIRED \
		and int(_app.stats.value("runs")) >= GameData.integer(_cfg, "consent_form_after_runs", 1)


## Called by AdsService between runs. Shows the consent form once per session
## if one is still needed; returns when the player has answered it.
func between_runs() -> void:
	if not needs_consent_form():
		return
	_form_shown = true
	_bridge.consent_load_and_present_if_required()
	await SignalRace.first(_bridge, ["consent_form_dismissed"], 600.0)
	_after_consent("between_runs")


func privacy_options_required() -> bool:
	return _supported() and _consent_checked and bool(_bridge.consent_is_privacy_options_required())


## The Settings "Privacy choices" row. Returns when the form closes.
func show_privacy_options() -> void:
	if not privacy_options_required():
		return
	_bridge.consent_present_privacy_options()
	await SignalRace.first(_bridge, ["privacy_options_dismissed"], 600.0)
	_after_consent("privacy_options")


# ------------------------------------------------------------------ loading

func _start() -> void:
	if _started:
		return
	_started = true
	if not _bridge.is_started():
		_bridge.start()
		# Google's own initialisation gives up after 30 seconds.
		await SignalRace.first(_bridge, ["started"], 35.0)
	_load(REWARDED)
	_load(INTERSTITIAL)


func _unit(format: String) -> String:
	return GameData.text(GameData.dict(_cfg, "ios"), format)


func _wanted(format: String) -> bool:
	if format == INTERSTITIAL:
		var interstitial := GameData.dict(GameData.dict(_app.data.monetization, "ads"), "interstitial")
		return GameData.flag(interstitial, "enabled", false) and not _app.store.has_entitlement("remove_ads")
	return true


func _load(format: String) -> void:
	if not _started or not _wanted(format) or _unit(format).is_empty() or not _bridge.consent_can_request_ads():
		return
	if format == REWARDED:
		_bridge.load_rewarded(_unit(format))
	else:
		_bridge.load_interstitial(_unit(format))


func _on_loaded(format: String) -> void:
	_failures[format] = 0


func _on_load_failed(_error: String, format: String) -> void:
	if _retry_waiting[format]:
		return
	var delays: Array = GameData.list(_cfg, "retry_seconds")
	var delay := float(delays[mini(_failures[format], delays.size() - 1)]) if not delays.is_empty() else 60.0
	_failures[format] += 1
	_retry_waiting[format] = true
	await _app.get_tree().create_timer(delay).timeout
	_retry_waiting[format] = false
	_load(format)


# ------------------------------------------------------------------ showing

func _supported() -> bool:
	return _bridge != null and bool(_bridge.is_supported())


func is_rewarded_ready() -> bool:
	return _supported() and _started and _bridge.consent_can_request_ads() and _bridge.is_rewarded_loaded()


func is_interstitial_ready() -> bool:
	return _supported() and _started and _bridge.consent_can_request_ads() and _bridge.is_interstitial_loaded()


func show_rewarded(_placement: String) -> bool:
	if not is_rewarded_ready():
		return false
	var state := {"earned": false}
	var on_earned := func(_type: String, _amount: float) -> void: state.earned = true
	_bridge.rewarded_earned.connect(on_earned)
	var outcome: Array = []
	if _bridge.show_rewarded():
		outcome = await SignalRace.first(_bridge, ["rewarded_dismissed", "rewarded_failed_to_show"], _show_timeout())
		# The reward callback can trail the dismissal slightly.
		if not state.earned and not outcome.is_empty() and outcome[0] == "rewarded_dismissed":
			await _app.get_tree().create_timer(GameData.num(_cfg, "reward_grace_sec", 0.5)).timeout
	_bridge.rewarded_earned.disconnect(on_earned)
	_load(REWARDED)
	return state.earned


func show_interstitial(_placement: String) -> bool:
	if not is_interstitial_ready():
		return false
	var outcome: Array = []
	if _bridge.show_interstitial():
		outcome = await SignalRace.first(_bridge, ["interstitial_dismissed", "interstitial_failed_to_show"], _show_timeout())
	_load(INTERSTITIAL)
	return not outcome.is_empty() and outcome[0] == "interstitial_dismissed"


func _show_timeout() -> float:
	return GameData.num(_cfg, "show_timeout_sec", 300.0)
