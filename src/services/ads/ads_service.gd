class_name AdsService
extends RefCounted
## Advertising policy, independent of any ad network.
##
## Rules enforced here (not in UI code, so they cannot be bypassed by accident):
##   - Rewarded ads are always opt-in and always pay out what was promised.
##   - Interstitials only ever appear between runs, never during play, are
##     frequency capped (monetization.json), never follow a rewarded ad in the
##     same results flow, and stop entirely once Remove Ads is owned.

signal ad_opened
signal ad_closed

const REVIVE := "revive"
const DOUBLE_REWARDS := "double_rewards"
const REROLL := "reroll"
const DAILY_DOUBLE := "daily_double"
const SHOP_CREDITS := "shop_credits"

var provider: AdProvider

var _app: AppRoot
var _cfg: Dictionary
var _rewarded_this_flow := false
var _showing := false
var _last_ad: Dictionary = {}


func _init(app: AppRoot, p_provider: AdProvider) -> void:
	_app = app
	_cfg = GameData.dict(app.data.monetization, "ads")
	provider = p_provider
	provider.initialize(app)


func ads_removed() -> bool:
	return _app.store.has_entitlement("remove_ads")


func is_showing() -> bool:
	return _showing


## Call at quiet moments between runs: before a run starts and on returning to
## the menu. The provider may show its consent form here.
func between_runs() -> void:
	if _showing:
		return
	_showing = true
	await provider.between_runs()
	_showing = false


## The page for reporting an inappropriate ad (App Review Guideline 2.5.18),
## describing the last ad shown this session so support can find it. Carries
## no personal data: format, placement, time, network and app version.
func report_ad_url() -> String:
	var url := _app.data.link("report_ad")
	if url.is_empty():
		return ""
	var query := {
		"format": str(_last_ad.get("format", "")),
		"placement": str(_last_ad.get("placement", "")),
		"at": str(_last_ad.get("at", "")),
		"network": provider.describe(),
		"version": GameData.text(_app.data.game, "version"),
	}
	var parts := PackedStringArray()
	for key: String in query:
		parts.append("%s=%s" % [key, str(query[key]).uri_encode()])
	return url + ("&" if url.contains("?") else "?") + "&".join(parts)


func last_ad() -> Dictionary:
	return _last_ad.duplicate()


func privacy_options_required() -> bool:
	return provider.privacy_options_required()


func show_privacy_options() -> void:
	await provider.show_privacy_options()


# ----------------------------------------------------------------- rewarded

func rewarded_available(placement: String) -> bool:
	var cfg := GameData.dict(GameData.dict(_cfg, "rewarded"), placement)
	if not GameData.flag(cfg, "enabled", false) or not provider.is_rewarded_ready():
		return false
	if placement == SHOP_CREDITS:
		return shop_credit_ads_left() > 0
	return true


## Shows a rewarded ad. Returns true only when the reward was earned.
func show_rewarded(placement: String) -> bool:
	if _showing or not rewarded_available(placement):
		return false
	_app.analytics.track(Analytics.AD_REQUESTED, {"format": "rewarded", "placement": placement})
	_last_ad = {"format": "rewarded", "placement": placement, "at": _app.clock.now()}
	_begin()
	var earned: bool = await provider.show_rewarded(placement)
	_end()
	_app.analytics.track(Analytics.AD_VIEWED, {"format": "rewarded", "placement": placement, "completed": earned})
	if earned:
		_rewarded_this_flow = true
		_app.stats.add("ads_watched", 1.0)
		_app.analytics.track(Analytics.REWARDED_AD_COMPLETED, {"placement": placement})
	return earned


func shop_credit_reward() -> int:
	return GameData.integer(GameData.dict(GameData.dict(_cfg, "rewarded"), SHOP_CREDITS), "credits", 150)


func shop_credit_ads_left() -> int:
	var cap := GameData.integer(GameData.dict(GameData.dict(_cfg, "rewarded"), SHOP_CREDITS), "daily_cap", 3)
	var state := _app.save.section("ads")
	if int(state.get("shop_credits_day", -1)) != _app.clock.day_index():
		return cap
	return maxi(cap - int(state.get("shop_credits_count", 0)), 0)


## Free Credits for watching an ad, capped per day. Returns Credits granted.
func claim_shop_credits() -> int:
	var earned: bool = await show_rewarded(SHOP_CREDITS)
	if not earned:
		return 0
	var state := _app.save.section("ads")
	var today := _app.clock.day_index()
	if int(state.get("shop_credits_day", -1)) != today:
		state["shop_credits_day"] = today
		state["shop_credits_count"] = 0
	state["shop_credits_count"] = int(state.get("shop_credits_count", 0)) + 1
	_app.save.mark_dirty()
	var amount := shop_credit_reward()
	_app.economy.grant(Economy.CREDITS, amount, "ad_shop")
	return amount


# ------------------------------------------------------------- interstitial

## Call when a run's results are first shown; starts a fresh "flow".
func note_run_finished() -> void:
	_rewarded_this_flow = false
	var state := _app.save.section("ads")
	state["runs_since_interstitial"] = int(state.get("runs_since_interstitial", 0)) + 1
	_app.save.mark_dirty()


func should_show_interstitial() -> bool:
	var cfg := GameData.dict(_cfg, "interstitial")
	if not GameData.flag(cfg, "enabled", false) or ads_removed() or not provider.is_interstitial_ready():
		return false
	if _rewarded_this_flow and GameData.flag(cfg, "skip_if_rewarded_this_flow", true):
		return false
	if int(_app.stats.value("runs")) < GameData.integer(cfg, "min_runs_before_first", 3):
		return false
	var state := _app.save.section("ads")
	if int(state.get("runs_since_interstitial", 0)) < GameData.integer(cfg, "runs_between", 2):
		return false
	return _app.clock.now() - int(state.get("last_interstitial_at", 0)) >= GameData.integer(cfg, "min_interval_sec", 180)


## Shows an interstitial if policy allows. Only call this between runs.
func maybe_show_interstitial(placement: String) -> bool:
	if _showing or not should_show_interstitial():
		return false
	_app.analytics.track(Analytics.AD_REQUESTED, {"format": "interstitial", "placement": placement})
	_last_ad = {"format": "interstitial", "placement": placement, "at": _app.clock.now()}
	_begin()
	var shown: bool = await provider.show_interstitial(placement)
	_end()
	if shown:
		var state := _app.save.section("ads")
		state["last_interstitial_at"] = _app.clock.now()
		state["runs_since_interstitial"] = 0
		_app.save.mark_dirty()
		_app.analytics.track(Analytics.AD_VIEWED, {"format": "interstitial", "placement": placement, "completed": true})
	return shown


func _begin() -> void:
	_showing = true
	# The ad owns the speaker while it is up.
	_app.audio.set_silenced(true)
	ad_opened.emit()


func _end() -> void:
	_showing = false
	_app.audio.set_silenced(false)
	ad_closed.emit()
