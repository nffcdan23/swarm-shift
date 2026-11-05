class_name MemorySaveBackend
extends SaveBackend
## Keeps the profile in RAM. Used by tests, simulations and screenshot tours so
## automated runs can never touch a real player profile on disk.

var text := ""
var writes := 0
## Tests set this to make writes fail, as a full disk would.
var fail_writes := false


func read() -> String:
	return text


func write(p_text: String) -> bool:
	if fail_writes:
		return false
	text = p_text
	writes += 1
	return true


func erase() -> void:
	text = ""


func describe() -> String:
	return "memory"
