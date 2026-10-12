extends Weapon
## Plasma Mines - dropped where the player stands, armed a moment later, set
## off by the first enemy to touch them. Kiting through your own minefield is
## the whole game plan.

var _damage := 34.0
var _cooldown := 1.5
var _blast := 98.0
var _arm_time := 0.4
var _trigger := 44.0
var _max := 8
var _lifetime := 14.0
var _kb := 200.0
var _cluster := 0

var _mx := PackedFloat32Array()
var _my := PackedFloat32Array()
var _mage := PackedFloat32Array()
var _cell := 0.0


func _on_setup() -> void:
	_cell = _a.gfx.cell("mine")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_blast = stat("blast_radius")
	_arm_time = stat("arm_time")
	_trigger = stat("trigger_radius")
	_max = int(stat("max_mines"))
	_lifetime = stat("lifetime")
	_kb = stat("knockback")
	_cluster = int(stat("cluster"))


func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var glow := a.gfx.ground_glow
	var now := a.time

	_cd -= dt
	if _cd <= 0.0:
		_cd = cooldown_time(_cooldown)
		if _mx.size() >= _max:
			# At the cap the oldest mine goes off to make room.
			_detonate(0)
		_mx.append(player.x)
		_my.append(player.y)
		_mage.append(0.0)
		a.sfx("mine_drop")

	var i := _mx.size() - 1
	while i >= 0:
		var age := _mage[i] + dt
		_mage[i] = age
		var armed := age >= _arm_time
		var boom := age >= _lifetime * player.duration
		if armed and not boom:
			boom = enemies.overlap(_mx[i], _my[i], _trigger) > 0
		if boom:
			_detonate(i)
		else:
			# Slow pulse while arming, quick blink once live.
			var blink := 0.75 + 0.25 * sin(now * (16.0 if armed else 5.0) + float(i))
			var grow := minf(age * 6.0, 1.0)
			glow.add_sprite(_mx[i], _my[i], now * 0.9 + float(i), 54.0 * grow, Color(color.r, color.g, color.b, blink), _cell)
		i -= 1


func _detonate(i: int) -> void:
	var a := _a
	var x := _mx[i]
	var y := _my[i]
	_mx.remove_at(i)
	_my.remove_at(i)
	_mage.remove_at(i)
	var radius := _blast * a.player.area
	a.combat.blast(x, y, radius, _damage, src, color, _kb, 0.0, true)
	for k in _cluster:
		var angle := TAU * float(k) / float(_cluster) + a.rng.randf() * 0.8
		a.combat.blast(x + cos(angle) * radius * 0.85, y + sin(angle) * radius * 0.85, radius * 0.62, _damage * 0.5, src, color, _kb * 0.5)


func clear() -> void:
	_mx.clear()
	_my.clear()
	_mage.clear()
