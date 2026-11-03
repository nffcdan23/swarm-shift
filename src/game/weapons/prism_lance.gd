extends Weapon
## Prism Lance - bursts of beams that spin around the player like the spokes of
## a wheel.
##
## A cycle: when an enemy is within reach it charges for a moment (faint lines
## show where the spokes will appear and light gathers at the core), then the
## spokes fire and turn for `duration` - about one full turn - and switch off
## for `cooldown`. They never aim.
##
## Each time a spoke sweeps over an enemy it cuts away a share of that enemy's
## maximum health (`cut`) plus a little flat damage (`damage`), but never below
## a floor (`floor`). It cannot kill: a burst or two leaves an enemy at a
## sliver, and then any weapon's next hit finishes it. So the Lance is a
## partner weapon - it makes everything else one-shot - and stays useful at
## every sector because it scales with the enemy, not the run. For the same
## reason it cannot be the weapon a run starts with.
##
## Bosses take a smaller cut (`boss_cut`) and only down to `boss_floor`. A cut
## on anything big shows as a percentage, so the player can see what it did.
##
## Prism Wheel: more spokes, spinning faster. Sundering Lance: two long spokes
## that cut bosses hard.
##
## (Until November 2026 it aimed one beam down the most crowded line; players
## found it did almost nothing. A first spinning version was always on, which
## was not the weapon players wanted either.)

## Where a beam starts, clear of the core.
const MUZZLE := 22.0
## Faint copies drawn behind each spoke so the spin reads at a glance.
const TRAIL_STEPS := 3
const TRAIL_GAP := 0.07
## The last part of a burst, in seconds, over which the spokes fade out.
const FADE := 0.2

var _damage := 5.0
var _cut := 0.3
var _floor := 0.12
var _boss_cut := 0.025
var _boss_floor := 0.5
var _beams := 2
var _spin := 4.0
var _length := 260.0
var _width := 20.0
var _push := 30.0
var _charge := 0.35
var _duration := 1.6
var _cooldown := 2.2

## Angle of the first spoke; the rest follow at equal steps.
var _angle := 0.0
var _charging := 0.0
var _firing := 0.0
var _beam_cell := 0.0
var _glow_cell := 0.0
## Enemies cut and bursts fired so far, for the tests.
var cuts := 0
var bursts := 0


func _on_setup() -> void:
	_beam_cell = _a.gfx.cell("beam")
	_glow_cell = _a.gfx.cell("glow")


func _on_stats() -> void:
	_damage = stat("damage")
	_cut = clampf(stat("cut"), 0.0, 0.95)
	_floor = clampf(stat("floor"), 0.0, 1.0)
	_boss_cut = stat("boss_cut", 0.025)
	_boss_floor = clampf(stat("boss_floor", 0.5), 0.0, 1.0)
	_beams = maxi(int(stat("beams")), 1)
	_spin = stat("spin")
	_length = stat("length")
	_width = stat("width")
	_push = stat("knockback")
	_charge = maxf(stat("charge", 0.35), 0.05)
	_duration = stat("duration")
	_cooldown = stat("cooldown")


func is_charging() -> bool:
	return _charging > 0.0


func is_firing() -> bool:
	return _firing > 0.0


## The directions the spokes point along now, in radians.
func beam_angles() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in _beams:
		out.append(_angle + TAU * float(k) / float(_beams))
	return out


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var reach := _length * player.area

	if _firing <= 0.0 and _charging <= 0.0:
		_cd -= dt
		if _cd > 0.0:
			return
		# Only worth a burst when something is close enough to cut.
		if acquire(player.x, player.y, reach) < 0:
			_cd = 0.0
			return
		_charging = _charge
		a.sfx("lance_charge")

	if _charging > 0.0:
		_charging -= dt
		var progress := clampf(1.0 - _charging / _charge, 0.0, 1.0)
		for k in _beams:
			var angle := _angle + TAU * float(k) / float(_beams)
			var ux := cos(angle)
			var uy := sin(angle)
			a.gfx.telegraphs.lane(player.x + ux * MUZZLE, player.y + uy * MUZZLE, player.x + ux * reach, player.y + uy * reach,
				_width * player.area, color, progress)
		a.gfx.beams.add_sprite(player.x, player.y, 0.0, 40.0 + 70.0 * progress, Color(color.r, color.g, color.b, 0.35 + 0.5 * progress), _glow_cell)
		if _charging > 0.0:
			return
		_firing = _duration * player.duration
		_cd = cooldown_time(_cooldown)
		bursts += 1
		a.sfx("lance_fire")
		a.fx.flash(player.x, player.y, 120.0, color, 0.12)

	var step := _spin * minf(dt, _firing)
	var before := _angle
	_angle = wrapf(_angle + step, 0.0, TAU)
	_firing -= dt
	_cut_crossed(player.x, player.y, before, step, reach)
	_draw(player.x, player.y, reach, clampf(_firing / FADE, 0.0, 1.0))


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
			combat.cut(i, _cut * _boss_cut, _boss_floor, src, _damage, color)
		else:
			combat.cut(i, _cut, _floor, src, _damage, color)
		var d := sqrt(d2)
		# Each pass also shoves outwards: the Lance buys room as well.
		if (f & EnemySystem.F_HEAVY) == 0:
			enemies.kx[i] += dx / d * _push * enemies.inv_mass[i]
			enemies.ky[i] += dy / d * _push * enemies.inv_mass[i]
		a.gfx.particles.emit(ex[i], ey[i], dx / d * 120.0 + randf_range(-60.0, 60.0), dy / d * 120.0 + randf_range(-60.0, 60.0), 0.25, 14.0, 1.0, color, 4.0)
		n += 1
	cuts += n
	return n


func _draw(px: float, py: float, reach: float, fade: float) -> void:
	var a := _a
	var beams := a.gfx.beams
	var half_width := _width * a.player.area * 0.5 * (0.4 + 0.6 * fade)
	var flicker := 0.88 + 0.12 * sin(a.time * 50.0)
	var glow := Color(color.r, color.g, color.b, 0.8 * fade)
	for k in _beams:
		var angle := _angle + TAU * float(k) / float(_beams)
		# The trail first, fading out behind the direction of spin.
		for t in range(TRAIL_STEPS, 0, -1):
			var back := angle - TRAIL_GAP * float(t)
			var trail := 0.32 * fade * (1.0 - float(t) / float(TRAIL_STEPS + 1))
			beams.add_segment(px + cos(back) * MUZZLE, py + sin(back) * MUZZLE, px + cos(back) * reach, py + sin(back) * reach,
				half_width * 3.0, Color(color.r, color.g, color.b, trail), _beam_cell)
		var ux := cos(angle)
		var uy := sin(angle)
		var x0 := px + ux * MUZZLE
		var y0 := py + uy * MUZZLE
		var x1 := px + ux * reach
		var y1 := py + uy * reach
		beams.add_segment(x0, y0, x1, y1, half_width * 4.0 * flicker, glow, _beam_cell)
		beams.add_segment(x0, y0, x1, y1, half_width * 1.4, Color(1, 1, 1, 0.9 * fade), _beam_cell)
		beams.add_sprite(x1, y1, 0.0, half_width * 5.0, glow, _glow_cell)
	beams.add_sprite(px, py, 0.0, 70.0, Color(color.r, color.g, color.b, 0.35 * fade), _glow_cell)


func clear() -> void:
	_firing = 0.0
	_charging = 0.0
