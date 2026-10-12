class_name AdProvider
extends RefCounted
## Contract for an ad network SDK (AdMob, AppLovin MAX, ironSource...).
## Both `show_*` calls are awaited by AdsService and must only return once the
## ad has been dismissed.


func initialize(_app: AppRoot) -> void:
	pass


func is_rewarded_ready() -> bool:
	return false


func is_interstitial_ready() -> bool:
	return false


## Returns true only if the player earned the reward (watched to completion).
func show_rewarded(_placement: String) -> bool:
	return false


## Returns true if an ad was actually displayed.
func show_interstitial(_placement: String) -> bool:
	return false


func describe() -> String:
	return "null"
