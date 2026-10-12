extends Weapon
## Combat Drone - a wingman that trails the player and picks its own targets,
## so it covers whichever side the main guns are not pointing at.

var _damage := 7.0
var _cooldown := 0.36
var _drones := 1
var _pierce := 0
var _speed := 780.0
var _range := 430.0
var _radius := 6.0
var _follow := 74.0
var _kb := 50.0

var _dx := PackedFloat32Array()
var _dy := PackedFloat32Array()
var _dcd := PackedFloat32Array()
var _daim := PackedFloat32Array()
var _orbit := 0.0
var _cell := 0.0
var _shot_cell := 0.0


func _on_setup() -> void:
	_cell = _a.gfx.cell("drone")
	_shot_cell = _a.gfx.cell("pellet")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_drones = int(stat("drones"))
	_pierce = int(stat("pierce"))
	_speed = stat("speed")
	_range = stat("range")
	_radius = stat("radius")
	_follow = stat("follow_distance")
	_kb = stat("knockback")
	var player := _a.player
	while _dx.size() < _drones:
		_dx.append(player.x)
		_dy.append(player.y)
		_dcd.append(0.2 * float(_dx.size()))
		_daim.append(0.0)


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var shots := a.gfx.shots
	_orbit = fposmod(_orbit + dt * 1.1, TAU)
	var follow := 1.0 - exp(-dt * 7.0)
	var fired := false
	for k in _drones:
		var slot := _orbit + TAU * float(k) / float(_drones)
		var home_x := player.x + cos(slot) * _follow
		var home_y := player.y + sin(slot) * _follow
		var x := lerpf(_dx[k], home_x, follow)
		var y := lerpf(_dy[k], home_y, follow)
		_dx[k] = x
		_dy[k] = y
		_dcd[k] -= dt
		if _dcd[k] <= 0.0:
			var target := enemies.nearest(x, y, _range)
			if target >= 0:
				_dcd[k] = cooldown_time(_cooldown)
				var aim := atan2(enemies.y[target] - y, enemies.x[target] - x)
				_daim[k] = aim
				fire_bullet(x + cos(aim) * 12.0, y + sin(aim) * 12.0, aim, _damage, _speed, _range, _radius, _shot_cell, 44.0, _pierce, _kb)
				fired = true
			else:
				_dcd[k] = 0.1
		shots.add_sprite(x, y, _daim[k], 46.0, color, _cell)
	if fired:
		a.sfx("shoot_drone")
