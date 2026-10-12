class_name HapticsService
extends RefCounted
## Haptic feedback behind named intents ("light", "heavy", ...), so gameplay
## code never deals in milliseconds. Patterns live in game.json. Silently does
## nothing on desktop or when the player turned haptics off.

var _app: AppRoot
var _patterns: Dictionary
var _supported := false
var _last_ms := 0
var _min_interval_ms := 45

## Counts requests that would have fired; lets tests assert on feedback.
var fired := 0


func _init(app: AppRoot) -> void:
	_app = app
	_patterns = GameData.dict(app.data.game, "haptics")
	_min_interval_ms = GameData.integer(_patterns, "min_interval_ms", 45)
	_supported = OS.has_feature("mobile")


func light() -> void:
	play("light")


func medium() -> void:
	play("medium")


func heavy() -> void:
	play("heavy")


func success() -> void:
	play("success")


func warning() -> void:
	play("warning")


func play(kind: String) -> void:
	if not _app.settings.enabled(SettingsService.HAPTICS):
		return
	var now := Time.get_ticks_msec()
	# Strong pulses are allowed to cut in; chatter is rate limited.
	if kind == "light" and now - _last_ms < _min_interval_ms:
		return
	_last_ms = now
	fired += 1
	if not _supported:
		return
	var pattern := GameData.dict(_patterns, kind)
	Input.vibrate_handheld(GameData.integer(pattern, "ms", 20), GameData.num(pattern, "amp", 0.5))
