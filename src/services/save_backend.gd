class_name SaveBackend
extends RefCounted
## Where the serialized profile physically lives. The local file backend is the
## only one today; a cloud backend (iCloud / Play Games / own server) implements
## the same three calls and SaveService does not change.


func read() -> String:
	return ""


func write(_text: String) -> bool:
	return false


func erase() -> void:
	pass


func describe() -> String:
	return "null"
