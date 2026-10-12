extends Weapon
## Prism Lance - a sustained beam that slowly tracks the nearest enemy and
## burns everything along its length. Extra beams fan out evenly.

var _damage := 9.0
var _cooldown := 3.6
var _duration := 1.6
var _length := 470.0
var _width := 18.0
var _beams := 1
var _tick := 0.1
var _turn := 1.7

var _firing := 0.0
var _tick_cd := 0.0
var _angle := 0.0
var _beam_cell := 0.0


func _on_setup() -> void:
	_beam_cell = _a.gfx.cell("beam")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_duration = stat("duration")
	_length = stat("length")
	_width = stat("width")
	_beams = maxi(int(stat("beams")), 1)
	_tick = maxf(stat("tick"), 0.03)
	_turn = stat("turn_rate")


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var reach := _length * player.area

	if _firing <= 0.0:
		_cd -= dt
		if _cd > 0.0:
			return
		var target := acquire(player.x, player.y, reach)
		if target < 0:
			_cd = 0.0
			return
		_angle = atan2(enemies.y[target] - player.y, enemies.x[target] - player.x)
		_firing = _duration * player.duration
		_tick_cd = 0.0
		_cd = cooldown_time(_cooldown)
		a.sfx("laser")

	_firing -= dt
	# Sweep towards whatever is closest; with several beams this turns the
	# whole array into a slow rotor.
	var track := enemies.nearest_idx
	if track >= 0 and track < enemies.count:
		var want := atan2(enemies.y[track] - player.y, enemies.x[track] - player.x)
		if _beams > 1:
			_angle += _turn * dt
		else:
			_angle += clampf(wrapf(want - _angle, -PI, PI), -_turn * dt, _turn * dt)
	elif _beams > 1:
		_angle += _turn * dt

	_tick_cd -= dt
	var burn := _tick_cd <= 0.0
	if burn:
		_tick_cd += _tick
	var half_width := _width * player.area * 0.5
	var flicker := 0.85 + 0.15 * sin(a.time * 60.0)
	var beams := a.gfx.beams
	for k in _beams:
		var angle := _angle + TAU * float(k) / float(_beams)
		var ux := cos(angle)
		var uy := sin(angle)
		var x0 := player.x + ux * 22.0
		var y0 := player.y + uy * 22.0
		var x1 := player.x + ux * reach
		var y1 := player.y + uy * reach
		beams.add_segment(x0, y0, x1, y1, half_width * 5.0 * flicker, Color(color.r, color.g, color.b, 0.75), _beam_cell)
		beams.add_segment(x0, y0, x1, y1, half_width * 1.7, Color(1, 1, 1, 0.95), _beam_cell)
		if burn:
			_burn_line(player.x, player.y, ux, uy, reach, half_width)
	a.fx.flash(player.x, player.y, 70.0, color, 0.05)


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
			a.combat.hit(i, _damage, src)
			if (i + a.step_count) % 4 == 0:
				a.gfx.particles.emit(ex[i], ey[i], -ux * 60.0 + randf_range(-80.0, 80.0), -uy * 60.0 + randf_range(-80.0, 80.0), 0.2, 10.0, 1.0, color, 4.0)


func clear() -> void:
	_firing = 0.0
