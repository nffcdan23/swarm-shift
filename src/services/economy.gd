class_name Economy
extends RefCounted
## The only place currency balances change. Every grant and spend names its
## source or sink, which is what makes the economy auditable in analytics.

signal changed(currency: String, balance: int, delta: int)

const CREDITS := "credits"
const CRYSTALS := "crystals"

var _app: AppRoot


func _init(app: AppRoot) -> void:
	_app = app


func balance(currency: String) -> int:
	return int(_app.save.section("currencies").get(currency, 0))


func can_afford(currency: String, amount: int) -> bool:
	return balance(currency) >= amount


func grant(currency: String, amount: int, source: String) -> void:
	if amount <= 0:
		return
	var wallet := _app.save.section("currencies")
	wallet[currency] = balance(currency) + amount
	_app.save.mark_dirty()
	if currency == CREDITS:
		_app.stats.add("credits_earned", amount)
	_app.analytics.track(Analytics.CURRENCY_EARNED, {"currency": currency, "amount": amount, "source": source, "balance": wallet[currency]})
	changed.emit(currency, int(wallet[currency]), amount)


func spend(currency: String, amount: int, sink: String) -> bool:
	if amount < 0 or not can_afford(currency, amount):
		return false
	var wallet := _app.save.section("currencies")
	wallet[currency] = balance(currency) - amount
	_app.save.mark_dirty()
	_app.analytics.track(Analytics.CURRENCY_SPENT, {"currency": currency, "amount": amount, "sink": sink, "balance": wallet[currency]})
	changed.emit(currency, int(wallet[currency]), -amount)
	return true


## Grants a reward bundle such as {"credits": 150, "crystals": 5, "account_xp": 40}.
func grant_bundle(bundle: Dictionary, source: String) -> void:
	grant(CREDITS, int(bundle.get("credits", 0)), source)
	grant(CRYSTALS, int(bundle.get("crystals", 0)), source)
	var xp := int(bundle.get("account_xp", 0))
	if xp > 0:
		_app.account.add_xp(xp, source)
