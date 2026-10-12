class_name MockAdProvider
extends AdProvider
## Stand-in ad network for development. Shows an obviously fake full-screen
## "ad" with a short countdown so the whole reward flow can be played through
## without any SDK or account. In automated runs it resolves instantly.

var rewarded_seconds := 2.5
var interstitial_seconds := 1.5
## What an automated (headless) run reports for rewarded ads.
var auto_complete := true

var shown_rewarded := 0
var shown_interstitial := 0

var _app: AppRoot


func initialize(app: AppRoot) -> void:
	_app = app


func is_rewarded_ready() -> bool:
	return true


func is_interstitial_ready() -> bool:
	return true


func show_rewarded(placement: String) -> bool:
	shown_rewarded += 1
	if _app.automated:
		return auto_complete
	var overlay := MockAdOverlay.new()
	overlay.configure("REWARDED AD", placement, rewarded_seconds, true)
	_app.add_child(overlay)
	var completed: bool = await overlay.finished
	return completed


func show_interstitial(placement: String) -> bool:
	shown_interstitial += 1
	if _app.automated:
		return true
	var overlay := MockAdOverlay.new()
	overlay.configure("INTERSTITIAL AD", placement, interstitial_seconds, false)
	_app.add_child(overlay)
	await overlay.finished
	return true


func describe() -> String:
	return "mock"
