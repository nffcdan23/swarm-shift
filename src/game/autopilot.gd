class_name Autopilot
extends RefCounted
## A simple bot that plays the game: it backs away from threats, drifts towards
## energy when it is safe, and picks upgrades with a rough sense of priority.
##
## It exists so the game can be run headless thousands of steps per second for
## tests, balance sweeps and soak runs. `skill` (0..1) controls reaction time
## and steering noise, which makes it a usable stand-in for players of
## different ability when tuning difficulty.

var skill := 0.7

var _a: Arena
var _dir := Vector2.ZERO
var _think := 0.0
var _wander := 0.0
var _rng := RandomNumberGenerator.new()


func setup(arena: Arena, p_skill: float, p_seed: int) -> void:
	_a = arena
	skill = clampf(p_skill, 0.0, 1.0)
	_rng.seed = p_seed + 7919


func decide(dt: float) -> Vector2:
	_think -= dt
	if _think > 0.0:
		return _dir
	_think = lerpf(0.24, 0.05, skill)
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var px := player.x
	var py := player.y
	var push := Vector2.ZERO

	var sense := 240.0
	var found := enemies.overlap(px, py, sense)
	for h in found:
		var e := enemies.hits[h]
		var dx := px - enemies.x[e]
		var dy := py - enemies.y[e]
		var centre_dist := sqrt(dx * dx + dy * dy) + 0.001
		var gap := maxf(centre_dist - enemies.radius[e] - player.radius, 6.0)
		var weight := (70.0 / gap) * (70.0 / gap)
		# A dasher winding up or mid-dash is worth more respect.
		if enemies.ai[e] == EnemySystem.AI_DASHER and enemies.state[e] != 0:
			weight *= 2.5
		push += Vector2(dx / centre_dist, dy / centre_dist) * minf(weight, 30.0)

	var bullets := a.bullets
	for i in bullets.count:
		var bx := bullets.x[i] - px
		var by := bullets.y[i] - py
		var d2 := bx * bx + by * by
		if d2 > 170.0 * 170.0:
			continue
		# Only dodge bullets that are actually closing.
		if bx * bullets.vx[i] + by * bullets.vy[i] >= 0.0:
			continue
		var speed := sqrt(bullets.vx[i] * bullets.vx[i] + bullets.vy[i] * bullets.vy[i]) + 0.001
		var cross := (bx * bullets.vy[i] - by * bullets.vx[i]) / speed
		if absf(cross) < 46.0:
			var side := Vector2(-bullets.vy[i], bullets.vx[i]) / speed
			push += side * (1.0 if cross >= 0.0 else -1.0) * 2.4

	push += a.hazards.threat_at(px, py, 46.0) * 6.0
	push += a.boss.threat_vector(px, py)
	if a.boss.wall_up():
		var rel := Vector2(px, py) - a.boss.centre
		var edge := a.boss.arena_radius - rel.length()
		if edge < 150.0:
			push -= rel.normalized() * (1.0 - edge / 150.0) * 3.0

	var danger := push.length()
	var pull := Vector2.ZERO
	var pickups := a.pickups
	var stride := maxi(pickups.count / 48, 1)
	for i in range(0, pickups.count, stride):
		var dx := pickups.x[i] - px
		var dy := pickups.y[i] - py
		var d := sqrt(dx * dx + dy * dy) + 1.0
		if d < 460.0:
			var worth := 1.0 + pickups.value[i] * 0.2 + (3.0 if pickups.kind[i] != PickupSystem.KIND_XP else 0.0)
			pull += Vector2(dx, dy) / d * worth / (d + 60.0)
	if pull.length_squared() > 0.000001:
		pull = pull.normalized()

	var want := push + pull * (0.9 if danger < 0.7 else 0.3)
	if want.length_squared() < 0.0025:
		_wander += _rng.randf_range(-0.6, 0.9)
		want = Vector2.from_angle(_wander)
	want = want.rotated(_rng.randf_range(-1.0, 1.0) * (1.0 - skill) * 0.9)
	_dir = want.normalized()
	return _dir


## Index of the upgrade the bot takes from a level-up choice.
func pick(offers: Array) -> int:
	var best := 0
	var best_score := -INF
	var weapon_count := _a.build.weapon_order.size()
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var score := 0.0
		match str(offer.kind):
			UpgradeSystem.KIND_WEAPON:
				score = (3.2 if weapon_count < 3 else 1.6) if bool(offer.is_new) else 2.3
			UpgradeSystem.KIND_AUGMENT:
				score = 3.1 if str(offer.rarity) == "legendary" else 2.6
			UpgradeSystem.KIND_PASSIVE:
				score = 1.9 if str(offer.id) in ["amplifier", "overclock", "multishot"] else 1.4
			UpgradeSystem.KIND_HEAL:
				score = 3.6 if _a.player.hp_fraction() < 0.4 else 0.2
			_:
				score = 0.1
		score += _rng.randf() * (0.3 + 1.4 * (1.0 - skill))
		if score > best_score:
			best_score = score
			best = i
	return best
