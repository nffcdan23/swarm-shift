class_name DailyRewardService
extends RefCounted
## Seven-day login calendar. One claim per local day; the calendar simply
## advances and loops. Missing a day never resets progress - coming back should
## feel good, not punishing.

signal changed

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func cycle() -> Array:
	return GameData.list(GameData.dict(_app.data.retention, "daily_rewards"), "cycle")


## Index (0-based) of the reward that is next to be claimed.
func current_index() -> int:
	var n := cycle().size()
	if n == 0:
		return 0
	return posmod(int(_app.save.section("daily").get("index", 0)), n)


func can_claim() -> bool:
	var last := int(_app.save.section("daily").get("last_claim_day", -1))
	return not cycle().is_empty() and _app.clock.day_index() > last


func next_reward() -> Dictionary:
	var rewards := cycle()
	if rewards.is_empty():
		return {}
	return rewards[current_index()]


## Claims today's reward. `multiplier` is 2 when the player chose to watch a
## rewarded ad to double it.
func claim(multiplier: int = 1) -> Dictionary:
	if not can_claim():
		return {}
	var reward: Dictionary = next_reward().duplicate()
	for key: String in reward:
		reward[key] = int(reward[key]) * multiplier
	var state := _app.save.section("daily")
	var day_number := current_index() + 1
	state["last_claim_day"] = _app.clock.day_index()
	state["index"] = current_index() + 1
	_app.save.mark_dirty()
	_app.economy.grant_bundle(reward, "daily_reward")
	_app.analytics.track(Analytics.DAILY_REWARD_CLAIMED, {"day": day_number, "multiplier": multiplier})
	_app.save.flush()
	changed.emit()
	return reward
