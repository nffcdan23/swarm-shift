class_name GameData
extends RefCounted
## Loads every balance/content table from res://data/*.json.
##
## All tuning lives in those files. `apply_overrides()` deep-merges a second
## dictionary on top, which is the hook for remote config and A/B tests: ship a
## JSON blob shaped like {"enemies": {"types": {"swarmer": {"hp": 12}}}} and it
## wins over the bundled value without a client update.

const DATA_DIR := "res://data/"
const FILES: PackedStringArray = ["game", "enemies", "weapons", "upgrades", "stages", "meta", "retention", "monetization", "audio", "sprites"]

var game: Dictionary = {}
var enemies: Dictionary = {}
var weapons: Dictionary = {}
var upgrades: Dictionary = {}
var stages: Dictionary = {}
var meta: Dictionary = {}
var retention: Dictionary = {}
var monetization: Dictionary = {}
var audio: Dictionary = {}
var sprites: Dictionary = {}

var errors: PackedStringArray = []


func load_all() -> bool:
	errors.clear()
	for file in FILES:
		set(file, _read_json(DATA_DIR + file + ".json"))
	return errors.is_empty()


func apply_overrides(overrides: Dictionary) -> void:
	for file in FILES:
		if overrides.has(file) and overrides[file] is Dictionary:
			var table: Dictionary = get(file)
			deep_merge(table, overrides[file])


static func deep_merge(base: Dictionary, over: Dictionary) -> void:
	for key: Variant in over:
		if base.has(key) and base[key] is Dictionary and over[key] is Dictionary:
			deep_merge(base[key], over[key])
		else:
			base[key] = over[key]


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Missing data file: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		errors.append(path + ": root must be an object")
		return {}
	return json.data


# ------------------------------------------------------------ typed lookups

static func num(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	var v: Variant = d.get(key)
	if v is float or v is int:
		return float(v)
	return fallback


static func integer(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v: Variant = d.get(key)
	if v is float or v is int:
		return int(v)
	return fallback


static func text(d: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = d.get(key)
	if v is String:
		return v
	return fallback


static func flag(d: Dictionary, key: String, fallback: bool = false) -> bool:
	var v: Variant = d.get(key)
	if v is bool:
		return v
	if v is float or v is int:
		return float(v) != 0.0
	return fallback


static func dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	if v is Dictionary:
		return v
	return {}


static func list(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key)
	if v is Array:
		return v
	return []


static func color(d: Dictionary, key: String, fallback: Color = Color.WHITE) -> Color:
	return Fmt.hex(text(d, key), fallback)


## Piecewise-linear lookup over [[t, value], ...] keyframes sorted by t.
static func curve(points: Array, t: float) -> float:
	var n := points.size()
	if n == 0:
		return 0.0
	var first: Array = points[0]
	if t <= float(first[0]):
		return float(first[1])
	for i in range(1, n):
		var b: Array = points[i]
		var bt := float(b[0])
		if t <= bt:
			var a: Array = points[i - 1]
			var at := float(a[0])
			var span := bt - at
			if span <= 0.0:
				return float(b[1])
			return lerpf(float(a[1]), float(b[1]), (t - at) / span)
	var last: Array = points[n - 1]
	return float(last[1])


# ------------------------------------------------------------- convenience

func title() -> String:
	return text(game, "title", "GAME")


func weapon_defs() -> Dictionary:
	return dict(weapons, "weapons")


func weapon(id: String) -> Dictionary:
	return dict(weapon_defs(), id)


func enemy_types() -> Dictionary:
	return dict(enemies, "types")


func passives() -> Dictionary:
	return dict(upgrades, "passives")


func augments() -> Dictionary:
	return dict(upgrades, "augments")


func synergies() -> Dictionary:
	return dict(upgrades, "synergies")


func cores() -> Dictionary:
	return dict(meta, "cores")


func skins() -> Dictionary:
	return dict(meta, "skins")


func meta_upgrades() -> Dictionary:
	return dict(meta, "upgrades")


func products() -> Dictionary:
	return dict(monetization, "products")


func rarity(id: String) -> Dictionary:
	return dict(dict(game, "rarities"), id)


func run_cfg() -> Dictionary:
	return dict(game, "run")


# -------------------------------------------------------------- validation

## Cross-checks references between tables. Returns human-readable problems.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	var enemy_ids := enemy_types()
	var weapon_ids := weapon_defs()
	var atlas: Array = list(sprites, "atlas")

	for id: String in enemy_ids:
		var e: Dictionary = enemy_ids[id]
		if not atlas.has(text(e, "sprite")):
			out.append("enemy '%s': sprite '%s' is not in sprites.json atlas" % [id, text(e, "sprite")])
		var split := dict(e, "split")
		if not split.is_empty() and not enemy_ids.has(text(split, "into")):
			out.append("enemy '%s': splits into unknown '%s'" % [id, text(split, "into")])

	for name: String in atlas:
		if not ResourceLoader.exists("res://assets/sprites/atlas/%s.png" % name):
			out.append("sprites.json: missing atlas image '%s'" % name)

	var max_level := integer(weapons, "max_level", 5)
	for id: String in weapon_ids:
		var w: Dictionary = weapon_ids[id]
		if not ResourceLoader.exists("res://src/game/weapons/%s.gd" % text(w, "script")):
			out.append("weapon '%s': script '%s' not found" % [id, text(w, "script")])
		if list(w, "levels").size() != max_level:
			out.append("weapon '%s': expected %d levels, found %d" % [id, max_level, list(w, "levels").size()])

	var timeline := dict(stages, "timeline")
	for track: Dictionary in list(timeline, "tracks"):
		if not enemy_ids.has(text(track, "enemy")):
			out.append("stage track: unknown enemy '%s'" % text(track, "enemy"))
	for event: Dictionary in list(timeline, "events"):
		_check_event(event, "stage event @%s" % str(event.get("t")), out)
	if not dict(stages, "bosses").has(text(timeline, "boss")):
		out.append("timeline: unknown boss '%s'" % text(timeline, "boss"))

	# Sector briefs and mutators.
	var sectors := dict(stages, "sectors")
	var mutators := dict(sectors, "mutators")
	for mutator_id: String in list(sectors, "rotation"):
		if not mutators.has(mutator_id):
			out.append("sectors.rotation: unknown mutator '%s'" % mutator_id)
	for mutator_id: String in mutators:
		var mutator: Dictionary = mutators[mutator_id]
		for enemy_id: String in dict(mutator, "tracks"):
			if not enemy_ids.has(enemy_id):
				out.append("mutator '%s': unknown enemy '%s'" % [mutator_id, enemy_id])
		var every := dict(mutator, "every")
		if not every.is_empty():
			_check_event(dict(every, "event"), "mutator '%s' event" % mutator_id, out)
		var affix := text(mutator, "elite_affix")
		if not affix.is_empty() and not dict(dict(enemies, "elite"), "affixes").has(affix):
			out.append("mutator '%s': unknown elite affix '%s'" % [mutator_id, affix])
	for brief: Dictionary in list(sectors, "briefs"):
		for enemy_id: String in list(brief, "new"):
			if not enemy_ids.has(enemy_id):
				out.append("sector %s brief: unknown enemy '%s'" % [str(brief.get("sector")), enemy_id])

	# Permanent upgrades.
	var categories := dict(meta, "upgrade_categories")
	for id: String in meta_upgrades():
		var upgrade: Dictionary = meta_upgrades()[id]
		if not categories.has(text(upgrade, "category")):
			out.append("upgrade '%s': unknown category '%s'" % [id, text(upgrade, "category")])
		if dict(upgrade, "mods").size() != 1:
			out.append("upgrade '%s': must have exactly one modifier" % id)
		if not text(upgrade, "format") in ["percent", "number"]:
			out.append("upgrade '%s': format must be 'percent' or 'number'" % id)
		if integer(upgrade, "unlock_level") > integer(dict(meta, "account"), "max_level", 100):
			out.append("upgrade '%s': unlock level is above the level cap" % id)

	var rarities := dict(game, "rarities")
	for group_key: String in ["passives", "augments"]:
		var group := dict(upgrades, group_key)
		for id: String in group:
			var u: Dictionary = group[id]
			if not rarities.has(text(u, "rarity")):
				out.append("%s '%s': unknown rarity '%s'" % [group_key, id, text(u, "rarity")])
			var req := dict(u, "requires")
			for token: String in list(req, "any") + list(req, "all"):
				_check_token(token, "%s '%s'" % [group_key, id], out)
	for id: String in synergies():
		var syn: Dictionary = synergies()[id]
		for token: String in list(syn, "requires"):
			_check_token(token, "synergy '%s'" % id, out)

	for id: String in cores():
		var core: Dictionary = cores()[id]
		if not weapon_ids.has(text(core, "start_weapon")):
			out.append("core '%s': unknown start weapon '%s'" % [id, text(core, "start_weapon")])

	for id: String in skins():
		var unlock := dict(skins()[id], "unlock")
		if text(unlock, "type") == "product" and not products().has(text(unlock, "product")):
			out.append("skin '%s': unknown product '%s'" % [id, text(unlock, "product")])

	for product_id: String in list(monetization, "shop_layout"):
		if not products().has(product_id):
			out.append("shop_layout: unknown product '%s'" % product_id)

	for id: String in dict(audio, "sfx"):
		var file := text(dict(audio, "sfx")[id], "file")
		if not ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % file):
			out.append("audio: missing sfx file '%s.wav'" % file)
	for id: String in dict(audio, "music"):
		var file := text(dict(audio, "music")[id], "file")
		if not ResourceLoader.exists("res://assets/audio/music/%s.wav" % file):
			out.append("audio: missing music file '%s.wav'" % file)
	return out


## One scripted set piece: its type must be known and its enemies must exist.
func _check_event(event: Dictionary, owner: String, out: PackedStringArray) -> void:
	var enemy_ids := enemy_types()
	var etype := text(event, "type")
	if not etype in ["surge", "elite", "pack", "pincer", "line", "bombard"]:
		out.append("%s: unknown event type '%s'" % [owner, etype])
	if etype in ["elite", "pack", "pincer", "line"] and not enemy_ids.has(text(event, "enemy")):
		out.append("%s: unknown enemy '%s'" % [owner, text(event, "enemy")])
	for group_key: String in ["spawns", "escort"]:
		for enemy_id: String in dict(event, group_key):
			if not enemy_ids.has(enemy_id):
				out.append("%s: unknown enemy '%s'" % [owner, enemy_id])


func _check_token(token: String, owner: String, out: PackedStringArray) -> void:
	var parts := token.split(":")
	if parts.size() != 2:
		out.append("%s: malformed requirement '%s'" % [owner, token])
		return
	var table: Dictionary = {}
	match parts[0]:
		"w": table = weapon_defs()
		"p": table = passives()
		"a": table = augments()
		_:
			out.append("%s: unknown requirement kind '%s'" % [owner, token])
			return
	if not table.has(parts[1]):
		out.append("%s: requirement '%s' refers to nothing" % [owner, token])
