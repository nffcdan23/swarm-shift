class_name StoreService
extends RefCounted
## Real-money purchases, independent of the platform store.
##
## Flow: purchase() -> provider.purchase() -> _deliver() grants the product's
## `grants` block (currencies, skin, entitlement), records the transaction,
## saves, and only then tells the provider to finish the transaction. A store
## that keeps unfinished transactions (StoreKit) hands one back on the next
## launch if the game closed in between; a transaction id already in the
## history is never paid twice.
##
## Validation: StoreKitStoreProvider only reports transactions StoreKit has
## verified (signed by the App Store for this app). Server-side validation of
## `receipt` (the signed transaction) would go in _deliver(), marked below; it
## is optional for a game of this size (APP_STORE_READINESS.md B-8).

signal purchase_completed(product_id: String)
signal purchase_failed(product_id: String, reason: String)
signal entitlements_changed
## Prices or availability changed: the shop should redraw.
signal catalog_changed

var provider: StoreProvider
## The reason the last purchase() failed ("" after a success).
var last_error := ""

var _app: AppRoot
var _busy := false


func _init(app: AppRoot, p_provider: StoreProvider) -> void:
	_app = app
	provider = p_provider
	provider.transaction_arrived.connect(_on_transaction_arrived)
	provider.revoked.connect(_on_revoked)
	provider.entitlements_reported.connect(_on_entitlements_reported)
	provider.products_changed.connect(_on_products_changed)
	provider.initialize(app, app.data.products())


func is_busy() -> bool:
	return _busy


func has_entitlement(name: String) -> bool:
	var owned: Array = _app.save.section("purchases").get("entitlements", [])
	return owned.has(name)


func is_owned(product_id: String) -> bool:
	var def := GameData.dict(_app.data.products(), product_id)
	if GameData.text(def, "type") != "non_consumable":
		return false
	return has_entitlement(GameData.text(GameData.dict(def, "grants"), "entitlement", product_id))


func price(product_id: String) -> String:
	var live := provider.price(product_id)
	if not live.is_empty():
		return live
	if not provider.shows_fallback_prices():
		return "-"
	return GameData.text(GameData.dict(_app.data.products(), product_id), "price", "-")


## Whether the store can sell this product right now (it has a real price).
func is_available(product_id: String) -> bool:
	return not provider.price(product_id).is_empty() or provider.shows_fallback_prices()


## Shop rows in display order.
func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for product_id: String in GameData.list(_app.data.monetization, "shop_layout"):
		var def := GameData.dict(_app.data.products(), product_id)
		if def.is_empty():
			continue
		out.append({
			"id": product_id,
			"name": GameData.text(def, "name"),
			"desc": GameData.text(def, "desc"),
			"icon": GameData.text(def, "icon", "gift"),
			"tag": GameData.text(def, "tag"),
			"price": price(product_id),
			"owned": is_owned(product_id),
		})
	return out


func purchase(product_id: String) -> bool:
	if _busy:
		return false
	if not _app.data.products().has(product_id) or is_owned(product_id):
		purchase_failed.emit(product_id, "not_purchasable")
		return false
	_busy = true
	_app.analytics.track(Analytics.PURCHASE_STARTED, {"product": product_id})
	var result: Dictionary = await provider.purchase(product_id)
	_busy = false
	if not bool(result.get("ok", false)):
		var reason := str(result.get("error", "failed"))
		last_error = reason
		_app.analytics.track(Analytics.PURCHASE_FAILED, {"product": product_id, "reason": reason})
		purchase_failed.emit(product_id, reason)
		return false
	last_error = ""
	_deliver(product_id, result, "purchase")
	return true


## Re-grants non-consumables the store reports as owned (required by Apple).
func restore() -> int:
	if _busy:
		return 0
	_busy = true
	var owned: Array = await provider.restore()
	_busy = false
	last_error = provider.last_restore_error()
	return _restore_owned(owned)


func _restore_owned(owned: Array) -> int:
	var restored := 0
	for product_id: Variant in owned:
		var id := str(product_id)
		# Only non-consumables are restorable; a store that ever lists a
		# consumable here must not pay it out again.
		if GameData.text(GameData.dict(_app.data.products(), id), "type") != "non_consumable" or is_owned(id):
			continue
		_fulfil(id, {"receipt": "", "transaction_id": "restore"}, "restore", false)
		restored += 1
	return restored


## Sources that mean "this transaction's goods were handed out here".
const DELIVERED := ["purchase", "arrived", "foreign"]


## Whether this transaction has already been handed out on this device.
func is_delivered(transaction_id: String) -> bool:
	return not _delivery(transaction_id).is_empty()


## The history entry that handed out `transaction_id`, or {}.
func _delivery(transaction_id: String) -> Dictionary:
	if transaction_id.is_empty() or transaction_id == "restore":
		return {}
	for entry: Variant in _app.save.section("purchases").get("history", []):
		var e := entry as Dictionary
		if str(e.get("transaction_id", "")) == transaction_id and DELIVERED.has(str(e.get("source", ""))):
			return e
	return {}


## Whether this device has paid out the currency of `product_id` and it has not
## been refunded (a non-consumable's Crystals and Credits are paid once).
func _currency_paid_here(product_id: String) -> bool:
	for entry: Variant in _app.save.section("purchases").get("history", []):
		var e := entry as Dictionary
		var paid := e.get("paid", {}) as Dictionary
		if str(e.get("product", "")) == product_id and not bool(e.get("refunded", false)) \
				and (int(paid.get("crystals", 0)) > 0 or int(paid.get("credits", 0)) > 0):
			return true
	return false


## Pays out a store transaction once, saves, then closes it with the store.
## If the save cannot be written the transaction stays open, so the store hands
## it over again next launch rather than it being lost.
func _deliver(product_id: String, result: Dictionary, source: String, pay_currency: bool = true) -> void:
	var transaction_id := str(result.get("transaction_id", ""))
	# >>> SERVER VALIDATION WOULD GO HERE: verify result.receipt before granting. <<<
	var saved := true
	if not is_delivered(transaction_id):
		saved = _fulfil(product_id, result, source, pay_currency)
	if saved:
		provider.finish(transaction_id)


func _on_products_changed() -> void:
	catalog_changed.emit()


## A purchase the store handed over on its own. Only one this install started
## ("mine": an interrupted purchase, an approved Ask to Buy) pays currency; one
## from another device of the same Apple account was paid there, so here it
## only brings what is account-wide - an entitlement and its skin - and is left
## for its own device to finish.
func _on_transaction_arrived(product_id: String, result: Dictionary) -> void:
	if not _app.data.products().has(product_id) or not bool(result.get("ok", false)):
		return
	var transaction_id := str(result.get("transaction_id", ""))
	var non_consumable := GameData.text(GameData.dict(_app.data.products(), product_id), "type") == "non_consumable"
	if not bool(result.get("mine", false)):
		if non_consumable and not is_owned(product_id):
			_fulfil(product_id, result, "foreign", false)
		return
	if is_delivered(transaction_id):
		provider.finish(transaction_id)
		return
	# A non-consumable pays its currency once per device, however it arrives
	# (it may already be owned through a launch restore that paid none).
	_deliver(product_id, result, "arrived", not (non_consumable and _currency_paid_here(product_id)))


## The store refunded or revoked a purchase. What is account-wide (the
## entitlement and its skin) goes; currency comes back only if this device
## paid it for this very transaction, once, and only as far as the balance
## still holds it.
func _on_revoked(product_id: String, transaction_id: String) -> void:
	var def := GameData.dict(_app.data.products(), product_id)
	if def.is_empty():
		return
	var grants := GameData.dict(def, "grants")
	var purchases := _app.save.section("purchases")
	var entitlement := GameData.text(grants, "entitlement")
	if GameData.text(def, "type") == "non_consumable":
		if not entitlement.is_empty() and has_entitlement(entitlement):
			var owned: Array = purchases.get("entitlements", [])
			owned.erase(entitlement)
			purchases["entitlements"] = owned
			entitlements_changed.emit()
		var skin := GameData.text(grants, "skin")
		if not skin.is_empty():
			_app.arsenal.revoke(ArsenalService.SKINS, skin, "iap_revoked:" + product_id)
	var entry := _delivery(transaction_id)
	if not entry.is_empty() and not bool(entry.get("refunded", false)):
		var paid := entry.get("paid", {}) as Dictionary
		for currency: String in [Economy.CRYSTALS, Economy.CREDITS]:
			var back := mini(int(paid.get(currency, 0)), _app.economy.balance(currency))
			if back > 0:
				_app.economy.spend(currency, back, "iap_revoked:" + product_id)
		entry["refunded"] = true
	_record(product_id, transaction_id, "revoked")
	_app.analytics.track(Analytics.PURCHASE_FAILED, {"product": product_id, "reason": "revoked"})


## At launch the store reports what the account owns: anything missing here
## (a new phone, a reinstall) comes back quietly, like Restore Purchases.
func _on_entitlements_reported(product_ids: Array, source: String) -> void:
	if source == "launch" and _restore_owned(product_ids) > 0:
		catalog_changed.emit()


func _record(product_id: String, transaction_id: String, source: String) -> void:
	var purchases := _app.save.section("purchases")
	var history: Array = purchases.get("history", [])
	history.append({"product": product_id, "at": _app.clock.now(), "transaction_id": transaction_id, "source": source})
	purchases["history"] = history
	_app.save.mark_dirty()
	_app.save.flush()


## Hands out a product's grants and records exactly what was paid, so a refund
## can take back that and no more. Returns whether the save was written.
func _fulfil(product_id: String, result: Dictionary, source: String, pay_currency: bool = true) -> bool:
	var def := GameData.dict(_app.data.products(), product_id)
	var grants := GameData.dict(def, "grants")
	var purchases := _app.save.section("purchases")
	var paid := {}

	var entitlement := GameData.text(grants, "entitlement")
	if not entitlement.is_empty() and not has_entitlement(entitlement):
		var owned: Array = purchases.get("entitlements", [])
		owned.append(entitlement)
		purchases["entitlements"] = owned
		entitlements_changed.emit()
	# Currency only for a purchase paid on this device: a restore, or a
	# purchase made on another device, brings the entitlement and skin only.
	if pay_currency and source in ["purchase", "arrived"]:
		for currency: String in [Economy.CREDITS, Economy.CRYSTALS]:
			var amount := GameData.integer(grants, currency)
			if amount > 0:
				_app.economy.grant(currency, amount, "iap:" + product_id)
				paid[currency] = amount
	var skin := GameData.text(grants, "skin")
	if not skin.is_empty() and not _app.arsenal.is_owned(ArsenalService.SKINS, skin):
		_app.arsenal.grant(ArsenalService.SKINS, skin, "iap:" + product_id)
		paid["skin"] = skin

	var history: Array = purchases.get("history", [])
	history.append({
		"product": product_id,
		"at": _app.clock.now(),
		"transaction_id": str(result.get("transaction_id", "")),
		"source": source,
		"paid": paid,
	})
	purchases["history"] = history
	_app.save.mark_dirty()
	var saved := _app.save.flush()
	_app.analytics.track(Analytics.PURCHASE_COMPLETED, {"product": product_id, "source": source, "price": price(product_id)})
	purchase_completed.emit(product_id)
	return saved
