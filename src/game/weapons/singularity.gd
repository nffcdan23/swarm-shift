extends Weapon
## Singularity - throws a black hole into the thickest part of the swarm. It
## drags everything nearby into a ball, grinds it, then implodes. On its own it
## is crowd control; next to any area weapon it is the combo piece.

var _damage := 5.0
var _cooldown := 6.5
var _duration := 2.6
var _radius := 160.0
var _pull := 260.0
var _throw := 250.0
var _tick := 0.2
var _implosion := 55.0

var _active := false
var _age := 0.0
var _life := 0.0
var _x := 0.0
var _y := 0.0
var _from_x := 0.0
var _from_y := 0.0
var _to_x := 0.0
var _to_y := 0.0
var _tick_cd := 0.0
var _cell := 0.0
var _span := 2.0

const TRAVEL := 0.35


func _on_setup() -> void:
	_cell = _a.gfx.cell("hole")
	_span = _a.gfx.span("hole")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_duration = stat("duration")
	_radius = stat("radius")
	_pull = stat("pull")
	_throw = stat("throw_distance")
	_tick = maxf(stat("tick"), 0.05)
	_implosion = stat("implosion_damage")


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	if not _active:
		_cd -= dt
		if _cd > 0.0:
			return
		var target := acquire(player.x, player.y, _throw * 2.2)
		if target < 0:
			_cd = 0.0
			return
		_cd = cooldown_time(_cooldown)
		_active = true
		_age = 0.0
		_life = _duration * player.duration
		_tick_cd = 0.0
		_from_x = player.x
		_from_y = player.y
		# Aim past the nearest enemy so the hole lands inside the pack.
		var dx := enemies.x[target] - player.x
		var dy := enemies.y[target] - player.y
		var d := sqrt(dx * dx + dy * dy) + 0.001
		var reach := minf(d + 60.0, _throw)
		_to_x = player.x + dx / d * reach
		_to_y = player.y + dy / d * reach
		a.sfx("singularity")

	_age += dt
	var radius := _radius * player.area
	var travel := minf(_age / TRAVEL, 1.0)
	var eased := 1.0 - (1.0 - travel) * (1.0 - travel)
	_x = lerpf(_from_x, _to_x, eased)
	_y = lerpf(_from_y, _to_y, eased)

	if travel >= 1.0:
		var found := enemies.overlap(_x, _y, radius)
		_tick_cd -= dt
		var grind := _tick_cd <= 0.0
		if grind:
			_tick_cd += _tick
		var step := _pull * dt
		for h in found:
			var e := enemies.hits[h]
			if (enemies.flags[e] & EnemySystem.F_HEAVY) == 0:
				var dx := _x - enemies.x[e]
				var dy := _y - enemies.y[e]
				var d := sqrt(dx * dx + dy * dy) + 0.001
				# Stronger near the rim so the edge of the field visibly collapses.
				var move := minf(step * (0.6 + 0.8 * d / radius), d)
				enemies.x[e] += dx / d * move
				enemies.y[e] += dy / d * move
			if grind:
				a.combat.hit(e, _damage, src, 0.0, 0.0, false)
		if a.step_count % 2 == 0:
			var angle := randf() * TAU
			var px := _x + cos(angle) * radius
			var py := _y + sin(angle) * radius
			a.gfx.particles.emit(px, py, -cos(angle) * radius * 2.2 - sin(angle) * 120.0, -sin(angle) * radius * 2.2 + cos(angle) * 120.0, 0.4, 5.0, 12.0, color, 0.5, 1.5)

	var size := radius * (0.5 + 0.5 * travel) * (1.0 + 0.05 * sin(a.time * 13.0))
	a.gfx.ground.add_sprite(_x, _y, -a.time * 2.5, size * 1.5, Color(1, 1, 1, minf(travel * 2.0, 1.0)), _cell, _span)
	if travel >= 1.0:
		a.gfx.zones.add_raw(_x, _y, radius * 2.0, Color(color.r, color.g, color.b, 0.3), 0.04, 0.03, 0.06, 0.0)

	if _age >= TRAVEL + _life:
		_active = false
		a.combat.blast(_x, _y, radius * 0.9, _implosion, src, color, 420.0, 0.0, true)
		a.fx.shake(0.25)
		a.sfx("implosion")


func clear() -> void:
	_active = false
