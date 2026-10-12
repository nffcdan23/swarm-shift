class_name SaveService
extends RefCounted
## Owns the player profile (`state`) and its persistence.
##
## Services mutate their own section of `state` and call `mark_dirty()`; writes
## are debounced so a burst of changes becomes one file write. `flush()` forces
## it out (app backgrounded, run finished, purchase made).
##
## The envelope carries a checksum. That is tamper *evidence* only: anything of
## real-money value must be validated server-side before launch (see
## ARCHITECTURE.md, "Before real money").

signal loaded
signal saved

const DEBOUNCE_SECONDS := 2.0
const SALT := "swarmshift.local.v1"

var state: Dictionary = {}
var backend: SaveBackend
var is_new_profile := false
var integrity_ok := true

var _dirty := false
var _dirty_for := 0.0


func _init(p_backend: SaveBackend = null) -> void:
	backend = p_backend if p_backend != null else LocalSaveBackend.new()


func load_or_create() -> void:
	var payload := _decode(backend.read())
	if payload.is_empty() and backend is LocalSaveBackend:
		payload = _decode((backend as LocalSaveBackend).read_backup())
	if payload.is_empty():
		is_new_profile = true
		payload = SaveMigrations.defaults()
		payload["install_id"] = _new_install_id()
		payload["created_at"] = int(Time.get_unix_time_from_system())
	state = SaveMigrations.migrate(payload)
	state["last_seen"] = int(Time.get_unix_time_from_system())
	if is_new_profile:
		flush()
	loaded.emit()


func section(key: String) -> Dictionary:
	if not (state.get(key) is Dictionary):
		state[key] = {}
	return state[key]


func mark_dirty() -> void:
	_dirty = true


func tick(delta: float) -> void:
	if not _dirty:
		return
	_dirty_for += delta
	if _dirty_for >= DEBOUNCE_SECONDS:
		flush()


func flush() -> bool:
	_dirty = false
	_dirty_for = 0.0
	state["last_seen"] = int(Time.get_unix_time_from_system())
	var ok := backend.write(_encode(state))
	if ok:
		saved.emit()
	return ok


func reset() -> void:
	backend.erase()
	is_new_profile = false
	load_or_create()


# ---------------------------------------------------------------- encoding

func _encode(payload: Dictionary) -> String:
	var body := JSON.stringify(payload)
	return JSON.stringify({"v": SaveMigrations.CURRENT_VERSION, "sum": _checksum(body), "body": body})


func _decode(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var envelope: Variant = _parse_quietly(text)
	if not (envelope is Dictionary):
		return {}
	var body: Variant = (envelope as Dictionary).get("body")
	if not (body is String):
		return {}
	var payload: Variant = _parse_quietly(body)
	if not (payload is Dictionary):
		return {}
	integrity_ok = str((envelope as Dictionary).get("sum", "")) == _checksum(body)
	return payload


## A corrupt save is an expected condition, not an engine error worth logging.
func _parse_quietly(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


func _checksum(body: String) -> String:
	return (SALT + body).sha256_text()


func _new_install_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%08x%08x" % [rng.randi(), rng.randi()]
