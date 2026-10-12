class_name MockStoreProvider
extends StoreProvider
## Development store. Asks for confirmation in a clearly labelled dialog and
## never touches real money. Automated runs approve instantly unless told not to.

var auto_approve := true
var purchases := 0

var _app: AppRoot
var _catalog: Dictionary
var _owned: Array = []


func initialize(app: AppRoot, catalog: Dictionary) -> void:
	_app = app
	_catalog = catalog


func price(product_id: String) -> String:
	return GameData.text(GameData.dict(_catalog, product_id), "price", "-")


func purchase(product_id: String) -> Dictionary:
	if not _catalog.has(product_id):
		return {"ok": false, "error": "unknown_product"}
	var approved := auto_approve
	if not _app.automated:
		var dialog := MockPurchaseDialog.new()
		dialog.configure(GameData.text(GameData.dict(_catalog, product_id), "name", product_id), price(product_id))
		_app.add_child(dialog)
		approved = await dialog.finished
	if not approved:
		return {"ok": false, "error": "cancelled"}
	purchases += 1
	if GameData.text(GameData.dict(_catalog, product_id), "type") == "non_consumable" and not _owned.has(product_id):
		_owned.append(product_id)
	return {
		"ok": true,
		"receipt": "mock-receipt-%s-%d" % [product_id, purchases],
		"transaction_id": "mock-%d-%d" % [Time.get_ticks_msec(), purchases],
	}


func restore() -> Array:
	return _owned.duplicate()


func describe() -> String:
	return "mock"
