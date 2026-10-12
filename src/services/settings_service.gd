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
const SCREEN_SHAKE := "screen_shake"
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


func set_value(key: String, v: Variant) -> void:
	var table := _app.save.section("settings")
	if table.get(key) == v:
		return
	table[key] = v
	_app.save.mark_dirty()
	changed.emit(key, v)
