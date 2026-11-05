extends Weapon
## Railgun - the heavy-target specialist. It marks the biggest threat in range
## (a boss, then an elite, then a Tank, then any other big enemy), charges for a
## moment while a lane brightens along the shot, then fires one instant line:
## full damage to the mark, with extra punch against bosses and elites, and a
## fraction to anything else along the line.
##
## Every other weapon aims at the nearest enemy or the densest area. This one
## deals with what those leave standing. With nothing big in range it does not
## waste the shot on one swarmer: it fires down the lane that passes through the
## most enemies instead.
##
## A shot never goes into empty space. If the mark dies while the shot charges
## (another weapon got there first), the lane swings to the next target; if
## nothing is left, the shot is called off and the gun is ready again at once.

var _damage := 120.0
var _cooldown := 1.6
var _charge := 0.25
var _width := 14.0
var _reach := 1100.0
var _kb := 240.0
var _shots := 1
var _falloff := 0.4
var _hunt_range := 900.0
var _boss_mult := 2.5

## Marked enemies, by id (-1: a lane shot through a crowd, no single mark), and
## the direction of each shot.
var _marks := PackedInt32Array()
var _angles := PackedFloat32Array()
var _charging := 0.0
var _flash := 0.0
var _beam_cell := 0.0

## Shots fired since the run began, for tests and tools.
var fired := 0
## Charges called off because nothing was left to hit, for tests and tools.
var called_off := 0

const FLASH := 0.16
## How many enemies a lane search tries as the line's anchor.
const LANE_SAMPLES := 16


func _on_setup() -> void:
	_beam_cell = _a.gfx.cell("beam")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_charge = maxf(stat("charge"), 0.05)
	_width = stat("width")
	_reach = stat("length")
	_kb = stat("knockback")
	_shots = maxi(int(stat("shots")), 1)
	_falloff = stat("line_damage")
	_hunt_range = stat("range")
	_boss_mult = stat("boss_mult", 1.0)


func is_charging() -> bool:
	return _charging > 0.0


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	if _flash > 0.0:
		_flash -= dt
		_draw_shots()
	if _charging > 0.0:
		_charging -= dt
		var progress := clampf(1.0 - _charging / _charge, 0.0, 1.0)
		if not _refresh_aim():
			# Everything it was aiming at is gone: no shot, and no wait for one.
			_charging = 0.0
			_cd = 0.0
			called_off += 1
			return
		for k in _angles.size():
			a.gfx.telegraphs.lane(player.x + cos(_angles[k]) * 22.0, player.y + sin(_angles[k]) * 22.0,
				player.x + cos(_angles[k]) * _reach, player.y + sin(_angles[k]) * _reach, _width, color, progress)
		a.gfx.beams.add_sprite(player.x, player.y, 0.0, 30.0 + 50.0 * progress, Color(color.r, color.g, color.b, 0.3 + 0.5 * progress), a.gfx.cell("glow"))
		if _charging <= 0.0:
			_fire()
		return
	_cd -= dt
	if _cd > 0.0:
		return
	if not _pick_marks():
		_cd = 0.0
		return
	_cd = cooldown_time(_cooldown)
	_charging = _charge
	a.sfx("lance_charge", 1.5)


## How much the Railgun wants an enemy: 0 for ordinary small ones.
func _priority(i: int) -> int:
	var f := _a.enemies.flags[i]
	if (f & EnemySystem.F_BOSS) != 0:
		return 4
	if (f & EnemySystem.F_ELITE) != 0:
		return 3
	if (f & EnemySystem.F_HEAVY) != 0:
		return 2
	if (f & EnemySystem.F_BIG) != 0:
		return 1
	return 0


## The biggest threat in range not already marked: highest priority, then most
## health, then nearest. -1 if nothing big is in range.
func _heavy_target(skip: PackedInt32Array) -> int:
	var enemies := _a.enemies
	var player := _a.player
	var r2 := _hunt_range * _hunt_range
	var best := -1
	var best_rank := 0
	var best_hp := -1.0
	var best_d2 := INF
	for i in enemies.count:
		var health := enemies.hp[i]
		if health <= 0.0:
			continue
		var rank := _priority(i)
		if rank == 0 or rank < best_rank:
			continue
		var dx := enemies.x[i] - player.x
		var dy := enemies.y[i] - player.y
		var d2 := dx * dx + dy * dy
		if d2 > r2 or skip.has(enemies.id[i]):
			continue
		if rank == best_rank and (health < best_hp or (health == best_hp and d2 >= best_d2)):
			continue
		best = i
		best_rank = rank
		best_hp = health
		best_d2 = d2
	return best


## The direction of the line that passes through the most enemies in range, or
## NAN if there are none. Each candidate line runs from the player through one
## enemy; the one that catches most wins, the nearer anchor on a tie.
func _best_lane() -> float:
	var enemies := _a.enemies
	var player := _a.player
	var px := player.x
	var py := player.y
	var r2 := _hunt_range * _hunt_range
	var half := _width * player.area * 0.5
	var anchors := PackedInt32Array()
	var start := _a.rng.randi_range(0, maxi(enemies.count - 1, 0))
	var nearest := enemies.nearest(px, py, _hunt_range)
	if nearest < 0:
		return NAN
	anchors.append(nearest)
	# A spread of other anchors, so a big field costs the same as a small one.
	var stride := maxi(enemies.count / LANE_SAMPLES, 1)
	for k in mini(enemies.count, LANE_SAMPLES * 2):
		if anchors.size() >= LANE_SAMPLES:
			break
		var i := (start + k * stride) % enemies.count
		if i == nearest or enemies.hp[i] <= 0.0:
			continue
		var dx := enemies.x[i] - px
		var dy := enemies.y[i] - py
		if dx * dx + dy * dy <= r2:
			anchors.append(i)
	var best_angle := NAN
	var best_hits := 0
	var best_d2 := INF
	for i in anchors:
		var dx := enemies.x[i] - px
		var dy := enemies.y[i] - py
		var d2 := dx * dx + dy * dy
		var d := sqrt(d2) + 0.001
		var ux := dx / d
		var uy := dy / d
		var caught := 0
		for j in enemies.count:
			if enemies.hp[j] <= 0.0:
				continue
			var rx := enemies.x[j] - px
			var ry := enemies.y[j] - py
			var along := rx * ux + ry * uy
			if along < -enemies.radius[j] or along > _reach + enemies.radius[j]:
				continue
			if absf(rx * uy - ry * ux) <= half + enemies.radius[j]:
				caught += 1
		if caught > best_hits or (caught == best_hits and d2 < best_d2):
			best_hits = caught
			best_d2 = d2
			best_angle = atan2(dy, dx)
	return best_angle


## One shot's aim: the next heavy target, else the busiest lane. Appends to the
## marks; false if there is nothing at all to shoot.
func _aim_one() -> bool:
	var enemies := _a.enemies
	var player := _a.player
	var heavy := _heavy_target(_marks)
	if heavy >= 0:
		_marks.append(enemies.id[heavy])
		_angles.append(atan2(enemies.y[heavy] - player.y, enemies.x[heavy] - player.x))
		return true
	var lane := _best_lane()
	if is_nan(lane):
		return false
	_marks.append(-1)
	_angles.append(lane)
	return true


func _pick_marks() -> bool:
	_marks.resize(0)
	_angles.resize(0)
	if not _aim_one():
		return false
	for k in range(1, _shots):
		var before := _marks.size()
		if _heavy_target(_marks) >= 0:
			_aim_one()
		# Nothing else big: the extra shot doubles up on the first mark.
		if _marks.size() == before:
			_marks.append(_marks[0])
			_angles.append(_angles[0])
	return true


## Marks move while the shot charges: keep each lane on its mark, and swing a
## lane whose mark has died onto the next target. False if nothing is left.
func _refresh_aim() -> bool:
	var a := _a
	var enemies := a.enemies
	var player := a.player
	var any := false
	for k in _marks.size():
		var mark := _marks[k]
		if mark < 0:
			any = true
			continue
		var i := enemies.find_id(mark)
		if i < 0 or enemies.hp[i] <= 0.0:
			# Its target is gone. Look again, leaving out the other live marks.
			var others := PackedInt32Array()
			for m in _marks.size():
				if m != k and _marks[m] >= 0 and _marks[m] != mark:
					others.append(_marks[m])
			var next := _heavy_target(others)
			if next < 0:
				next = _heavy_target(PackedInt32Array())
			if next >= 0:
				_marks[k] = enemies.id[next]
				i = next
			else:
				var lane := _best_lane()
				if is_nan(lane):
					continue
				_marks[k] = -1
				_angles[k] = lane
				any = true
				continue
		_angles[k] = atan2(enemies.y[i] - player.y, enemies.x[i] - player.x)
		any = true
	return any


func _fire() -> void:
	var a := _a
	var player := a.player
	fired += 1
	for k in _angles.size():
		_burn(player.x, player.y, cos(_angles[k]), sin(_angles[k]), _marks[k])
	_flash = FLASH
	a.fx.flash(player.x, player.y, 150.0, color, 0.14)
	a.sfx("lance_fire", 1.4)
	player.aim_angle = _angles[0]
	_draw_shots()


func _burn(ox: float, oy: float, ux: float, uy: float, mark: int) -> void:
	var a := _a
	var enemies := a.enemies
	var half := _width * a.player.area * 0.5
	for i in enemies.count:
		if enemies.hp[i] <= 0.0:
			continue
		var rx := enemies.x[i] - ox
		var ry := enemies.y[i] - oy
		var along := rx * ux + ry * uy
		if along < -enemies.radius[i] or along > _reach + enemies.radius[i]:
			continue
		if absf(rx * uy - ry * ux) <= half + enemies.radius[i]:
			var dmg := _damage * _falloff
			if enemies.id[i] == mark:
				dmg = _damage
				if (enemies.flags[i] & (EnemySystem.F_BOSS | EnemySystem.F_ELITE)) != 0:
					dmg *= _boss_mult
			a.combat.hit(i, dmg, src, ux * _kb, uy * _kb)
			a.fx.spark(enemies.x[i], enemies.y[i], color, ux, uy)


func _draw_shots() -> void:
	var a := _a
	var player := a.player
	var strength := clampf(_flash / FLASH, 0.0, 1.0)
	for k in _angles.size():
		var ux := cos(_angles[k])
		var uy := sin(_angles[k])
		var x0 := player.x + ux * 22.0
		var y0 := player.y + uy * 22.0
		var x1 := player.x + ux * _reach
		var y1 := player.y + uy * _reach
		a.gfx.beams.add_segment(x0, y0, x1, y1, _width * 3.2, Color(color.r, color.g, color.b, 0.9 * strength), _beam_cell)
		a.gfx.beams.add_segment(x0, y0, x1, y1, _width, Color(1, 1, 1, strength), _beam_cell)


func clear() -> void:
	_charging = 0.0
	_flash = 0.0
