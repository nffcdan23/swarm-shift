class_name Analytics
extends RefCounted
## Provider-agnostic analytics front door. Game code only ever calls `track()`
## with one of the event constants below; which SDK (if any) receives it is
## decided at startup in AppRoot.
##
## Every event is stamped with session, install age and account level so
## retention cohorts (D1/D7/D30) can be cut without extra plumbing.

const GAME_STARTED := "game_started"
const GAME_ENDED := "game_ended"
const PLAYER_DEATH := "player_death"
const PLAYER_REVIVED := "player_revived"
const PLAYER_LEVEL_UP := "player_level_up"
const UPGRADE_SELECTED := "upgrade_selected"
const UPGRADE_REROLLED := "upgrade_rerolled"
const SYNERGY_FOUND := "synergy_found"
const BOSS_STARTED := "boss_started"
const BOSS_DEFEATED := "boss_defeated"
const AD_REQUESTED := "ad_requested"
const AD_VIEWED := "ad_viewed"
const REWARDED_AD_COMPLETED := "rewarded_ad_completed"
const PURCHASE_STARTED := "purchase_started"
const PURCHASE_COMPLETED := "purchase_completed"
const PURCHASE_FAILED := "purchase_failed"
const CURRENCY_EARNED := "currency_earned"
const CURRENCY_SPENT := "currency_spent"
const MISSION_COMPLETED := "mission_completed"
const ACHIEVEMENT_CLAIMED := "achievement_claimed"
const DAILY_REWARD_CLAIMED := "daily_reward_claimed"
const ACCOUNT_LEVEL_UP := "account_level_up"
const META_UPGRADE_PURCHASED := "meta_upgrade_purchased"
const ITEM_UNLOCKED := "item_unlocked"
const SESSION_START := "session_start"
const SESSION_END := "session_end"
const TUTORIAL_STEP := "tutorial_step"
const SCREEN_VIEW := "screen_view"

var enabled := true
var session_id := ""

var _providers: Array[AnalyticsProvider] = []
var _app: AppRoot
var _session_started_at := 0


func _init(app: AppRoot) -> void:
	_app = app
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	session_id = "%08x" % rng.randi()


func add_provider(provider: AnalyticsProvider) -> void:
	_providers.append(provider)


func start_session() -> void:
	_session_started_at = _app.clock.now()
	track(SESSION_START, {
		"new_install": _app.save.is_new_profile,
		"save_integrity": _app.save.integrity_ok,
		"platform": OS.get_name(),
	})


func end_session() -> void:
	track(SESSION_END, {"seconds": _app.clock.now() - _session_started_at})
	flush()


func track(event: String, props: Dictionary = {}) -> void:
	if not enabled:
		return
	var created := int(_app.save.state.get("created_at", 0))
	var stamped := props.duplicate()
	stamped["session"] = session_id
	stamped["ts"] = _app.clock.now()
	stamped["days_since_install"] = maxi(0, int(float(_app.clock.now() - created) / 86400.0)) if created > 0 else 0
	stamped["account_level"] = _app.account.level() if _app.account != null else 1
	stamped["app_version"] = GameData.text(_app.data.game, "version", "0")
	stamped["ab_group"] = str(_app.save.section("ab").get("group", ""))
	for provider in _providers:
		provider.track(event, stamped)


func set_user_property(key: String, value: Variant) -> void:
	for provider in _providers:
		provider.set_user_property(key, value)


func flush() -> void:
	for provider in _providers:
		provider.flush()
