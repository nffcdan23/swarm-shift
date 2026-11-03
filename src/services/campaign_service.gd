class_name CampaignService
extends RefCounted
## Sector progression. Clearing sector N unlocks N+1; clearing the configured
## sector opens Endless (Overdrive).
##
## Sectors share one timeline but are not the same fight with bigger numbers:
##   - the first sectors each add enemies and set pieces (`min_sector` in
##     stages.json), so Sector 1 teaches the basics and 2 and 3 add mechanics;
##   - from `mutator_start` every sector carries a mutator from a rotation,
##     and later sectors carry two - a rule change, shown in the lobby;
##   - underneath, health/damage/spawn rate scale with the tier.
##
## Threat levels (the "threat" block in stages.json) are for sectors already
## cleared: ten cumulative tiers, each adding one more mutator. Each sector has
## its own ladder - level N needs that sector cleared at N - 1 - and each level
## opens across all sectors once the campaign has reached its `unlock_sector`.
## Casual play is untouched: level 0 is the ordinary sector.

signal changed

const MODE_SECTOR := "sector"
const MODE_ENDLESS := "endless"
## A Daily or Weekly Challenge (ChallengeService). Never counts as a sector clear.
const MODE_CHALLENGE := "challenge"

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func sector_count() -> int:
	return GameData.integer(_app.data.stages, "sector_count", 20)


func highest_cleared() -> int:
	return int(_app.save.section("sectors").get("highest_cleared", 0))


func max_selectable() -> int:
	return mini(highest_cleared() + 1, sector_count())


func selected() -> int:
	return clampi(int(_app.save.section("sectors").get("selected", 1)), 1, max_selectable())


func select(tier: int) -> void:
	_app.save.section("sectors")["selected"] = clampi(tier, 1, max_selectable())
	_app.save.mark_dirty()
	changed.emit()


func endless_unlocked() -> bool:
	return highest_cleared() >= GameData.integer(_app.data.stages, "endless_unlock_sector", 3)


func best_time(tier: int) -> float:
	var times: Dictionary = _app.save.section("sectors").get("best_times", {})
	return float(times.get(str(tier), 0.0))


func endless_best() -> float:
	return float(_app.save.section("sectors").get("endless_best", 0.0))


func theme(tier: int) -> Dictionary:
	var themes := GameData.list(_app.data.stages, "themes")
	if themes.is_empty():
		return {}
	return themes[posmod(tier - 1, themes.size())]


# ------------------------------------------------------- sector character

func _sectors() -> Dictionary:
	return GameData.dict(_app.data.stages, "sectors")


## Mutator ids in force for a sector. Overdrive passes its cycle count: the
## first cycle is clean, then each cycle rotates in one mutator.
func mutator_ids(mode: String, tier: int, cycle: int = 0) -> Array[String]:
	var out: Array[String] = []
	var cfg := _sectors()
	var rotation := GameData.list(cfg, "rotation")
	if rotation.is_empty():
		return out
	if mode == MODE_ENDLESS:
		if cycle >= 1:
			out.append(str(rotation[(cycle - 1) % rotation.size()]))
		return out
	var first := GameData.integer(cfg, "mutator_start", 4)
	if tier < first:
		return out
	out.append(str(rotation[(tier - first) % rotation.size()]))
	var second := GameData.integer(cfg, "second_mutator_start", 10)
	if tier >= second and rotation.size() > 1:
		# Half a rotation away, so the pair is never the same mutator twice.
		@warning_ignore("integer_division")
		out.append(str(rotation[(tier - first + rotation.size() / 2) % rotation.size()]))
	return out


func mutator_def(id: String) -> Dictionary:
	return GameData.dict(GameData.dict(_sectors(), "mutators"), id)


## The combined effect of a set of mutators, in the shape the Director reads:
## {"speed", "hp", "spawn", "tracks": {enemy: mult}, "every": [...], "elite_affix",
## "elite_extra_affix", "elite_hp", "shot_speed", "shooter_spread", "heal",
## "revives", "boss": {"phase_floor", "idle_mult", "bullets_mult", "final_phase"}}.
## Multipliers multiply, so stacked Threat levels compound.
func mutator_effects(ids: Array[String]) -> Dictionary:
	var out := {"speed": 1.0, "hp": 1.0, "spawn": 1.0, "tracks": {}, "every": [], "elite_affix": "",
		"elite_extra_affix": "", "elite_hp": 1.0, "shot_speed": 1.0, "shooter_spread": 1, "heal": 1.0, "revives": true,
		"boss": {"phase_floor": 0, "idle_mult": 1.0, "bullets_mult": 1.0, "final_phase": {}}}
	for id in ids:
		var def := mutator_def(id)
		out.speed = float(out.speed) * GameData.num(def, "speed", 1.0)
		out.hp = float(out.hp) * GameData.num(def, "hp", 1.0)
		out.spawn = float(out.spawn) * GameData.num(def, "spawn", 1.0)
		var tracks := GameData.dict(def, "tracks")
		for enemy_id: String in tracks:
			out.tracks[enemy_id] = float(out.tracks.get(enemy_id, 1.0)) * float(tracks[enemy_id])
		var every := GameData.dict(def, "every")
		if not every.is_empty():
			(out.every as Array).append(every)
		if not GameData.text(def, "elite_affix").is_empty():
			out.elite_affix = GameData.text(def, "elite_affix")
		if not GameData.text(def, "elite_extra_affix").is_empty():
			out.elite_extra_affix = GameData.text(def, "elite_extra_affix")
		out.elite_hp = float(out.elite_hp) * GameData.num(def, "elite_hp", 1.0)
		out.shot_speed = float(out.shot_speed) * GameData.num(def, "shot_speed", 1.0)
		out.shooter_spread = maxi(int(out.shooter_spread), GameData.integer(def, "shooter_spread", 1))
		out.heal = float(out.heal) * GameData.num(def, "heal", 1.0)
		if not GameData.flag(def, "revives", true):
			out.revives = false
		var boss_def := GameData.dict(def, "boss")
		var boss: Dictionary = out.boss
		boss.phase_floor = maxi(int(boss.phase_floor), GameData.integer(boss_def, "phase_floor", 0))
		boss.idle_mult = float(boss.idle_mult) * GameData.num(boss_def, "idle_mult", 1.0)
		boss.bullets_mult = float(boss.bullets_mult) * GameData.num(boss_def, "bullets_mult", 1.0)
		if not GameData.dict(boss_def, "final_phase").is_empty():
			boss.final_phase = GameData.dict(boss_def, "final_phase")
	return out


## What the lobby says about a sector: its name, a one-line brief, the enemies
## it introduces and its mutators ({"id", "name", "desc", "color"}).
func sector_brief(tier: int) -> Dictionary:
	var out := {"name": "", "brief": "", "new": [], "mutators": []}
	for entry: Dictionary in GameData.list(_sectors(), "briefs"):
		if GameData.integer(entry, "sector") == tier:
			out.name = GameData.text(entry, "name")
			out.brief = GameData.text(entry, "brief")
			for enemy_id: String in GameData.list(entry, "new"):
				(out.new as Array).append(GameData.text(GameData.dict(_app.data.enemy_types(), enemy_id), "name", enemy_id))
	for id in mutator_ids(MODE_SECTOR, tier):
		var def := mutator_def(id)
		(out.mutators as Array).append({"id": id, "name": GameData.text(def, "name", id.to_upper()),
			"desc": GameData.text(def, "desc"), "color": GameData.color(def, "color", Color("ffc247"))})
	if str(out.brief).is_empty():
		var descs: PackedStringArray = []
		for mutator: Dictionary in out.mutators:
			descs.append(str(mutator.desc))
		out.brief = ". ".join(descs) if not descs.is_empty() else "Everything the swarm has, harder."
	return out


# ----------------------------------------------------------------- threat

func _threat_cfg() -> Dictionary:
	return GameData.dict(_app.data.stages, "threat")


func _threat_state() -> Dictionary:
	return _app.save.section("threat")


func threat_levels() -> Array:
	return GameData.list(_threat_cfg(), "levels")


func threat_max() -> int:
	return threat_levels().size()


func threat_unlock_sector(level: int) -> int:
	if level <= 0 or level > threat_max():
		return 0
	return GameData.integer(threat_levels()[level - 1], "unlock_sector", 4)


## Has the campaign reached the point where this level opens at all?
func threat_level_open(level: int) -> bool:
	return level >= 1 and level <= threat_max() and highest_cleared() >= threat_unlock_sector(level)


## Whether Threat exists for this player yet (it needs Threat 1 open).
func threat_available() -> bool:
	return threat_level_open(1)


## The highest Threat this sector has been cleared at (0: only the ordinary clear).
func threat_cleared(tier: int) -> int:
	var by_sector: Dictionary = _threat_state().get("cleared", {})
	return int(by_sector.get(str(tier), 0))


## The highest Threat this sector can be played at now: one above its own
## best, if that level is open. 0 for a sector not yet cleared.
func max_threat(tier: int) -> int:
	if tier < 1 or tier > highest_cleared():
		return 0
	var level := mini(threat_cleared(tier) + 1, threat_max())
	while level > 0 and not threat_level_open(level):
		level -= 1
	return level


func selected_threat() -> int:
	return clampi(int(_threat_state().get("selected", 0)), 0, max_threat(selected()))


func select_threat(level: int) -> void:
	_threat_state()["selected"] = clampi(level, 0, max_threat(selected()))
	_app.save.mark_dirty()
	changed.emit()


## The mutators a Threat level adds, lowest level first (cumulative).
func threat_mutators(level: int) -> Array[String]:
	var out: Array[String] = []
	var levels := threat_levels()
	for i in clampi(level, 0, levels.size()):
		out.append(GameData.text(levels[i], "mutator"))
	return out


## The mutator a Threat level adds on top of the one below it.
func threat_mutator(level: int) -> String:
	if level <= 0 or level > threat_max():
		return ""
	return GameData.text(threat_levels()[level - 1], "mutator")


func threat_reward_mult(level: int) -> float:
	return 1.0 + GameData.num(_threat_cfg(), "reward_per_level", 0.12) * float(maxi(level, 0))


func threat_xp_mult(level: int) -> float:
	return 1.0 + GameData.num(_threat_cfg(), "xp_per_level", 0.08) * float(maxi(level, 0))


## Credits for clearing this sector at this level for the first time.
func threat_first_clear_credits(tier: int, level: int) -> int:
	return int(round(GameData.num(_threat_cfg(), "first_clear_credits", 50.0) * float(level) * float(scaling(float(tier)).reward)))


## Crystals for the first clear of this level on any sector; 0 once paid.
func threat_milestone_crystals(level: int) -> int:
	var paid: Array = _threat_state().get("milestones", [])
	if level <= 0 or paid.has(level):
		return 0
	return GameData.integer(_threat_cfg(), "milestone_crystals", 5) * level


func highest_threat_cleared() -> int:
	var best := 0
	var by_sector: Dictionary = _threat_state().get("cleared", {})
	for key: String in by_sector:
		best = maxi(best, int(by_sector[key]))
	return best


## How many sectors have been cleared at this Threat or above.
func sectors_at_threat(level: int) -> int:
	var n := 0
	var by_sector: Dictionary = _threat_state().get("cleared", {})
	for key: String in by_sector:
		if int(by_sector[key]) >= level:
			n += 1
	return n


## Multipliers applied to a run at the given (possibly fractional) tier.
func scaling(tier: float) -> Dictionary:
	var s := GameData.dict(_app.data.stages, "scaling")
	var steps := maxf(tier - 1.0, 0.0)
	var squared := steps * steps
	return {
		"hp": 1.0 + GameData.num(s, "hp_per_tier") * steps + GameData.num(s, "hp_per_tier_sq") * squared,
		"damage": 1.0 + GameData.num(s, "damage_per_tier") * steps + GameData.num(s, "damage_per_tier_sq") * squared,
		"speed": minf(1.0 + GameData.num(s, "speed_per_tier") * steps, GameData.num(s, "speed_cap", 1.3)),
		"spawn": minf(1.0 + GameData.num(s, "spawn_per_tier") * steps, GameData.num(s, "spawn_cap", 1.6)),
		"boss_hp": 1.0 + GameData.num(s, "boss_hp_per_tier") * steps + GameData.num(s, "boss_hp_per_tier_sq") * squared,
		"reward": 1.0 + GameData.num(s, "reward_per_tier") * steps,
		"account_xp": 1.0 + GameData.num(s, "account_xp_per_tier") * steps,
	}


## The tier a run is paid at. A sector pays its own tier. Overdrive climbs fast
## and pays by how deep it got, but never past what the player has earned in the
## campaign: otherwise it is simply the best way to earn from Sector 3 onwards,
## and the sectors stop mattering.
func reward_tier(mode: String, effective_tier: float) -> float:
	if mode == MODE_ENDLESS or mode == MODE_CHALLENGE:
		return minf(effective_tier, float(highest_cleared()) + 1.0)
	return effective_tier


## Records a finished run. Returns {"first_clear": bool, "new_best": bool,
## "threat_first_clear": bool}.
func record_run(mode: String, tier: int, cleared: bool, seconds: float, threat: int = 0) -> Dictionary:
	var sectors := _app.save.section("sectors")
	var out := {"first_clear": false, "new_best": false, "threat_first_clear": false}
	if mode == MODE_CHALLENGE:
		return out
	if mode == MODE_SECTOR and threat > 0:
		# A Threat run is never an ordinary clear: the sector was already
		# cleared, and its best time stays the ordinary one.
		if cleared:
			out.threat_first_clear = threat > threat_cleared(tier)
			var state := _threat_state()
			var by_sector: Dictionary = state.get("cleared", {})
			by_sector[str(tier)] = maxi(threat, threat_cleared(tier))
			state["cleared"] = by_sector
			var paid: Array = state.get("milestones", [])
			if not paid.has(threat):
				paid.append(threat)
			state["milestones"] = paid
		_app.save.mark_dirty()
		changed.emit()
		return out
	if mode == MODE_ENDLESS:
		if seconds > endless_best():
			sectors["endless_best"] = seconds
			out.new_best = true
	elif cleared:
		var times: Dictionary = sectors.get("best_times", {})
		var key := str(tier)
		if not times.has(key) or seconds < float(times[key]):
			times[key] = seconds
			sectors["best_times"] = times
			out.new_best = true
		if tier > highest_cleared():
			sectors["highest_cleared"] = tier
			out.first_clear = true
			# Move the selector forward so the next press of PLAY is fresh content.
			sectors["selected"] = mini(tier + 1, sector_count())
	_app.save.mark_dirty()
	changed.emit()
	return out
