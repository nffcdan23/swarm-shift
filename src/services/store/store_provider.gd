class_name StoreProvider
extends RefCounted
## Contract for a real-money store (StoreKit 2, Google Play Billing).
##
## `purchase()` is awaited and resolves to:
##   {"ok": bool, "receipt": String, "transaction_id": String, "error": String}
## The receipt must be passed to the validation backend before anything is
## granted in production - see StoreService._fulfil().


func initialize(_app: AppRoot, _catalog: Dictionary) -> void:
	pass


## Localised display price, or "" if the store has not answered yet.
func price(_product_id: String) -> String:
	return ""


func purchase(_product_id: String) -> Dictionary:
	return {"ok": false, "error": "unavailable"}


## Product ids of non-consumables the store says this account owns.
func restore() -> Array:
	return []


func describe() -> String:
	return "null"
