class_name ProjectileSystem
extends RefCounted
## The player's projectiles: bolts, pellets, missiles, drone shots, ice shards.
## One packed-array pool for all of them; behaviour differences are flags.

const F_HOMING := 1       ## hard homing on a target (missiles)
const F_SEEK := 2         ## gentle curve towards the nearest enemy (Seeker Rounds)
const F_EXPLODE := 4      ## blast on impact or expiry
const F_SPLIT := 8        ## splits in two after its first hit
const F_NO_CRIT := 16
const F_BLAST_ONLY := 32  ## all damage comes from the blast, none from the impact
const F_TRAIL := 64       ## leaves an exhaust trail

const CAPACITY := 520

var count := 0
var fired_total := 0

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var life := PackedFloat32Array()
var damage := PackedFloat32Array()
var hit_radius := PackedFloat32Array()
var size := PackedFloat32Array()
var cell := PackedFloat32Array()
var blast := PackedFloat32Array()
var turn := PackedFloat32Array()
var knockback := PackedFloat32Array()
var seek_cd := PackedFloat32Array()
var col_r := PackedFloat32Array()
var col_g := PackedFloat32Array()
var col_b := PackedFloat32Array()
var pierce := PackedInt32Array()
var flags := PackedInt32Array()
var last_hit := PackedInt32Array()
var target_idx := PackedInt32Array()
var target_id := PackedInt32Array()
var source := PackedInt32Array()

var _a: Arena
var _batch: SpriteBatch


func setup(arena: Arena) -> void:
	_a = arena
	_batch = arena.gfx.shots
	for arr: PackedFloat32Array in [x, y, vx, vy, life, damage, hit_radius, size, cell, blast, turn, knockback, seek_cd, col_r, col_g, col_b]:
		arr.resize(CAPACITY)
	for arr: PackedInt32Array in [pierce, flags, last_hit, target_idx, target_id, source]:
		arr.resize(CAPACITY)


func spawn(sx: float, sy: float, svx: float, svy: float, dmg: float, lifetime: float, radius: float,
		sprite_cell: float, sprite_size: float, color: Color, pierce_count: int, flag_bits: int,
		kb: float, source_id: int, blast_radius: float = 0.0, turn_rate: float = 0.0) -> int:
	if count >= CAPACITY:
		return -1
	var i := count
	count += 1
	fired_total += 1
	x[i] = sx
	y[i] = sy
	vx[i] = svx
	vy[i] = svy
	life[i] = lifetime
	damage[i] = dmg
	hit_radius[i] = radius
	size[i] = sprite_size
	cell[i] = sprite_cell
	blast[i] = blast_radius
	turn[i] = turn_rate
	knockback[i] = kb
	seek_cd[i] = 0.0
	col_r[i] = color.r
	col_g[i] = color.g
	col_b[i] = color.b
	pierce[i] = pierce_count
	flags[i] = flag_bits
	last_hit[i] = -1
	target_idx[i] = -1
	target_id[i] = -1
	source[i] = source_id
	return i


func update(dt: float) -> void:
	var a := _a
	var enemies := a.enemies
	var combat := a.combat
	var buf := _batch.buf
	var o := _batch.count * SpriteBatch.STRIDE
	var drawn := _batch.count
	var room := _batch.capacity
	var seek_turn := combat.seeker_turn
	var i := count - 1
	while i >= 0:
		var fl := flags[i]
		var bx := x[i]
		var by := y[i]
		var bvx := vx[i]
		var bvy := vy[i]
		var left := life[i] - dt

		if (fl & (F_HOMING | F_SEEK)) != 0:
			var ti := target_idx[i]
			if not enemies.is_valid(ti, target_id[i]):
				ti = -1
				seek_cd[i] -= dt
				if seek_cd[i] <= 0.0:
					seek_cd[i] = 0.14
					if (fl & F_HOMING) != 0:
						ti = enemies.random_in_range(bx, by, 560.0)
					else:
						ti = enemies.nearest(bx, by, 250.0, last_hit[i])
					target_idx[i] = ti
					target_id[i] = enemies.id[ti] if ti >= 0 else -1
			if ti >= 0:
				var speed := sqrt(bvx * bvx + bvy * bvy)
				var heading := atan2(bvy, bvx)
				var want := atan2(enemies.y[ti] - by, enemies.x[ti] - bx)
				var rate := turn[i] if (fl & F_HOMING) != 0 else seek_turn
				heading += clampf(wrapf(want - heading, -PI, PI), -rate * dt, rate * dt)
				if (fl & F_HOMING) != 0:
					speed = minf(speed * (1.0 + 1.6 * dt), 980.0)
				bvx = cos(heading) * speed
				bvy = sin(heading) * speed

		bx += bvx * dt
		by += bvy * dt
		var gone := left <= 0.0
		var struck := -1
		var found := enemies.overlap(bx, by, hit_radius[i])
		if found > 0:
			var skip := last_hit[i]
			for h in found:
				var e := enemies.hits[h]
				if enemies.id[e] != skip:
					struck = e
					break
		if struck >= 0:
			var struck_id := enemies.id[struck]
			var speed := sqrt(bvx * bvx + bvy * bvy) + 0.001
			var ux := bvx / speed
			var uy := bvy / speed
			var color := Color(col_r[i], col_g[i], col_b[i])
			a.fx.spark(bx, by, color, ux, uy)
			if (fl & F_EXPLODE) != 0:
				combat.blast(bx, by, blast[i], damage[i] if (fl & F_BLAST_ONLY) != 0 else damage[i] * combat.explosive_pct,
					source[i], color, knockback[i])
			if (fl & F_BLAST_ONLY) == 0:
				combat.hit(struck, damage[i], source[i], ux * knockback[i], uy * knockback[i], (fl & F_NO_CRIT) == 0)
			if (fl & F_SPLIT) != 0:
				_split(i, bx, by, bvx, bvy, left, struck_id)
				fl &= ~F_SPLIT
				flags[i] = fl
			if pierce[i] > 0:
				pierce[i] -= 1
				last_hit[i] = struck_id
				target_idx[i] = -1
			else:
				gone = true
		elif gone and (fl & F_EXPLODE) != 0 and (fl & F_BLAST_ONLY) != 0:
			# A missile that ran out of fuel still goes off.
			combat.blast(bx, by, blast[i], damage[i], source[i], Color(col_r[i], col_g[i], col_b[i]), knockback[i])

		if gone:
			count -= 1
			var last := count
			if i != last:
				x[i] = x[last]
				y[i] = y[last]
				vx[i] = vx[last]
				vy[i] = vy[last]
				life[i] = life[last]
				damage[i] = damage[last]
				hit_radius[i] = hit_radius[last]
				size[i] = size[last]
				cell[i] = cell[last]
				blast[i] = blast[last]
				turn[i] = turn[last]
				knockback[i] = knockback[last]
				seek_cd[i] = seek_cd[last]
				col_r[i] = col_r[last]
				col_g[i] = col_g[last]
				col_b[i] = col_b[last]
				pierce[i] = pierce[last]
				flags[i] = flags[last]
				last_hit[i] = last_hit[last]
				target_idx[i] = target_idx[last]
				target_id[i] = target_id[last]
				source[i] = source[last]
		else:
			x[i] = bx
			y[i] = by
			vx[i] = bvx
			vy[i] = bvy
			life[i] = left
			if (fl & F_TRAIL) != 0 and (i + a.step_count) % 2 == 0:
				a.gfx.particles.emit(bx, by, -bvx * 0.08, -bvy * 0.08, 0.3, 13.0, 2.0, Color(col_r[i], col_g[i], col_b[i], 0.8), 2.0)
			if drawn < room:
				var speed := sqrt(bvx * bvx + bvy * bvy) + 0.001
				var s := size[i]
				# Shrink away in the last moments rather than vanishing.
				if left < 0.08:
					s *= left / 0.08
				var cs := bvx / speed * s
				var sn := bvy / speed * s
				buf[o] = cs
				buf[o + 1] = -sn
				buf[o + 3] = bx
				buf[o + 4] = sn
				buf[o + 5] = cs
				buf[o + 7] = by
				buf[o + 8] = col_r[i]
				buf[o + 9] = col_g[i]
				buf[o + 10] = col_b[i]
				buf[o + 11] = 1.0
				buf[o + 12] = cell[i]
				buf[o + 13] = 0.0
				buf[o + 14] = 1.0
				o += 16
				drawn += 1
		i -= 1
	_batch.count = drawn


func _split(i: int, bx: float, by: float, bvx: float, bvy: float, left: float, struck_id: int) -> void:
	var heading := atan2(bvy, bvx)
	var speed := sqrt(bvx * bvx + bvy * bvy)
	var color := Color(col_r[i], col_g[i], col_b[i])
	var child_flags := flags[i] & ~(F_SPLIT | F_HOMING)
	for side: float in [-0.5, 0.5]:
		var child := spawn(bx, by, cos(heading + side) * speed, sin(heading + side) * speed,
			damage[i] * _a.combat.split_pct, maxf(left * 0.8, 0.0) + 0.18, hit_radius[i] * 0.85,
			cell[i], size[i] * 0.78, color, 0, child_flags, knockback[i] * 0.6, source[i], blast[i] * 0.8, turn[i])
		if child >= 0:
			last_hit[child] = struck_id


func clear() -> void:
	count = 0
