class_name GameClock
extends RefCounted
## Single source of "what time is it" for daily systems.
##
## Everything date-driven (missions, login calendar, ad caps) reads the clock
## from here, so swapping in server time later - and time-travelling in tests -
## is a one-line change. `offset_seconds` is that hook.

var offset_seconds := 0


func now() -> int:
	return int(Time.get_unix_time_from_system()) + offset_seconds


## Local calendar day number. Changes at the player's local midnight.
func day_index() -> int:
	var zone := Time.get_time_zone_from_system()
	var bias_minutes := int(zone.get("bias", 0))
	return floori(float(now() + bias_minutes * 60) / 86400.0)


func seconds_until_next_day() -> int:
	var zone := Time.get_time_zone_from_system()
	var local := now() + int(zone.get("bias", 0)) * 60
	return 86400 - posmod(local, 86400)
