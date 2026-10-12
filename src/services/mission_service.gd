class_name MissionService
extends RefCounted
## Daily missions. Three are drawn from the pool each local day using a seed
## derived from the date and install id, so the set is stable across app
## restarts and different per player. No streak penalties, no expiry pressure
## beyond the natural daily reset.

signal changed

var _app: AppRoot
var _cfg: Dictionary


func _init(app: AppRoot) -> void:
	_app = app
	_cfg = GameData.dict(app.data.retention, "daily_missions")


## Call on boot and whenever a mission screen opens.
func refresh() -> void:
	var state := _app.save.section("missions")
	var today := _app.clock.day_index()
	if int(state.get("day", -1)) == today:
		return
	# A clock set backwards must not hand out a fresh set.
	if today < int(state.get("day", -1)):
		return
	state["day"] = today
	state["bonus_claimed"] = false
	state["list"] = _roll(today)
	_app.save.mark_dirty()
	changed.emit()


func _roll(day: int) -> Array:
	var pool: Array = GameData.list(_cfg, "pool").duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [day, str(_app.save.state.get("install_id", ""))])
	var picked: Array = []
	var count := mini(GameData.integer(_cfg, "count", 3), pool.size())
	while picked.size() < count:
		var def: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		# Avoid two missions tracking the same stat on one day.
		var duplicate := false
		for existing: Dictionary in picked:
			if _def(str(existing.id)).get("stat") == def.get("stat"):
				duplicate = true
		if duplicate and pool.size() >= count - picked.size():
			continue
		picked.append({"id": def.id, "progress": 0.0, "claimed": false})
	return picked


func _def(id: String) -> Dictionary:
	for def: Dictionary in GameData.list(_cfg, "pool"):
		if str(def.get("id")) == id:
			return def
	return {}


## Today's missions merged with their definitions, ready for display.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _app.save.section("missions").get("list", []):
		var def := _def(str(entry.get("id", "")))
		if def.is_empty():
			continue
		var target := GameData.num(def, "target", 1.0)
		var progress := minf(float(entry.get("progress", 0.0)), target)
		out.append({
			"id": def.id,
			"text": GameData.text(def, "text"),
			"progress": progress,
			"target": target,
			"complete": progress >= target,
			"claimed": bool(entry.get("claimed", false)),
			"reward": GameData.dict(def, "reward"),
		})
	return out


## Feeds one finished run's numbers in. Returns ids completed by this run.
func apply_run(run: Dictionary) -> Array[String]:
	var completed: Array[String] = []
	for entry: Dictionary in _app.save.section("missions").get("list", []):
		var def := _def(str(entry.get("id", "")))
		if def.is_empty() or not run.has(GameData.text(def, "stat")):
			continue
		var target := GameData.num(def, "target", 1.0)
		var before := float(entry.get("progress", 0.0))
		var amount := float(run[GameData.text(def, "stat")])
		match GameData.text(def, "mode"):
			"sum": entry["progress"] = before + amount
			"single": entry["progress"] = maxf(before, amount)
			_: continue
		if before < target and float(entry["progress"]) >= target:
			completed.append(str(def.id))
			_app.analytics.track(Analytics.MISSION_COMPLETED, {"id": def.id})
	_app.save.mark_dirty()
	changed.emit()
	return completed


## Progress for 'event' missions that are not tied to a run.
func notify_event(stat: String, amount: float) -> void:
	var touched := false
	for entry: Dictionary in _app.save.section("missions").get("list", []):
		var def := _def(str(entry.get("id", "")))
		if GameData.text(def, "mode") != "event" or GameData.text(def, "stat") != stat:
			continue
		var target := GameData.num(def, "target", 1.0)
		var before := float(entry.get("progress", 0.0))
		entry["progress"] = before + amount
		if before < target and float(entry["progress"]) >= target:
			_app.analytics.track(Analytics.MISSION_COMPLETED, {"id": def.id})
		touched = true
	if touched:
		_app.save.mark_dirty()
		changed.emit()


func claim(id: String) -> Dictionary:
	for mission in active():
		if str(mission.id) != id or not bool(mission.complete) or bool(mission.claimed):
			continue
		for entry: Dictionary in _app.save.section("missions").get("list", []):
			if str(entry.get("id")) == id:
				entry["claimed"] = true
		_app.save.mark_dirty()
		_app.economy.grant_bundle(mission.reward, "mission")
		changed.emit()
		return mission.reward
	return {}


func all_claimed() -> bool:
	var list := active()
	if list.is_empty():
		return false
	for mission in list:
		if not bool(mission.claimed):
			return false
	return true


func bonus_reward() -> Dictionary:
	return GameData.dict(_cfg, "all_complete_reward")


func bonus_claimed() -> bool:
	return bool(_app.save.section("missions").get("bonus_claimed", false))


func claim_bonus() -> Dictionary:
	if not all_claimed() or bonus_claimed():
		return {}
	_app.save.section("missions")["bonus_claimed"] = true
	_app.save.mark_dirty()
	_app.economy.grant_bundle(bonus_reward(), "mission_bonus")
	changed.emit()
	return bonus_reward()


func claimable_count() -> int:
	var n := 0
	for mission in active():
		if bool(mission.complete) and not bool(mission.claimed):
			n += 1
	if all_claimed() and not bonus_claimed():
		n += 1
	return n
