extends Weapon
## Pulse Cannon - the starter. Fast, accurate bolts at the nearest enemy.
##
## Every bolt in a volley is aimed to hit. The nearest enemy gets as many bolts
## as it takes to kill it, the next nearest gets the next ones, and so on; bolts
## left over once everything in range is covered go into the nearest. Bolts
## sharing a target leave the barrel side by side and meet on it, so none of
## them flies past into empty space.
##
## Storm Repeater: one tight stream, for single targets. Breach Cannon: slow
## shells that burst on everything they pass through, for the swarm.

var _damage := 10.0
var _cooldown := 0.42
var _projectiles := 1.0
var _pierce := 0
var _speed := 800.0
var _range := 640.0
var _radius := 8.0
var _kb := 90.0
var _blast := 0.0
var _cell := 0.0
var _shots := 0

## Scratch for a volley: the nearest enemies (index, squared distance) and how
## many bolts each gets.
var _near_idx := PackedInt32Array()
var _near_d2 := PackedFloat32Array()
var _bolts := PackedInt32Array()

## How far apart, side to side, bolts sharing a target leave the barrel.
const SIDE_STEP := 9.0


func _on_setup() -> void:
	_cell = _a.gfx.cell("bolt")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_projectiles = stat("projectiles")
	_pierce = int(stat("pierce"))
	_speed = stat("speed")
	_range = stat("range")
	_radius = stat("radius")
	_kb = stat("knockback")
	_blast = stat("blast_radius", 0.0)


func update(dt: float) -> void:
	_cd -= dt
	if _cd > 0.0:
		return
	var player := _a.player
	var enemies := _a.enemies
	var target := acquire(player.x, player.y, _range)
	if target < 0:
		_cd = 0.0
		return
	_cd = maxf(_cd, -0.05) + cooldown_time(_cooldown)
	var n := shot_count(_projectiles)
	if n <= 1:
		_near_idx.resize(1)
		_near_idx[0] = target
		_bolts.resize(1)
		_bolts[0] = 1
	else:
		_share_out(player.x, player.y, n)
	for t in _near_idx.size():
		var i := _near_idx[t]
		var m := _bolts[t]
		for k in m:
			_fire_at(i, (float(k) - float(m - 1) * 0.5) * SIDE_STEP)
	var aim := atan2(enemies.y[target] - player.y, enemies.x[target] - player.x)
	_a.fx.flash(player.x + cos(aim) * 24.0, player.y + sin(aim) * 24.0, 80.0 if _blast > 0.0 else 44.0, color, 0.07)
	_shots += 1
	# At Repeater speed every shot would be a buzz, not a rhythm.
	if evolution.is_empty() or _shots % 3 == 0:
		_a.sfx("shoot_pulse", 0.72 if _blast > 0.0 else 1.0)
	player.aim_angle = aim


## One bolt from beside the barrel (`side` units across the line of fire),
## aimed from where it starts at the middle of enemy `i`.
func _fire_at(i: int, side: float) -> void:
	var player := _a.player
	var enemies := _a.enemies
	var dx := enemies.x[i] - player.x
	var dy := enemies.y[i] - player.y
	var d := sqrt(dx * dx + dy * dy) + 0.001
	var ux := dx / d
	var uy := dy / d
	var sx := player.x + ux * 20.0 - uy * side
	var sy := player.y + uy * 20.0 + ux * side
	var angle := atan2(enemies.y[i] - sy, enemies.x[i] - sx)
	fire_bullet(sx, sy, angle, _damage, _speed, _range, _radius, _cell, 8.0 * _radius, _pierce, _kb, 0, _blast)


## Shares `n` bolts out over the nearest enemies in range, nearest first, each
## getting enough to kill it. Fills `_near_idx` and `_bolts`.
func _share_out(px: float, py: float, n: int) -> void:
	var enemies := _a.enemies
	_near_idx.resize(0)
	_near_d2.resize(0)
	var r2 := _range * _range
	# The `n` nearest, kept sorted by distance (n is a handful).
	for i in enemies.count:
		if enemies.hp[i] <= 0.0:
			continue
		var dx := enemies.x[i] - px
		var dy := enemies.y[i] - py
		var d2 := dx * dx + dy * dy
		if d2 > r2:
			continue
		var size := _near_idx.size()
		if size >= n and d2 >= _near_d2[size - 1]:
			continue
		var at := size
		while at > 0 and _near_d2[at - 1] > d2:
			at -= 1
		_near_idx.insert(at, i)
		_near_d2.insert(at, d2)
		if _near_idx.size() > n:
			_near_idx.resize(n)
			_near_d2.resize(n)
	# What one bolt takes off, before crits and armour.
	var per_bolt := maxf(_damage * _a.player.damage, 0.001)
	_bolts.resize(_near_idx.size())
	_bolts.fill(0)
	var left := n
	for t in _near_idx.size():
		if left <= 0:
			break
		var needed := maxi(ceili(enemies.hp[_near_idx[t]] / per_bolt), 1)
		var given := mini(needed, left)
		_bolts[t] = given
		left -= given
	# Everything in range is covered: the rest go into the nearest.
	_bolts[0] += left
