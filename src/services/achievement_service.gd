class_name AchievementService
extends RefCounted
## Achievements are thresholds over lifetime stats, so "is it complete" is
## derived rather than stored - only the claimed flag is persisted. They are the
## main free source of Crystals.

signal changed

var _app: AppRoot
var _announced: Dictionary = {}


func _init(app: AppRoot) -> void:
	_app = app
	# Anything already complete at boot is old news, not a toast.
	for entry in all():
		if bool(entry.complete):
			_announced[entry.id] = true


func all() -> Array[Dictionary]:
	var claimed: Array = _app.save.section("achievements").get("claimed", [])
	var out: Array[Dictionary] = []
	for def: Dictionary in GameData.list(_app.data.retention, "achievements"):
		var target := GameData.num(def, "target", 1.0)
		var current := minf(_app.stats.value(GameData.text(def, "stat")), target)
		out.append({
			"id": GameData.text(def, "id"),
			"name": GameData.text(def, "name"),
			"text": GameData.text(def, "text"),
			"progress": current,
			"target": target,
			"complete": current >= target,
			"claimed": claimed.has(def.get("id")),
			"crystals": GameData.integer(def, "crystals"),
		})
	return out


func claim(id: String) -> int:
	for entry in all():
		if str(entry.id) != id or not bool(entry.complete) or bool(entry.claimed):
			continue
		var section := _app.save.section("achievements")
		var claimed: Array = section.get("claimed", [])
		claimed.append(id)
		section["claimed"] = claimed
		_app.save.mark_dirty()
		_app.economy.grant(Economy.CRYSTALS, int(entry.crystals), "achievement")
		_app.analytics.track(Analytics.ACHIEVEMENT_CLAIMED, {"id": id})
		changed.emit()
		return int(entry.crystals)
	return 0


func claimable_count() -> int:
	var n := 0
	for entry in all():
		if bool(entry.complete) and not bool(entry.claimed):
			n += 1
	return n


## Achievements that became complete since the last call (for toasts).
func poll_newly_completed() -> Array[Dictionary]:
	var fresh: Array[Dictionary] = []
	for entry in all():
		if bool(entry.complete) and not _announced.has(entry.id):
			_announced[entry.id] = true
			fresh.append(entry)
	return fresh
