class_name FakeAdMobBridge
extends Object
## Stand-in for the native AdMob bridge (native/admob): same methods, same
## signals, emitted deferred like the real one. Tests set the knobs below to
## script what Google's SDKs would do and read the counters afterwards.
## An Object, like the real singleton: free it at the end of the test.

signal consent_info_updated(error: String)
signal consent_form_dismissed(error: String)
signal privacy_options_dismissed(error: String)
signal started
signal rewarded_loaded
signal rewarded_failed_to_load(error: String)
signal rewarded_shown
signal rewarded_failed_to_show(error: String)
signal rewarded_earned(type: String, amount: float)
signal rewarded_dismissed
signal interstitial_loaded
signal interstitial_failed_to_load(error: String)
signal interstitial_shown
signal interstitial_failed_to_show(error: String)
signal interstitial_dismissed

# --- knobs
var supported := true
## Consent before the form: 1 required, 2 not required, 3 obtained.
var status := 2
var can_request := true
## What answering the form leads to.
var status_after_form := 3
var can_request_after_form := true
var privacy_required := false
## false: every load fails with no fill.
var fill := true
## "earn", "earn_late" (reward after dismissal), "no_reward", "fail" or "hang".
var show_mode := "earn"

# --- counters
var updates := 0
var forms := 0
var starts := 0
var rewarded_loads := 0
var interstitial_loads := 0
var rewarded_shows := 0
var interstitial_shows := 0
var max_rating := ""
var age_treatment := -1

var _started := false
var _rewarded := false
var _interstitial := false


func is_supported() -> bool:
	return supported


func get_sdk_version() -> String:
	return "fake"


func debug_log(_text: String) -> void:
	pass


func consent_request_update(_geography: int, _test_ids: PackedStringArray, _under_age: bool) -> void:
	updates += 1
	call_deferred("emit_signal", "consent_info_updated", "")


func consent_load_and_present_if_required() -> void:
	forms += 1
	if status == 1:
		status = status_after_form
		can_request = can_request_after_form
	call_deferred("emit_signal", "consent_form_dismissed", "")


func consent_can_request_ads() -> bool:
	return can_request


func consent_get_status() -> int:
	return status


func consent_is_privacy_options_required() -> bool:
	return privacy_required


func consent_present_privacy_options() -> void:
	call_deferred("emit_signal", "privacy_options_dismissed", "")


func consent_reset() -> void:
	pass


func get_tracking_status() -> int:
	return 0


func set_test_device_ids(_ids: PackedStringArray) -> void:
	pass


func set_max_ad_content_rating(rating: String) -> void:
	max_rating = rating


func set_age_treatment(treatment: int) -> void:
	age_treatment = treatment


func start() -> void:
	starts += 1
	_started = true
	call_deferred("emit_signal", "started")


func is_started() -> bool:
	return _started


func load_rewarded(_unit: String) -> void:
	if _rewarded:
		return
	rewarded_loads += 1
	if fill:
		_rewarded = true
		call_deferred("emit_signal", "rewarded_loaded")
	else:
		call_deferred("emit_signal", "rewarded_failed_to_load", "no fill")


func is_rewarded_loaded() -> bool:
	return _rewarded


func show_rewarded() -> bool:
	if not _rewarded:
		return false
	_rewarded = false
	rewarded_shows += 1
	match show_mode:
		"fail":
			call_deferred("emit_signal", "rewarded_failed_to_show", "fake failure")
		"hang":
			pass
		_:
			call_deferred("emit_signal", "rewarded_shown")
			if show_mode == "earn":
				call_deferred("emit_signal", "rewarded_earned", "coins", 10.0)
			call_deferred("emit_signal", "rewarded_dismissed")
			if show_mode == "earn_late":
				_earn_late.call_deferred()
	return true


func _earn_late() -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(0.1).timeout
	rewarded_earned.emit("coins", 10.0)


func load_interstitial(_unit: String) -> void:
	if _interstitial:
		return
	interstitial_loads += 1
	if fill:
		_interstitial = true
		call_deferred("emit_signal", "interstitial_loaded")
	else:
		call_deferred("emit_signal", "interstitial_failed_to_load", "no fill")


func is_interstitial_loaded() -> bool:
	return _interstitial


func show_interstitial() -> bool:
	if not _interstitial:
		return false
	_interstitial = false
	interstitial_shows += 1
	call_deferred("emit_signal", "interstitial_shown")
	call_deferred("emit_signal", "interstitial_dismissed")
	return true
