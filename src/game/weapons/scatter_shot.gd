extends Weapon
## Scatter Shot - a wide cone of short-lived pellets. Huge damage point blank,
## nothing at range, and enough knockback to punch a hole in a closing ring.

var _damage := 7.0
var _cooldown := 1.05
var _projectiles := 5.0
var _pierce := 0
var _speed := 640.0
var _range := 300.0
var _radius := 6.0
var _spread := 0.8
var _kb := 220.0
var _cell := 0.0


func _on_setup() -> void:
	_cell = _a.gfx.cell("pellet")


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
	# Only worth firing when something is close enough to catch the cone.
	var target := acquire(player.x, player.y, _range * 1.15)
	if target < 0:
		_cd = 0.0
		return
	_cd = maxf(_cd, -0.05) + cooldown_time(_cooldown)
	var aim := atan2(enemies.y[target] - player.y, enemies.x[target] - player.x)
	var n := shot_count(_projectiles)
	var rng := _a.rng
	for k in n:
		var along := (float(k) + 0.5) / float(n) - 0.5
		var angle := aim + along * _spread + rng.randf_range(-0.04, 0.04)
		fire_bullet(player.x + cos(angle) * 18.0, player.y + sin(angle) * 18.0, angle, _damage,
			_speed * rng.randf_range(0.82, 1.1), _range, _radius, _cell, 50.0, _pierce, _kb)
	_a.fx.flash(player.x + cos(aim) * 30.0, player.y + sin(aim) * 30.0, 90.0, color, 0.09)
	_a.gfx.particles.burst(player.x, player.y, 6, 200.0, 520.0, 0.1, 0.22, 10.0, 1.0, color, 5.0, 2.0, aim, _spread)
	_a.fx.shake(0.05)
	_a.sfx("shoot_scatter")
	player.aim_angle = aim
