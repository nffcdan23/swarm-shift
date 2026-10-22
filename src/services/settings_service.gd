class_name SettingsService
extends RefCounted
## Player preferences, persisted in the profile. Other services subscribe to
## `changed` rather than polling.

signal changed(key: String, value: Variant)

const MASTER := "master"
const MUSIC := "music"
const SFX := "sfx"
const HAPTICS := "haptics"
const DAMAGE_NUMBERS := "damage_numbers"
## Off / Low / Normal (see shake_level). Replaces the old 0..1 slider value,
## which is still read once to choose a starting level for existing players.
const SHAKE_LEVEL := "shake_level"
const SCREEN_SHAKE := "screen_shake"
const SHAKE_OFF := "off"
const SHAKE_LOW := "low"
const SHAKE_NORMAL := "normal"
const SHAKE_LEVELS: PackedStringArray = ["off", "low", "normal"]
const LOW_EFFECTS := "low_effects"

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func value(key: String) -> Variant:
	return _app.save.section("settings").get(key)


func number(key: String, fallback: float = 1.0) -> float:
	var v: Variant = value(key)
	return float(v) if (v is float or v is int) else fallback


func enabled(key: String, fallback: bool = true) -> bool:
	var v: Variant = value(key)
	return v if v is bool else fallback


## The Screen Shake level. A player who has never chosen one gets Low on a
## phone or tablet and Normal on a computer; one who had moved the old slider
## keeps the nearest level (all the way down is Off, part way is Low).
func shake_level() -> String:
	var chosen := str(value(SHAKE_LEVEL))
	if SHAKE_LEVELS.has(chosen):
		return chosen
	return SettingsService.initial_shake_level(value(SCREEN_SHAKE), OS.has_feature("mobile"))


static func initial_shake_level(old_slider: Variant, mobile: bool) -> String:
	if old_slider is float or old_slider is int:
		var old := float(old_slider)
		if old <= 0.001:
			return SHAKE_OFF
		if old < 0.999:
			return SHAKE_LOW
	return SHAKE_LOW if mobile else SHAKE_NORMAL


## Multiplier on the camera's shake offset for the current level.
func shake_scale() -> float:
	var levels := GameData.dict(GameData.dict(GameData.dict(_app.data.game, "feel"), "shake"), "levels")
	return GameData.num(levels, shake_level(), 1.0)


func set_value(key: String, v: Variant) -> void:
	var table := _app.save.section("settings")
	if table.get(key) == v:
		return
	table[key] = v
	_app.save.mark_dirty()
	changed.emit(key, v)
