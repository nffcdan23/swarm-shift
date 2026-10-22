class_name AdMobCheck
extends Node
## On-device check of the AdMob bridge (native/admob). Launch the installed
## app with `--admob-check` and it walks the whole SDK path once, using
## Google's demo ad units, which only ever serve test ads:
##
##   consent info update -> consent form if required -> start the SDK
##   -> load a rewarded and an interstitial ad -> show both
##
##   xcrun devicectl device process launch --console --device <id> <bundle-id> -- --admob-check
##
## The consent form and the ads need a person to tap through them; each step
## waits up to two minutes. Options: `--admob-reset` forgets stored consent
## first so the form shows again; `--admob-no-show` stops after loading.
##
## Lines are printed with an `[admob-check]` prefix and written to
## user://admob_check.txt. It never touches the player's profile.

const REPORT_PATH := "user://admob_check.txt"
const STEP_TIMEOUT := 120.0
const REWARDED_TEST_UNIT := "ca-app-pub-3940256099942544/1712485313"
const INTERSTITIAL_TEST_UNIT := "ca-app-pub-3940256099942544/4411468910"

var _lines: PackedStringArray = []
var _passes := 0
var _failures: PackedStringArray = []
var _ads: Object


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	App.analytics.enabled = false
	if FileAccess.file_exists(REPORT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPORT_PATH))
	if Engine.has_singleton("AdMob"):
		_ads = Engine.get_singleton("AdMob")
	_say("generated: " + Time.get_datetime_string_from_system(false, true))
	await get_tree().create_timer(1.0).timeout
	await _run()
	_finish()


func _run() -> void:
	if not Engine.has_singleton("AdMob"):
		_fail("the AdMob bridge is not in this build (run tools/build_admob.sh before exporting)")
		return
	if not _ads.is_supported():
		_fail("the AdMob bridge is the desktop stub - run this on an iPhone")
		return
	_pass("bridge loaded, Google Mobile Ads SDK " + str(_ads.get_sdk_version()))
	_say("tracking authorisation: " + _tracking_name(_ads.get_tracking_status()))

	if App.cli.has("admob-reset"):
		_ads.consent_reset()
		_say("stored consent cleared")
	_ads.consent_request_update(0, PackedStringArray(), false)
	var update: Array = await _wait("consent_info_updated")
	if not _expect(update.size() > 0 and str(update[0]).is_empty(), "consent information updated" + _error_suffix(update)):
		return
	_say("consent status: %s, privacy options entry point %s" % [_consent_name(_ads.consent_get_status()), "required" if _ads.consent_is_privacy_options_required() else "not required"])

	_say("showing the consent form if one is required - answer it on the phone")
	_ads.consent_load_and_present_if_required()
	var form: Array = await _wait("consent_form_dismissed")
	_expect(form.size() > 0 and str(form[0]).is_empty(), "consent form step completed" + _error_suffix(form))
	_say("consent status now: %s, tracking: %s" % [_consent_name(_ads.consent_get_status()), _tracking_name(_ads.get_tracking_status())])
	if not _expect(_ads.consent_can_request_ads(), "consent allows ad requests"):
		return

	_ads.start()
	if not _expect(not (await _wait_any(["started"])).is_empty(), "SDK started"):
		return

	_ads.load_rewarded(REWARDED_TEST_UNIT)
	var rewarded: Array = await _wait_any(["rewarded_loaded", "rewarded_failed_to_load"])
	_expect(_ads.is_rewarded_loaded(), "test rewarded ad loaded" + _error_suffix(rewarded.slice(1)))
	_ads.load_interstitial(INTERSTITIAL_TEST_UNIT)
	var interstitial: Array = await _wait_any(["interstitial_loaded", "interstitial_failed_to_load"])
	_expect(_ads.is_interstitial_loaded(), "test interstitial ad loaded" + _error_suffix(interstitial.slice(1)))
	if App.cli.has("admob-no-show"):
		return

	if _ads.is_rewarded_loaded():
		_say("showing the rewarded test ad - watch it to the end, then close it")
		var earned := []
		var on_earned := func(type: String, amount: float) -> void: earned.append("%s x%s" % [type, amount])
		_ads.rewarded_earned.connect(on_earned)
		_expect(_ads.show_rewarded(), "rewarded ad presented")
		var closed: Array = await _wait_any(["rewarded_dismissed", "rewarded_failed_to_show"])
		_ads.rewarded_earned.disconnect(on_earned)
		_expect(closed.size() > 0 and closed[0] == "rewarded_dismissed", "rewarded ad closed" + _error_suffix(closed.slice(1)))
		_expect(not earned.is_empty(), "reward reported (%s)" % (", ".join(earned) if not earned.is_empty() else "none"))
	if _ads.is_interstitial_loaded():
		_say("showing the interstitial test ad - close it")
		_expect(_ads.show_interstitial(), "interstitial ad presented")
		var shut: Array = await _wait_any(["interstitial_dismissed", "interstitial_failed_to_show"])
		_expect(shut.size() > 0 and shut[0] == "interstitial_dismissed", "interstitial ad closed" + _error_suffix(shut.slice(1)))


## Waits for one bridge signal that carries arguments; returns them, or [] on
## timeout. For a signal without arguments use _wait_any, which tells the two apart.
func _wait(signal_name: String) -> Array:
	var result: Array = await _wait_any([signal_name])
	return result.slice(1) if not result.is_empty() else []


## Waits for the first of several signals; returns [name, args...], or [] on timeout.
func _wait_any(signal_names: Array) -> Array:
	var result: Array = await SignalRace.first(_ads, signal_names, STEP_TIMEOUT)
	if result.is_empty():
		_say("timed out after %d s waiting for %s" % [int(STEP_TIMEOUT), " / ".join(signal_names)])
	return result


func _error_suffix(args: Array) -> String:
	return "" if args.is_empty() or str(args[0]).is_empty() else " - " + str(args[0])


func _consent_name(status: int) -> String:
	return ["unknown", "required", "not required", "obtained"][status] if status >= 0 and status <= 3 else str(status)


func _tracking_name(status: int) -> String:
	return ["not determined", "restricted", "denied", "authorised"][status] if status >= 0 and status <= 3 else str(status)


# ------------------------------------------------------------------ reporting

func _say(text: String) -> void:
	_lines.append(text)
	print("[admob-check] ", text)
	# The device log reaches an attached Mac; print() does not.
	if _ads != null:
		_ads.debug_log("check: " + text)
	# Written after every line, so an interrupted check still leaves a record.
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()


func _pass(what: String) -> void:
	_passes += 1
	_say("PASS  " + what)


func _fail(what: String) -> void:
	_failures.append(what)
	_say("FAIL  " + what)


func _expect(condition: bool, what: String) -> bool:
	if condition:
		_pass(what)
	else:
		_fail(what)
	return condition


func _finish() -> void:
	var verdict := "RESULT %s - %d passed, %d failed" % ["PASS" if _failures.is_empty() else "FAIL", _passes, _failures.size()]
	_say(verdict)
	printerr("[admob-check] " + verdict)
	await get_tree().create_timer(0.5).timeout
	# iOS does not let an app end itself; whoever launched the check closes it.
	get_tree().quit()
