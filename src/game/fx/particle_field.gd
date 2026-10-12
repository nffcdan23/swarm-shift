class_name ParticleField
extends MultiMeshInstance2D
## Ring buffer of stateless GPU particles (see particle.gdshader). `emit`
## writes one instance; nothing is simulated on the CPU afterwards. The buffer
## is only re-uploaded on frames where something was emitted.

const STRIDE := 16

## Scales burst sizes; lowered by the "reduce effects" setting.
var density := 1.0
var emitted := 0

var _buf := PackedFloat32Array()
var _capacity := 0
var _head := 0
var _dirty := false
var _now := 0.0
var _shader_material: ShaderMaterial


func setup(p_capacity: int) -> void:
	_capacity = p_capacity
	_buf.resize(_capacity * STRIDE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = SpriteBatch.quad_mesh()
	mm.instance_count = _capacity
	mm.custom_aabb = AABB(Vector3(-1000000.0, -1000000.0, -1.0), Vector3(2000000.0, 2000000.0, 2.0))
	mm.buffer = _buf
	multimesh = mm
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = load("res://assets/shaders/particle.gdshader")
	material = _shader_material


## Sets the simulation clock particles are measured against.
func set_time(sim_time: float) -> void:
	_now = sim_time


func emit(x: float, y: float, vx: float, vy: float, life: float, size_start: float, size_end: float, color: Color, drag: float = 0.0, stretch: float = 0.0) -> void:
	var o := _head * STRIDE
	_buf[o] = _now
	_buf[o + 1] = vx
	_buf[o + 3] = x
	_buf[o + 4] = life
	_buf[o + 5] = vy
	_buf[o + 7] = y
	_buf[o + 8] = color.r
	_buf[o + 9] = color.g
	_buf[o + 10] = color.b
	_buf[o + 11] = color.a
	_buf[o + 12] = size_start
	_buf[o + 13] = size_end
	_buf[o + 14] = drag
	_buf[o + 15] = stretch
	_head += 1
	if _head >= _capacity:
		_head = 0
	_dirty = true
	emitted += 1


## Radial spray. `arc` narrows it into a cone around `direction`.
func burst(x: float, y: float, amount: int, speed_min: float, speed_max: float, life_min: float, life_max: float,
		size_start: float, size_end: float, color: Color, drag: float = 3.0, stretch: float = 0.0,
		direction: float = 0.0, arc: float = TAU) -> void:
	var n := maxi(int(round(float(amount) * density)), 1)
	for i in n:
		var angle := direction + (randf() - 0.5) * arc
		var speed := randf_range(speed_min, speed_max)
		emit(x, y, cos(angle) * speed, sin(angle) * speed, randf_range(life_min, life_max), size_start, size_end, color, drag, stretch)


func commit() -> void:
	_shader_material.set_shader_parameter("u_time", _now)
	if _dirty:
		multimesh.buffer = _buf
		_dirty = false


func clear() -> void:
	_buf.fill(0.0)
	_head = 0
	_dirty = true
