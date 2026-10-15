class_name RunConfig
extends RefCounted
## Everything a run needs to know before it starts. Built from the player's
## profile for a real run, or filled in by hand for tests and simulations - the
## arena itself never reads the profile.

var mode := CampaignService.MODE_SECTOR
var tier := 1
var core := "vanguard"
var color := Color("2de2ff")
var start_weapon := "pulse"
## Weapons that may be offered on level-up.
var weapon_pool: Array[String] = []
## Permanent upgrades plus the core's own modifiers.
var base_mods: Dictionary = {}
var theme: Dictionary = {}
## 0 picks a random seed; anything else makes the run reproducible.
var rng_seed := 0
## Drive the player with the built-in bot (tests, simulations, attract mode).
var autopilot := false
var autopilot_skill := 0.7
var show_tutorial := false
## 0 uses the balance table. Stress tests raise it far past the shipped cap.
var max_enemies := 0


static func from_profile(app: AppRoot, p_mode: String = CampaignService.MODE_SECTOR) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.mode = p_mode
	cfg.tier = 1 if p_mode == CampaignService.MODE_ENDLESS else app.campaign.selected()
	cfg.core = app.arsenal.selected_core()
	cfg.color = app.arsenal.player_color()
	cfg.theme = app.campaign.theme(cfg.tier)
	var core_def := GameData.dict(app.data.cores(), cfg.core)
	cfg.start_weapon = GameData.text(core_def, "start_weapon", "pulse")
	cfg.weapon_pool = app.arsenal.unlocked_weapons()
	if not cfg.weapon_pool.has(cfg.start_weapon):
		cfg.weapon_pool.append(cfg.start_weapon)
	app.meta.collect_mods(cfg.base_mods)
	var core_mods := GameData.dict(core_def, "mods")
	for key: String in core_mods:
		cfg.base_mods[key] = float(cfg.base_mods.get(key, 0.0)) + float(core_mods[key])
	cfg.show_tutorial = not bool(app.save.section("tutorial").get("moved", false))
	return cfg


## A run with every weapon available and no permanent upgrades.
static func for_testing(data: GameData, p_seed: int = 1) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.rng_seed = p_seed
	cfg.autopilot = true
	for weapon_id: String in data.weapon_defs():
		cfg.weapon_pool.append(weapon_id)
	return cfg
