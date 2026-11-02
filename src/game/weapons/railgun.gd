extends Weapon
## Railgun - hunts the toughest enemy on screen. It marks a target, charges for
## a moment while a lane brightens along the shot, then fires one instant line:
## full damage to the mark, a fraction to anything else along the line.
##
## Every other weapon aims at the nearest enemy or the densest area. This is the
## one that deals with what those leave standing: elites, Tanks, Shooters at
## range, bosses. Against a plain swarm it is slow and wasteful.

var _damage := 120.0
var _cooldown := 2.6
var _charge := 0.35
var _width := 14.0
var _reach := 1100.0
var _kb := 240.0
var _shots := 1
var _falloff := 0.4
var _hunt_range := 900.0

## Marked enemies, by id, and the direction of each shot.
var _marks := PackedInt32Array()
var _angles := PackedFloat32Array()
var _charging := 0.0
var _flash := 0.0
var _beam_cell := 0.0

## Shots fired since the run began, for tests and tools.
var fired := 0

const FLASH := 0.16


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


func is_charging() -> bool:
	return _charging > 0.0


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	if _flash > 0.0:
		_flash -= dt
		_draw_shots()
	if _charging > 0.0:
		_charging -= dt
		var progress := clampf(1.0 - _charging / _charge, 0.0, 1.0)
		_refresh_aim()
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


## The toughest enemy, then the next toughest not already marked.
func _pick_marks() -> bool:
	var a := _a
	var enemies := a.enemies
	var player := a.player
	_marks.resize(0)
	_angles.resize(0)
	var first := enemies.strongest(player.x, player.y, _hunt_range)
	if first < 0:
		return false
	_marks.append(enemies.id[first])
	_angles.append(atan2(enemies.y[first] - player.y, enemies.x[first] - player.x))
	for k in range(1, _shots):
		var other := enemies.random_in_range(player.x, player.y, _hunt_range)
		if other < 0:
			break
		_marks.append(enemies.id[other])
		_angles.append(atan2(enemies.y[other] - player.y, enemies.x[other] - player.x))
	return true


## The mark moves while the shot charges: keep the lane on it.
func _refresh_aim() -> void:
	var a := _a
	var enemies := a.enemies
	var player := a.player
	for k in _marks.size():
		var i := enemies.find_id(_marks[k])
		if i >= 0 and enemies.hp[i] > 0.0:
			_angles[k] = atan2(enemies.y[i] - player.y, enemies.x[i] - player.x)


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
			var full := enemies.id[i] == mark
			a.combat.hit(i, _damage if full else _damage * _falloff, src, ux * _kb, uy * _kb)
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
