extends Weapon
## Arc Caster - instant lightning that jumps between enemies, losing a little
## power with each jump. Best against tightly packed swarms.

var _damage := 14.0
var _cooldown := 1.3
var _chains := 3
var _range := 380.0
var _jump := 190.0
var _falloff := 0.88
var _forks := 1

var _visited := PackedInt32Array()


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_chains = int(stat("chains"))
	_range = stat("range")
	_jump = stat("jump_range")
	_falloff = stat("falloff")
	_forks = maxi(int(stat("forks")), 1)


func update(dt: float) -> void:
	_cd -= dt
	if _cd > 0.0:
		return
	var a := _a
	var player := a.player
	var enemies := a.enemies
	var first := acquire(player.x, player.y, _range)
	if first < 0:
		_cd = 0.0
		return
	_cd = cooldown_time(_cooldown)
	_visited.clear()
	_cast(first, player.x, player.y)
	for fork in range(1, _forks):
		var other := enemies.random_in_range(player.x, player.y, _range)
		if other >= 0 and not _visited.has(enemies.id[other]) and enemies.hp[other] > 0.0:
			_cast(other, player.x, player.y)
	a.sfx("lightning")


func _cast(start: int, from_x: float, from_y: float) -> void:
	var a := _a
	var enemies := a.enemies
	var current := start
	var fx_x := from_x
	var fx_y := from_y
	var dmg := _damage
	var reach := _jump * a.player.area
	for jump in _chains + 1:
		var ex := enemies.x[current]
		var ey := enemies.y[current]
		_visited.append(enemies.id[current])
		a.fx.lightning(fx_x, fx_y, ex, ey, color, 12.0 if jump == 0 else 9.0)
		a.combat.hit(current, dmg, src)
		dmg *= _falloff
		fx_x = ex
		fx_y = ey
		# Next link: the closest enemy near this one that has not been struck.
		var found := enemies.overlap(ex, ey, reach)
		var best := -1
		var best_d2 := INF
		for h in found:
			var e := enemies.hits[h]
			if _visited.has(enemies.id[e]):
				continue
			var dx := enemies.x[e] - ex
			var dy := enemies.y[e] - ey
			var d2 := dx * dx + dy * dy
			if d2 < best_d2:
				best_d2 = d2
				best = e
		if best < 0:
			return
		current = best
