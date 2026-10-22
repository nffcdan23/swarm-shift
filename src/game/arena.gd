class_name Arena
extends Node2D
## One run. Owns every gameplay system, advances them in a fixed order each
## step, and reports what happened through signals - it knows nothing about
## menus or the HUD, which is what lets the same class run headless for tests.
##
## `step(dt)` is the whole simulation. In normal play it is called once per
## frame; tests and balance sweeps call it directly in a tight loop.

signal choice_started(offers: Array, is_cache: bool)
signal choice_finished
signal run_ended(result: Dictionary)
signal announced(text: String, style: String)
signal player_downed(can_use_ad: bool)
signal player_revived
signal boss_appeared(display_name: String)
signal boss_gone
signal synergy_activated(synergy: Dictionary)
signal pause_changed(paused: bool)

enum State { PLAYING, CHOOSING, PAUSED, DOWNED, ENDING, ENDED }

const PROFILE_SECTIONS: PackedStringArray = ["player/director/boss", "enemies", "weapons", "projectiles", "combat", "bullets/hazards/pickups", "sweep/fx", "draw commit"]
const C_HURT := Color(1.0, 0.3, 0.36)
const C_LEVEL := Color(0.36, 1.0, 0.69)

var app: AppRoot
var data: GameData
var config: RunConfig
var rng := RandomNumberGenerator.new()

var state := State.PLAYING
## Identifies this run to the ledger, so it can only ever be paid out once.
var run_id := ""
var time := 0.0
var step_count := 0
var level := 1
var xp := 0.0
var xp_needed := 10.0
var credits := 0.0
var rerolls_left := 0
var ad_rerolls_left := 0
var free_revives_left := 0
var ad_revives_left := 0
var revives_used := 0
var peak_enemies := 0
## Exponential moving average of one step's cost, in milliseconds.
var step_ms := 0.0
var step_ms_worst := 0.0
## When set, `step()` accumulates time per section into `profile_usec`.
var profile := false
var profile_usec := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
## Joystick / keyboard / autopilot direction, length 0..1.
var move_input := Vector2.ZERO
## When true the owner calls `step()` itself (tests, simulations).
var manual_stepping := false

var gfx: ArenaGfx
var fx: FxSystem
var background: ArenaBackground
var camera: Camera2D
var player: PlayerUnit
var boss: Boss
var enemies: EnemySystem
var projectiles: ProjectileSystem
var bullets: BulletSystem
var pickups: PickupSystem
var hazards: HazardSystem
var combat: Combat
var build: RunBuild
var upgrades: UpgradeSystem
var director: Director
var autopilot: Autopilot
var weapons: Array[Weapon] = []
var current_offers: Array[Dictionary] = []
var choosing_cache := false
## Counts every hand of cards dealt (level-ups, caches and rerolls). The HUD
## compares it with the hand it is showing to prove the two agree.
var choice_serial := 0
var diag := RunDiagnostics.new()

var _weapon_by_id: Dictionary = {}
var _run_cfg: Dictionary
var _feel: Dictionary
var _pending_levels := 0
var _pending_caches := 0
var _levels_this_step := 0
var _last_choice_closed := -1.0
var _hitstop := 0.0
var _time_scale := 1.0
var _end_timer := 0.0
var _end_cleared := false
var _victory_timer := -1.0
var _vacuum_at := -1.0
var _auto_revive := -1.0
var _purge_radius := -1.0
var _purge_origin := Vector2.ZERO
var _zoom := 0.88
var _zoom_target := 0.88
var _shake_scale := 1.0
var _src_reactive := 0
var _finished := false
var _mutator_note := ""
var _mutator_note_at := 0.0


# ---------------------------------------------------------------------- setup

func setup(p_app: AppRoot, p_config: RunConfig) -> void:
	app = p_app
	data = p_app.data
	config = p_config
	_run_cfg = data.run_cfg()
	_feel = GameData.dict(data.game, "feel")
	rng.seed = config.rng_seed if config.rng_seed != 0 else int(Time.get_ticks_usec()) ^ hash(p_app.analytics.session_id)
	# Not drawn from `rng`: the id must be unique even when the seed is fixed.
	run_id = "%s-%x-%04x" % [p_app.analytics.session_id, Time.get_ticks_usec(), randi() % 65536]

	var max_enemies := max_enemy_count()
	var enemy_capacity := max_enemies + 110

	background = ArenaBackground.new()
	add_child(background)
	background.set_theme_colors(GameData.color(config.theme, "grid", Color("16324a")), GameData.color(config.theme, "accent", Color("2de2ff")))
	background.set_detail(not app.settings.enabled(SettingsService.LOW_EFFECTS, false))

	gfx = ArenaGfx.new()
	gfx.name = "Gfx"
	add_child(gfx)
	gfx.setup(data, enemy_capacity, GameData.integer(_run_cfg, "max_pickups", 340) + 24,
		GameData.integer(GameData.dict(data.enemies, "bullets"), "max", 260), GameData.integer(_feel, "damage_number_cap", 44))
	gfx.numbers.enabled = app.settings.enabled(SettingsService.DAMAGE_NUMBERS)
	gfx.particles.density = 0.5 if app.settings.enabled(SettingsService.LOW_EFFECTS, false) else 1.0
	_shake_scale = app.settings.shake_scale()

	fx = FxSystem.new()
	fx.setup(gfx, GameData.dict(_feel, "shake"))

	build = RunBuild.new(data, config.base_mods)
	combat = Combat.new()
	combat.setup(self)
	_src_reactive = combat.source("reactive")

	enemies = EnemySystem.new()
	enemies.setup(self, enemy_capacity)
	combat.max_queued_blasts = enemy_capacity + Combat.BLAST_QUEUE_HEADROOM
	projectiles = ProjectileSystem.new()
	projectiles.setup(self)
	bullets = BulletSystem.new()
	bullets.setup(self)
	pickups = PickupSystem.new()
	pickups.setup(self)
	hazards = HazardSystem.new()
	hazards.setup(self)

	boss = Boss.new()
	boss.name = "Boss"
	gfx.actors.add_child(boss)
	boss.setup(self)

	player = PlayerUnit.new()
	player.name = "Player"
	gfx.actors.add_child(player)
	player.setup(self, config.color)

	upgrades = UpgradeSystem.new()
	upgrades.setup(self)
	director = Director.new()
	director.setup(self)

	camera = Camera2D.new()
	add_child(camera)
	_zoom = GameData.num(_run_cfg, "camera_zoom", 0.88)
	_zoom_target = _zoom
	camera.zoom = Vector2(_zoom, _zoom)
	camera.make_current()

	if config.autopilot:
		autopilot = Autopilot.new()
		autopilot.setup(self, config.autopilot_skill, int(rng.seed))

	rerolls_left = GameData.integer(_run_cfg, "base_rerolls", 1) + int(build.mod("run.rerolls"))
	ad_rerolls_left = GameData.integer(_run_cfg, "ad_rerolls_per_run", 2)
	free_revives_left = int(build.mod("run.revives"))
	ad_revives_left = GameData.integer(_run_cfg, "ad_revives_per_run", 1)
	xp_needed = _xp_for(level)
	grant_weapon(config.start_weapon, 1 + int(build.mod("run.start_weapon_level")))


func start() -> void:
	state = State.PLAYING
	app.audio.play_music("combat")
	app.audio.set_muffled(false)
	sfx("run_start")
	app.analytics.track(Analytics.GAME_STARTED, {"mode": config.mode, "tier": config.tier, "core": config.core})
	if config.mode == CampaignService.MODE_ENDLESS:
		announce("OVERDRIVE", "title")
	else:
		announce("SECTOR %02d" % config.tier, "title")
	_queue_mutator_note()
	_update_camera(0.0)


## Names the sector's mutators once the opening banner has cleared.
func _queue_mutator_note() -> void:
	var names: PackedStringArray = []
	for id in director.mutator_ids():
		names.append(GameData.text(app.campaign.mutator_def(id), "name", id.to_upper()))
	_mutator_note = "  +  ".join(names)
	_mutator_note_at = time + 2.6


## The most enemies the director will keep alive at once.
func max_enemy_count() -> int:
	return config.max_enemies if config.max_enemies > 0 else GameData.integer(_run_cfg, "max_enemies", 420)


func _xp_for(for_level: int) -> float:
	var l := float(for_level)
	return GameData.num(_run_cfg, "xp_base", 6.0) + GameData.num(_run_cfg, "xp_linear", 4.0) * l + GameData.num(_run_cfg, "xp_quad", 0.0) * l * l


# ----------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	if manual_stepping:
		return
	var dt := minf(delta, 1.0 / 30.0)
	match state:
		State.PLAYING, State.ENDING:
			if _hitstop > 0.0:
				_hitstop -= delta
				dt *= 0.05
			step(dt * _time_scale)
			if state == State.ENDING:
				_end_timer -= delta
				if _end_timer <= 0.0:
					_complete()
		State.DOWNED:
			if _auto_revive >= 0.0:
				_auto_revive -= delta
				if _auto_revive < 0.0:
					revive()
	_update_camera(delta)


## Advances the whole simulation by `dt` seconds.
func step(dt: float) -> void:
	var started := Time.get_ticks_usec()
	var mark := started
	time += dt
	step_count += 1
	gfx.begin(time)

	if autopilot != null:
		move_input = autopilot.decide(dt)
	player.update(dt, move_input)
	if state == State.PLAYING:
		director.update(dt)
	boss.update(dt)
	if profile:
		mark = _lap(0, mark)
	enemies.update(dt)
	if enemies.touch_damage > 0.0:
		player.take_hit(enemies.touch_damage, player.x, player.y)
	if profile:
		mark = _lap(1, mark)
	if player.alive:
		for weapon in weapons:
			weapon.update(dt)
	if profile:
		mark = _lap(2, mark)
	projectiles.update(dt)
	if profile:
		mark = _lap(3, mark)
	_update_purge(dt)
	combat.flush()
	if profile:
		mark = _lap(4, mark)
	bullets.update(dt)
	hazards.update(dt)
	pickups.update(dt)
	if profile:
		mark = _lap(5, mark)
	enemies.sweep()
	fx.update(dt)
	gfx.numbers.update(dt)
	if profile:
		mark = _lap(6, mark)
	gfx.commit()
	if profile:
		mark = _lap(7, mark)

	if enemies.count > peak_enemies:
		peak_enemies = enemies.count
	if _levels_this_step > diag.levels_in_one_step:
		diag.levels_in_one_step = _levels_this_step
	_levels_this_step = 0
	_after_step(dt)
	var cost := float(Time.get_ticks_usec() - started) / 1000.0
	step_ms = cost if step_ms == 0.0 else lerpf(step_ms, cost, 0.05)
	if cost > step_ms_worst:
		step_ms_worst = cost


func _lap(section: int, since: int) -> int:
	var now := Time.get_ticks_usec()
	profile_usec[section] += now - since
	return now


func _after_step(dt: float) -> void:
	if state != State.PLAYING:
		return
	if _vacuum_at >= 0.0 and time >= _vacuum_at:
		_vacuum_at = -1.0
		pickups.magnetise_all()
	if not _mutator_note.is_empty() and time >= _mutator_note_at:
		announce(_mutator_note, "warning")
		_mutator_note = ""
	if _victory_timer >= 0.0:
		_victory_timer -= dt
		player.invulnerable_for = maxf(player.invulnerable_for, 0.5)
		if _victory_timer < 0.0:
			_finish(true)
		return
	if _pending_caches > 0:
		_begin_choice(true)
	elif _pending_levels > 0:
		_begin_choice(false)


func is_playing() -> bool:
	return state == State.PLAYING and _victory_timer < 0.0


# ------------------------------------------------------------------ progress

## Most levels one grant of energy can give. Far above anything a real run
## produces; it exists so that a corrupt amount can never spin the loop below.
const MAX_LEVELS_PER_GRANT := 40

## Adds run energy. Each level gained is queued as a pending choice, opened one
## at a time at the end of a step - never from inside the simulation.
func add_xp(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0:
		diag.xp_rejected += 1
		return
	xp += amount
	var gained := 0
	while xp >= xp_needed and gained < MAX_LEVELS_PER_GRANT:
		xp -= xp_needed
		level += 1
		xp_needed = maxf(_xp_for(level), 1.0)
		_pending_levels += 1
		gained += 1
		app.analytics.track(Analytics.PLAYER_LEVEL_UP, {"level": level, "time": time})
	if xp >= xp_needed:
		xp = xp_needed - 1.0
	_levels_this_step += gained


func add_credits(amount: float) -> void:
	credits += amount * player.credit_gain


func open_cache() -> void:
	_pending_caches += 1


## Upgrade screens still owed to the player (not counting one that is open).
func pending_choices() -> int:
	return _pending_levels + _pending_caches


## The Run Level the hand on the table belongs to. When several levels were
## gained at once, each hand is headed by its own level, not by the last one.
func choice_level() -> int:
	if state != State.CHOOSING or choosing_cache:
		return level
	return level - maxi(_pending_levels - 1, 0)


func _begin_choice(is_cache: bool) -> void:
	if state != State.PLAYING:
		return
	var offers := upgrades.roll(GameData.integer(_run_cfg, "elite_cache_choices", 3) if is_cache else 3, is_cache)
	if offers.is_empty():
		# Nothing to offer: never wait on a choice that cannot be made.
		_pending_caches = maxi(_pending_caches - (1 if is_cache else 0), 0)
		_pending_levels = maxi(_pending_levels - (0 if is_cache else 1), 0)
		return
	state = State.CHOOSING
	choosing_cache = is_cache
	current_offers = offers
	choice_serial += 1
	diag.choices += 1
	if _last_choice_closed >= 0.0:
		var gap := time - _last_choice_closed
		diag.shortest_choice_gap = minf(diag.shortest_choice_gap, gap)
		if gap <= RunDiagnostics.QUICK_WINDOW:
			diag.quick_choices += 1
	sfx("cache_open" if is_cache else "level_up")
	haptic("success")
	if not is_cache:
		fx.shockwave(player.x, player.y, 150.0, C_LEVEL)
	app.audio.set_muffled(true)
	if autopilot != null:
		choose(autopilot.pick(current_offers))
	else:
		choice_started.emit(current_offers, is_cache)


## The player picked card `index` on the level-up screen.
func choose(index: int) -> void:
	if state != State.CHOOSING or index < 0 or index >= current_offers.size():
		return
	var offer := current_offers[index]
	if not upgrades.apply(offer):
		# The card no longer fits the build. Deal a fresh hand for the same
		# level rather than applying it or leaving the screen with nothing.
		current_offers = upgrades.roll(current_offers.size(), choosing_cache)
		choice_serial += 1
		choice_started.emit(current_offers, choosing_cache)
		if autopilot != null:
			choose(autopilot.pick(current_offers))
		return
	app.analytics.track(Analytics.UPGRADE_SELECTED, {
		"kind": offer.kind, "id": offer.id, "level": offer.level, "rarity": offer.rarity,
		"run_level": level, "time": time, "cache": choosing_cache,
	})
	if choosing_cache:
		_pending_caches = maxi(_pending_caches - 1, 0)
	else:
		_pending_levels = maxi(_pending_levels - 1, 0)
	state = State.PLAYING
	if _pending_caches > 0 or _pending_levels > 0:
		# More waiting: deal the next hand straight away. The screen never
		# closes in between, so this is not a "quick" reopen.
		_last_choice_closed = -1.0
		_begin_choice(_pending_caches > 0)
		if state == State.CHOOSING:
			return
	_resume_from_choice()


func _resume_from_choice() -> void:
	state = State.PLAYING
	_last_choice_closed = time
	app.audio.set_muffled(false)
	# Coming back from a menu into a wall of enemies is not fun: clear some room.
	var radius := GameData.num(_run_cfg, "levelup_shockwave_radius", 230.0)
	enemies.repel(player.x, player.y, radius, GameData.num(_run_cfg, "levelup_shockwave_force", 520.0))
	bullets.clear_circle(player.x, player.y, radius * 0.7)
	fx.shockwave(player.x, player.y, radius, C_LEVEL)
	player.invulnerable_for = maxf(player.invulnerable_for, GameData.num(_run_cfg, "levelup_invuln", 0.8))
	choice_finished.emit()


func can_reroll() -> bool:
	return state == State.CHOOSING and rerolls_left > 0


func reroll() -> bool:
	if not can_reroll():
		return false
	rerolls_left -= 1
	_reroll_offers("free")
	return true


## Reroll paid for with a rewarded ad (the caller has already shown it).
func reroll_from_ad() -> bool:
	if state != State.CHOOSING or ad_rerolls_left <= 0:
		return false
	ad_rerolls_left -= 1
	_reroll_offers("ad")
	return true


func _reroll_offers(source: String) -> void:
	current_offers = upgrades.roll(current_offers.size(), choosing_cache)
	choice_serial += 1
	sfx("reroll")
	app.analytics.track(Analytics.UPGRADE_REROLLED, {"source": source, "run_level": level})
	choice_started.emit(current_offers, choosing_cache)


func grant_weapon(weapon_id: String, weapon_level: int) -> void:
	build.set_weapon(weapon_id, weapon_level)
	var weapon: Weapon = _weapon_by_id.get(weapon_id)
	if weapon == null:
		var script_name := GameData.text(data.weapon(weapon_id), "script")
		var script: GDScript = load("res://src/game/weapons/%s.gd" % script_name)
		if script == null:
			push_error("Arena: weapon script missing for '%s'" % weapon_id)
			return
		weapon = script.new()
		weapon.setup(self, weapon_id)
		weapons.append(weapon)
		_weapon_by_id[weapon_id] = weapon
	weapon.level = weapon_level
	refresh_build()


## Pushes the current build into everything that caches numbers from it.
func refresh_build() -> void:
	build.recompute()
	player.apply_stats()
	combat.refresh()
	for weapon in weapons:
		weapon.refresh()


func on_synergy(synergy_id: String) -> void:
	var def := GameData.dict(data.synergies(), synergy_id)
	sfx("synergy")
	haptic("success")
	fx.shockwave(player.x, player.y, 320.0, Color(1.0, 0.76, 0.28))
	fx.shake(FxSystem.Shake.LIGHT)
	app.analytics.track(Analytics.SYNERGY_FOUND, {"id": synergy_id, "run_level": level})
	synergy_activated.emit({"id": synergy_id, "name": GameData.text(def, "name"), "desc": GameData.text(def, "desc")})


# ------------------------------------------------------------- player events

func on_player_hit(amount: float, _from_x: float, _from_y: float) -> void:
	var cfg := GameData.dict(data.game, "player")
	var radius := GameData.num(cfg, "hit_shockwave_radius", 130.0)
	# A big hit is worth a noticeable shake; chip damage in a swarm only a light one.
	var big := amount >= player.max_hp * GameData.num(GameData.dict(_feel, "shake"), "big_hit_fraction", 0.2)
	fx.shake(FxSystem.Shake.MEDIUM if big else FxSystem.Shake.LIGHT)
	fx.shockwave(player.x, player.y, radius, C_HURT)
	gfx.particles.burst(player.x, player.y, 12, 120.0, 380.0, 0.2, 0.45, 12.0, 2.0, C_HURT, 5.0, 1.5)
	fx.text(player.x, player.y - 40.0, "-%d" % int(ceilf(amount)), C_HURT, 1.15)
	enemies.repel(player.x, player.y, radius, GameData.num(cfg, "hit_shockwave_force", 460.0))
	_hitstop = GameData.num(_feel, "hitstop_player_hit", 0.06)
	sfx("player_hurt")
	haptic("heavy")
	if build.enabled("fx.reactive"):
		combat.blast(player.x, player.y, build.mod("fx.reactive_radius", 200.0) * player.area,
			build.mod("fx.reactive_damage", 40.0), _src_reactive, Color(0.6, 0.8, 1.0), 520.0)


func on_player_down() -> void:
	state = State.DOWNED
	sfx("player_death")
	haptic("heavy")
	fx.shake(FxSystem.Shake.HEAVY)
	fx.explosion(player.x, player.y, 180.0, C_HURT)
	app.analytics.track(Analytics.PLAYER_DEATH, {"time": time, "level": level, "kills": combat.kills, "boss_active": boss.active})
	if free_revives_left > 0:
		free_revives_left -= 1
		announce("EMERGENCY REBOOT", "good")
		if manual_stepping:
			revive()
		else:
			_auto_revive = 0.9
		return
	var ad_ok := ad_revives_left > 0 and autopilot == null and app.ads.rewarded_available(AdsService.REVIVE)
	if ad_ok:
		player_downed.emit(true)
	else:
		_finish(false)


## True while a free revive is counting down to bring the player back.
func is_reviving() -> bool:
	return state == State.DOWNED and _auto_revive >= 0.0


## Brings the player back (free revive, or after a rewarded ad).
func revive() -> void:
	if state != State.DOWNED:
		return
	_auto_revive = -1.0
	revives_used += 1
	player.revive(GameData.num(_run_cfg, "revive_hp_fraction", 0.5), GameData.num(_run_cfg, "revive_invuln", 2.5))
	var radius := GameData.num(_run_cfg, "revive_shockwave_radius", 420.0)
	combat.blast(player.x, player.y, radius, 60.0, _src_reactive, C_LEVEL, 700.0)
	bullets.clear()
	hazards.clear()
	fx.shockwave(player.x, player.y, radius, C_LEVEL)
	sfx("revive")
	haptic("success")
	app.analytics.track(Analytics.PLAYER_REVIVED, {"time": time})
	state = State.PLAYING
	player_revived.emit()


## The revive prompt was shown and the player chose the ad and finished it.
func accept_ad_revive() -> void:
	if state == State.DOWNED and ad_revives_left > 0:
		ad_revives_left -= 1
		revive()


func decline_revive() -> void:
	if state == State.DOWNED:
		_finish(false)


# ---------------------------------------------------------------------- boss

func on_boss_warning() -> void:
	var boss_def := GameData.dict(GameData.dict(data.stages, "bosses"), GameData.text(GameData.dict(data.stages, "timeline"), "boss"))
	announce("WARNING  %s" % GameData.text(boss_def, "name", "BOSS"), "boss")
	sfx("boss_warning")
	haptic("warning")
	app.audio.set_music_pitch(1.06)


func spawn_boss(boss_id: String, hp_scale: float, damage_scale: float) -> void:
	var at := Vector2(player.x, player.y - 330.0)
	boss.spawn(boss_id, at, hp_scale, damage_scale)
	# A wave rolls out from the boss and clears the field for the duel.
	_purge_origin = at
	_purge_radius = 0.0
	# ...and everything it drops comes to the player: a last power spike
	# before the fight, and nothing is stranded outside the arena wall.
	_vacuum_at = time + 1.4
	_zoom_target = GameData.num(_run_cfg, "boss_camera_zoom", 0.74)
	fx.shockwave(at.x, at.y, 700.0, Boss.C_BODY)
	fx.shake(FxSystem.Shake.HEAVY)
	sfx("boss_spawn")
	haptic("heavy")
	app.analytics.track(Analytics.BOSS_STARTED, {"boss": boss_id, "time": time, "level": level, "cycle": director.cycle})
	boss_appeared.emit(boss.display_name)


func on_boss_phase(phase_index: int) -> void:
	announce("PHASE %d" % (phase_index + 1), "boss")
	fx.shockwave(boss.x, boss.y, 380.0, Boss.C_BODY)
	fx.shake(FxSystem.Shake.HEAVY)
	bullets.clear()
	_hitstop = GameData.num(_feel, "hitstop_boss_phase", 0.12)
	sfx("boss_phase")
	haptic("heavy")


func on_boss_killed(x: float, y: float) -> void:
	boss.die()
	bullets.clear()
	hazards.clear()
	_purge_origin = Vector2(x, y)
	_purge_radius = 0.0
	_zoom_target = GameData.num(_run_cfg, "camera_zoom", 0.88)
	fx.shockwave(x, y, 900.0, Color(1.0, 0.85, 0.5))
	fx.shake(FxSystem.Shake.EPIC)
	_hitstop = 0.2
	sfx("boss_die")
	haptic("heavy")
	app.audio.set_music_pitch(1.0)

	var boss_def := GameData.dict(GameData.dict(data.stages, "bosses"), GameData.text(GameData.dict(data.stages, "timeline"), "boss"))
	var gems := 24
	var xp_each := GameData.num(boss_def, "xp", 150.0) / float(gems)
	for k in gems:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(20.0, 150.0)
		pickups.drop_xp(x + cos(angle) * dist, y + sin(angle) * dist, xp_each)
	var coins := 10
	var credit_each := GameData.num(boss_def, "credits", 150.0) * float(director.reward_scale().reward) / float(coins)
	for k in coins:
		var angle := rng.randf() * TAU
		pickups.drop(PickupSystem.KIND_CREDIT, x + cos(angle) * 80.0, y + sin(angle) * 80.0, credit_each)
	_vacuum_at = time + 0.9
	app.analytics.track(Analytics.BOSS_DEFEATED, {"time": time, "level": level, "cycle": director.cycle})
	boss_gone.emit()

	if config.mode == CampaignService.MODE_ENDLESS:
		director.begin_next_cycle()
		announce("CYCLE %d" % (director.cycle + 1), "title")
		_queue_mutator_note()
	else:
		announce("SECTOR CLEARED", "good")
		_victory_timer = 2.8


func _update_purge(dt: float) -> void:
	if _purge_radius < 0.0:
		return
	_purge_radius += 1900.0 * dt
	var r2 := _purge_radius * _purge_radius
	for i in enemies.count:
		if enemies.hp[i] <= 0.0 or (enemies.flags[i] & EnemySystem.F_BOSS) != 0:
			continue
		var dx := enemies.x[i] - _purge_origin.x
		var dy := enemies.y[i] - _purge_origin.y
		if dx * dx + dy * dy <= r2:
			enemies.hurt(i, 1000000.0)
	if _purge_radius > 2600.0:
		_purge_radius = -1.0


## Keeps the player inside the boss arena while the wall is up.
func confine(unit: PlayerUnit) -> void:
	if not boss.wall_up():
		return
	var rel := Vector2(unit.x, unit.y) - boss.centre
	var limit := boss.arena_radius - unit.radius
	if rel.length() > limit:
		var clamped := boss.centre + rel.normalized() * limit
		unit.x = clamped.x
		unit.y = clamped.y


# ----------------------------------------------------------------------- end

func set_paused(paused: bool) -> void:
	if paused and state == State.PLAYING:
		state = State.PAUSED
		app.audio.set_muffled(true)
		pause_changed.emit(true)
	elif not paused and state == State.PAUSED:
		state = State.PLAYING
		app.audio.set_muffled(false)
		pause_changed.emit(false)


## Player quit from the pause menu. Whatever was earned so far is kept.
func abandon() -> void:
	if _finished:
		return
	_finished = true
	state = State.ENDED
	_shutdown_audio()
	run_ended.emit(build_result(false, false, true))


func _finish(cleared: bool) -> void:
	if state == State.ENDING or state == State.ENDED:
		return
	_end_cleared = cleared
	state = State.ENDING
	_time_scale = GameData.num(_feel, "death_slowmo_scale", 0.25) if not cleared else 0.6
	_end_timer = GameData.num(_feel, "death_slowmo_time", 1.1)
	player.visible = cleared
	if manual_stepping:
		_complete()


func _complete() -> void:
	if _finished:
		return
	_finished = true
	state = State.ENDED
	_time_scale = 1.0
	_shutdown_audio()
	sfx("victory" if _end_cleared else "defeat")
	run_ended.emit(build_result(_end_cleared, not _end_cleared, false))


func _shutdown_audio() -> void:
	app.audio.set_muffled(false)
	app.audio.set_music_pitch(1.0)
	for weapon in weapons:
		weapon.clear()


func build_result(cleared: bool, died: bool, abandoned: bool) -> Dictionary:
	var by_source: Dictionary = {}
	for i in combat.source_names.size():
		if combat.damage_by_source[i] > 0.0:
			by_source[combat.source_names[i]] = combat.damage_by_source[i]
	return {
		"run_id": run_id,
		"mode": config.mode, "tier": config.tier, "effective_tier": director.effective_tier(), "core": config.core,
		"time": time, "kills": combat.kills, "elites": combat.elites_killed, "bosses": combat.bosses_killed,
		"level": level, "level_ups": level - 1, "damage": combat.total_damage,
		"credits_picked": int(round(credits)), "credit_gain": player.credit_gain,
		"cleared": cleared, "died": died, "abandoned": abandoned,
		"synergies": build.synergies.duplicate(), "revives": revives_used,
		"weapons": build.weapons.duplicate(), "passives": build.passives.duplicate(), "augments": build.augments.duplicate(),
		"damage_by_source": by_source, "cycle": director.cycle,
	}


# -------------------------------------------------------------------- helpers

func sfx(id: String, pitch: float = 1.0) -> void:
	app.audio.play(id, pitch)


func haptic(kind: String) -> void:
	app.haptics.play(kind)


func announce(text: String, style: String = "info") -> void:
	announced.emit(text, style)


func xp_fraction() -> float:
	return clampf(xp / maxf(xp_needed, 1.0), 0.0, 1.0)


func _update_camera(delta: float) -> void:
	var target := Vector2(player.x, player.y)
	if boss.wall_up():
		# Frame the duel: bias the view towards the arena centre.
		target = target.lerp(boss.centre, 0.3)
	camera.position = target if delta <= 0.0 else camera.position.lerp(target, 1.0 - exp(-delta * 16.0))
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-delta * 2.5)) if delta > 0.0 else _zoom
	camera.zoom = Vector2(_zoom, _zoom)
	var max_offset := GameData.num(_feel, "shake_max_offset", 22.0) * _shake_scale
	var shake := fx.shake_amount() * max_offset
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	var view := get_viewport_rect().size
	director.view_half = view / (2.0 * _zoom)
	background.track(camera.position, _zoom, delta)
	var health := player.hp_fraction()
	background.set_danger((0.35 - health) / 0.35 * (0.7 + 0.3 * sin(time * 7.0)) if health < 0.35 and player.alive else 0.0)
