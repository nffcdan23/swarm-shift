class_name LocalLogAnalyticsProvider
extends AnalyticsProvider
## Development provider: appends one JSON object per line to
## user://analytics.jsonl and keeps the most recent events in memory for tests
## and debug overlays. Nothing leaves the device.

const PATH := "user://analytics.jsonl"
const MAX_FILE_BYTES := 512 * 1024
const MEMORY_EVENTS := 300

var recent: Array[Dictionary] = []
var echo := false
var write_file := true

var _pending: PackedStringArray = []
var _user: Dictionary = {}


func track(event: String, props: Dictionary) -> void:
	var record := {"event": event, "props": props}
	recent.append(record)
	if recent.size() > MEMORY_EVENTS:
		recent.pop_front()
	_pending.append(JSON.stringify(record))
	if echo:
		print("[analytics] ", event, " ", props)
	if _pending.size() >= 20:
		flush()


func set_user_property(key: String, value: Variant) -> void:
	_user[key] = value


func flush() -> void:
	if _pending.is_empty() or not write_file:
		_pending.clear()
		return
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE
	var file := FileAccess.open(PATH, mode)
	if file == null:
		_pending.clear()
		return
	if file.get_length() > MAX_FILE_BYTES:
		# Development log only: start over rather than grow without bound.
		file.close()
		file = FileAccess.open(PATH, FileAccess.WRITE)
		if file == null:
			_pending.clear()
			return
	file.seek_end()
	for line in _pending:
		file.store_line(line)
	file.close()
	_pending.clear()


func count(event: String) -> int:
	var n := 0
	for record in recent:
		if record.event == event:
			n += 1
	return n
