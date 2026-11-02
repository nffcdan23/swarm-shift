extends Weapon
## Nanite Swarm - infects enemies. An infected enemy loses health over time,
## part of it a share of its own maximum health, so it matters most against the
## tough enemies of late sectors. When a host dies its nanites jump to the
## enemies closest to it.
##
## Slow to start and quiet to watch; a run that keeps killing keeps it spreading.
## The infection itself lives in `EnemySystem.infected`, so it follows the enemy
## through the swarm's array shuffling without a per-step search. Bosses take the
## flat part and a capped share, so a boss is worn down, not melted.

## Seconds between damage ticks. Each host counts from when it was infected, so
## they do not land in unison.
const TICK := 0.3

var _damage := 3.0
var _cooldown := 1.4
var _range := 460.0
var _hosts := 1
var _duration := 6.0
var _share := 0.012
var _share_cap := 40.0
var _spread := 2
var _spread_range := 150.0
var _max_infected := 40
var _orb_cell := 0.0
var _clock := 0.0
var _pending := PackedVector2Array()

## Live hosts as of the last tick, for tests and tools.
var infected_count := 0


func _on_setup() -> void:
	_orb_cell = _a.gfx.cell("nanite")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_range = stat("range")
	_hosts = maxi(int(stat("hosts")), 1)
	_duration = stat("duration")
	_share = stat("health_share")
	_share_cap = stat("share_cap")
	_spread = int(stat("spread"))
	_spread_range = stat("spread_range")
	_max_infected = int(stat("max_infected"))


## An infected enemy died at this spot. Called from inside the kill, where a new
## overlap query is not allowed, so it is only remembered until the next update.
func host_died(x: float, y: float) -> void:
	if _pending.size() < 24:
		_pending.append(Vector2(x, y))


func update(dt: float) -> void:
	var a := _a
	var enemies := a.enemies
	var player := a.player
	_clock += dt
	for spot in _pending:
		_spread_from(spot)
	_pending.resize(0)

	_cd -= dt
	if _cd <= 0.0:
		var reach := _range * player.area
		var sent := 0
		for k in _hosts:
			var target := _next_host(player.x, player.y, reach)
			if target < 0:
				break
			_infect(target)
			a.fx.lightning(player.x, player.y, enemies.x[target], enemies.y[target], color, 7.0, 0.1)
			sent += 1
		_cd = cooldown_time(_cooldown) if sent > 0 else 0.0
		if sent > 0:
			a.sfx("shoot_drone", 0.7)

	var shots := a.gfx.shots
	var infected := enemies.infected
	var now := a.time
	var live := 0
	for i in enemies.count:
		var left := infected[i]
		if left <= 0.0:
			continue
		if enemies.hp[i] <= 0.0:
			continue
		var ticks := int((left - dt) / TICK) != int(left / TICK)
		left -= dt
		infected[i] = left
		live += 1
		var r := enemies.radius[i]
		shots.add_sprite(enemies.x[i], enemies.y[i], now * 2.2 + float(i), maxf(r * 2.6, 26.0), Color(color.r, color.g, color.b, 0.8), _orb_cell)
		if ticks:
			var share := minf(enemies.max_hp[i] * _share, _share_cap)
			a.combat.hit(i, _damage + share, src, 0.0, 0.0, false)
	infected_count = live


## The nearest enemy that is not already infected. Falls back to refreshing the
## nearest one when everything in reach already carries nanites.
func _next_host(x: float, y: float, reach: float) -> int:
	var enemies := _a.enemies
	var found := enemies.overlap(x, y, reach)
	var best := -1
	var best_d2 := INF
	for h in found:
		var e := enemies.hits[h]
		if enemies.infected[e] > 0.0:
			continue
		var dx := enemies.x[e] - x
		var dy := enemies.y[e] - y
		var d2 := dx * dx + dy * dy
		if d2 < best_d2:
			best_d2 = d2
			best = e
	return best if best >= 0 else enemies.nearest(x, y, reach)


func _infect(i: int) -> void:
	if infected_count >= _max_infected and _a.enemies.infected[i] <= 0.0:
		return
	_a.enemies.infected[i] = _duration * _a.player.duration


func _spread_from(spot: Vector2) -> void:
	var a := _a
	var enemies := a.enemies
	var reach := _spread_range * a.player.area
	var found := enemies.overlap(spot.x, spot.y, reach)
	var sent := 0
	for h in found:
		if sent >= _spread:
			break
		var e := enemies.hits[h]
		if enemies.infected[e] > 0.0:
			continue
		_infect(e)
		a.fx.lightning(spot.x, spot.y, enemies.x[e], enemies.y[e], color, 5.0, 0.08)
		sent += 1


func clear() -> void:
	_pending.resize(0)
