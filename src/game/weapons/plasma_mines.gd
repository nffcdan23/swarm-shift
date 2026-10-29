extends Weapon
## Plasma Mines - area denial. Every cooldown a mine is lobbed into the path of
## the nearest threat (most of the way there, never further than `throw`), or
## dropped at the player's feet if nothing is close. It arms a moment later and
## goes off when an enemy comes within `trigger_radius`: chasers run straight
## into the minefield, and a boss standing its ground gets mines landed at it.
##
## Armed mines are drawn above the swarm (gfx.shots) so they stay visible under
## a crowd; their soft floor glow stays on the ground layer. At the active-mine
## cap the oldest goes off to make room. From level 4 the blasts leave enemies
## chilled (slowed); level 5 adds a ring of smaller cluster blasts.
##
## (Until October 2026 mines were only dropped where the player stood, with a
## small trigger, and drawn under the enemies: they did nothing against a target
## that held its ground and could not be seen working in a crowd.)

var _damage := 44.0
var _cooldown := 1.2
var _blast := 115.0
var _arm_time := 0.25
var _trigger := 70.0
var _max := 10
var _lifetime := 14.0
var _kb := 220.0
var _cluster := 0
var _throw := 170.0
var _seek := 300.0
var _chill := 0.0

var _mx := PackedFloat32Array()
var _my := PackedFloat32Array()
var _mage := PackedFloat32Array()
var _cell := 0.0
var _glow_cell := 0.0

## Mines placed and set off since the run began, for tests and tools.
var placed := 0
var detonated := 0


func _on_setup() -> void:
	_cell = _a.gfx.cell("mine")
	_glow_cell = _a.gfx.cell("glow")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_blast = stat("blast_radius")
	_arm_time = stat("arm_time")
	_trigger = stat("trigger_radius")
	_max = int(stat("max_mines"))
	_lifetime = stat("lifetime")
	_kb = stat("knockback")
	_cluster = int(stat("cluster"))
	_throw = stat("throw", 170.0)
	_seek = stat("seek_range", 300.0)
	_chill = stat("chill_time", 0.0)


func mine_count() -> int:
	return _mx.size()


func mine_position(i: int) -> Vector2:
	return Vector2(_mx[i], _my[i])


func is_armed(i: int) -> bool:
	return _mage[i] >= _arm_time


func trigger_radius() -> float:
	return _trigger * _a.player.area


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var glow := a.gfx.ground_glow
	var shots := a.gfx.shots
	var now := a.time
	var trigger := trigger_radius()

	_cd -= dt
	if _cd <= 0.0:
		_cd = cooldown_time(_cooldown)
		if _mx.size() >= _max:
			# At the cap the oldest mine goes off to make room.
			_detonate(0)
		var spot := _placement()
		_mx.append(spot.x)
		_my.append(spot.y)
		_mage.append(0.0)
		placed += 1
		a.sfx("mine_drop")

	var i := _mx.size() - 1
	while i >= 0:
		var age := _mage[i] + dt
		_mage[i] = age
		var armed := age >= _arm_time
		var boom := age >= _lifetime * player.duration
		if armed and not boom:
			boom = enemies.overlap(_mx[i], _my[i], trigger) > 0
		if boom:
			_detonate(i)
		else:
			# Slow pulse while arming, quick blink once live.
			var blink := 0.7 + 0.3 * sin(now * (18.0 if armed else 5.0) + float(i))
			var grow := minf(age * 7.0, 1.0)
			glow.add_sprite(_mx[i], _my[i], 0.0, trigger * 2.2 * grow, Color(color.r, color.g, color.b, 0.22 if armed else 0.1), _glow_cell)
			shots.add_sprite(_mx[i], _my[i], now * 0.9 + float(i), 60.0 * grow, Color(color.r, color.g, color.b, blink), _cell)
		i -= 1


## Where the next mine goes: into the path of the nearest enemy within
## `seek_range` (60% of the way, at most `throw`), else at the player's feet.
func _placement() -> Vector2:
	var player := _a.player
	var target := acquire(player.x, player.y, _seek * player.area)
	if target < 0:
		return Vector2(player.x, player.y)
	var to := Vector2(_a.enemies.x[target] - player.x, _a.enemies.y[target] - player.y)
	var dist := to.length()
	if dist < 1.0:
		return Vector2(player.x, player.y)
	return Vector2(player.x, player.y) + to / dist * minf(dist * 0.6, _throw * player.area)


func _detonate(i: int) -> void:
	var a := _a
	var x := _mx[i]
	var y := _my[i]
	_mx.remove_at(i)
	_my.remove_at(i)
	_mage.remove_at(i)
	detonated += 1
	var radius := _blast * a.player.area
	a.combat.blast(x, y, radius, _damage, src, color, _kb, _chill, true)
	for k in _cluster:
		var angle := TAU * float(k) / float(_cluster) + a.rng.randf() * 0.8
		a.combat.blast(x + cos(angle) * radius * 0.85, y + sin(angle) * radius * 0.85, radius * 0.62, _damage * 0.5, src, color, _kb * 0.5, _chill)


func clear() -> void:
	_mx.clear()
	_my.clear()
	_mage.clear()
