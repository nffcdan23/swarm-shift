class_name ArenaGfx
extends Node2D
## The battlefield's draw layers, bottom to top. Each layer is one draw call no
## matter how much is in it. Gameplay systems write instances into these every
## simulation step between `begin()` and `commit()`.

var atlas: SpriteAtlas

var ground: SpriteBatch        ## alpha-blended: singularities
var ground_glow: SpriteBatch   ## additive: mines, floor glows
var telegraphs: Telegraphs     ## dash lanes, charge lines
var zones: SpriteBatch         ## ring shader: danger zones, arena wall
var pickups: SpriteBatch       ## alpha-blended: energy, credits, drops
var enemies: SpriteBatch       ## alpha-blended: the swarm
var actors: Node2D             ## boss and player nodes
var shots: SpriteBatch         ## additive: player projectiles, blades, drones
var bullets: SpriteBatch       ## additive: enemy fire
var particles: ParticleField   ## additive GPU particles
var beams: SpriteBatch         ## additive: lightning, lasers, flashes
var rings: SpriteBatch         ## ring shader: shockwaves, blasts
var numbers: DamageNumbers

var _cells: Dictionary = {}
var _spans: Dictionary = {}
var _mix: ShaderMaterial
var _add: ShaderMaterial
var _ring: ShaderMaterial


func setup(data: GameData, enemy_capacity: int, pickup_capacity: int, bullet_capacity: int, number_cap: int) -> void:
	atlas = SpriteAtlas.new()
	atlas.build(data)
	for sprite_name: String in GameData.list(data.sprites, "atlas"):
		_cells[sprite_name] = atlas.cell_of(sprite_name)
		_spans[sprite_name] = atlas.span_of(sprite_name)

	_mix = _atlas_material("res://assets/shaders/sprite_mix.gdshader")
	_add = _atlas_material("res://assets/shaders/sprite_add.gdshader")
	_ring = ShaderMaterial.new()
	_ring.shader = load("res://assets/shaders/ring.gdshader")

	ground = _batch("Ground", 24, _mix)
	ground_glow = _batch("GroundGlow", 96, _add)
	telegraphs = Telegraphs.new()
	telegraphs.name = "Telegraphs"
	add_child(telegraphs)
	zones = _batch("Zones", 48, _ring)
	pickups = _batch("Pickups", pickup_capacity + 16, _mix)
	# Elites add an aura instance each, hence the headroom.
	enemies = _batch("Enemies", enemy_capacity + 48, _mix)
	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)
	shots = _batch("Shots", 560, _add)
	bullets = _batch("Bullets", bullet_capacity + 8, _add)
	particles = ParticleField.new()
	particles.name = "Particles"
	add_child(particles)
	particles.setup(3072)
	beams = _batch("Beams", 420, _add)
	rings = _batch("Rings", 96, _ring)
	numbers = DamageNumbers.new()
	numbers.name = "Numbers"
	add_child(numbers)
	numbers.setup(number_cap, null)


func _atlas_material(shader_path: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("atlas", atlas.texture)
	mat.set_shader_parameter("grid", float(atlas.grid))
	return mat


func _batch(node_name: String, capacity: int, mat: Material) -> SpriteBatch:
	var batch := SpriteBatch.new()
	batch.name = node_name
	add_child(batch)
	batch.setup(capacity, mat)
	return batch


func cell(sprite_name: String) -> float:
	return float(_cells.get(sprite_name, 0.0))


func span(sprite_name: String) -> float:
	return float(_spans.get(sprite_name, 1.0))


func begin(sim_time: float) -> void:
	ground.begin()
	ground_glow.begin()
	telegraphs.begin()
	zones.begin()
	pickups.begin()
	enemies.begin()
	shots.begin()
	bullets.begin()
	beams.begin()
	rings.begin()
	particles.set_time(sim_time)


func commit() -> void:
	ground.commit()
	ground_glow.commit()
	telegraphs.commit()
	zones.commit()
	pickups.commit()
	enemies.commit()
	shots.commit()
	bullets.commit()
	beams.commit()
	rings.commit()
	particles.commit()
