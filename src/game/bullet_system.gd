class_name BulletSystem
extends RefCounted
## Enemy projectiles. Deliberately slow, bright and round so they always read
## as "dodge this" against the player's thin, fast bolts.
##
## They are drawn on the arena's topmost layer (`gfx.hostile`) with normal
## blending, using a sprite no other object shares: a dark outline, a red body
## and a white-hot centre. The red body's edge is the hit radius exactly
## (`size` is four times `radius`), so a shot that looks like it missed did.
## A short, faint trail in the additive layer shows which way each one moves.
## (Before October 2026 they were small additive red dots on a layer below
## particles and explosions: invisible over red enemies and any blast.)

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
var _trail_cell := 0.0
var _color := Color(1.0, 0.36, 0.3)
var _hostile: SpriteBatch


func setup(arena: Arena) -> void:
	_a = arena
	_batch = arena.gfx.bullets
	var cfg := GameData.dict(arena.data.enemies, "bullets")
	_capacity = GameData.integer(cfg, "max", 260)
	_radius = GameData.num(cfg, "radius", 8.0)
	_size = GameData.num(cfg, "size", 32.0)
	_lifetime = GameData.num(cfg, "lifetime", 5.0)
	_cell = arena.gfx.cell("hostile")
	_trail_cell = arena.gfx.cell("glow")
	_hostile = arena.gfx.hostile
	for arr: PackedFloat32Array in [x, y, vx, vy, life, damage]:
		arr.resize(_capacity)


func capacity() -> int:
	return _capacity


## Collision radius of a bullet (the player's own radius is added separately).
func hit_radius() -> float:
	return _radius


## Drawn diameter of the sprite; its solid body spans half of it.
func draw_size() -> float:
	return _size


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
			# Trail: two faint glows behind, along the line of travel.
			_batch.add_sprite(bx - vx[i] * 0.05, by - vy[i] * 0.05, 0.0, _size * 0.8, Color(_color.r, _color.g, _color.b, 0.35), _trail_cell)
			_batch.add_sprite(bx - vx[i] * 0.1, by - vy[i] * 0.1, 0.0, _size * 0.55, Color(_color.r, _color.g, _color.b, 0.18), _trail_cell)
			_hostile.add_sprite(bx, by, 0.0, _size, Color.WHITE, _cell)
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
