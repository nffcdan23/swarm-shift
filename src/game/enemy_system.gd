class_name EnemySystem
extends RefCounted
## Every enemy in the run, stored as parallel packed arrays (one array per
## field, one index per enemy) instead of one node each. A single loop per step
## does AI, movement, crowd separation, player contact and writes the draw
## instance - which is what lets several hundred enemies stay cheap in GDScript.
##
## Rules for callers:
##  - An index is only valid for the current step. Keep `id[i]` if you need to
##    refer to an enemy later, and re-validate with `is_valid()`.
##  - Kills are deferred: `hurt()` marks an enemy dead and `sweep()` compacts
##    the arrays once at the end of the step. Skip anything with hp <= 0.
##  - `overlap()` returns its results in the shared `hits` scratch array, so do
##    not start another overlap query while still iterating a previous one.

const AI_SEEK := 0
const AI_DASHER := 1
const AI_SHOOTER := 2
const AI_NONE := 3
const AI_MORTAR := 4     ## keeps its distance and shells where the player is heading
const AI_WEAVER := 5     ## circles in from the side instead of running straight at you
const AI_BOMBER := 6     ## runs in, plants itself and detonates after a short fuse

const F_ELITE := 1
const F_BIG := 2
const F_HEAVY := 4       ## immune to knockback, pulls, chill and freeze
const F_ARMORED := 8
const F_VOLATILE := 16
const F_SPAWNER := 32
const F_BOSS := 64
const F_NO_DROPS := 128
const F_HIDDEN := 256    ## drawn by something else (the boss)

## Enemies wider than this live in the small `big` list as well as the grid.
const SMALL_RADIUS := 24.0
const GRID_CELL := 64.0
const GRID_COLS := 56
const GRID_ROWS := 72
## Extra query reach to cover one step of movement since the grid was built.
const QUERY_PAD := 10.0

var count := 0
var capacity := 0

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var kx := PackedFloat32Array()
var ky := PackedFloat32Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var radius := PackedFloat32Array()
var speed := PackedFloat32Array()
var damage := PackedFloat32Array()
var inv_mass := PackedFloat32Array()
var flash := PackedFloat32Array()
var chill := PackedFloat32Array()
var freeze := PackedFloat32Array()
var timer := PackedFloat32Array()
var aux := PackedFloat32Array()
var dir_x := PackedFloat32Array()
var dir_y := PackedFloat32Array()
var blade_cd := PackedFloat32Array()
var phase := PackedFloat32Array()
var size := PackedFloat32Array()
var cell := PackedFloat32Array()
var span := PackedFloat32Array()
var xp := PackedFloat32Array()
var type := PackedInt32Array()
var ai := PackedInt32Array()
var flags := PackedInt32Array()
var state := PackedInt32Array()
var id := PackedInt32Array()

## Scratch output of `overlap()`.
var hits := PackedInt32Array()

## Set by the director each step.
var hp_mult := 1.0
var damage_mult := 1.0
var speed_mult := 1.0

## Per-step outputs.
var touch_damage := 0.0
var nearest_idx := -1
var nearest_dist := INF
var killed_total := 0
## Dasher charges begun since the run began.
var dashes_total := 0

var type_ids: Array[String] = []
var type_defs: Array[Dictionary] = []
var type_colors: Array[Color] = []

var _a: Arena
var _batch: SpriteBatch
var _type_index: Dictionary = {}
var _t_ai := PackedInt32Array()
var _t_wobble := PackedFloat32Array()
var _t_directional := PackedByteArray()
var _tp_a := PackedFloat32Array()
var _tp_b := PackedFloat32Array()
var _tp_c := PackedFloat32Array()
var _tp_d := PackedFloat32Array()
var _tp_e := PackedFloat32Array()
var _tp_f := PackedFloat32Array()
var _tp_g := PackedFloat32Array()
var _tp_h := PackedFloat32Array()

var _elite_cfg: Dictionary
var _affixes: Dictionary
var _separation := 0.55
var _kb_decay := 7.0
var _chill_factor := 0.55
var _recycle_dist := 1500.0
var _armored_mult := 0.6
var _aura_cell := 0.0
var _aura_span := 2.0

var _grid_head := PackedInt32Array()
var _grid_next := PackedInt32Array()
var _grid_ox := 0.0
var _grid_oy := 0.0
var _frame := 0
var _last_px := 0.0
var _last_py := 0.0
var _big := PackedInt32Array()
var _big_count := 0
var _dead := PackedInt32Array()
var _dead_count := 0
var _next_id := 1
var _pending_spawns: Array[Dictionary] = []


func setup(arena: Arena, p_capacity: int) -> void:
	_a = arena
	_batch = arena.gfx.enemies
	capacity = p_capacity
	for arr: PackedFloat32Array in [x, y, kx, ky, hp, max_hp, radius, speed, damage, inv_mass, flash, chill, freeze, timer, aux, dir_x, dir_y, blade_cd, phase, size, cell, span, xp]:
		arr.resize(capacity)
	for arr: PackedInt32Array in [type, ai, flags, state, id, hits, _grid_next, _dead]:
		arr.resize(capacity)
	_big.resize(capacity)
	_grid_head.resize(GRID_COLS * GRID_ROWS)
	# -1 terminates every cell list. A zero-filled grid would read as "enemy 0
	# links to enemy 0" and spin forever on the first query.
	_grid_head.fill(-1)
	_grid_next.fill(-1)

	var data := arena.data
	var behaviour := GameData.dict(data.enemies, "behaviour")
	_separation = GameData.num(behaviour, "separation_strength", 0.55)
	_kb_decay = GameData.num(behaviour, "knockback_decay", 7.0)
	_chill_factor = 1.0 - GameData.num(behaviour, "chill_slow", 0.45)
	_recycle_dist = GameData.num(behaviour, "recycle_distance", 1500.0)
	_elite_cfg = GameData.dict(data.enemies, "elite")
	_affixes = GameData.dict(_elite_cfg, "affixes")
	_armored_mult = GameData.num(GameData.dict(_affixes, "armored"), "damage_taken_mult", 0.6)
	_aura_cell = arena.gfx.cell("elite_aura")
	_aura_span = arena.gfx.span("elite_aura")

	var types := data.enemy_types()
	for type_id: String in types:
		var def: Dictionary = types[type_id]
		_type_index[type_id] = type_ids.size()
		type_ids.append(type_id)
		type_defs.append(def)
		type_colors.append(GameData.color(def, "color", Color.WHITE))
		var ai_name := GameData.text(def, "ai", "seek")
		var params := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		var ai_code := AI_SEEK
		var directional := 0
		if ai_name == "dasher":
			ai_code = AI_DASHER
			directional = 1
			var dash := GameData.dict(def, "dash")
			params = PackedFloat32Array([GameData.num(dash, "trigger_range", 320.0), GameData.num(dash, "telegraph", 0.5),
				GameData.num(dash, "speed", 560.0), GameData.num(dash, "duration", 0.45), GameData.num(dash, "cooldown", 2.6), 0.0, 0.0, 0.0])
		elif ai_name == "shooter":
			ai_code = AI_SHOOTER
			directional = 1
			var shoot := GameData.dict(def, "shoot")
			params = PackedFloat32Array([GameData.num(shoot, "range", 420.0), GameData.num(shoot, "keep_min", 270.0),
				GameData.num(shoot, "cooldown", 2.4), GameData.num(shoot, "telegraph", 0.35),
				GameData.num(shoot, "bullet_speed", 250.0), GameData.num(shoot, "bullet_damage", 12.0), 0.0, 0.0])
		elif ai_name == "mortar":
			ai_code = AI_MORTAR
			directional = 1
			var lob := GameData.dict(def, "lob")
			params = PackedFloat32Array([GameData.num(lob, "range", 520.0), GameData.num(lob, "keep_min", 330.0),
				GameData.num(lob, "cooldown", 3.6), GameData.num(lob, "windup", 0.5),
				GameData.num(lob, "flight", 1.15), GameData.num(lob, "blast_radius", 92.0),
				GameData.num(lob, "damage", 16.0), GameData.num(lob, "lead", 0.35)])
		elif ai_name == "weaver":
			ai_code = AI_WEAVER
			directional = 1
			var weave := GameData.dict(def, "weave")
			params = PackedFloat32Array([GameData.num(weave, "orbit_range", 300.0), GameData.num(weave, "inward", 0.38),
				GameData.num(weave, "strike_range", 120.0), GameData.num(weave, "strike_speed", 1.15), 0.0, 0.0, 0.0, 0.0])
		elif ai_name == "bomber":
			ai_code = AI_BOMBER
			var bomb := GameData.dict(def, "bomb")
			params = PackedFloat32Array([GameData.num(bomb, "trigger_range", 105.0), GameData.num(bomb, "fuse", 0.75),
				GameData.num(bomb, "blast_radius", 118.0), GameData.num(bomb, "damage", 22.0), 0.0, 0.0, 0.0, 0.0])
		elif type_id == "swarmer":
			directional = 1
		_t_ai.append(ai_code)
		_t_wobble.append(GameData.num(def, "wobble", 0.0))
		_t_directional.append(directional)
		_tp_a.append(params[0])
		_tp_b.append(params[1])
		_tp_c.append(params[2])
		_tp_d.append(params[3])
		_tp_e.append(params[4])
		_tp_f.append(params[5])
		_tp_g.append(params[6])
		_tp_h.append(params[7])


func type_of(type_id: String) -> int:
	return int(_type_index.get(type_id, -1))


# ---------------------------------------------------------------------- spawn

func spawn(type_idx: int, sx: float, sy: float, elite: bool = false, affix: String = "", extra_flags: int = 0) -> int:
	if count >= capacity or type_idx < 0:
		return -1
	var i := count
	count += 1
	var def := type_defs[type_idx]
	var rng := _a.rng
	var r := GameData.num(def, "radius", 14.0)
	var health := GameData.num(def, "hp", 10.0) * hp_mult
	var dmg := GameData.num(def, "damage", 8.0) * damage_mult
	var spd := GameData.num(def, "speed", 100.0) * speed_mult * rng.randf_range(0.93, 1.07)
	var sprite_size := GameData.num(def, "size", r * 3.2)
	var xp_value := GameData.num(def, "xp", 1.0)
	var mass := maxf(GameData.num(def, "mass", 1.0), 0.05)
	var f := extra_flags
	if elite:
		f |= F_ELITE
		r *= GameData.num(_elite_cfg, "size_mult", 1.35)
		sprite_size *= GameData.num(_elite_cfg, "size_mult", 1.35)
		health *= GameData.num(_elite_cfg, "hp_mult", 7.0)
		dmg *= GameData.num(_elite_cfg, "damage_mult", 1.4)
		spd *= GameData.num(_elite_cfg, "speed_mult", 1.05)
		xp_value *= GameData.num(_elite_cfg, "xp_mult", 10.0)
		mass *= 4.0
		match affix:
			"swift":
				spd *= GameData.num(GameData.dict(_affixes, "swift"), "speed_mult", 1.5)
			"armored":
				f |= F_ARMORED
			"volatile":
				f |= F_VOLATILE
			"spawner":
				f |= F_SPAWNER
	if r > SMALL_RADIUS:
		f |= F_BIG
	if mass >= 20.0:
		f |= F_HEAVY
	x[i] = sx
	y[i] = sy
	kx[i] = 0.0
	ky[i] = 0.0
	hp[i] = health
	max_hp[i] = health
	radius[i] = r
	speed[i] = spd
	damage[i] = dmg
	inv_mass[i] = 1.0 / mass
	flash[i] = 0.0
	chill[i] = 0.0
	freeze[i] = 0.0
	timer[i] = rng.randf_range(0.4, 1.6)
	aux[i] = GameData.num(GameData.dict(_affixes, "spawner"), "spawn_interval", 2.2)
	dir_x[i] = 1.0
	dir_y[i] = 0.0
	blade_cd[i] = 0.0
	phase[i] = rng.randf() * TAU
	size[i] = sprite_size
	var sprite := GameData.text(def, "sprite")
	cell[i] = _a.gfx.cell(sprite)
	span[i] = _a.gfx.span(sprite)
	xp[i] = xp_value
	type[i] = type_idx
	ai[i] = _t_ai[type_idx]
	flags[i] = f
	state[i] = 0
	id[i] = _next_id
	_next_id += 1
	return i


## Turns an already-spawned enemy into an externally driven one (the boss).
func make_boss(i: int, health: float, contact_damage: float, body_radius: float) -> void:
	hp[i] = health
	max_hp[i] = health
	damage[i] = contact_damage
	radius[i] = body_radius
	ai[i] = AI_NONE
	flags[i] = F_BOSS | F_BIG | F_HEAVY | F_HIDDEN
	inv_mass[i] = 0.0


func queue_spawn(type_id: String, sx: float, sy: float, amount: int, scatter: float) -> void:
	_pending_spawns.append({"type": type_of(type_id), "x": sx, "y": sy, "n": amount, "scatter": scatter})


func _flush_spawns() -> void:
	if _pending_spawns.is_empty():
		return
	for entry in _pending_spawns:
		for k in int(entry.n):
			var angle := _a.rng.randf() * TAU
			var dist := _a.rng.randf() * float(entry.scatter)
			spawn(int(entry.type), float(entry.x) + cos(angle) * dist, float(entry.y) + sin(angle) * dist)
	_pending_spawns.clear()


# --------------------------------------------------------------------- update

func update(dt: float) -> void:
	var a := _a
	var player := a.player
	var px := player.x
	var py := player.y
	var pr := player.radius
	var now := a.time
	_frame += 1
	_last_px = px
	_last_py = py
	_rebuild_grid(px, py)

	# Locals: member access in the hot loop is measurably slower.
	var ax := x
	var ay := y
	var akx := kx
	var aky := ky
	var aradius := radius
	var aspeed := speed
	var adamage := damage
	var aflash := flash
	var achill := chill
	var afreeze := freeze
	var atimer := timer
	var aphase := phase
	var asize := size
	var acell := cell
	var aspan := span
	var atype := type
	var aai := ai
	var aflags := flags
	var astate := state
	var nxt := _grid_next
	var wobble_t := _t_wobble
	var directional_t := _t_directional
	var buf := _batch.buf

	var kb_keep := maxf(1.0 - _kb_decay * dt, 0.0)
	var chill_factor := _chill_factor
	var sep := _separation
	var recycle2 := _recycle_dist * _recycle_dist
	var best_edge := INF
	var best_i := -1
	var touch := 0.0
	var push_x := 0.0
	var push_y := 0.0
	var o := 0
	var n := count

	for i in n:
		var ex := ax[i]
		var ey := ay[i]
		var dx := px - ex
		var dy := py - ey
		var d2 := dx * dx + dy * dy
		var d := sqrt(d2) + 0.0001
		var nx := dx / d
		var ny := dy / d
		var f := aflags[i]
		var spd := aspeed[i]
		var mvx := 0.0
		var mvy := 0.0
		var face_x := nx
		var face_y := ny
		var pulse := 0.0
		var t_idx := atype[i]

		var slow := 1.0
		var frozen := afreeze[i]
		var chilled := achill[i]
		if frozen > 0.0:
			afreeze[i] = frozen - dt
			slow = 0.0
		elif chilled > 0.0:
			achill[i] = chilled - dt
			slow = chill_factor

		var mode := aai[i]
		if mode == AI_SEEK:
			var wob := wobble_t[t_idx]
			if wob > 0.0:
				pulse = sin(now * 3.1 + aphase[i])
				var w := pulse * wob
				face_x = nx - ny * w
				face_y = ny + nx * w
			mvx = face_x * spd
			mvy = face_y * spd
		elif mode == AI_DASHER:
			var st := astate[i]
			var tm := atimer[i] - dt * (1.0 if slow > 0.0 else 0.0)
			if st == 0:
				mvx = nx * spd
				mvy = ny * spd
				if tm <= 0.0 and d < _tp_a[t_idx]:
					st = 1
					tm = _tp_b[t_idx]
					dir_x[i] = nx
					dir_y[i] = ny
					dashes_total += 1
					a.sfx("dash_warn")
			elif st == 1:
				face_x = dir_x[i]
				face_y = dir_y[i]
				var reach := _tp_c[t_idx] * _tp_d[t_idx]
				var progress := 1.0 - tm / _tp_b[t_idx]
				a.gfx.telegraphs.lane(ex, ey, ex + face_x * reach, ey + face_y * reach, aradius[i] * 2.0, type_colors[t_idx], progress)
				aflash[i] = maxf(aflash[i], 0.25 + 0.45 * progress)
				if tm <= 0.0:
					st = 2
					tm = _tp_d[t_idx]
			else:
				face_x = dir_x[i]
				face_y = dir_y[i]
				mvx = face_x * _tp_c[t_idx]
				mvy = face_y * _tp_c[t_idx]
				if (_frame + i) % 3 == 0:
					a.gfx.particles.emit(ex, ey, -mvx * 0.1, -mvy * 0.1, 0.25, 16.0, 2.0, type_colors[t_idx], 2.0)
				if tm <= 0.0:
					st = 0
					tm = _tp_e[t_idx]
			astate[i] = st
			atimer[i] = tm
		elif mode == AI_SHOOTER:
			var st := astate[i]
			var tm := atimer[i] - dt * (1.0 if slow > 0.0 else 0.0)
			if st == 1:
				aflash[i] = maxf(aflash[i], 0.5)
				if tm <= 0.0:
					a.bullets.spawn(ex + nx * aradius[i], ey + ny * aradius[i], nx * _tp_e[t_idx], ny * _tp_e[t_idx], _tp_f[t_idx] * damage_mult)
					a.sfx("enemy_shoot")
					st = 0
					tm = _tp_c[t_idx] * a.rng.randf_range(0.85, 1.15)
			else:
				var reach := _tp_a[t_idx]
				if d > reach:
					mvx = nx * spd
					mvy = ny * spd
				elif d < _tp_b[t_idx]:
					mvx = -nx * spd * 0.8
					mvy = -ny * spd * 0.8
				else:
					var side := 1.0 if aphase[i] > PI else -1.0
					mvx = -ny * spd * 0.6 * side
					mvy = nx * spd * 0.6 * side
				if tm <= 0.0 and d < reach * 1.15:
					st = 1
					tm = _tp_d[t_idx]
			astate[i] = st
			atimer[i] = tm
		elif mode == AI_MORTAR:
			var st := astate[i]
			var tm := atimer[i] - dt * (1.0 if slow > 0.0 else 0.0)
			if st == 1:
				# Winding up: it glows, then the shell is already on its way.
				aflash[i] = maxf(aflash[i], 0.6)
				if tm <= 0.0:
					# Aimed a little ahead of the player, so neither standing still
					# nor running in a straight line is the answer - a turn is.
					var lead := _tp_h[t_idx]
					a.hazards.add(px + player.velocity.x * lead, py + player.velocity.y * lead, _tp_f[t_idx], _tp_e[t_idx],
						_tp_g[t_idx] * damage_mult, type_colors[t_idx], ex, ey)
					a.sfx("enemy_shoot", 0.7)
					st = 0
					tm = _tp_c[t_idx] * a.rng.randf_range(0.85, 1.15)
			else:
				var reach := _tp_a[t_idx]
				if d > reach:
					mvx = nx * spd
					mvy = ny * spd
				elif d < _tp_b[t_idx]:
					mvx = -nx * spd * 0.9
					mvy = -ny * spd * 0.9
				else:
					var side := 1.0 if aphase[i] > PI else -1.0
					mvx = -ny * spd * 0.45 * side
					mvy = nx * spd * 0.45 * side
				if tm <= 0.0 and d < reach * 1.1:
					st = 1
					tm = _tp_d[t_idx]
			astate[i] = st
			atimer[i] = tm
		elif mode == AI_WEAVER:
			if d < _tp_c[t_idx]:
				# Close enough: commit to the strike.
				mvx = nx * spd * _tp_d[t_idx]
				mvy = ny * spd * _tp_d[t_idx]
			else:
				# Circle in. Far out it mostly closes the distance; inside its
				# orbit it mostly slides sideways, arriving from the flank.
				var side := 1.0 if aphase[i] > PI else -1.0
				var inward := _tp_b[t_idx] if d < _tp_a[t_idx] else 0.78
				var wx := -ny * side * (1.0 - inward) + nx * inward
				var wy := nx * side * (1.0 - inward) + ny * inward
				var wl := sqrt(wx * wx + wy * wy) + 0.0001
				face_x = wx / wl
				face_y = wy / wl
				mvx = face_x * spd
				mvy = face_y * spd
		elif mode == AI_BOMBER:
			if astate[i] == 0:
				pulse = sin(now * 5.0 + aphase[i])
				mvx = nx * spd
				mvy = ny * spd
				if d < _tp_a[t_idx]:
					# Plant and arm. The blast circle is the telegraph: it shows
					# exactly where not to be and how long there is to leave.
					astate[i] = 1
					atimer[i] = _tp_b[t_idx]
					a.hazards.add(ex, ey, _tp_c[t_idx], _tp_b[t_idx], _tp_d[t_idx] * damage_mult, type_colors[t_idx])
					a.sfx("dash_warn", 1.3)
			else:
				var fuse := atimer[i] - dt
				atimer[i] = fuse
				aflash[i] = maxf(aflash[i], 0.35 + 0.65 * absf(sin(now * 26.0)))
				if fuse <= 0.0:
					expire(i)

		var kvx := akx[i]
		var kvy := aky[i]
		ex += (mvx * slow + kvx) * dt
		ey += (mvy * slow + kvy) * dt
		if kvx != 0.0 or kvy != 0.0:
			akx[i] = kvx * kb_keep
			aky[i] = kvy * kb_keep

		# Crowd separation against the rest of this enemy's grid cell.
		var my_r := aradius[i]
		var j := nxt[i]
		while j >= 0:
			var ox := ex - ax[j]
			var oy := ey - ay[j]
			var rr := my_r + aradius[j]
			var od2 := ox * ox + oy * oy
			if od2 < rr * rr and od2 > 0.0001:
				var od := sqrt(od2)
				var shove := (rr - od) / od * 0.5 * sep
				ox *= shove
				oy *= shove
				if (f & F_HEAVY) == 0:
					ex += ox
					ey += oy
				if (aflags[j] & F_HEAVY) == 0:
					ax[j] -= ox
					ay[j] -= oy
			j = nxt[j]

		# Contact with the player.
		var touch_r := my_r + pr
		if d2 < touch_r * touch_r:
			if (f & F_HEAVY) != 0:
				# Immovable things shove the player instead.
				push_x += nx * (touch_r - d)
				push_y += ny * (touch_r - d)
			else:
				ex = px - nx * touch_r
				ey = py - ny * touch_r
			if adamage[i] > touch:
				touch = adamage[i]
		elif d2 > recycle2 and (f & (F_ELITE | F_BOSS)) == 0:
			# Left far behind: bring it back around so the pressure never thins out.
			var fresh := a.director.spawn_point()
			ex = fresh.x
			ey = fresh.y
		ax[i] = ex
		ay[i] = ey
		# Nearest by edge, not centre, so large bodies are targeted fairly.
		var edge := d - my_r
		if edge < best_edge:
			best_edge = edge
			best_i = i

		if (f & F_SPAWNER) != 0:
			var left := aux[i] - dt
			if left <= 0.0:
				var brood := GameData.dict(_affixes, "spawner")
				left = GameData.num(brood, "spawn_interval", 2.2)
				queue_spawn(GameData.text(brood, "spawn_enemy", "swarmer"), ex, ey, GameData.integer(brood, "spawn_count", 3), my_r + 20.0)
			aux[i] = left

		var fl := aflash[i]
		if fl > 0.0:
			aflash[i] = maxf(fl - dt * 7.0, 0.0)

		# Draw instance.
		var sz := asize[i]
		var cs: float
		var sn: float
		if (f & F_HIDDEN) != 0:
			cs = 0.0
			sn = 0.0
		elif directional_t[t_idx] != 0:
			sz *= 1.0 + pulse * 0.07
			cs = face_x * sz
			sn = face_y * sz
		else:
			var spin := now * 0.7 + aphase[i]
			cs = cos(spin) * sz
			sn = sin(spin) * sz
		buf[o] = cs
		buf[o + 1] = -sn
		buf[o + 3] = ex
		buf[o + 4] = sn
		buf[o + 5] = cs
		buf[o + 7] = ey
		if frozen > 0.0:
			buf[o + 8] = 0.5
			buf[o + 9] = 0.8
			buf[o + 10] = 1.0
		elif chilled > 0.0:
			buf[o + 8] = 0.72
			buf[o + 9] = 0.9
			buf[o + 10] = 1.0
		elif (f & F_ELITE) != 0:
			buf[o + 8] = 1.0
			buf[o + 9] = 0.92
			buf[o + 10] = 0.62
		else:
			buf[o + 8] = 1.0
			buf[o + 9] = 1.0
			buf[o + 10] = 1.0
		buf[o + 11] = 1.0
		buf[o + 12] = acell[i]
		buf[o + 13] = fl
		buf[o + 14] = aspan[i]
		o += 16

	_batch.count = n
	touch_damage = touch
	nearest_idx = best_i
	nearest_dist = maxf(best_edge, 0.0) if best_i >= 0 else INF
	if push_x != 0.0 or push_y != 0.0:
		player.nudge(-push_x, -push_y)

	_separate_big()
	_draw_auras(now)
	_flush_spawns()


func _rebuild_grid(px: float, py: float) -> void:
	# Alternate a half-cell shift so pairs split by a cell edge still meet.
	var shift := GRID_CELL * 0.5 if (_frame & 1) == 1 else 0.0
	_grid_ox = floorf(px / GRID_CELL) * GRID_CELL - float(GRID_COLS) * GRID_CELL * 0.5 + shift
	_grid_oy = floorf(py / GRID_CELL) * GRID_CELL - float(GRID_ROWS) * GRID_CELL * 0.5 + shift
	var head := _grid_head
	var nxt := _grid_next
	head.fill(-1)
	var ax := x
	var ay := y
	var aflags := flags
	var big := _big
	var bigs := 0
	var inv := 1.0 / GRID_CELL
	var gox := _grid_ox
	var goy := _grid_oy
	var max_cx := GRID_COLS - 1
	var max_cy := GRID_ROWS - 1
	for i in count:
		var cx := int((ax[i] - gox) * inv)
		var cy := int((ay[i] - goy) * inv)
		if cx < 0:
			cx = 0
		elif cx > max_cx:
			cx = max_cx
		if cy < 0:
			cy = 0
		elif cy > max_cy:
			cy = max_cy
		var c := cy * GRID_COLS + cx
		nxt[i] = head[c]
		head[c] = i
		if (aflags[i] & F_BIG) != 0:
			big[bigs] = i
			bigs += 1
	_big_count = bigs


## Large bodies push the small ones out of themselves (the grid pass only
## handles neighbours that share a cell).
func _separate_big() -> void:
	for b in _big_count:
		var bi := _big[b]
		if hp[bi] <= 0.0:
			continue
		var bx := x[bi]
		var by := y[bi]
		var br := radius[bi]
		var found := overlap(bx, by, br * 0.92)
		for h in found:
			var j := hits[h]
			if j == bi or (flags[j] & F_BIG) != 0:
				continue
			var ox := x[j] - bx
			var oy := y[j] - by
			var od := sqrt(ox * ox + oy * oy) + 0.001
			var want := br * 0.92 + radius[j]
			if od < want:
				var shove := (want - od) / od * 0.6
				x[j] += ox * shove
				y[j] += oy * shove


func _draw_auras(now: float) -> void:
	for i in count:
		if (flags[i] & F_ELITE) == 0 or (flags[i] & F_HIDDEN) != 0:
			continue
		var pulse := 1.0 + 0.06 * sin(now * 5.0 + phase[i])
		_batch.add_sprite(x[i], y[i], now * 0.8 + phase[i], size[i] * 1.5 * pulse, Color(1.0, 0.9, 0.55, 0.9), _aura_cell, _aura_span)


# --------------------------------------------------------------------- damage

## Applies damage and knockback. Returns true if this killed the enemy.
func hurt(i: int, amount: float, kb_x: float = 0.0, kb_y: float = 0.0) -> bool:
	var health := hp[i]
	if health <= 0.0:
		return false
	var f := flags[i]
	if (f & F_ARMORED) != 0:
		amount *= _armored_mult
	health -= amount
	flash[i] = 1.0
	if (f & F_HEAVY) == 0:
		kx[i] += kb_x * inv_mass[i]
		ky[i] += kb_y * inv_mass[i]
	if health <= 0.0:
		hp[i] = -1.0
		_dead[_dead_count] = i
		_dead_count += 1
		killed_total += 1
		_a.combat.on_enemy_killed(i)
		return true
	hp[i] = health
	return false


## Removes an enemy that destroyed itself (a Bomber going off). Not a kill:
## nothing is dropped and the player's kill count is untouched.
func expire(i: int) -> void:
	if hp[i] <= 0.0:
		return
	hp[i] = -1.0
	_dead[_dead_count] = i
	_dead_count += 1
	_a.fx.death(x[i], y[i], type_colors[type[i]], radius[i])


## Slows an enemy; `freeze_time` > 0 also stops it dead.
func apply_cold(i: int, chill_time: float, freeze_time: float = 0.0) -> void:
	if (flags[i] & F_HEAVY) != 0:
		chill_time *= 0.5
		freeze_time = 0.0
	if chill_time > chill[i]:
		chill[i] = chill_time
	if freeze_time > freeze[i]:
		freeze[i] = freeze_time


func is_cold(i: int) -> bool:
	return chill[i] > 0.0 or freeze[i] > 0.0


## Removes everything killed this step. Call once, at the end of the step.
func sweep() -> void:
	if _dead_count == 0:
		return
	var dead := _dead.slice(0, _dead_count)
	dead.sort()
	for k in range(dead.size() - 1, -1, -1):
		var i := dead[k]
		count -= 1
		var last := count
		if i == last:
			continue
		x[i] = x[last]
		y[i] = y[last]
		kx[i] = kx[last]
		ky[i] = ky[last]
		hp[i] = hp[last]
		max_hp[i] = max_hp[last]
		radius[i] = radius[last]
		speed[i] = speed[last]
		damage[i] = damage[last]
		inv_mass[i] = inv_mass[last]
		flash[i] = flash[last]
		chill[i] = chill[last]
		freeze[i] = freeze[last]
		timer[i] = timer[last]
		aux[i] = aux[last]
		dir_x[i] = dir_x[last]
		dir_y[i] = dir_y[last]
		blade_cd[i] = blade_cd[last]
		phase[i] = phase[last]
		size[i] = size[last]
		cell[i] = cell[last]
		span[i] = span[last]
		xp[i] = xp[last]
		type[i] = type[last]
		ai[i] = ai[last]
		flags[i] = flags[last]
		state[i] = state[last]
		id[i] = id[last]
	_dead_count = 0
	# Indices moved, so rebuild the grid: queries made between steps (level-up
	# shockwave, revive blast) must still see the survivors.
	nearest_idx = -1
	_rebuild_grid(_last_px, _last_py)


# -------------------------------------------------------------------- queries

func is_valid(i: int, enemy_id: int) -> bool:
	return i >= 0 and i < count and id[i] == enemy_id and hp[i] > 0.0


func find_id(enemy_id: int) -> int:
	for i in count:
		if id[i] == enemy_id:
			return i
	return -1


## Fills `hits` with living enemies touching the circle; returns how many.
func overlap(cx: float, cy: float, r: float) -> int:
	var found := 0
	var reach := r + SMALL_RADIUS + QUERY_PAD
	var inv := 1.0 / GRID_CELL
	var x0 := clampi(int((cx - reach - _grid_ox) * inv), 0, GRID_COLS - 1)
	var x1 := clampi(int((cx + reach - _grid_ox) * inv), 0, GRID_COLS - 1)
	var y0 := clampi(int((cy - reach - _grid_oy) * inv), 0, GRID_ROWS - 1)
	var y1 := clampi(int((cy + reach - _grid_oy) * inv), 0, GRID_ROWS - 1)
	var head := _grid_head
	var nxt := _grid_next
	var ax := x
	var ay := y
	var aradius := radius
	var ahp := hp
	var aflags := flags
	var out := hits
	for gy in range(y0, y1 + 1):
		var row := gy * GRID_COLS
		for gx in range(x0, x1 + 1):
			var i := head[row + gx]
			while i >= 0:
				if (aflags[i] & F_BIG) == 0 and ahp[i] > 0.0:
					var dx := ax[i] - cx
					var dy := ay[i] - cy
					var rr := r + aradius[i]
					if dx * dx + dy * dy <= rr * rr:
						out[found] = i
						found += 1
				i = nxt[i]
	for b in _big_count:
		var i := _big[b]
		if ahp[i] <= 0.0:
			continue
		var dx := ax[i] - cx
		var dy := ay[i] - cy
		var rr := r + aradius[i]
		if dx * dx + dy * dy <= rr * rr:
			out[found] = i
			found += 1
	return found


## Closest living enemy within `max_range` of a point, or -1.
func nearest(cx: float, cy: float, max_range: float, skip_id: int = -1) -> int:
	var best := -1
	var best_d2 := max_range * max_range
	var ax := x
	var ay := y
	var ahp := hp
	for i in count:
		if ahp[i] <= 0.0:
			continue
		var dx := ax[i] - cx
		var dy := ay[i] - cy
		var d2 := dx * dx + dy * dy
		if d2 < best_d2 and id[i] != skip_id:
			best_d2 = d2
			best = i
	return best


## A random living enemy within range (for weapons that should spread fire).
func random_in_range(cx: float, cy: float, max_range: float) -> int:
	if count == 0:
		return -1
	var r2 := max_range * max_range
	var start := _a.rng.randi_range(0, count - 1)
	for k in mini(count, 24):
		var i := (start + k * 7) % count
		if hp[i] <= 0.0:
			continue
		var dx := x[i] - cx
		var dy := y[i] - cy
		if dx * dx + dy * dy <= r2:
			return i
	return nearest(cx, cy, max_range)


## Pushes every non-heavy enemy within `r` directly away from a point.
func repel(cx: float, cy: float, r: float, force: float) -> void:
	var found := overlap(cx, cy, r)
	for h in found:
		var i := hits[h]
		if (flags[i] & F_HEAVY) != 0:
			continue
		var dx := x[i] - cx
		var dy := y[i] - cy
		var d := sqrt(dx * dx + dy * dy) + 0.001
		var falloff := 1.0 - minf(d / (r + radius[i]), 1.0) * 0.5
		kx[i] += dx / d * force * falloff * inv_mass[i]
		ky[i] += dy / d * force * falloff * inv_mass[i]


func alive_count() -> int:
	return count - _dead_count


func clear() -> void:
	count = 0
	_dead_count = 0
	_big_count = 0
	_grid_head.fill(-1)
	_pending_spawns.clear()
	nearest_idx = -1
