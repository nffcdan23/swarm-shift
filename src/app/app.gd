class_name AppRoot
extends Node
## Composition root and the project's only autoload (registered as `App`).
##
## It builds the app-lifetime services in dependency order and hands each one a
## reference back to itself. Everything run-scoped (enemies, weapons, the HUD)
## is owned by the Arena instead, so nothing gameplay-related lives in a global.
##
## Swapping an implementation (real ads, real store, cloud saves, another
## analytics SDK) happens here and nowhere else.

signal booted

const REMOTE_CONFIG_PATH := "user://remote_config.json"

var data: GameData
var clock: GameClock
var save: SaveService
var analytics: Analytics
var analytics_log: LocalLogAnalyticsProvider
var settings: SettingsService
var economy: Economy
var stats: StatsService
var account: AccountService
var meta: MetaService
var arsenal: ArsenalService
var campaign: CampaignService
var missions: MissionService
var achievements: AchievementService
var daily: DailyRewardService
var haptics: HapticsService
var audio: AudioService
var ads: AdsService
var store: StoreService

## "--key=value" / "--flag" arguments passed after `--` on the command line.
var cli: Dictionary = {}
var headless := false
## True for tests, simulations and screenshot tours: uses an in-memory profile
## and makes the mock ad/store providers resolve without prompting.
var automated := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cli()
	headless = DisplayServer.get_name() == "headless"
	automated = headless or cli.has("test") or cli.has("sim") or cli.has("bench") or cli.has("shots")
	boot(MemorySaveBackend.new() if automated else null)


## (Re)builds every service. Tests call this with a fresh MemorySaveBackend to
## start from a clean profile.
func boot(backend: SaveBackend = null) -> void:
	data = GameData.new()
	if not data.load_all():
		for problem in data.errors:
			push_error("Data: " + problem)
	_apply_remote_config()

	clock = GameClock.new()
	save = SaveService.new(backend)
	save.load_or_create()

	analytics = Analytics.new(self)
	analytics_log = LocalLogAnalyticsProvider.new()
	analytics_log.write_file = not automated
	analytics_log.echo = cli.has("log-analytics")
	analytics.add_provider(analytics_log)

	settings = SettingsService.new(self)
	stats = StatsService.new(self)
	economy = Economy.new(self)
	account = AccountService.new(self)
	meta = MetaService.new(self)
	arsenal = ArsenalService.new(self)
	campaign = CampaignService.new(self)
	missions = MissionService.new(self)
	achievements = AchievementService.new(self)
	daily = DailyRewardService.new(self)
	haptics = HapticsService.new(self)

	if audio != null:
		audio.queue_free()
	audio = AudioService.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)

	# Provider selection point: replace the mocks with real SDK adapters here.
	store = StoreService.new(self, MockStoreProvider.new())
	ads = AdsService.new(self, MockAdProvider.new())

	_assign_ab_group()
	missions.refresh()
	analytics.start_session()
	booted.emit()


func _process(delta: float) -> void:
	if save != null:
		save.tick(delta)


func _exit_tree() -> void:
	# Static caches hold engine resources; release them for a clean shutdown.
	UiTheme.release()
	SpriteBatch.release()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if save != null:
				save.flush()
			if analytics != null:
				analytics.flush()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if analytics != null:
				analytics.end_session()
			if save != null:
				save.flush()
		NOTIFICATION_APPLICATION_RESUMED:
			if missions != null:
				missions.refresh()


func _parse_cli() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq == -1:
			cli[body] = "1"
		else:
			cli[body.substr(0, eq)] = body.substr(eq + 1)


## Remote balancing hook. Whatever fetches config in future only has to write
## this file; the overrides are layered over the bundled tables at boot.
func _apply_remote_config() -> void:
	if automated or not FileAccess.file_exists(REMOTE_CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REMOTE_CONFIG_PATH))
	if parsed is Dictionary:
		data.apply_overrides(parsed)


## Stable 50/50 bucket per install, stamped on every analytics event.
func _assign_ab_group() -> void:
	var ab := save.section("ab")
	if str(ab.get("group", "")).is_empty():
		ab["group"] = "A" if hash(str(save.state.get("install_id", ""))) % 2 == 0 else "B"
		save.mark_dirty()


func cli_int(key: String, fallback: int) -> int:
	return int(str(cli.get(key))) if cli.has(key) and str(cli.get(key)).is_valid_int() else fallback


func cli_text(key: String, fallback: String = "") -> String:
	return str(cli.get(key)) if cli.has(key) else fallback
