extends Weapon
## Seeker Missiles - slow to fire, but each one hunts its own target and
## explodes. They fan out before turning in, which spreads the damage around.
##
## Hive Pods: a cloud of small missiles. Bunker Buster: one heavy warhead that
## locks on to the toughest enemy on screen.

var _damage := 26.0
var _cooldown := 2.0
var _projectiles := 1.0
var _blast := 80.0
var _speed := 420.0
var _turn := 7.0
var _lifetime := 3.0
var _launch_angle := 0.0
var _hunt := false
var _size := 46.0


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_projectiles = stat("projectiles")
	_blast = stat("blast_radius")
	_speed = stat("speed")
	_turn = stat("turn_rate")
	_lifetime = stat("lifetime")
	_hunt = stat("hunt", 0.0) > 0.0
	_size = stat("missile_size", 46.0)


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
	var enemies := a.enemies
	var mark := enemies.strongest(player.x, player.y, 900.0) if _hunt else -1
	for k in n:
		var angle := _launch_angle + TAU * float(k) / float(n)
		var missile := a.combat.launch_missile(player.x, player.y, angle, _damage, _blast * player.area, src, color,
			_speed * player.projectile_speed, _turn, _lifetime, _size)
		if missile >= 0 and mark >= 0:
			a.projectiles.target_idx[missile] = mark
			a.projectiles.target_id[missile] = enemies.id[mark]
	a.sfx("shoot_missile")
