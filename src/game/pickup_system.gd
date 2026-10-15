class_name PickupSystem
extends RefCounted
## Things on the floor: energy (XP), Credits, and the rare special drops. They
## pop out of a dying enemy, settle, then fly to the player once inside the
## pickup radius. Collection is what feeds the level-up loop, so the vacuum
## must feel generous.

const KIND_XP := 0
const KIND_CREDIT := 1
const KIND_REPAIR := 2
const KIND_MAGNET := 3
const KIND_BOMB := 4
const KIND_CACHE := 5

var count := 0
var collected_xp := 0.0
## Energy put on the field, before the player's gain multiplier. With
## `collected_xp` and `field_xp()` this proves nothing is lost when gems merge.
var dropped_xp := 0.0

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var value := PackedFloat32Array()
var age := PackedFloat32Array()
var size := PackedFloat32Array()
var cell := PackedFloat32Array()
var kind := PackedInt32Array()
var pulled := PackedByteArray()

var _a: Arena
var _batch: SpriteBatch
var _capacity := 0
var _soft_cap := 340
var _credit_cap := 70
var _credit_count := 0
var _collect_r := 26.0
var _magnet_speed := 620.0
var _magnet_accel := 2600.0
var _tiers: Array = []
var _combo := 0
var _combo_timer := 0.0
var _special_cells: Dictionary = {}
var _xp_color := Color("5cffb1")
var _credit_color := Color("ffd15c")


func setup(arena: Arena) -> void:
	_a = arena
	_batch = arena.gfx.pickups
	var cfg := GameData.dict(arena.data.game, "pickups")
	_soft_cap = GameData.integer(arena.data.run_cfg(), "max_pickups", 340)
	_credit_cap = GameData.integer(arena.data.run_cfg(), "max_credit_pickups", 70)
	_capacity = _soft_cap + 24
	_collect_r = GameData.num(cfg, "collect_radius", 26.0)
	_magnet_speed = GameData.num(cfg, "magnet_speed", 620.0)
	_magnet_accel = GameData.num(cfg, "magnet_accel", 2600.0)
	_tiers = GameData.list(cfg, "gem_tiers")
	for arr: PackedFloat32Array in [x, y, vx, vy, value, age, size, cell]:
		arr.resize(_capacity)
	kind.resize(_capacity)
	pulled.resize(_capacity)
	_special_cells = {
		KIND_CREDIT: arena.gfx.cell("credit"), KIND_REPAIR: arena.gfx.cell("repair"),
		KIND_MAGNET: arena.gfx.cell("magnet"), KIND_BOMB: arena.gfx.cell("bomb"), KIND_CACHE: arena.gfx.cell("cache"),
	}


func capacity() -> int:
	return _capacity


func drop_xp(sx: float, sy: float, amount: float) -> void:
	if amount <= 0.0 or not is_finite(amount):
		return
	dropped_xp += amount
	if count >= _soft_cap:
		# Field is saturated: fold the energy into an existing gem instead of
		# losing it. The gem grows a tier if that pushes it over a threshold.
		var target := _find(KIND_XP)
		if target >= 0:
			value[target] += amount
			_style_gem(target)
			_a.diag.pickups_merged += 1
			return
	var i := _add(sx, sy, KIND_XP, amount, 110.0)
	if i >= 0:
		_style_gem(i)
	else:
		# No room and no gem to fold into: hand it over rather than lose it.
		collected_xp += amount * _a.player.xp_gain
		_a.add_xp(amount * _a.player.xp_gain)
		_a.diag.pickups_merged += 1


## Drops anything that is not energy. Nothing the player has earned is ever
## discarded because the field is full: Credits merge into a pile that is
## already there, and a cache or helper takes the place of an energy gem.
func drop(drop_kind: int, sx: float, sy: float, amount: float = 1.0) -> void:
	if drop_kind == KIND_CREDIT and (_credit_count >= _credit_cap or count >= _capacity):
		var pile := _find(KIND_CREDIT)
		_a.diag.pickups_merged += 1
		if pile >= 0:
			value[pile] += amount
			_style_credit(pile)
		else:
			_a.add_credits(amount)
		return
	if count >= _capacity:
		_make_room()
	var i := _add(sx, sy, drop_kind, amount, 150.0)
	if i < 0:
		# Could not free a slot (no energy on the field at all).
		if drop_kind == KIND_CACHE:
			_a.open_cache()
		return
	cell[i] = float(_special_cells.get(drop_kind, 0.0))
	size[i] = 64.0 if drop_kind == KIND_CACHE else 50.0
	if drop_kind == KIND_CREDIT:
		_style_credit(i)


## A pickup of that kind, starting the search at a random slot. -1 if none.
func _find(wanted: int) -> int:
	if count == 0:
		return -1
	var start := _a.rng.randi_range(0, count - 1)
	for k in count:
		var i := (start + k) % count
		if kind[i] == wanted:
			return i
	return -1


## Frees one slot by folding an energy gem into another one.
func _make_room() -> void:
	var victim := _find(KIND_XP)
	if victim < 0:
		return
	var energy := value[victim]
	_remove(victim)
	var into := _find(KIND_XP)
	if into >= 0:
		value[into] += energy
		_style_gem(into)
	else:
		collected_xp += energy * _a.player.xp_gain
		_a.add_xp(energy * _a.player.xp_gain)
	_a.diag.pickups_merged += 1


func _remove(i: int) -> void:
	if kind[i] == KIND_CREDIT:
		_credit_count -= 1
	count -= 1
	var last := count
	x[i] = x[last]
	y[i] = y[last]
	vx[i] = vx[last]
	vy[i] = vy[last]
	value[i] = value[last]
	age[i] = age[last]
	size[i] = size[last]
	cell[i] = cell[last]
	kind[i] = kind[last]
	pulled[i] = pulled[last]


## Energy lying on the field, before the player's gain multiplier.
func field_xp() -> float:
	var total := 0.0
	for i in count:
		if kind[i] == KIND_XP:
			total += value[i]
	return total


## Credits lying on the field, before the player's gain multiplier.
func field_credits() -> float:
	var total := 0.0
	for i in count:
		if kind[i] == KIND_CREDIT:
			total += value[i]
	return total


func _style_credit(i: int) -> void:
	# A bigger pile reads as a bigger coin.
	size[i] = clampf(36.0 + sqrt(maxf(value[i], 0.0)) * 3.0, 38.0, 62.0)


func _add(sx: float, sy: float, drop_kind: int, amount: float, pop: float) -> int:
	if count >= _capacity:
		return -1
	var i := count
	count += 1
	var angle := _a.rng.randf() * TAU
	var burst := _a.rng.randf_range(0.3, 1.0) * pop
	x[i] = sx
	y[i] = sy
	vx[i] = cos(angle) * burst
	vy[i] = sin(angle) * burst
	value[i] = amount
	age[i] = 0.0
	kind[i] = drop_kind
	pulled[i] = 0
	if drop_kind == KIND_CREDIT:
		_credit_count += 1
	return i


func _style_gem(i: int) -> void:
	var chosen: Dictionary = {}
	for tier: Dictionary in _tiers:
		if value[i] >= GameData.num(tier, "min_xp", 1.0):
			chosen = tier
	cell[i] = _a.gfx.cell(GameData.text(chosen, "sprite", "gem_s"))
	size[i] = GameData.num(chosen, "size", 26.0)


## Sends every energy gem on the field to the player.
func magnetise_all() -> void:
	for i in count:
		if kind[i] == KIND_XP or kind[i] == KIND_CREDIT:
			pulled[i] = 1


func update(dt: float) -> void:
	var player := _a.player
	var px := player.x
	var py := player.y
	var pull_r := player.pickup_radius
	var pull_r2 := pull_r * pull_r
	var collect2 := _collect_r * _collect_r
	var now := _a.time
	var buf := _batch.buf
	var o := 0
	var drawn := 0
	_combo_timer -= dt
	if _combo_timer <= 0.0:
		_combo = 0
	var friction := maxf(1.0 - 5.0 * dt, 0.0)
	var i := count - 1
	while i >= 0:
		var gx := x[i]
		var gy := y[i]
		var dx := px - gx
		var dy := py - gy
		var d2 := dx * dx + dy * dy
		var t := age[i] + dt
		age[i] = t
		if pulled[i] == 0 and d2 < pull_r2 and t > 0.18:
			pulled[i] = 1
		if pulled[i] != 0:
			var d := sqrt(d2) + 0.001
			# Accelerate in, with a floor speed so nothing orbits the player.
			var speed := minf(_magnet_speed + _magnet_accel * maxf(t - 0.18, 0.0), 1700.0)
			gx += dx / d * speed * dt
			gy += dy / d * speed * dt
			if d < _collect_r + speed * dt:
				d2 = 0.0
		else:
			gx += vx[i] * dt
			gy += vy[i] * dt
			vx[i] *= friction
			vy[i] *= friction
		if d2 < collect2:
			_collect(i)
			_remove(i)
		else:
			x[i] = gx
			y[i] = gy
			# Pop in with a little overshoot, then breathe.
			var grow := minf(t * 7.0, 1.0)
			var s := size[i] * (grow + 0.25 * sin(grow * PI)) * (1.0 + 0.07 * sin(now * 5.0 + gx * 0.05))
			buf[o] = s
			buf[o + 1] = 0.0
			buf[o + 3] = gx
			buf[o + 4] = 0.0
			buf[o + 5] = s
			buf[o + 7] = gy
			buf[o + 8] = 1.0
			buf[o + 9] = 1.0
			buf[o + 10] = 1.0
			buf[o + 11] = 1.0
			buf[o + 12] = cell[i]
			buf[o + 13] = 0.0
			buf[o + 14] = 1.0
			o += 16
			drawn += 1
		i -= 1
	_batch.count = drawn


func _collect(i: int) -> void:
	var a := _a
	var player := a.player
	match kind[i]:
		KIND_XP:
			var gained := value[i] * player.xp_gain
			collected_xp += gained
			a.add_xp(gained)
			_combo = mini(_combo + 1, 18)
			_combo_timer = 0.3
			a.sfx("pickup_xp", 1.0 + float(_combo) * 0.045)
			a.fx.pickup_pop(player.x, player.y, _xp_color)
		KIND_CREDIT:
			a.add_credits(value[i])
			a.sfx("pickup_credit")
			a.fx.pickup_pop(player.x, player.y, _credit_color)
		KIND_REPAIR:
			var heal := player.max_hp * GameData.num(GameData.dict(a.data.game, "pickups"), "repair_heal_fraction", 0.25)
			player.heal(heal)
			a.sfx("pickup_special")
			a.haptic("medium")
			a.fx.shockwave(player.x, player.y, 120.0, Color("5cff8a"))
		KIND_MAGNET:
			magnetise_all()
			a.sfx("pickup_special")
			a.haptic("medium")
			a.fx.shockwave(player.x, player.y, 420.0, Color("ff4d5e"))
		KIND_BOMB:
			a.sfx("pickup_special")
			a.combat.detonate_bomb()
		KIND_CACHE:
			a.open_cache()


func clear() -> void:
	count = 0
	_credit_count = 0
