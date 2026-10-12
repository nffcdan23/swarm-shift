extends Weapon
## Seeker Missiles - slow to fire, but each one hunts its own target and
## explodes. They fan out before turning in, which spreads the damage around.

var _damage := 26.0
var _cooldown := 2.0
var _projectiles := 1.0
var _blast := 80.0
var _speed := 420.0
var _turn := 7.0
var _lifetime := 3.0
var _launch_angle := 0.0


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_projectiles = stat("projectiles")
	_blast = stat("blast_radius")
	_speed = stat("speed")
	_turn = stat("turn_rate")
	_lifetime = stat("lifetime")


func update(dt: float) -> void:
	_cd -= dt
	if _cd > 0.0:
		return
	var a := _a
	var player := a.player
	if a.enemies.nearest_dist > 640.0:
		_cd = 0.0
		return
	_cd = cooldown_time(_cooldown)
	var n := shot_count(_projectiles)
	_launch_angle += 2.4
	for k in n:
		var angle := _launch_angle + TAU * float(k) / float(n)
		a.combat.launch_missile(player.x, player.y, angle, _damage, _blast * player.area, src, color,
			_speed * player.projectile_speed, _turn, _lifetime)
	a.sfx("shoot_missile")
