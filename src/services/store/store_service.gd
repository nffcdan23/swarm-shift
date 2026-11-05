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
		if _app.data.products().has(str(product_id)) and not is_owned(str(product_id)):
			_fulfil(str(product_id), {"receipt": "", "transaction_id": "restore"}, "restore")
			restored += 1
	return restored


## Whether this transaction has already been paid out.
func is_delivered(transaction_id: String) -> bool:
	if transaction_id.is_empty() or transaction_id == "restore":
		return false
	for entry: Variant in _app.save.section("purchases").get("history", []):
		if str((entry as Dictionary).get("transaction_id", "")) == transaction_id and str((entry as Dictionary).get("source", "")) != "revoked":
			return true
	return false


## Pays out a store transaction once, saves, then closes it with the store.
func _deliver(product_id: String, result: Dictionary, source: String) -> void:
	var transaction_id := str(result.get("transaction_id", ""))
	# >>> SERVER VALIDATION WOULD GO HERE: verify result.receipt before granting. <<<
	if not is_delivered(transaction_id):
		_fulfil(product_id, result, source)
	provider.finish(transaction_id)


func _on_products_changed() -> void:
	catalog_changed.emit()


func _on_transaction_arrived(product_id: String, result: Dictionary) -> void:
	if not _app.data.products().has(product_id) or not bool(result.get("ok", false)):
		return
	var transaction_id := str(result.get("transaction_id", ""))
	if is_delivered(transaction_id):
		provider.finish(transaction_id)
		return
	# A non-consumable already owned (restored earlier) only needs closing.
	if is_owned(product_id):
		_record(product_id, transaction_id, "arrived")
		provider.finish(transaction_id)
		return
	_deliver(product_id, result, "arrived")


## The store refunded or revoked a purchase: take back what it gave, as far as
## it is still there.
func _on_revoked(product_id: String, transaction_id: String) -> void:
	var def := GameData.dict(_app.data.products(), product_id)
	if def.is_empty():
		return
	var grants := GameData.dict(def, "grants")
	var entitlement := GameData.text(grants, "entitlement")
	var purchases := _app.save.section("purchases")
	if not entitlement.is_empty() and has_entitlement(entitlement):
		var owned: Array = purchases.get("entitlements", [])
		owned.erase(entitlement)
		purchases["entitlements"] = owned
		entitlements_changed.emit()
	if GameData.text(def, "type") == "consumable":
		var crystals := mini(GameData.integer(grants, "crystals"), _app.economy.balance(Economy.CRYSTALS))
		if crystals > 0:
			_app.economy.spend(Economy.CRYSTALS, crystals, "iap_revoked:" + product_id)
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


func _fulfil(product_id: String, result: Dictionary, source: String) -> void:
	var def := GameData.dict(_app.data.products(), product_id)
	var grants := GameData.dict(def, "grants")
	var purchases := _app.save.section("purchases")

	var entitlement := GameData.text(grants, "entitlement")
	if not entitlement.is_empty() and not has_entitlement(entitlement):
		var owned: Array = purchases.get("entitlements", [])
		owned.append(entitlement)
		purchases["entitlements"] = owned
		entitlements_changed.emit()
	# Currency from a restored non-consumable is not paid out a second time.
	if source in ["purchase", "arrived"]:
		_app.economy.grant(Economy.CREDITS, GameData.integer(grants, "credits"), "iap:" + product_id)
		_app.economy.grant(Economy.CRYSTALS, GameData.integer(grants, "crystals"), "iap:" + product_id)
	var skin := GameData.text(grants, "skin")
	if not skin.is_empty():
		_app.arsenal.grant(ArsenalService.SKINS, skin, "iap:" + product_id)

	var history: Array = purchases.get("history", [])
	history.append({
		"product": product_id,
		"at": _app.clock.now(),
		"transaction_id": str(result.get("transaction_id", "")),
		"source": source,
	})
	purchases["history"] = history
	_app.save.mark_dirty()
	_app.save.flush()
	_app.analytics.track(Analytics.PURCHASE_COMPLETED, {"product": product_id, "source": source, "price": price(product_id)})
	purchase_completed.emit(product_id)
