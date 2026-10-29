extends Weapon
## Prism Lance - a heavy, piercing beam for dense formations.
##
## Each cycle: choose the line through the most enemies within reach, charge
## for a moment (an aim line brightens along it and the core gathers light),
## then fire a beam that burns everything along that line for `duration`.
## Extra beams take the next-best lines, at least `SPREAD` apart, so every
## upgrade adds damage where it counts. Against a single target - a boss -
## all beams converge on it, slightly fanned.
##
## The trade-off against fast weapons is time: it charges, fires in bursts and
## then cools down, and it does little against a lone enemy that is out of reach.
##
## (Until October 2026 it tracked the nearest enemy with a thin beam, and at
## two or more beams it stopped tracking and spun in a fixed circle, so its
## single-target damage fell from level 3 to level 5.)

## Directions are tried towards up to this many of the nearest enemies.
const CANDIDATES := 10
## Minimum angle between two beams aimed at different lines.
const SPREAD := 0.42
## Beams with no separate line to take fan out this far around the best one.
const FAN := 0.45

var _damage := 10.0
var _cooldown := 1.8
var _duration := 1.2
var _length := 620.0
var _width := 28.0
var _beams := 1
var _tick := 0.1
var _turn := 1.2
var _charge := 0.45
var _push := 26.0

var _charging := 0.0
var _firing := 0.0
var _tick_cd := 0.0
var _angles := PackedFloat32Array()
var _anchors := PackedInt32Array()
var _beam_cell := 0.0
var _glow_cell := 0.0
var _order: Array = []
# The enemies within reach at aiming time, relative to the player, so each
# candidate line scans a compact list instead of the whole swarm.
var _rx := PackedFloat32Array()
var _ry := PackedFloat32Array()
var _rr := PackedFloat32Array()


func _on_setup() -> void:
	_beam_cell = _a.gfx.cell("beam")
	_glow_cell = _a.gfx.cell("glow")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_duration = stat("duration")
	_length = stat("length")
	_width = stat("width")
	_beams = maxi(int(stat("beams")), 1)
	_tick = maxf(stat("tick"), 0.03)
	_turn = stat("turn_rate")
	_charge = maxf(stat("charge", 0.45), 0.05)
	_push = stat("knockback", 26.0)


func is_charging() -> bool:
	return _charging > 0.0


func is_firing() -> bool:
	return _firing > 0.0


## The directions the beams are (or will be) aimed along, in radians.
func beam_angles() -> PackedFloat32Array:
	return _angles


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var reach := _length * player.area
	var half_width := _width * player.area * 0.5

	if _firing <= 0.0 and _charging <= 0.0:
		_cd -= dt
		if _cd > 0.0:
			return
		if not _aim(reach, half_width):
			_cd = 0.0
			return
		_charging = _charge
		a.sfx("lance_charge")

	if _charging > 0.0:
		_charging -= dt
		var progress := clampf(1.0 - _charging / _charge, 0.0, 1.0)
		for k in _angles.size():
			var ux := cos(_angles[k])
			var uy := sin(_angles[k])
			a.gfx.telegraphs.lane(player.x + ux * 22.0, player.y + uy * 22.0, player.x + ux * reach, player.y + uy * reach,
				half_width * 2.0, color, progress)
		a.gfx.beams.add_sprite(player.x, player.y, 0.0, 40.0 + 70.0 * progress, Color(color.r, color.g, color.b, 0.35 + 0.5 * progress), _glow_cell)
		if _charging > 0.0:
			return
		# Re-aim at the moment of release: the swarm has moved during the charge
		# and the enemy it was aimed at may be gone.
		_aim(reach, half_width)
		_firing = _duration * player.duration
		_tick_cd = 0.0
		_cd = cooldown_time(_cooldown)
		a.sfx("lance_fire")
		a.fx.flash(player.x, player.y, 120.0, color, 0.12)

	_firing -= dt
	_track(dt)
	_tick_cd -= dt
	var burn := _tick_cd <= 0.0
	if burn:
		_tick_cd += _tick
	var flicker := 0.85 + 0.15 * sin(a.time * 60.0)
	var beams := a.gfx.beams
	for k in _angles.size():
		var ux := cos(_angles[k])
		var uy := sin(_angles[k])
		var x0 := player.x + ux * 22.0
		var y0 := player.y + uy * 22.0
		var x1 := player.x + ux * reach
		var y1 := player.y + uy * reach
		# Outer glow, then a white core as wide as the burn itself.
		beams.add_segment(x0, y0, x1, y1, half_width * 5.0 * flicker, Color(color.r, color.g, color.b, 0.85), _beam_cell)
		beams.add_segment(x0, y0, x1, y1, half_width * 2.0, Color(1, 1, 1, 0.95), _beam_cell)
		if burn:
			_burn_line(player.x, player.y, ux, uy, reach, half_width)
	a.fx.flash(player.x, player.y, 80.0, color, 0.05)


## Chooses the beam directions. Returns false if no enemy is within reach.
func _aim(reach: float, half_width: float) -> bool:
	var a := _a
	var enemies := a.enemies
	var px := a.player.x
	var py := a.player.y
	var reach2 := reach * reach
	_order.clear()
	_rx.resize(0)
	_ry.resize(0)
	_rr.resize(0)
	var ex := enemies.x
	var ey := enemies.y
	var er := enemies.radius
	var ehp := enemies.hp
	for i in enemies.count:
		if ehp[i] <= 0.0:
			continue
		var dx := ex[i] - px
		var dy := ey[i] - py
		var d2 := dx * dx + dy * dy
		var far := reach + er[i]
		if d2 <= far * far:
			_rx.append(dx)
			_ry.append(dy)
			_rr.append(er[i])
		if d2 <= reach2:
			_order.append(Vector2(d2, float(i)))
	if _order.is_empty():
		return false
	_order.sort()
	var candidates: Array = []
	for k in mini(_order.size(), CANDIDATES):
		var i := int((_order[k] as Vector2).y)
		var angle := atan2(enemies.y[i] - py, enemies.x[i] - px)
		candidates.append([_count_line(cos(angle), sin(angle), reach, half_width), -k, angle, enemies.id[i]])
	# Most enemies in line first; nearer anchor breaks ties.
	candidates.sort_custom(func(l: Array, r: Array) -> bool: return l[0] > r[0] or (l[0] == r[0] and l[1] > r[1]))
	_angles.resize(0)
	_anchors.resize(0)
	for c: Array in candidates:
		if _angles.size() >= _beams:
			break
		var clear := true
		for taken in _angles:
			if absf(wrapf(float(c[2]) - taken, -PI, PI)) < SPREAD:
				clear = false
				break
		if clear:
			_angles.append(float(c[2]))
			_anchors.append(int(c[3]))
	# Not enough separate lines: fan the rest around the best one.
	var best := _angles[0]
	var extra := 0
	while _angles.size() < _beams:
		extra += 1
		_angles.append(best + FAN * floorf(float(extra + 1) / 2.0) * (1.0 if extra % 2 == 1 else -1.0))
		_anchors.append(_anchors[0])
	return true


## How many of the enemies within reach a beam along (ux, uy) would touch.
func _count_line(ux: float, uy: float, reach: float, half_width: float) -> int:
	var n := 0
	for k in _rx.size():
		var rx := _rx[k]
		var ry := _ry[k]
		var r := _rr[k]
		var along := rx * ux + ry * uy
		if along < -r or along > reach + r:
			continue
		if absf(rx * uy - ry * ux) <= half_width + r:
			n += 1
	return n


## Each beam turns after the enemy it was aimed at, by at most turn_rate * dt.
func _track(dt: float) -> void:
	var a := _a
	var enemies := a.enemies
	for k in _angles.size():
		var i := enemies.find_id(_anchors[k])
		if i < 0:
			continue
		var want := atan2(enemies.y[i] - a.player.y, enemies.x[i] - a.player.x)
		if k > 0 and _anchors[k] == _anchors[0]:
			want += _angles[k] - _angles[0]
		_angles[k] += clampf(wrapf(want - _angles[k], -PI, PI), -_turn * dt, _turn * dt)


## Damages every enemy within `half_width` of the segment. A straight scan of
## the swarm is cheaper and more exact than tiling the beam with circle queries.
func _burn_line(ox: float, oy: float, ux: float, uy: float, reach: float, half_width: float) -> void:
	var a := _a
	var enemies := a.enemies
	var ex := enemies.x
	var ey := enemies.y
	var er := enemies.radius
	var ehp := enemies.hp
	for i in enemies.count:
		if ehp[i] <= 0.0:
			continue
		var rx := ex[i] - ox
		var ry := ey[i] - oy
		var along := rx * ux + ry * uy
		if along < -er[i] or along > reach + er[i]:
			continue
		var off := absf(rx * uy - ry * ux)
		if off <= half_width + er[i]:
			# Each tick also shoves along the beam: the lance buys room as well.
			a.combat.hit(i, _damage, src, ux * _push, uy * _push)
			if (i + a.step_count) % 3 == 0:
				a.gfx.particles.emit(ex[i], ey[i], -ux * 60.0 + randf_range(-90.0, 90.0), -uy * 60.0 + randf_range(-90.0, 90.0), 0.22, 12.0, 1.0, color, 4.0)


func clear() -> void:
	_firing = 0.0
	_charging = 0.0
