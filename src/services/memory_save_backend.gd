class_name MemorySaveBackend
extends SaveBackend
## Keeps the profile in RAM. Used by tests, simulations and screenshot tours so
## automated runs can never touch a real player profile on disk.

var text := ""
var writes := 0


func read() -> String:
	return text


func write(p_text: String) -> bool:
	text = p_text
	writes += 1
	return true


func erase() -> void:
	text = ""


func describe() -> String:
	return "memory"
