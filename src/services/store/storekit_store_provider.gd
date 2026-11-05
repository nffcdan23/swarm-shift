class_name StoreKitStoreProvider
extends StoreProvider
## The App Store, through StoreKit 2 (the "StoreKit" engine singleton built
## from native/storekit by tools/build_storekit.sh).
##
## Game product ids ("crystals_s") map to App Store product ids through
## monetization.json: a product's "ios_id" if it has one, otherwise
## "store"."ios_prefix" + the game id ("com.starscale.swarmshift.crystals_s").
## Prices are StoreKit's localised ones; until they arrive the shop shows none.
##
## The native side only ever reports transactions StoreKit has verified, and
## keeps each one open until finish() is called after StoreService has saved
## the goods.

## A purchase answer from the bridge (payload of its "purchase" event).
signal _purchase_answered(payload: Dictionary)
## The answer to a sync (Restore Purchases): entitlements or a failure.
signal _restore_answered(product_ids: Array, error: String)

const PRODUCTS_TIMEOUT_SEC := 20.0

var _app: AppRoot
var _bridge: Object
var _catalog: Dictionary
var _prefix := ""
## App Store id -> game id, and back.
var _to_game := {}
var _to_store := {}
## Game id -> StoreKit's localised price.
var _prices := {}
var _loaded := false
var _load_error := ""
var _restore_error := ""


func _init(bridge: Object) -> void:
	_bridge = bridge


func initialize(app: AppRoot, catalog: Dictionary) -> void:
	_app = app
	_catalog = catalog
	_prefix = GameData.text(GameData.dict(app.data.monetization, "store"), "ios_prefix")
	for product_id: String in catalog:
		var store_id := store_id_for(GameData.dict(catalog, product_id), product_id, _prefix)
		_to_game[store_id] = product_id
		_to_store[product_id] = store_id
	_bridge.connect("event", _on_event)
	# Listen first: StoreKit hands over pending and unfinished purchases as soon
	# as something is listening.
	_bridge.start()
	_bridge.load_products(PackedStringArray(_to_game.keys()))


## The App Store product id for a catalogue entry.
static func store_id_for(def: Dictionary, product_id: String, prefix: String) -> String:
	var explicit := GameData.text(def, "ios_id")
	return explicit if not explicit.is_empty() else prefix + product_id


func price(product_id: String) -> String:
	return str(_prices.get(product_id, ""))


func shows_fallback_prices() -> bool:
	return false


func purchase(product_id: String) -> Dictionary:
	if not _to_store.has(product_id):
		return {"ok": false, "error": "unknown_product"}
	if not _loaded:
		await _wait_for_products()
	if not _prices.has(product_id):
		return {"ok": false, "error": "unavailable"}
	var store_id: String = _to_store[product_id]
	_bridge.purchase(store_id)
	while true:
		var payload: Dictionary = await _purchase_answered
		if str(payload.get("product", "")) == store_id:
			return _result(payload)
	return {"ok": false, "error": "failed"}


func finish(transaction_id: String) -> void:
	if not transaction_id.is_empty():
		_bridge.finish_transaction(transaction_id)


func restore() -> Array:
	_restore_error = ""
	_bridge.sync()
	var answer: Array = await _restore_answered
	_restore_error = str(answer[1])
	var owned: Array = []
	for store_id: Variant in answer[0]:
		if _to_game.has(str(store_id)):
			owned.append(_to_game[str(store_id)])
	return owned


func last_restore_error() -> String:
	return _restore_error


func describe() -> String:
	return "storekit"


# ------------------------------------------------------------------- events

func _on_event(name: String, payload: Dictionary) -> void:
	match name:
		"products":
			for entry: Variant in payload.get("products", []):
				var store_id := str((entry as Dictionary).get("id", ""))
				if _to_game.has(store_id):
					_prices[_to_game[store_id]] = str((entry as Dictionary).get("price", ""))
			_loaded = true
			_load_error = ""
			var missing: Array = payload.get("invalid", [])
			if not missing.is_empty():
				push_warning("StoreKit: not found in App Store Connect: %s" % ", ".join(PackedStringArray(missing)))
			products_changed.emit()
		"products_failed":
			_loaded = true
			_load_error = str(payload.get("error", "failed"))
			push_warning("StoreKit: products failed to load: %s" % _load_error)
			products_changed.emit()
		"purchase":
			_purchase_answered.emit(payload)
		"transaction":
			var store_id := str(payload.get("product", ""))
			if _to_game.has(store_id):
				transaction_arrived.emit(_to_game[store_id], _result(payload))
		"revoked":
			var store_id := str(payload.get("product", ""))
			if _to_game.has(store_id):
				revoked.emit(_to_game[store_id], str(payload.get("transaction_id", "")))
		"entitlements":
			var owned: Array = []
			for store_id: Variant in payload.get("products", []):
				if _to_game.has(str(store_id)):
					owned.append(_to_game[str(store_id)])
			var source := str(payload.get("source", "launch"))
			if source == "restore":
				_restore_answered.emit(payload.get("products", []), "")
			entitlements_reported.emit(owned, source)
		"sync_failed":
			_restore_answered.emit([], str(payload.get("error", "failed")))


static func _result(payload: Dictionary) -> Dictionary:
	var status := str(payload.get("status", "failed"))
	if status == "purchased":
		return {"ok": true, "transaction_id": str(payload.get("transaction_id", "")), "receipt": str(payload.get("jws", "")),
			"original_id": str(payload.get("original_id", ""))}
	var error := status if status in ["cancelled", "pending", "unverified"] else str(payload.get("error", "failed"))
	if error == "product_not_loaded":
		error = "unavailable"
	return {"ok": false, "error": error}


func _wait_for_products() -> void:
	var deadline := Time.get_ticks_msec() + int(PRODUCTS_TIMEOUT_SEC * 1000.0)
	while not _loaded and Time.get_ticks_msec() < deadline:
		await _app.get_tree().process_frame
