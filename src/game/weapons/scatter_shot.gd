extends Weapon
## Scatter Shot - a wide cone of short-lived pellets. Huge damage point blank,
## nothing at range, and enough knockback to punch a hole in a closing ring.
##
## It aims the cone, not a pellet: of every way it could point, it picks the one
## that catches the most enemies in range (nearer ones count a little more,
## since the pellets are tighter there). A pack off to one side is hit as a
## pack, rather than the cone centring on the single nearest enemy and missing
## the rest.
##
## Flak Burster: fewer, longer-ranged shells that burst where they land. Slug
## Thrower: a tight cone of heavy slugs for point-blank single-target damage.

var _damage := 7.0
var _cooldown := 1.05
var _projectiles := 5.0
var _pierce := 0
var _speed := 640.0
var _range := 300.0
var _radius := 6.0
var _spread := 0.8
var _kb := 220.0
var _blast := 0.0
var _cell := 0.0
## Enemies under consideration, as (angle from the player, weight). Kept
## between volleys so aiming allocates nothing.
var _seen := PackedVector2Array()

## How far beyond the cone's edge an enemy still counts, as a share of the
## spread: pellets wobble a little and enemies have bodies.
const EDGE_SLACK := 0.15
## How much more an enemy at point blank counts than one at the edge of range.
const NEAR_BONUS := 0.5


func _on_setup() -> void:
	_cell = _a.gfx.cell("pellet")


func _on_stats() -> void:
	_damage = stat("damage")
	_cooldown = stat("cooldown")
	_projectiles = stat("projectiles")
	_pierce = int(stat("pierce"))
	_speed = stat("speed")
	_range = stat("range")
	_radius = stat("radius")
	_spread = deg_to_rad(stat("spread"))
	_kb = stat("knockback")
	_blast = stat("blast_radius", 0.0)


func update(dt: float) -> void:
	_cd -= dt
	if _cd > 0.0:
		return
	var player := _a.player
	var enemies := _a.enemies
	var reach := _range * 1.15
	# Only worth firing when something is close enough to catch the cone.
	var target := acquire(player.x, player.y, reach)
	if target < 0:
		_cd = 0.0
		return
	_cd = maxf(_cd, -0.05) + cooldown_time(_cooldown)
	var aim := group_aim(player.x, player.y, reach, atan2(enemies.y[target] - player.y, enemies.x[target] - player.x))
	var n := shot_count(_projectiles)
	var rng := _a.rng
	for k in n:
		var along := (float(k) + 0.5) / float(n) - 0.5
		var angle := aim + along * _spread + rng.randf_range(-0.04, 0.04)
		fire_bullet(player.x + cos(angle) * 18.0, player.y + sin(angle) * 18.0, angle, _damage,
			_speed * rng.randf_range(0.82, 1.1), _range, _radius, _cell, 76.0 if evolved_shot() else 50.0, _pierce, _kb, 0, _blast)
	_a.fx.flash(player.x + cos(aim) * 30.0, player.y + sin(aim) * 30.0, 90.0, color, 0.09)
	_a.gfx.particles.burst(player.x, player.y, 6, 200.0, 520.0, 0.1, 0.22, 10.0, 1.0, color, 5.0, 2.0, aim, _spread)
	_a.sfx("shoot_scatter")
	player.aim_angle = aim


## The direction that puts the most enemies within `reach` inside the cone, the
## cone centred on the pack it catches. `fallback` (the nearest enemy's
## direction) when there is nothing to choose between.
func group_aim(px: float, py: float, reach: float, fallback: float) -> float:
	var enemies := _a.enemies
	var found := enemies.overlap(px, py, reach)
	if found <= 1:
		return fallback
	_seen.resize(found)
	for h in found:
		var i := enemies.hits[h]
		var dx := enemies.x[i] - px
		var dy := enemies.y[i] - py
		var d := sqrt(dx * dx + dy * dy)
		_seen[h] = Vector2(atan2(dy, dx), 1.0 + NEAR_BONUS * (1.0 - minf(d / reach, 1.0)))
	_seen.sort()
	# Best arc of the cone's width, by a sliding window over the sorted angles.
	# Walking the list twice (the second time a full turn on) covers the arcs
	# that wrap past straight left.
	var width := _spread * (1.0 + EDGE_SLACK)
	var best := -1.0
	var best_from := 0.0
	var best_to := 0.0
	var sum := 0.0
	var tail := 0
	for k in found * 2:
		var head := _seen[k % found]
		var head_angle := head.x + (TAU if k >= found else 0.0)
		sum += head.y
		while true:
			var t := _seen[tail % found]
			var tail_angle := t.x + (TAU if tail >= found else 0.0)
			if head_angle - tail_angle <= width:
				break
			sum -= t.y
			tail += 1
		if k - tail + 1 > found:
			# The window has gone all the way round: everything fits at once.
			break
		if sum > best + 0.0001:
			best = sum
			var from := _seen[tail % found].x + (TAU if tail >= found else 0.0)
			best_from = from
			best_to = head_angle
	if best < 0.0:
		return fallback
	return wrapf((best_from + best_to) * 0.5, -PI, PI)


func evolved_shot() -> bool:
	return not evolution.is_empty()
