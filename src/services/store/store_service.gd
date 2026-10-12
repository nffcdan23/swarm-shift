class_name StoreService
extends RefCounted
## Real-money purchases, independent of the platform store.
##
## Flow: purchase() -> provider.purchase() -> _fulfil() grants the product's
## `grants` block (currencies, skin, entitlement) and records the transaction.
##
## PRODUCTION NOTE: `_fulfil()` currently trusts the provider's answer, which is
## fine for the mock but not for money. Before enabling a real provider, send
## the receipt to a server, validate it with Apple/Google, and only grant on the
## server's say-so. The marked line below is where that call goes.

signal purchase_completed(product_id: String)
signal purchase_failed(product_id: String, reason: String)
signal entitlements_changed

var provider: StoreProvider

var _app: AppRoot
var _busy := false


func _init(app: AppRoot, p_provider: StoreProvider) -> void:
	_app = app
	provider = p_provider
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
	return live if not live.is_empty() else GameData.text(GameData.dict(_app.data.products(), product_id), "price", "-")


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
		_app.analytics.track(Analytics.PURCHASE_FAILED, {"product": product_id, "reason": reason})
		purchase_failed.emit(product_id, reason)
		return false
	_fulfil(product_id, result, "purchase")
	return true


## Re-grants non-consumables the store reports as owned (required by Apple).
func restore() -> int:
	if _busy:
		return 0
	_busy = true
	var owned: Array = await provider.restore()
	_busy = false
	var restored := 0
	for product_id: String in owned:
		if _app.data.products().has(product_id) and not is_owned(product_id):
			_fulfil(product_id, {"receipt": "", "transaction_id": "restore"}, "restore")
			restored += 1
	return restored


func _fulfil(product_id: String, result: Dictionary, source: String) -> void:
	# >>> SERVER VALIDATION GOES HERE: verify result.receipt before granting. <<<
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
	if source == "purchase":
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
