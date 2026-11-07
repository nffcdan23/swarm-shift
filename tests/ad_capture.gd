extends Node
## Footage for the social ad in marketing/swarm-shift-ad. Stages moments of
## real runs - the real arena, weapons, HUD and sound - while Godot's Movie
## Maker records every frame:
##
##   godot --path . --resolution 1080x1920 --fixed-fps 60 \
##     --write-movie /abs/folder/frame.png res://tests/ad_capture.tscn -- --shots=none --take=start
##
## Movie Maker records at the window size the project asks for at launch, so
## for 1080x1920 put an override.cfg in the project root while recording (and
## delete it afterwards):
##   [display]
##   window/size/window_width_override=1080
##   window/size/window_height_override=1920
##
## Movie takes (the ad uses all five): hook, start, montage, payoff, boss.
## Each prints "MARK <label> drawn=<n>" lines (n = frames drawn so far, which
## is the movie frame index) so the usable stretches can be cut out, and the
## start take prints "THUMB <drawn> <x> <y> <down>" for every frame so an
## overlay can follow the synthetic thumb. Probe takes (probe_weapons, probe_bosses,
## probe_late) save stills to --out=<folder> instead.
##
## The game's music is muted while recording (the ad lays the same track under
## the cut as one continuous bed); every sound effect is kept.
##
## --shots puts the app in automated mode (in-memory profile, mock ads and
## store), so nothing is written to the real save.

const DT := 1.0 / 30.0
const WEAPON_IDS := ["pulse", "scatter", "orbit", "nova", "chain", "missile", "mine", "drone", "laser", "singularity", "railgun", "nanite"]
## Where the thumb rests, in the 720x1280 design space: above the band a
## social app covers with its caption.
const THUMB_ORIGIN := Vector2(360.0, 830.0)
const THUMB_REACH := 62.0

var _main: Node
var _out := ""
var arena: Arena
var hud: Hud

var _zoom_lock := 0.0
var _zoom_from := 1.0
var _zoom_to := 1.0
var _zoom_t := 0.0
var _zoom_seconds := 0.0

## Steers from the on-screen stick, like a player's thumb, and leaves every
## hand of cards on the table for the capture to present. Being a pilot also
## keeps a lost window focus from pausing the run mid-recording.
class ThumbPilot extends Autopilot:
	var stick: Joystick

	func decide(_dt: float) -> Vector2:
		return stick.current() if stick != null else Vector2.ZERO

	func pick(_offers: Array) -> int:
		return -1


## Holds still and takes the first card of any hand (an elite's cache): for
## shots where the core stands its ground.
class StillPilot extends Autopilot:
	func decide(_dt: float) -> Vector2:
		return Vector2.ZERO

	func pick(_offers: Array) -> int:
		return 0


## Synthetic one-thumb steering for the start take.
var _bot: Autopilot
var _thumb_pilot: ThumbPilot
var _steering := false
var _thumb_down := false
var _thumb_dir := Vector2.ZERO
var _log_thumb := false


func _ready() -> void:
	# --shots made the app automated; the screenshot tour itself must not run.
	App.cli.erase("shots")
	_main = get_parent()
	_out = App.cli_text("out", "user://ad_capture")
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	await get_tree().process_frame
	_profile()
	var take := App.cli_text("take", "probe_weapons")
	print("AD CAPTURE START ", take, " viewport=", get_viewport().get_visible_rect().size, " window=", DisplayServer.window_get_size())
	if not take.begins_with("probe"):
		_quiet_music()
	match take:
		"probe_weapons":
			await _probe_weapons()
		"probe_bosses":
			await _probe_bosses()
		"probe_late":
			await _probe_late()
		"start":
			await _take_start()
		"montage":
			await _take_montage()
		"hook":
			await _take_hook()
		"payoff":
			await _take_payoff()
		"boss":
			await _take_boss()
		_:
			push_error("ad_capture: unknown take '%s'" % take)
	print("AD CAPTURE DONE ", take)
	get_tree().quit()


## A profile well into the game: every weapon owned, tutorials seen.
func _profile() -> void:
	for id: String in App.data.weapon_defs():
		App.arsenal.grant(ArsenalService.WEAPONS, id, "ad")
	App.save.section("tutorial")["moved"] = true
	App.save.section("tutorial")["pickups"] = true


func _quiet_music() -> void:
	var bus := AudioServer.get_bus_index(AudioService.BUS_MUSIC)
	if bus >= 0:
		AudioServer.set_bus_mute(bus, true)


func _process(delta: float) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	if _zoom_seconds > 0.0:
		_zoom_t += delta
		var k := clampf(_zoom_t / _zoom_seconds, 0.0, 1.0)
		# Ease in and out (cubic), like a camera operator's push.
		var e := 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0
		_zoom_lock = lerpf(_zoom_from, _zoom_to, e)
		if k >= 1.0:
			_zoom_seconds = 0.0
	if _zoom_lock > 0.0:
		arena._zoom = _zoom_lock
		arena._zoom_target = _zoom_lock
	if _steering:
		_steer(delta)
	if _log_thumb:
		var knob := THUMB_ORIGIN + _thumb_dir * THUMB_REACH
		print("THUMB %d %.1f %.1f %d" % [Engine.get_frames_drawn(), knob.x, knob.y, 1 if _thumb_down else 0])


# ------------------------------------------------------------------ helpers

func _start(tier: int, seed_value: int, bot: bool = true) -> void:
	for t in range(1, tier):
		App.campaign.record_run(CampaignService.MODE_SECTOR, t, true, 300.0)
	App.cli["seed"] = str(seed_value)
	if bot:
		App.cli["autoplay"] = "1"
	else:
		App.cli.erase("autoplay")
	App.campaign.select(tier)
	_main.start_run(CampaignService.MODE_SECTOR)
	for k in 200:
		await get_tree().process_frame
		if _main.in_run() and _main.arena.state == Arena.State.PLAYING and _main.hud != null:
			break
	arena = _main.arena
	hud = _main.hud
	arena.ad_revives_left = 0
	arena.free_revives_left = 0


func _end_run() -> void:
	_zoom_lock = 0.0
	_zoom_seconds = 0.0
	_main._teardown_run()
	_main.menu.set_active(true)
	arena = null
	await _wait(0.3)


## Runs the simulation flat out until `target` seconds of run time.
func _ff(target: float, keep_alive: bool = true) -> void:
	var guard := 0
	arena.manual_stepping = true
	while arena.time < target and arena.state != Arena.State.ENDED and guard < 60000:
		if arena.state == Arena.State.PLAYING:
			if keep_alive:
				arena.player.hp = maxf(arena.player.hp, arena.player.max_hp * 0.7)
				arena.player.invulnerable_for = maxf(arena.player.invulnerable_for, 0.5)
			arena.step(DT)
		elif arena.state == Arena.State.CHOOSING and arena.autopilot != null:
			arena.choose(arena.autopilot.pick(arena.current_offers))
		else:
			await get_tree().process_frame
		guard += 1
		if guard % 300 == 0:
			await get_tree().process_frame
	arena.manual_stepping = false


## Lets real frames play (and be recorded) until `seconds` of run time pass.
func _play(seconds: float, keep_alive: bool = true) -> void:
	var until := arena.time + seconds
	var guard := 0
	var last_time := arena.time
	var stalled := 0
	while is_instance_valid(arena) and arena.time < until and arena.state != Arena.State.ENDED and guard < 4000:
		if keep_alive:
			arena.player.hp = arena.player.max_hp
			arena.player.invulnerable_for = maxf(arena.player.invulnerable_for, 1.0)
		await get_tree().process_frame
		guard += 1
		# A run that stops advancing (a hand nobody picks) must not keep the
		# movie recording.
		stalled = stalled + 1 if is_equal_approx(arena.time, last_time) else 0
		last_time = arena.time
		if stalled > 90:
			push_error("ad_capture: run stalled at %.2f (state %d)" % [arena.time, arena.state])
			break


func _frames(count: int) -> void:
	for k in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _still(still_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_out, still_name])
	print("still ", still_name)


func _mark(label: String) -> void:
	var live := arena != null and is_instance_valid(arena)
	print("MARK %s drawn=%d time=%.3f kills=%d level=%d enemies=%d" % [label, Engine.get_frames_drawn(),
		arena.time if live else -1.0, arena.combat.kills if live else -1,
		arena.level if live else -1, arena.enemies.count if live else -1])


func _zoom_now(z: float) -> void:
	_zoom_seconds = 0.0
	_zoom_lock = z
	arena._zoom = z
	arena._zoom_target = z


func _zoom_move(z: float, seconds: float) -> void:
	_zoom_from = _zoom_lock if _zoom_lock > 0.0 else arena._zoom
	_zoom_to = z
	_zoom_t = 0.0
	_zoom_seconds = maxf(seconds, 0.01)


func _spawn_swarm(amount: int, types: Array, near: float, far: float) -> void:
	for k in amount:
		var angle := arena.rng.randf() * TAU
		var dist := arena.rng.randf_range(near, far)
		arena.enemies.spawn(arena.enemies.type_of(str(types[k % types.size()])), arena.player.x + cos(angle) * dist, arena.player.y + sin(angle) * dist)


## A closing ring shaped to the portrait screen: an ellipse of enemies.
func _spawn_ring(amount: int, types: Array, rx: float, ry: float, depth: float) -> void:
	for k in amount:
		var angle := TAU * float(k) / float(amount) + arena.rng.randf_range(-0.03, 0.03)
		var grow := 1.0 + arena.rng.randf() * depth
		arena.enemies.spawn(arena.enemies.type_of(str(types[k % types.size()])), arena.player.x + cos(angle) * rx * grow, arena.player.y + sin(angle) * ry * grow)


## Limits the cards a run can deal to these weapons (as if they were the only
## ones the player had unlocked), so the bot builds what the shot needs.
func _pool(ids: Array) -> void:
	var pool: Array[String] = []
	for id in ids:
		pool.append(str(id))
	arena.config.weapon_pool = pool


func _build(weapons: Dictionary, augments: Array = [], evolutions: Dictionary = {}) -> void:
	for weapon_id: String in weapons:
		arena.grant_weapon(weapon_id, int(weapons[weapon_id]))
	for augment_id in augments:
		if not arena.build.augments.has(str(augment_id)):
			arena.build.add_augment(str(augment_id))
	arena.refresh_build()
	for weapon_id: String in evolutions:
		if not arena.build.evolved.has(weapon_id):
			arena.evolve_weapon(weapon_id, str(evolutions[weapon_id]))


## Shows the level-up screen for the choice the run is waiting on, dealing
## these weapon cards (the dealt hand if any of them cannot be offered).
func _present_hand(ids: Array) -> void:
	var pool: Array[Dictionary] = arena.upgrades._candidates(false)
	var hand: Array[Dictionary] = []
	for id in ids:
		for offer: Dictionary in pool:
			if str(offer.id) == str(id) and str(offer.kind) == UpgradeSystem.KIND_WEAPON:
				hand.append(offer)
				break
	if hand.size() < ids.size():
		push_warning("ad_capture: forced hand incomplete, keeping the dealt one")
		hand = arena.current_offers
	arena.current_offers = hand
	arena.choice_serial += 1
	arena.choice_started.emit(hand, false)


# ------------------------------------------------------- synthetic thumb

func _touch(pressed: bool, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = pressed
	touch.position = at
	get_viewport().push_input(touch, true)


func _drag(at: Vector2, relative: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = at
	drag.relative = relative
	get_viewport().push_input(drag, true)


func _thumb_press() -> void:
	if _thumb_down:
		return
	_thumb_down = true
	_thumb_dir = Vector2.ZERO
	_touch(true, THUMB_ORIGIN)


func _thumb_release() -> void:
	if not _thumb_down:
		return
	_thumb_down = false
	_touch(false, THUMB_ORIGIN + _thumb_dir * THUMB_REACH)
	_thumb_dir = Vector2.ZERO


## Steers like a calm player: follows the bot's choice of direction, eased so
## the thumb never jumps.
func _steer(delta: float) -> void:
	if not _thumb_down or arena.state != Arena.State.PLAYING:
		return
	var want := _bot.decide(delta)
	if want.length() > 1.0:
		want = want.normalized()
	var before := _thumb_dir
	_thumb_dir = _thumb_dir.lerp(want, 1.0 - exp(-delta * 7.0))
	_drag(THUMB_ORIGIN + _thumb_dir * THUMB_REACH, (_thumb_dir - before) * THUMB_REACH)


func _tap(at: Vector2) -> void:
	_touch(true, at)
	await _frames(7)
	_touch(false, at)


# ------------------------------------------------------------- movie takes

## 0:00. The first moments of a first run: the tutorial hint, a thumb on the
## glass steering, the first kills, then the first level-up and a pick.
func _take_start() -> void:
	App.save.section("tutorial")["moved"] = false
	App.save.section("tutorial")["pickups"] = true
	var seed_value := App.cli_int("seed", 3)
	await _start(1, seed_value, false)
	_thumb_pilot = ThumbPilot.new()
	_thumb_pilot.stick = hud.joystick
	arena.autopilot = _thumb_pilot
	_mark("run_started")
	_bot = Autopilot.new()
	_bot.setup(arena, 0.8, seed_value)
	_zoom_now(1.12)
	_log_thumb = true
	_steering = true
	await _play_until(1.4)
	_mark("thumb_down")
	_thumb_press()
	# Steer until a level-up is due (forced after 7 s if energy is slow).
	var guard := 0
	while arena.state == Arena.State.PLAYING and guard < 2000:
		if arena.time > 7.0:
			arena.add_xp(arena.xp_needed - arena.xp + 0.05)
		_keep_alive()
		await get_tree().process_frame
		guard += 1
	_mark("levelup_open")
	_thumb_release()
	# The pilot left the hand on the table: present a hand of three weapons
	# as a player would see it.
	arena.autopilot = null
	_present_hand(["chain", "missile", "orbit"])
	# Let the cards land and be read, then tap the middle one.
	await _frames(70)
	var cards: Array = hud._levelup._cards
	if cards.is_empty():
		push_error("ad_capture: no cards on screen")
		await _end_run()
		return
	var pick := 1 if cards.size() > 1 else 0
	var card: Control = cards[pick]
	var centre := card.get_global_rect().get_center()
	_mark("tap")
	print("TAP %d %.1f %.1f" % [Engine.get_frames_drawn(), centre.x, centre.y])
	await _tap(centre)
	guard = 0
	while arena.state == Arena.State.CHOOSING and guard < 600:
		await get_tree().process_frame
		guard += 1
	arena.autopilot = _thumb_pilot
	_mark("resumed")
	await _frames(8)
	_thumb_press()
	await _play(3.2)
	_mark("start_end")
	_steering = false
	_thumb_release()
	_log_thumb = false
	await _frames(10)
	await _end_run()


func _play_until(run_time: float) -> void:
	var guard := 0
	while arena.time < run_time and guard < 2000:
		_keep_alive()
		await get_tree().process_frame
		guard += 1


func _keep_alive() -> void:
	arena.player.hp = arena.player.max_hp
	arena.player.invulnerable_for = maxf(arena.player.invulnerable_for, 1.0)


## One weapon at work in each arena colour, the run clock rising from clip to
## clip. The featured weapon carries the build (a light Pulse Cannon beside
## it), and a pack of the swarm closes in so the weapon has something to do.
## [sector, seed, run time, featured weapon, evolution, zoom, swarm size]
func _take_montage() -> void:
	var clips: Array = [
		[2, 32, 128.0, "missile", "hive", 1.0, 170],
		[3, 33, 150.0, "laser", "sweep", 1.05, 150],
		[4, 34, 188.0, "singularity", "supernova", 0.95, 200],
		[6, 36, 214.0, "mine", "shaped", 1.0, 170],
	]
	var only := App.cli_text("clip")
	for clip: Array in clips:
		var featured := str(clip[3])
		if not only.is_empty() and only != featured:
			continue
		await _start(int(clip[0]), int(clip[1]), true)
		_pool(["pulse", featured])
		await _ff(float(clip[2]) - 20.0)
		_build({"pulse": 2, featured: 5}, [], {featured: str(clip[4])})
		await _ff(float(clip[2]) - 3.0)
		# Run banners belong to the run, not to this shot: hide them, and let
		# real frames pass so anything queued during the fast-forward drains.
		hud._banners.visible = false
		_zoom_now(float(clip[5]))
		await _play(2.6)
		_spawn_ring(int(clip[6]), ["swarmer", "swarmer", "swarmer", "brute", "splitter"], 430.0, 760.0, 0.45)
		await _play(0.5)
		_mark("clip_%s_in" % featured)
		await _play(5.0)
		_mark("clip_%s_out" % featured)
		await _end_run()


## The hook: minute four of a run in the Cyan Grid with a modest build, so the
## swarm piles up. Close on the core, then pull back as a ring of the swarm
## closes in from every side.
func _take_hook() -> void:
	var seed_value := App.cli_int("seed", 5)
	await _start(1, seed_value, true)
	_pool(["pulse", "orbit"])
	# A core that never levelled: what minute four looks like without a build.
	arena.player.xp_gain = 0.0
	await _ff(248.0)
	_build({"pulse": 1, "orbit": 2})
	await _ff(255.0)
	hud._banners.visible = false
	arena.gfx.numbers.enabled = false
	# The thumb lifts: the core holds still while the swarm comes for it, the
	# way the app icon shows it.
	arena.autopilot = StillPilot.new()
	_zoom_now(1.7)
	await _play(1.6)
	arena.enemies.clear()
	await _play(0.5)
	_spawn_ring(460, ["swarmer", "swarmer", "swarmer", "swarmer", "swarmer", "brute", "splitter"], 470.0, 830.0, 0.3)
	_mark("hook_in")
	await _play(0.55)
	_zoom_move(0.74, 1.4)
	await _play(5.0)
	_mark("hook_out")
	await _end_run()


## The payoff: minute four and a half with everything a build can be - Prism
## Wheel, Hive Pods, Singularity and Pulse Cannon, enemies exploding on death -
## close enough that the screen is all weapon.
func _take_payoff() -> void:
	var seed_value := App.cli_int("seed", 8)
	await _start(1, seed_value, true)
	_pool(["pulse", "laser", "missile", "singularity"])
	await _ff(230.0)
	_build({"pulse": 5, "laser": 5, "missile": 5, "singularity": 5}, ["volatile", "storm_crit"],
		{"laser": "sweep", "missile": "hive"})
	await _ff(263.0)
	hud._banners.visible = false
	_zoom_now(1.0)
	await _play(2.6)
	_mark("payoff_in")
	_spawn_ring(260, ["swarmer", "swarmer", "swarmer", "brute", "splitter", "dasher"], 380.0, 680.0, 0.4)
	await _play(4.0)
	_spawn_ring(260, ["swarmer", "swarmer", "swarmer", "brute", "splitter"], 400.0, 720.0, 0.4)
	await _play(5.0)
	_mark("payoff_out")
	await _end_run()


## 5:00 in Sector 20, the Crimson Void: the warning, the Overseer, the fight,
## and the kill.
func _take_boss() -> void:
	var seed_value := App.cli_int("seed", 20)
	await _start(20, seed_value, true)
	_pool(["pulse", "railgun", "laser", "missile"])
	# Sector 20 is no place for a level-1 core: arrive with the build a player
	# who got this far would have.
	_build({"pulse": 5, "railgun": 5, "laser": 5, "missile": 5}, ["storm_crit"], {"missile": "hive"})
	arena.player.invulnerable_for = 1000.0
	await _ff(240.0)
	var boss_at := arena.director.boss_time()
	print("boss_time=", boss_at, " timeline=", arena.director.timeline_time, " time=", arena.time)
	await _ff(boss_at - 12.0)
	arena.player.invulnerable_for = 1000.0
	# Drain the banners queued during the fast-forward, out of sight, so the
	# boss warning is the next one shown.
	hud._banners.visible = false
	_zoom_now(0.9)
	await _play(3.4)
	hud._banners.visible = true
	_mark("boss_warning_window_in")
	var guard := 0
	while not arena.boss.active and guard < 1200:
		_keep_alive()
		await get_tree().process_frame
		guard += 1
	_mark("boss_active")
	await _play(9.0)
	_mark("boss_fight_late")
	# Bring the fight to its end: the next hits finish it.
	var slot := arena.enemies.find_id(arena.boss.enemy_id) if arena.boss.active else -1
	if slot >= 0:
		arena.enemies.hp[slot] = arena.enemies.max_hp[slot] * 0.015
	guard = 0
	while arena.boss.active and guard < 1200:
		_keep_alive()
		await get_tree().process_frame
		guard += 1
	_mark("boss_killed")
	await _play(3.5)
	_mark("boss_out")
	await _frames(30)
	await _end_run()


# ------------------------------------------------------------------- probes

## Every weapon at level 5 against a held swarm: stills at three moments.
func _probe_weapons() -> void:
	for weapon_id: String in WEAPON_IDS:
		await _start(1, 21, false)
		arena.director.paused = true
		arena.player.invulnerable_for = 1000.0
		arena.grant_weapon(weapon_id, 5)
		arena.player.xp_gain = 0.0
		_zoom_now(1.0)
		_spawn_swarm(200, ["swarmer", "swarmer", "swarmer", "brute", "splitter"], 170.0, 620.0)
		arena.enemies.spawn(arena.enemies.type_of("tank"), arena.player.x + 300.0, arena.player.y - 280.0)
		for s in 150:
			arena.move_input = Vector2(cos(float(s) * 0.05), sin(float(s) * 0.05)) * 0.6
			arena.step(DT)
			if arena.enemies.count < 100:
				_spawn_swarm(40, ["swarmer"], 360.0, 420.0)
			if s == 45 or s == 90 or s == 135:
				await _frames(3)
				await _still("w_%s_%d" % [weapon_id, s])
		await _end_run()


## Bosses from each arena colour mid-fight, and the warning before one.
func _probe_bosses() -> void:
	for tier: int in [1, 4, 5, 8, 16, 20]:
		await _start(tier, tier, true)
		arena.grant_weapon("chain", 4)
		arena.grant_weapon("missile", 4)
		arena.player.invulnerable_for = 1000.0
		arena.director.timeline_time = arena.director.boss_time() - 4.0
		await _ff(arena.time + 3.2)
		await _wait(0.4)
		await _still("b_%02d_warning" % tier)
		await _ff(arena.time + 7.0)
		arena.player.invulnerable_for = 1000.0
		await _wait(0.3)
		await _still("b_%02d_%s_a" % [tier, arena.boss.boss_id])
		await _ff(arena.time + 4.0)
		await _wait(0.3)
		await _still("b_%02d_%s_b" % [tier, arena.boss.boss_id])
		await _end_run()


## A strong four-weapon build through the last minute: the 4:00 surge.
func _probe_late() -> void:
	await _start(1, 7, true)
	await _ff(225.0)
	for weapon_id: String in ["pulse", "chain", "missile", "orbit"]:
		arena.grant_weapon(weapon_id, 5)
	arena.build.add_augment("volatile")
	arena.refresh_build()
	arena.player.invulnerable_for = 1000.0
	_zoom_now(0.72)
	for t: float in [238.0, 239.5, 240.5, 241.5, 243.0, 246.0, 255.0, 265.0, 276.0, 277.5, 279.0]:
		await _ff(t)
		arena.player.invulnerable_for = 1000.0
		await _wait(0.25)
		await _still("late_%d" % int(t * 10.0))
	await _end_run()
