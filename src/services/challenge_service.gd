class_name ChallengeService
extends RefCounted
## Daily and Weekly Challenges: a fixed-seed run with its own rules and weapons,
## a new one each period, and a reward that pays once per period.
##
## The schedule is computed on the device from the period number (UTC days, and
## weeks from Monday 00:00 UTC) and the `salt` in retention.json. The same build
## therefore shows the same challenge everywhere for a period, but nothing
## enforces it: there is no shared server schedule and no validation, so no
## ranking built on this is cheat-proof. Results are kept in a shape a real
## leaderboard can take later (see LeaderboardService).
##
## The clock. Everything reads GameClock, and the profile remembers the latest
## time it has seen (`clock_high`). Moving the clock forward only brings the
## next challenge early; moving it back more than `clock_tolerance_hours` behind
## that mark pauses challenges - no play, no rewards - until real time catches
## up. So winding the clock forward and back costs the player the days they
## skipped. Works offline: nothing here needs a network.

signal changed

const DAILY := "daily"
const WEEKLY := "weekly"
const KINDS: Array[String] = [DAILY, WEEKLY]
## Claimed ids and best results kept, oldest dropped first.
const KEPT := 40

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func _cfg() -> Dictionary:
	return GameData.dict(_app.data.retention, "challenges")


func _state() -> Dictionary:
	return _app.save.section("challenges")


## Challenges open once the campaign reaches `unlock_sector` (Overdrive's gate).
func unlocked() -> bool:
	return _app.campaign.highest_cleared() >= GameData.integer(_cfg(), "unlock_sector", 3)


func unlock_sector() -> int:
	return GameData.integer(_cfg(), "unlock_sector", 3)


# ------------------------------------------------------------------- clock

## Records the current time as seen, unless the clock has gone back. Returns
## false when it has gone back too far, which pauses challenges.
func check_clock() -> bool:
	var now := _app.clock.now()
	var high := int(_state().get("clock_high", 0))
	if now + int(GameData.num(_cfg(), "clock_tolerance_hours", 2.0) * 3600.0) < high:
		return false
	if now > high:
		_state()["clock_high"] = now
		_app.save.mark_dirty()
	return true


func clock_ok() -> bool:
	var high := int(_state().get("clock_high", 0))
	return _app.clock.now() + int(GameData.num(_cfg(), "clock_tolerance_hours", 2.0) * 3600.0) >= high


# ----------------------------------------------------------------- schedule

func _kind_cfg(kind: String) -> Dictionary:
	return GameData.dict(_cfg(), kind)


func period_index(kind: String, at: int = -1) -> int:
	var cfg := _kind_cfg(kind)
	var t := _app.clock.now() if at < 0 else at
	var length := maxi(GameData.integer(cfg, "period_seconds", 86400), 3600)
	return floori(float(t - GameData.integer(cfg, "epoch_offset", 0)) / float(length))


func period_id(kind: String, index: int) -> String:
	return "%s-%d" % [kind, index]


func seconds_left(kind: String) -> int:
	var cfg := _kind_cfg(kind)
	var length := maxi(GameData.integer(cfg, "period_seconds", 86400), 3600)
	var ends := (period_index(kind) + 1) * length + GameData.integer(cfg, "epoch_offset", 0)
	return maxi(ends - _app.clock.now(), 0)


## FNV-1a, so the schedule does not depend on the engine's own hash.
static func stable_hash(text: String) -> int:
	var h := 2166136261
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xffffffff
	return h


## The challenge for a period: everything a lobby card and a run need.
func challenge(kind: String, index: int = -999999) -> Dictionary:
	if index == -999999:
		index = period_index(kind)
	var cfg := _kind_cfg(kind)
	var all := _cfg()
	var key := "%s|%s|%d" % [GameData.text(all, "salt"), kind, index]
	var h := stable_hash(key)
	# A Weekly leaves out what is marked "weekly": false (see retention.json).
	var loadouts: Array = []
	for entry: Dictionary in GameData.list(all, "loadouts"):
		if kind == DAILY or GameData.flag(entry, "weekly", true):
			loadouts.append(entry)
	var loadout: Dictionary = loadouts[h % loadouts.size()] if not loadouts.is_empty() else {}
	var rule_table := GameData.dict(all, "rules")
	var rule_ids: Array = []
	for rule_id: String in rule_table:
		if kind == DAILY or GameData.flag(GameData.dict(rule_table, rule_id), "weekly", true):
			rule_ids.append(rule_id)
	rule_ids.sort()
	var rules: Array[String] = []
	var pick := stable_hash(key + "|rules")
	for k in mini(GameData.integer(cfg, "rules", 1), rule_ids.size()):
		var at := int((pick >> (k * 5)) + k * 7) % rule_ids.size()
		while rules.has(str(rule_ids[at])):
			at = (at + 1) % rule_ids.size()
		rules.append(str(rule_ids[at]))
	var tiers := GameData.list(cfg, "tiers")
	var low := int(tiers[0]) if tiers.size() > 0 else 3
	var high := int(tiers[1]) if tiers.size() > 1 else low
	var tier := low + int(stable_hash(key + "|tier") % maxi(high - low + 1, 1))
	# Never past what the player can reach: one above their best clear.
	tier = clampi(tier, 1, maxi(_app.campaign.highest_cleared() + 1, 1))
	var mutators: Array[String] = []
	var mods: Dictionary = {}
	var names: PackedStringArray = []
	var descs: PackedStringArray = []
	for id in rules:
		var rule := GameData.dict(rule_table, id)
		names.append(GameData.text(rule, "name", id.to_upper()))
		descs.append(GameData.text(rule, "desc"))
		for mutator_id: String in GameData.list(rule, "mutators"):
			if not mutators.has(mutator_id):
				mutators.append(mutator_id)
		var rule_mods := GameData.dict(rule, "mods")
		for mod_key: String in rule_mods:
			mods[mod_key] = float(mods.get(mod_key, 0.0)) + float(rule_mods[mod_key])
	var threat := GameData.integer(cfg, "threat", 0)
	for mutator_id in _app.campaign.threat_mutators(threat):
		if not mutators.has(mutator_id):
			mutators.append(mutator_id)
	var weapons: Array[String] = []
	for weapon_id: String in GameData.list(loadout, "weapons"):
		if _app.data.weapon_defs().has(weapon_id):
			weapons.append(weapon_id)
	if weapons.is_empty():
		weapons.append("pulse")
	var id := period_id(kind, index)
	var reward_scale := float(_app.campaign.scaling(float(tier)).reward)
	return {
		"kind": kind, "id": id, "index": index, "name": GameData.text(cfg, "name", kind.to_upper()),
		"tier": tier, "threat": threat, "seed": (h % 2147483646) + 1,
		"loadout": GameData.text(loadout, "name", "PULSE ONLY"), "weapons": weapons,
		"rules": rules, "rule_names": names, "rule_descs": descs, "mutators": mutators, "mods": mods,
		"reward": {"credits": int(round(GameData.num(cfg, "credits", 400.0) * reward_scale)), "crystals": GameData.integer(cfg, "crystals", 5)},
		"claimed": is_claimed(id), "best": best(id), "leaderboard": GameData.text(cfg, "leaderboard"),
	}


func is_claimed(id: String) -> bool:
	return (_state().get("claimed", []) as Array).has(id)


func best(id: String) -> Dictionary:
	var table: Dictionary = _state().get("best", {})
	return table.get(id, {})


## Number of challenges ready to claim right now, for the lobby badge.
func open_count() -> int:
	if not unlocked() or not clock_ok():
		return 0
	var n := 0
	for kind in KINDS:
		if not is_claimed(period_id(kind, period_index(kind))):
			n += 1
	return n


# ------------------------------------------------------------------- playing

func selected_kind() -> String:
	var kind := str(_state().get("selected", DAILY))
	return kind if KINDS.has(kind) else DAILY


func select(kind: String) -> void:
	if KINDS.has(kind):
		_state()["selected"] = kind
		_app.save.mark_dirty()
		changed.emit()


## Whether the selected challenge can be started now.
func can_play() -> bool:
	return unlocked() and check_clock()


## Turns a run config into the selected challenge: its sector, seed, weapons,
## rules and Threat. Permanent upgrades, the core and its awakening still apply.
## `index` picks another period (tools only).
func apply_to(cfg: RunConfig, index: int = -999999) -> void:
	var c := challenge(selected_kind(), index)
	cfg.mode = CampaignService.MODE_CHALLENGE
	cfg.tier = int(c.tier)
	cfg.theme = _app.campaign.theme(cfg.tier)
	cfg.rng_seed = int(c.seed)
	var weapons: Array[String] = []
	weapons.assign(c.weapons)
	cfg.weapon_pool = weapons
	cfg.start_weapon = weapons[0]
	cfg.extra_mutators.assign(c.mutators)
	var mods: Dictionary = c.mods
	for key: String in mods:
		cfg.base_mods[key] = float(cfg.base_mods.get(key, 0.0)) + float(mods[key])
	cfg.challenge_kind = str(c.kind)
	cfg.challenge_id = str(c.id)
	cfg.challenge_name = str(c.name)


## Records a finished challenge run: its best result, and on a first clear in
## its period the reward. Returns {"kind", "name", "cleared", "claimed_now",
## "reward"} or an empty dictionary for any other run. Called once per run, by
## RunLedger.settle.
func record(result: Dictionary) -> Dictionary:
	var kind := str(result.get("challenge_kind", ""))
	var id := str(result.get("challenge_id", ""))
	if not KINDS.has(kind) or id.is_empty():
		return {}
	var index := int(id.get_slice("-", 1))
	var c := challenge(kind, index)
	var cleared := bool(result.get("cleared", false))
	var out := {"kind": kind, "name": str(c.name), "cleared": cleared, "claimed_now": false, "reward": {}}
	var entry := {"kills": int(result.get("kills", 0)), "time": float(result.get("time", 0.0)), "cleared": cleared, "tier": int(result.get("tier", 1))}
	var table: Dictionary = _state().get("best", {})
	var previous: Dictionary = table.get(id, {})
	if previous.is_empty() or score(entry) > score(previous):
		table[id] = entry
		_trim_dict(table)
		_state()["best"] = table
	_app.leaderboards.submit(str(c.leaderboard), id, score(entry), entry)
	# The reward: a clear, in this period or the one just ended (a run may cross
	# midnight), never twice, and not while the clock is behind.
	var current := period_index(kind)
	if cleared and not is_claimed(id) and index >= current - 1 and index <= current and check_clock():
		var claimed: Array = _state().get("claimed", [])
		claimed.append(id)
		while claimed.size() > KEPT:
			claimed.pop_front()
		_state()["claimed"] = claimed
		var reward: Dictionary = c.reward
		_app.economy.grant(Economy.CREDITS, int(reward.credits), "challenge_" + kind)
		_app.economy.grant(Economy.CRYSTALS, int(reward.crystals), "challenge_" + kind)
		_app.stats.add("%s_challenges_done" % kind, 1.0)
		out.claimed_now = true
		out.reward = reward
	_app.save.mark_dirty()
	changed.emit()
	return out


## One number per result, higher is better: a clear always beats a loss, then
## enemies destroyed. Leaderboards can take it as is.
static func score(entry: Dictionary) -> int:
	return (1000000 if bool(entry.get("cleared", false)) else 0) + int(entry.get("kills", 0))


static func _trim_dict(table: Dictionary) -> void:
	while table.size() > KEPT:
		table.erase(table.keys()[0])
