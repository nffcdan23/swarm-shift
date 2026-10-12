class_name LocalSaveBackend
extends SaveBackend
## Atomic local persistence: write to a temp file, keep the previous good file
## as a backup, then swap. A crash or kill mid-write can never leave the player
## with a truncated profile.

var _path: String
var _backup: String
var _temp: String


func _init(path: String = "user://profile.save") -> void:
	_path = path
	_backup = path + ".bak"
	_temp = path + ".tmp"


func read() -> String:
	for candidate: String in [_path, _backup]:
		if FileAccess.file_exists(candidate):
			var text := FileAccess.get_file_as_string(candidate)
			if not text.is_empty():
				return text
	return ""


## Used when the primary file exists but turned out to be unreadable.
func read_backup() -> String:
	if FileAccess.file_exists(_backup):
		return FileAccess.get_file_as_string(_backup)
	return ""


func write(text: String) -> bool:
	var file := FileAccess.open(_temp, FileAccess.WRITE)
	if file == null:
		push_error("Save: cannot open %s (%d)" % [_temp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(_path):
		if dir.file_exists(_backup):
			dir.remove(_backup)
		dir.rename(_path, _backup)
	return dir.rename(_temp, _path) == OK


func erase() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for candidate: String in [_path, _backup, _temp]:
		if dir.file_exists(candidate):
			dir.remove(candidate)


func describe() -> String:
	return "local:" + ProjectSettings.globalize_path(_path)
