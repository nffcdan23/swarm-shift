extends TestSuite
## Real purchases through StoreKit 2: StoreKitStoreProvider and StoreService
## driven by a fake bridge that answers the way the native one does (see
## native/storekit/src/StoreKitBridge.swift for the events). Covers prices,
## purchases, every failure, purchases that arrive on their own (a crash
## mid-purchase, Ask to Buy, another device), refunds and restores. The
## native side itself can only be exercised on a device against the App Store
## sandbox (docs/storekit/README.md).


## Stands in for the "StoreKit" engine singleton. Answers on the next idle
## frame, like the real bridge.
class FakeBridge:
	extends RefCounted
	signal event(name: String, payload: Dictionary)

	var started := 0
	var requested: PackedStringArray = []
	var purchases: Array[String] = []
	var finished: Array[String] = []
	var syncs := 0
	## App Store id -> price; anything not here is reported invalid.
	var catalog := {}
	## How the next purchase answers: "purchased", "cancelled", "pending", "failed", "unverified".
	var next_status := "purchased"
	var next_error := ""
	## What sync() reports: App Store ids, or a failure.
	var owned: Array = []
	var sync_error := ""
	var products_fail := false
	var _serial := 1000

	func is_supported() -> bool:
		return true

	func start() -> void:
		started += 1

	func load_products(ids: PackedStringArray) -> void:
		requested = ids
		if products_fail:
			_later("products_failed", {"error": "network"})
			return
		var found := []
		var invalid := []
		for id in ids:
			if catalog.has(id):
				found.append({"id": id, "price": catalog[id], "title": id, "description": "", "type": "consumable"})
			else:
				invalid.append(id)
		_later("products", {"products": found, "invalid": invalid})

	func purchase(store_id: String) -> void:
		purchases.append(store_id)
		if next_status == "purchased":
			_serial += 1
			_later("purchase", transaction(store_id, str(_serial)))
		else:
			_later("purchase", {"product": store_id, "status": next_status, "error": next_error})

	func finish_transaction(transaction_id: String) -> void:
		finished.append(transaction_id)

	func request_entitlements() -> void:
		_later("entitlements", {"products": owned, "source": "launch"})

	func sync() -> void:
		syncs += 1
		if sync_error.is_empty():
			_later("entitlements", {"products": owned, "source": "restore"})
		else:
			_later("sync_failed", {"error": sync_error})

	func transaction(store_id: String, transaction_id: String) -> Dictionary:
		return {"product": store_id, "status": "purchased", "transaction_id": transaction_id, "original_id": transaction_id, "jws": "signed." + transaction_id}

	## Pushes an event as if StoreKit sent it unprompted.
	func send(name: String, payload: Dictionary) -> void:
		emit_signal("event", name, payload)

	func _later(name: String, payload: Dictionary) -> void:
		call_deferred("emit_signal", "event", name, payload)


const PREFIX := "com.starscale.swarmshift."

func _frames(count: int) -> void:
	for i in count:
		await host.get_tree().process_frame


func _bridge() -> FakeBridge:
	var bridge := FakeBridge.new()
	for product_id: String in app.data.products():
		bridge.catalog[PREFIX + product_id] = "£%d.99" % (product_id.length() % 9)
	return bridge


func _store(bridge: FakeBridge) -> StoreService:
	return StoreService.new(app, StoreKitStoreProvider.new(bridge))


func _crystals() -> int:
	return app.economy.balance(Economy.CRYSTALS)


# ------------------------------------------------------------------ catalogue

func test_product_ids_and_prices_come_from_the_app_store() -> void:
	fresh_profile()
	var bridge := _bridge()
	var store := _store(bridge)
	check_eq(bridge.started, 1, "the bridge starts listening at launch")
	check(bridge.requested.has(PREFIX + "crystals_s"), "App Store ids are the prefix plus the game id")
	check_eq(bridge.requested.size(), app.data.products().size(), "every product is asked for")
	check_eq(StoreKitStoreProvider.store_id_for({"ios_id": "custom.id"}, "x", PREFIX), "custom.id", "a product can set its own App Store id")
	check_eq(store.price("crystals_s"), "-", "before the App Store answers, no price is shown - not a guessed one in dollars")
	check(not store.is_available("crystals_s"), "and it cannot be bought")
	var changed := [0]
	store.catalog_changed.connect(func() -> void: changed[0] += 1)
	await _frames(2)
	check_eq(store.price("crystals_s"), bridge.catalog[PREFIX + "crystals_s"], "then StoreKit's localised price is shown")
	check(store.is_available("crystals_s"), "and it can be bought")
	check(changed[0] >= 1, "the shop is told to redraw")


func test_a_product_missing_from_app_store_connect_is_unavailable() -> void:
	fresh_profile()
	var bridge := _bridge()
	bridge.catalog.erase(PREFIX + "crystals_l")
	var store := _store(bridge)
	await _frames(2)
	check(not store.is_available("crystals_l"), "a product App Store Connect does not have is unavailable")
	check(store.is_available("crystals_m"), "the others are fine")
	check(not await store.purchase("crystals_l"), "buying it fails")
	check_eq(store.last_error, "unavailable", "as unavailable")
	check(bridge.purchases.is_empty(), "without asking the App Store")

	fresh_profile()
	bridge = _bridge()
	bridge.products_fail = true
	store = _store(bridge)
	await _frames(2)
	check(not store.is_available("crystals_s"), "with no connection, nothing can be bought")
	check_eq(store.price("crystals_s"), "-", "and no price is shown")


# ------------------------------------------------------------------ purchases

func test_a_purchase_is_delivered_once_then_finished() -> void:
	fresh_profile()
	var bridge := _bridge()
	var store := _store(bridge)
	await _frames(2)
	var before := _crystals()
	check(await store.purchase("crystals_s"), "buying a Crystal pack succeeds")
	check_eq(bridge.purchases, [PREFIX + "crystals_s"] as Array[String], "through the App Store id")
	var grant := GameData.integer(GameData.dict(GameData.dict(app.data.products(), "crystals_s"), "grants"), "crystals")
	check_eq(_crystals(), before + grant, "the Crystals are paid")
	check_eq(bridge.finished.size(), 1, "and only then is the transaction finished")
	var history: Array = app.save.section("purchases").get("history", [])
	var transaction_id := str((history.back() as Dictionary).transaction_id)
	check_eq(bridge.finished[0], transaction_id, "the same transaction")
	check(store.is_delivered(transaction_id), "it is recorded as delivered")

	# StoreKit hands the same transaction over again (the app closed before
	# finish() reached it): it is closed, not paid twice.
	bridge.send("transaction", bridge.transaction(PREFIX + "crystals_s", transaction_id))
	check_eq(_crystals(), before + grant, "a transaction delivered again is not paid twice")
	check_eq(bridge.finished.size(), 2, "but is finished again")


func test_a_purchase_paid_but_never_saved_arrives_next_launch() -> void:
	fresh_profile()
	var bridge := _bridge()
	var store := _store(bridge)
	await _frames(2)
	var before := _crystals()
	# Paid for in an earlier session that closed before saving: StoreKit
	# delivers it as an unfinished transaction when the app starts listening.
	bridge.send("transaction", bridge.transaction(PREFIX + "crystals_m", "777"))
	var grant := GameData.integer(GameData.dict(GameData.dict(app.data.products(), "crystals_m"), "grants"), "crystals")
	check_eq(_crystals(), before + grant, "the purchase is delivered")
	check(bridge.finished.has("777"), "and finished")
	check(store.is_delivered("777"), "and recorded")


func test_failures_grant_nothing_and_say_why() -> void:
	fresh_profile()
	var bridge := _bridge()
	var store := _store(bridge)
	await _frames(2)
	var before := _crystals()
	for case: Array in [["cancelled", "", "cancelled"], ["pending", "", "pending"], ["failed", "network", "network"],
			["failed", "not_allowed", "not_allowed"], ["unverified", "bad signature", "unverified"]]:
		bridge.next_status = str(case[0])
		bridge.next_error = str(case[1])
		check(not await store.purchase("crystals_s"), "%s: the purchase fails" % case[0])
		check_eq(store.last_error, str(case[2]), "%s: reported as %s" % [case[0], case[2]])
	check_eq(_crystals(), before, "nothing was paid")
	check(bridge.finished.is_empty(), "and nothing finished")
	check(store.is_available("remove_ads"), "the store is still usable")
	check_eq(ShopScreen.failure_message("cancelled"), "", "a cancel says nothing")
	check(ShopScreen.failure_message("pending").contains("approval"), "a pending purchase says it waits for approval")
	check(ShopScreen.failure_message("network").contains("connection"), "a network failure says so")
	check(ShopScreen.failure_message("unverified").contains("not charged"), "any other failure says no charge was made")


func test_ask_to_buy_arrives_when_approved() -> void:
	fresh_profile()
	var bridge := _bridge()
	var store := _store(bridge)
	await _frames(2)
	bridge.next_status = "pending"
	check(not await store.purchase("remove_ads"), "a purchase waiting for a parent's approval does not complete yet")
	check(not store.has_entitlement("remove_ads"), "nothing granted yet")
	bridge.send("transaction", bridge.transaction(PREFIX + "remove_ads", "4242"))
	check(store.has_entitlement("remove_ads"), "approved later, it arrives and is granted")
	check(bridge.finished.has("4242"), "and finished")


# ------------------------------------------------------------- refunds, restore

func test_a_refund_takes_back_what_it_gave() -> void:
	fresh_profile()
	var bridge := _bridge()
	var store := _store(bridge)
	await _frames(2)
	check(await store.purchase("remove_ads"), "Remove Ads bought")
	check(store.has_entitlement("remove_ads"), "and active")
	bridge.send("revoked", {"product": PREFIX + "remove_ads", "transaction_id": "1001"})
	check(not store.has_entitlement("remove_ads"), "refunded, it is removed")
	check(store.is_available("remove_ads") and not store.is_owned("remove_ads"), "and can be bought again")

	var before := _crystals()
	check(await store.purchase("crystals_s"), "a Crystal pack bought")
	var grant := _crystals() - before
	bridge.send("revoked", {"product": PREFIX + "crystals_s", "transaction_id": "1002"})
	check_eq(_crystals(), before, "refunded, its Crystals are taken back (%d)" % grant)
	app.economy.spend(Economy.CRYSTALS, _crystals(), "test")
	check(await store.purchase("crystals_s"), "bought again")
	app.economy.spend(Economy.CRYSTALS, _crystals() - 10, "test")
	bridge.send("revoked", {"product": PREFIX + "crystals_s", "transaction_id": "1003"})
	check_eq(_crystals(), 0, "Crystals already spent are taken back only as far as the balance goes")


func test_restore_and_a_new_phone() -> void:
	fresh_profile()
	var bridge := _bridge()
	bridge.owned = [PREFIX + "remove_ads", PREFIX + "starter_pack"]
	var store := _store(bridge)
	await _frames(2)
	var before := _crystals()
	var restored: int = await store.restore()
	check_eq(restored, 2, "Restore Purchases brings back both non-consumables")
	check_eq(bridge.syncs, 1, "after syncing with the App Store")
	check(store.has_entitlement("remove_ads") and store.has_entitlement("starter_pack"), "both are active")
	check_eq(_crystals(), before, "without paying the Starter Pack's Crystals a second time")
	check_eq(await store.restore(), 0, "restoring again finds nothing new")

	bridge.sync_error = "network"
	fresh_profile()
	bridge = _bridge()
	bridge.sync_error = "network"
	store = _store(bridge)
	await _frames(2)
	check_eq(await store.restore(), 0, "a restore that cannot reach the App Store restores nothing")
	check_eq(store.last_error, "network", "and says why")
	check(ShopScreen.failure_message("network", true).contains("connection"), "the shop tells the player")

	# A reinstall or a new phone: what the account owns comes back at launch.
	fresh_profile()
	bridge = _bridge()
	bridge.owned = [PREFIX + "remove_ads"]
	store = _store(bridge)
	await _frames(2)
	check(not store.has_entitlement("remove_ads"), "a fresh install does not own Remove Ads yet")
	bridge.request_entitlements()
	await _frames(2)
	check(store.has_entitlement("remove_ads"), "the launch report restores it without asking")
	check_eq(bridge.syncs, 0, "and without the sign-in a full restore can need")


# ----------------------------------------------------------------- the game

func test_the_game_uses_the_test_store_off_device() -> void:
	fresh_profile()
	check(app.store.provider is MockStoreProvider, "automated runs and the desktop use the test store")
	if Engine.has_singleton("StoreKit"):
		check(not Engine.get_singleton("StoreKit").is_supported(), "the desktop bridge is the stub")
	var store := StoreService.new(app, MockStoreProvider.new())
	check(store.provider.shows_fallback_prices(), "the test store shows the catalogue's prices")
	check(store.is_available("crystals_s"), "and can always sell")


func test_no_store_sells_nothing() -> void:
	fresh_profile()
	# What a release build on a phone gets if the StoreKit bridge is missing.
	var store := StoreService.new(app, StoreProvider.new())
	for product_id: String in app.data.products():
		check(not store.is_available(product_id), "%s cannot be bought" % product_id)
		check_eq(store.price(product_id), "-", "and shows no price")
	var before := app.economy.balance(Economy.CRYSTALS)
	check(not await store.purchase("crystals_l"), "a purchase fails")
	check_eq(app.economy.balance(Economy.CRYSTALS), before, "and grants nothing")
	check(not app.is_release_device(), "tests are never a release device")
