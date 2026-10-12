extends Weapon
## Orbit Blades - always-on melee ring. Rewards wading into the swarm.

var _damage := 9.0
var _blades := 2
var _orbit := 96.0
var _rot_speed := 3.3
var _hit_cd := 0.42
var _radius := 17.0
var _kb := 130.0
var _angle := 0.0
var _cell := 0.0


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
		shots.add_sprite(bx, by, angle + PI * 0.5, 62.0 * player.area, color, _cell)
		if (a.step_count + k) % 3 == 0:
			a.gfx.particles.emit(bx, by, -uy * 40.0, ux * 40.0, 0.22, 15.0, 2.0, Color(color.r, color.g, color.b, 0.6), 2.0)
	if struck_any:
		a.sfx("blade_hit")
