class_name StoreProvider
extends RefCounted
## Contract for a real-money store (StoreKit 2, Google Play Billing).
##
## `purchase()` is awaited and resolves to:
##   {"ok": bool, "receipt": String, "transaction_id": String, "error": String}
## A successful result is delivered by StoreService, which then calls
## `finish(transaction_id)`: a real store keeps the transaction open until then,
## so a purchase paid for but not yet saved is delivered again next launch.
##
## Error codes StoreService and the shop understand: "cancelled", "pending"
## (waiting for approval, e.g. Ask to Buy), "network", "not_available",
## "unavailable" (the store is not reachable or has no such product),
## "unverified", "not_allowed"; anything else is a plain failure.

## A purchase that arrived outside purchase(): an unfinished one from an
## earlier launch, an approved "Ask to Buy", or one made on another device.
## `result` has the same keys as purchase()'s.
signal transaction_arrived(product_id: String, result: Dictionary)
## The store says a purchase was refunded or revoked.
signal revoked(product_id: String, transaction_id: String)
## Non-consumables the account owns, reported at launch ("launch") or after
## Restore Purchases ("restore").
signal entitlements_reported(product_ids: Array, source: String)
## Prices or availability changed (products finished loading).
signal products_changed


func initialize(_app: AppRoot, _catalog: Dictionary) -> void:
	pass


## Localised display price, or "" if the store has not answered yet.
func price(_product_id: String) -> String:
	return ""


## Whether the catalogue's fallback prices may be shown when price() is empty.
## A real store shows nothing rather than a guessed price in the wrong currency;
## this base class (the "no store" provider) sells nothing, so shows none.
func shows_fallback_prices() -> bool:
	return false


func purchase(_product_id: String) -> Dictionary:
	return {"ok": false, "error": "unavailable"}


## The purchase `transaction_id` has been delivered and saved.
func finish(_transaction_id: String) -> void:
	pass


## Product ids of non-consumables the store says this account owns.
func restore() -> Array:
	return []


## Why the last restore() came back empty, or "".
func last_restore_error() -> String:
	return ""


func describe() -> String:
	return "null"
