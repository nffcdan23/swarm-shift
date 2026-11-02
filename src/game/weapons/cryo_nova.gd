extends Weapon
## Cryo Nova - a frost pulse around the player that damages and slows. At max
## level it freezes outright. The set-up half of every cold synergy.
##
## Permafrost: each pulse leaves a field that keeps chilling and grinding what
## stands in it. Glacial Spikes: each pulse also hurls ice at the toughest
## enemies in range, which gives it real damage against a single target.

const SPIKE_RANGE := 640.0

var _damage := 12.0
var _cooldown := 3.4
var _radius := 175.0
var _chill := 2.2
var _freeze := 0.0
var _kb := 60.0
var _field_time := 0.0
var _field_damage := 0.0
var _spikes := 0
var _spike_damage := 0.0
var _shard_cell := 0.0
var _fields := FieldPool.new(3, 0.5, 1.2)


func _on_setup() -> void:
	_shard_cell = _a.gfx.cell("shard")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_radius = stat("radius")
	_chill = stat("chill_time")
	_freeze = stat("freeze_time")
	_kb = stat("knockback")
	_field_time = stat("field_time", 0.0)
	_field_damage = stat("field_damage", 0.0)
	_spikes = int(stat("spikes", 0.0))
	_spike_damage = stat("spike_damage", 0.0)


func update(dt: float) -> void:
	if _fields.count() > 0:
		_fields.update(_a, dt, _field_time * _a.player.duration, _field_damage, src, color, 0.26)
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
	if _field_time > 0.0:
		_fields.add(player.x, player.y, reach * 0.8)
	if _spikes > 0:
		_hurl_spikes()


func _hurl_spikes() -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var top := enemies.strongest(player.x, player.y, SPIKE_RANGE)
	if top < 0:
		return
	var aim := atan2(enemies.y[top] - player.y, enemies.x[top] - player.x)
	# Half at the toughest enemy, the rest wherever else they are needed.
	for k in _spikes:
		var angle := aim + float(k) * 0.05 - (float(_spikes) * 0.5 - 1.0) * 0.025
		if k % 2 == 1:
			var other := enemies.random_in_range(player.x, player.y, SPIKE_RANGE)
			if other >= 0:
				angle = atan2(enemies.y[other] - player.y, enemies.x[other] - player.x)
		fire_bullet(player.x + cos(angle) * 24.0, player.y + sin(angle) * 24.0, angle, _spike_damage, 760.0, SPIKE_RANGE, 12.0, _shard_cell, 74.0, 0, 120.0)


func clear() -> void:
	_fields.clear()
