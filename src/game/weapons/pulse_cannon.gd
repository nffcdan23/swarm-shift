extends Weapon
## Pulse Cannon - the starter. Fast, accurate bolts at the nearest enemy.

var _damage := 10.0
var _cooldown := 0.42
var _projectiles := 1.0
var _pierce := 0
var _speed := 800.0
var _range := 640.0
var _radius := 8.0
var _spread := 0.15
var _kb := 90.0
var _cell := 0.0


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
	_spread = deg_to_rad(stat("spread"))
	_kb = stat("knockback")


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
	var aim := atan2(enemies.y[target] - player.y, enemies.x[target] - player.x)
	var n := shot_count(_projectiles)
	for k in n:
		var angle := aim + (float(k) - float(n - 1) * 0.5) * _spread
		fire_bullet(player.x + cos(angle) * 20.0, player.y + sin(angle) * 20.0, angle, _damage, _speed, _range, _radius, _cell, 64.0, _pierce, _kb)
	_a.fx.flash(player.x + cos(aim) * 24.0, player.y + sin(aim) * 24.0, 44.0, color, 0.07)
	_a.sfx("shoot_pulse")
	player.aim_angle = aim
