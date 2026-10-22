extends Weapon
## Cryo Nova - a frost pulse around the player that damages and slows. At max
## level it freezes outright. The set-up half of every cold synergy.

var _damage := 12.0
var _cooldown := 3.4
var _radius := 175.0
var _chill := 2.2
var _freeze := 0.0
var _kb := 60.0


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_radius = stat("radius")
	_chill = stat("chill_time")
	_freeze = stat("freeze_time")
	_kb = stat("knockback")


func update(dt: float) -> void:
	_cd -= dt
	if _cd > 0.0:
		return
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var reach := _radius * player.area
	# Hold the pulse until it would actually catch something.
	if enemies.nearest_dist > reach:
		_cd = 0.0
		return
	_cd = cooldown_time(_cooldown)
	var chill_time := _chill * player.duration
	var freeze_time := _freeze * player.duration
	var found := enemies.overlap(player.x, player.y, reach)
	for h in found:
		var e := enemies.hits[h]
		var dx := enemies.x[e] - player.x
		var dy := enemies.y[e] - player.y
		var d := sqrt(dx * dx + dy * dy) + 0.001
		enemies.apply_cold(e, chill_time, freeze_time)
		a.combat.hit(e, _damage, src, dx / d * _kb, dy / d * _kb)
	a.fx.ring(player.x, player.y, 24.0, reach, 0.32, color, 0.16, 0.22)
	a.fx.ring(player.x, player.y, 12.0, reach * 0.72, 0.26, Color(1, 1, 1, 0.8), 0.07)
	a.fx.flash(player.x, player.y, reach * 1.5, color, 0.22)
	a.gfx.particles.burst(player.x, player.y, 16, reach * 1.6, reach * 3.2, 0.25, 0.45, 12.0, 2.0, color, 5.0, 1.0)
	a.sfx("nova")
