class_name StoreKitCheck
extends Node
## On-device check of the StoreKit bridge (native/storekit) against the real
## App Store Connect products, in Apple's sandbox. Launch the installed app with
## `--storekit-check` (tools/ios_deploy.sh --storekit-check does it all):
##
##   bridge loaded -> every product id found in App Store Connect, with its
##   localised price and type -> what the account owns
##   -> with --storekit-buy=<product>, one sandbox purchase, verified and finished
##
## A development or TestFlight build always buys in the sandbox: nobody is
## charged. The purchase step needs a sandbox account signed in on the phone
## (Settings > Developer > Sandbox Account) and someone to confirm the sheet.
##
## Lines are printed with a `[storekit-check]` prefix and written to
## user://storekit_check.txt. It never touches the player's profile: while it
## runs, the game's own shop uses the test store.

const REPORT_PATH := "user://storekit_check.txt"
const STEP_TIMEOUT := 120.0

var _lines: PackedStringArray = []
var _passes := 0
var _failures: PackedStringArray = []
var _bridge: Object
var _events: Array[Array] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	App.analytics.enabled = false
	if FileAccess.file_exists(REPORT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPORT_PATH))
	_say("generated: " + Time.get_datetime_string_from_system(false, true))
	# tools/ios_deploy.sh passes a fresh id per run and accepts only a report
	# carrying it, so a report left from an earlier run is never mistaken for this one.
	_say("run: " + App.cli_text("run-id", "-"))
	await get_tree().create_timer(1.0).timeout
	await _run()
	_finish()


func _run() -> void:
	if not Engine.has_singleton("StoreKit"):
		_fail("the StoreKit bridge is not in this build (run tools/build_storekit.sh before exporting)")
		return
	_bridge = Engine.get_singleton("StoreKit")
	if not _bridge.is_supported():
		_fail("the StoreKit bridge is the desktop stub - run this on an iPhone")
		return
	_bridge.connect("event", func(name: String, payload: Dictionary) -> void: _events.append([name, payload]))
	_bridge.start()
	_pass("bridge loaded")

	# --- products: every catalogue entry must exist in App Store Connect.
	var prefix := GameData.text(GameData.dict(App.data.monetization, "store"), "ios_prefix")
	var expected := {}
	for product_id: String in App.data.products():
		var def := GameData.dict(App.data.products(), product_id)
		expected[StoreKitStoreProvider.store_id_for(def, product_id, prefix)] = GameData.text(def, "type")
	_bridge.load_products(PackedStringArray(expected.keys()))
	var answer := await _wait(["products", "products_failed"])
	if answer.is_empty():
		_fail("the App Store did not answer the product request within %d s" % int(STEP_TIMEOUT))
		return
	if answer[0] == "products_failed":
		_fail("products failed to load: %s" % answer[1].get("error", "?"))
		return
	_say("asked the App Store for: %s" % ", ".join(PackedStringArray(answer[1].get("requested", []))))
	_say("App Store country: %s, products returned: %d" % [answer[1].get("storefront", "?"), (answer[1].get("products", []) as Array).size()])
	var found := {}
	for entry: Variant in answer[1].get("products", []):
		found[str(entry.id)] = entry
	for store_id: String in expected:
		if not found.has(store_id):
			_fail("%s is not in App Store Connect (or not available in this storefront)" % store_id)
			continue
		var entry: Dictionary = found[store_id]
		var type_ok := str(entry.get("type", "")) == str(expected[store_id])
		_expect(type_ok, "%s: %s, %s, type %s%s" % [store_id, entry.get("price", "?"), entry.get("title", "?"), entry.get("type", "?"),
			"" if type_ok else " (expected %s)" % expected[store_id]])

	# --- entitlements: what this Apple account owns, from StoreKit's cache.
	_bridge.request_entitlements()
	var owned := await _wait(["entitlements"])
	if owned.is_empty():
		_fail("no entitlement report within %d s" % int(STEP_TIMEOUT))
	else:
		var ids: Array = owned[1].get("products", [])
		_pass("entitlements reported: %s" % ("none" if ids.is_empty() else ", ".join(PackedStringArray(ids))))

	# --- optional sandbox purchase.
	var buy := App.cli_text("storekit-buy")
	if buy.is_empty():
		_say("no purchase made (add --storekit-buy=crystals_s to buy one in the sandbox)")
		return
	var def := GameData.dict(App.data.products(), buy)
	if def.is_empty():
		_fail("--storekit-buy: unknown product '%s'" % buy)
		return
	var store_id := StoreKitStoreProvider.store_id_for(def, buy, prefix)
	_say("buying %s - confirm the App Store sheet on the phone (sandbox: no charge)" % store_id)
	_bridge.purchase(store_id)
	var result := await _wait(["purchase"])
	if result.is_empty():
		_fail("no purchase answer within %d s" % int(STEP_TIMEOUT))
		return
	var payload: Dictionary = result[1]
	var status := str(payload.get("status", ""))
	if status != "purchased":
		_fail("purchase %s%s" % [status, (": " + str(payload.get("error"))) if str(payload.get("error", "")) != "" else ""])
		return
	_expect(not str(payload.get("jws", "")).is_empty(), "purchase verified by StoreKit, transaction %s" % payload.get("transaction_id", "?"))
	_expect(float(payload.get("mine", 0.0)) > 0.0, "the transaction carries this device's account token")
	_bridge.finish_transaction(str(payload.get("transaction_id", "")))
	_pass("transaction finished (the check grants nothing to the player's profile)")


## Waits for the next bridge event named in `names`; [] on timeout.
func _wait(names: Array) -> Array:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for i in _events.size():
			if names.has(_events[i][0]):
				return _events.pop_at(i)
		await get_tree().process_frame
	return []


# ------------------------------------------------------------------ reporting

func _say(text: String) -> void:
	_lines.append(text)
	print("[storekit-check] ", text)
	# Written after every line, so an interrupted check still leaves a record.
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()


func _pass(what: String) -> void:
	_passes += 1
	_say("PASS  " + what)


func _fail(what: String) -> void:
	_failures.append(what)
	_say("FAIL  " + what)


func _expect(condition: bool, what: String) -> bool:
	if condition:
		_pass(what)
	else:
		_fail(what)
	return condition


func _finish() -> void:
	_say("RESULT %s: %d passed, %d failed" % ["PASS" if _failures.is_empty() else "FAIL", _passes, _failures.size()])
