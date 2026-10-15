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

const CURRENT_VERSION := 1


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
		"loadout": {"core": "vanguard", "skin": "default"},
		"sectors": {"highest_cleared": 0, "selected": 1, "best_times": {}, "endless_best": 0.0},
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
			# 1: payload = _from_v1(payload)
			_:
				push_warning("Save: no migration registered from version %d" % version)
		version += 1
	payload["version"] = maxi(version, CURRENT_VERSION)
	fill_defaults(payload, defaults())
	return payload


static func fill_defaults(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		if not target.has(key):
			var value: Variant = source[key]
			target[key] = value.duplicate(true) if (value is Dictionary or value is Array) else value
		elif target[key] is Dictionary and source[key] is Dictionary:
			fill_defaults(target[key], source[key])
