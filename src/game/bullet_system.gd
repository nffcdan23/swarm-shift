class_name BulletSystem
extends RefCounted
## Enemy projectiles. Deliberately slow, bright and round so they always read
## as "dodge this" against the player's thin, fast bolts.

var count := 0
## Enemy shots fired since the run began.
var spawned_total := 0

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var life := PackedFloat32Array()
var damage := PackedFloat32Array()

var _a: Arena
var _batch: SpriteBatch
var _capacity := 0
var _radius := 8.0
var _size := 30.0
var _lifetime := 5.0
var _cell := 0.0
var _color := Color(1.0, 0.36, 0.3)


func setup(arena: Arena) -> void:
	_a = arena
	_batch = arena.gfx.bullets
	var cfg := GameData.dict(arena.data.enemies, "bullets")
	_capacity = GameData.integer(cfg, "max", 260)
	_radius = GameData.num(cfg, "radius", 8.0)
	_size = GameData.num(cfg, "size", 30.0)
	_lifetime = GameData.num(cfg, "lifetime", 5.0)
	_cell = arena.gfx.cell("bullet")
	for arr: PackedFloat32Array in [x, y, vx, vy, life, damage]:
		arr.resize(_capacity)


func capacity() -> int:
	return _capacity


func spawn(sx: float, sy: float, svx: float, svy: float, dmg: float) -> void:
	if count >= _capacity:
		return
	var i := count
	count += 1
	spawned_total += 1
	x[i] = sx
	y[i] = sy
	vx[i] = svx
	vy[i] = svy
	life[i] = _lifetime
	damage[i] = dmg


func update(dt: float) -> void:
	var player := _a.player
	var px := player.x
	var py := player.y
	var hit_r := _radius + player.radius * 0.8
	var hit_r2 := hit_r * hit_r
	var pulse := 1.0 + 0.12 * sin(_a.time * 14.0)
	var i := count - 1
	while i >= 0:
		var bx := x[i] + vx[i] * dt
		var by := y[i] + vy[i] * dt
		var left := life[i] - dt
		var dx := bx - px
		var dy := by - py
		var gone := left <= 0.0
		if not gone and dx * dx + dy * dy < hit_r2:
			player.take_hit(damage[i], bx, by)
			_a.fx.spark(bx, by, _color, vx[i], vy[i])
			gone = true
		if gone:
			count -= 1
			var last := count
			x[i] = x[last]
			y[i] = y[last]
			vx[i] = vx[last]
			vy[i] = vy[last]
			life[i] = life[last]
			damage[i] = damage[last]
		else:
			x[i] = bx
			y[i] = by
			life[i] = left
			_batch.add_sprite(bx, by, 0.0, _size * pulse, _color, _cell)
		i -= 1


## Removes bullets inside a circle (shockwaves clear the air). Returns how many.
func clear_circle(cx: float, cy: float, r: float) -> int:
	var removed := 0
	var r2 := r * r
	var i := count - 1
	while i >= 0:
		var dx := x[i] - cx
		var dy := y[i] - cy
		if dx * dx + dy * dy < r2:
			count -= 1
			var last := count
			x[i] = x[last]
			y[i] = y[last]
			vx[i] = vx[last]
			vy[i] = vy[last]
			life[i] = life[last]
			damage[i] = damage[last]
			removed += 1
		i -= 1
	return removed


func clear() -> void:
	count = 0
