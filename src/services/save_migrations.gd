class_name SaveMigrations
extends RefCounted
## Versioned profile schema.
##
## Purely additive changes (a new key with a default) need no migration:
## `defaults()` is deep-merged underneath every loaded profile, so old saves
## simply gain the new key.
##
## For a breaking change (rename, restructure, unit change):
##   1. bump CURRENT_VERSION
##   2. add a `_from_vN(payload)` function that converts version N to N+1
##   3. add its `N:` arm to the `match` in `migrate()`
## Steps run in sequence, so a player returning from any old build is walked
## forward one version at a time. Never delete a step once it has shipped.
##
## Keep a fixture of the old format in tests/fixtures and load it in a test.

const CURRENT_VERSION := 2

## Version 1 to 2: the head start in weapon mastery for existing players.
const VETERAN_XP_PER_RUN := 6.0
const VETERAN_XP_CAP := 300
const VETERAN_STARTERS: Array[String] = ["pulse", "scatter", "orbit", "nova"]


static func defaults() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"install_id": "",
		"created_at": 0,
		"last_seen": 0,
		"play_seconds": 0.0,
		"account": {"level": 1, "xp": 0},
		"currencies": {"credits": 0, "crystals": 0},
		"meta_upgrades": {},
		"unlocks": {"weapons": [], "cores": [], "skins": []},
		"loadout": {"core": "vanguard", "skin": "default", "doctrine": "", "start_weapon": ""},
		# Per weapon: {"xp", "kills", "damage", "runs"} (see MasteryService).
		"mastery": {},
		"evolutions": {"unlocked": []},
		"sectors": {"highest_cleared": 0, "selected": 1, "best_times": {}, "endless_best": 0.0},
		# Threat: per sector, the highest level cleared; the level picked in the
		# lobby; the levels whose one-off Crystal milestone has been paid.
		"threat": {"cleared": {}, "selected": 0, "milestones": []},
		# Daily and Weekly Challenges (ChallengeService): rewards claimed, best
		# results, and the latest clock reading seen, for the clock check.
		"challenges": {"claimed": [], "best": {}, "clock_high": 0, "selected": "daily"},
		"stats": {},
		"achievements": {"claimed": []},
		"missions": {"day": -1, "list": [], "bonus_claimed": false},
		"daily": {"last_claim_day": -1, "index": 0},
		"synergies": [],
		"settings": {
			"master": 1.0, "music": 0.7, "sfx": 1.0,
			"haptics": true, "damage_numbers": true, "screen_shake": 1.0,
			"low_effects": false
		},
		"purchases": {"entitlements": [], "history": []},
		"ads": {"last_interstitial_at": 0, "runs_since_interstitial": 0, "shop_credits_day": -1, "shop_credits_count": 0},
		"tutorial": {"moved": false, "levelled": false, "pickups": false},
		# Which runs have been paid out, and the run in progress (see RunLedger).
		"runs": {"settled": {}, "order": [], "pending": {}},
		"ab": {"group": ""},
	}


## Returns the payload upgraded to CURRENT_VERSION. Unknown keys are preserved,
## so a profile written by a newer build survives being opened by an older one.
static func migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("version", 1))
	while version < CURRENT_VERSION:
		match version:
			1:
				payload = _from_v1(payload)
			_:
				push_warning("Save: no migration registered from version %d" % version)
		version += 1
	payload["version"] = maxi(version, CURRENT_VERSION)
	fill_defaults(payload, defaults())
	return payload


## Version 2 (November 2026, the progression overhaul) adds weapon mastery. No
## existing progress changes: upgrade levels, unlocks, skins and balances are
## all still valid. So that a veteran does not start the new system from
## nothing, every weapon they own gets Mastery XP in proportion to the runs they
## have played, up to Rank 2, which is what the new start-weapon and perk
## systems look at first.
static func _from_v1(payload: Dictionary) -> Dictionary:
	var stats: Dictionary = payload.get("stats", {})
	var runs := float(stats.get("runs", 0.0))
	var grant := mini(int(runs * VETERAN_XP_PER_RUN), VETERAN_XP_CAP)
	if grant <= 0:
		return payload
	var unlocks: Dictionary = payload.get("unlocks", {})
	var weapons: Array = VETERAN_STARTERS.duplicate()
	for id: String in unlocks.get("weapons", []):
		if not weapons.has(id):
			weapons.append(id)
	var mastery: Dictionary = payload.get("mastery", {})
	for id: String in weapons:
		mastery[id] = {"xp": grant, "kills": 0, "damage": 0.0, "runs": 0}
	payload["mastery"] = mastery
	return payload


static func fill_defaults(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		if not target.has(key):
			var value: Variant = source[key]
			target[key] = value.duplicate(true) if (value is Dictionary or value is Array) else value
		elif target[key] is Dictionary and source[key] is Dictionary:
			fill_defaults(target[key], source[key])
