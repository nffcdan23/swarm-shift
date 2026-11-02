extends Weapon
## Orbit Blades - always-on melee ring. Rewards wading into the swarm.
##
## Ripper Discs: blades fling out at far targets, which gives the ring reach.
## Aegis Halo: a wider ring whose blades destroy enemy shots.

var _damage := 9.0
var _blades := 2
var _orbit := 96.0
var _rot_speed := 3.3
var _hit_cd := 0.42
var _radius := 17.0
var _kb := 130.0
var _angle := 0.0
var _cell := 0.0
var _disc_every := 0.0
var _disc_mult := 0.0
var _disc_range := 0.0
var _disc_cd := 0.0
var _next_disc := 0
var _aegis := false


func _on_setup() -> void:
	_cell = _a.gfx.cell("blade")


func _on_stats() -> void:
	_damage = stat("damage")
	_blades = int(stat("blades"))
	_orbit = stat("orbit_radius")
	_rot_speed = stat("rot_speed")
	_hit_cd = stat("hit_cooldown")
	_radius = stat("radius")
	_kb = stat("knockback")
	_disc_every = stat("disc_cooldown", 0.0)
	_disc_mult = stat("disc_damage", 0.0)
	_disc_range = stat("disc_range", 0.0)
	_aegis = stat("aegis", 0.0) > 0.0


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var combat := a.combat
	var shots := a.gfx.shots
	var now := a.time
	# Area widens the ring a little and fattens the blades.
	var orbit := _orbit * (1.0 + (player.area - 1.0) * 0.5)
	var reach := _radius * player.area
	_angle = fposmod(_angle + _rot_speed * dt, TAU)
	var struck_any := false
	for k in _blades:
		var angle := _angle + TAU * float(k) / float(_blades)
		var ux := cos(angle)
		var uy := sin(angle)
		var bx := player.x + ux * orbit
		var by := player.y + uy * orbit
		var found := enemies.overlap(bx, by, reach)
		for h in found:
			var e := enemies.hits[h]
			if enemies.blade_cd[e] > now:
				continue
			enemies.blade_cd[e] = now + _hit_cd
			combat.hit(e, _damage, src, ux * _kb, uy * _kb)
			struck_any = true
		if _aegis:
			a.bullets.clear_circle(bx, by, reach + 8.0)
		shots.add_sprite(bx, by, angle + PI * 0.5, 62.0 * player.area, color, _cell)
		if (a.step_count + k) % 3 == 0:
			a.gfx.particles.emit(bx, by, -uy * 40.0, ux * 40.0, 0.22, 15.0, 2.0, Color(color.r, color.g, color.b, 0.6), 2.0)
	if struck_any:
		a.sfx("blade_hit")
	if _disc_every > 0.0:
		_fling_disc(dt, orbit)


## One disc per cycle; more blades, shorter cycle. Starts from a blade's place in
## the ring so it reads as that blade leaving, and goes for the nearest enemy
## beyond the ring: anything closer is already being cut.
func _fling_disc(dt: float, orbit: float) -> void:
	_disc_cd -= dt
	if _disc_cd > 0.0:
		return
	var a := _a
	var player := a.player
	var target := a.enemies.nearest(player.x, player.y, _disc_range)
	if target < 0:
		_disc_cd = 0.0
		return
	_disc_cd = cooldown_time(_disc_every * 3.0 / float(maxi(_blades, 1)))
	_next_disc = (_next_disc + 1) % maxi(_blades, 1)
	var angle := _angle + TAU * float(_next_disc) / float(maxi(_blades, 1))
	var bx := player.x + cos(angle) * orbit
	var by := player.y + sin(angle) * orbit
	var aim := atan2(a.enemies.y[target] - by, a.enemies.x[target] - bx)
	fire_bullet(bx, by, aim, _damage * _disc_mult, 640.0, _disc_range, 20.0, _cell, 62.0, 2, _kb * 0.5)
