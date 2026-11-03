extends Weapon
## Prism Lance - beams that spin around the player like the spokes of a wheel.
##
## It does not aim. Each time a beam sweeps over an enemy it cuts away a share
## of that enemy's maximum health (`cut`) plus a little flat damage (`damage`),
## but never below a floor (`floor`). It cannot kill anything: three or so
## passes leave an enemy at a sliver, and then any weapon's next hit finishes
## it. So the Lance is a partner weapon - it makes everything else one-shot -
## and stays useful at every sector because it scales with the enemy, not the
## run. For the same reason it cannot be the weapon a run starts with.
##
## Elites take a smaller cut, bosses a much smaller one and only down to
## `boss_floor`, so it never melts a boss on its own.
##
## Prism Wheel: more spokes, spinning faster. Sundering Lance: fewer, longer
## spokes that cut bosses and elites hard.
##
## (Until November 2026 it charged and fired a beam down the most crowded line.
## Players found it did almost nothing, so it became this.)

## Where a beam starts, clear of the core.
const MUZZLE := 22.0
## Faint copies drawn behind each spoke so the spin reads at a glance.
const TRAIL_STEPS := 3
const TRAIL_GAP := 0.07
## Shortest gap between two cutting sounds.
const SOUND_GAP := 0.45

var _damage := 5.0
var _cut := 0.3
var _floor := 0.12
var _elite_cut := 0.5
var _boss_cut := 0.01
var _boss_floor := 0.5
var _beams := 2
var _spin := 2.2
var _length := 260.0
var _width := 20.0
var _push := 30.0

## Angle of the first spoke; the rest follow at equal steps.
var _angle := 0.0
var _sound_cd := 0.0
var _beam_cell := 0.0
var _glow_cell := 0.0
## Enemies cut so far, for the tests.
var cuts := 0


func _on_setup() -> void:
	_beam_cell = _a.gfx.cell("beam")
	_glow_cell = _a.gfx.cell("glow")


func _on_stats() -> void:
	_damage = stat("damage")
	_cut = clampf(stat("cut"), 0.0, 0.95)
	_floor = clampf(stat("floor"), 0.0, 1.0)
	_elite_cut = stat("elite_cut", 0.5)
	_boss_cut = stat("boss_cut", 0.01)
	_boss_floor = clampf(stat("boss_floor", 0.5), 0.0, 1.0)
	_beams = maxi(int(stat("beams")), 1)
	_spin = stat("spin")
	_length = stat("length")
	_width = stat("width")
	_push = stat("knockback")


## The directions the spokes point along now, in radians.
func beam_angles() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in _beams:
		out.append(_angle + TAU * float(k) / float(_beams))
	return out


## Radians per second, after the player's fire-rate bonus.
func spin_speed() -> float:
	return _spin * maxf(_a.player.fire_rate, 0.1)


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var reach := _length * player.area
	var step := spin_speed() * dt
	var before := _angle
	_angle = wrapf(_angle + step, 0.0, TAU)
	_sound_cd -= dt
	if _cut_crossed(player.x, player.y, before, step, reach) > 0 and _sound_cd <= 0.0:
		_sound_cd = SOUND_GAP
		a.sfx("lance_charge", 1.35)
	_draw(player.x, player.y, reach)


## Cuts every enemy a spoke swept over this step: those whose bearing lies
## between where a spoke was and where it is now. Each pass over an enemy
## counts once, however wide the beam. Returns how many were cut.
func _cut_crossed(px: float, py: float, from: float, step: float, reach: float) -> int:
	var a := _a
	var enemies := a.enemies
	var combat := a.combat
	var gap := TAU / float(_beams)
	var ex := enemies.x
	var ey := enemies.y
	var er := enemies.radius
	var ehp := enemies.hp
	var ef := enemies.flags
	var n := 0
	for i in enemies.count:
		if ehp[i] <= 0.0:
			continue
		var dx := ex[i] - px
		var dy := ey[i] - py
		var far := reach + er[i]
		var d2 := dx * dx + dy * dy
		if d2 > far * far or d2 < 1.0:
			continue
		if fposmod(atan2(dy, dx) - from, gap) >= step:
			continue
		var f := ef[i]
		if (f & EnemySystem.F_BOSS) != 0:
			combat.cut(i, _cut * _boss_cut, _boss_floor, src, _damage)
		elif (f & EnemySystem.F_ELITE) != 0:
			combat.cut(i, _cut * _elite_cut, _floor, src, _damage)
		else:
			combat.cut(i, _cut, _floor, src, _damage)
		var d := sqrt(d2)
		# Each pass also shoves outwards: the Lance buys room as well.
		if (f & EnemySystem.F_HEAVY) == 0:
			enemies.kx[i] += dx / d * _push * enemies.inv_mass[i]
			enemies.ky[i] += dy / d * _push * enemies.inv_mass[i]
		a.gfx.particles.emit(ex[i], ey[i], dx / d * 120.0 + randf_range(-60.0, 60.0), dy / d * 120.0 + randf_range(-60.0, 60.0), 0.25, 14.0, 1.0, color, 4.0)
		n += 1
	cuts += n
	return n


func _draw(px: float, py: float, reach: float) -> void:
	var a := _a
	var beams := a.gfx.beams
	var half_width := _width * a.player.area * 0.5
	var flicker := 0.88 + 0.12 * sin(a.time * 50.0)
	var glow := Color(color.r, color.g, color.b, 0.8)
	for k in _beams:
		var angle := _angle + TAU * float(k) / float(_beams)
		# The trail first, fading out behind the direction of spin.
		for t in range(TRAIL_STEPS, 0, -1):
			var back := angle - TRAIL_GAP * float(t)
			var fade := 0.32 * (1.0 - float(t) / float(TRAIL_STEPS + 1))
			beams.add_segment(px + cos(back) * MUZZLE, py + sin(back) * MUZZLE, px + cos(back) * reach, py + sin(back) * reach,
				half_width * 3.0, Color(color.r, color.g, color.b, fade), _beam_cell)
		var ux := cos(angle)
		var uy := sin(angle)
		var x0 := px + ux * MUZZLE
		var y0 := py + uy * MUZZLE
		var x1 := px + ux * reach
		var y1 := py + uy * reach
		beams.add_segment(x0, y0, x1, y1, half_width * 4.0 * flicker, glow, _beam_cell)
		beams.add_segment(x0, y0, x1, y1, half_width * 1.4, Color(1, 1, 1, 0.9), _beam_cell)
		beams.add_sprite(x1, y1, 0.0, half_width * 5.0, glow, _glow_cell)
	beams.add_sprite(px, py, 0.0, 70.0, Color(color.r, color.g, color.b, 0.35), _glow_cell)
