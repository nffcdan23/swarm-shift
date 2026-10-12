class_name SpriteBatch
extends MultiMeshInstance2D
## One draw call for up to `capacity` sprites. Systems fill `buf` every frame
## (16 floats per instance) and call `commit()`; there are no per-entity nodes.
##
## Instance layout: 8 floats of 2D transform, 4 of colour, 4 of custom data.
## Hot loops write straight into `buf` and set `count`; everything else can use
## the `add*` helpers.

const STRIDE := 16

var buf := PackedFloat32Array()
var capacity := 0
var count := 0

static var _quad: ArrayMesh


static func quad_mesh() -> ArrayMesh:
	if _quad == null:
		_quad = ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad


static func release() -> void:
	_quad = null


func setup(p_capacity: int, p_material: Material) -> void:
	capacity = p_capacity
	buf.resize(capacity * STRIDE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad_mesh()
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	# Instances move every frame; a fixed, generous bound avoids both the
	# per-frame bounds recompute and any chance of being culled.
	mm.custom_aabb = AABB(Vector3(-1000000.0, -1000000.0, -1.0), Vector3(2000000.0, 2000000.0, 2.0))
	multimesh = mm
	material = p_material


func begin() -> void:
	count = 0


## Rotated sprite from the atlas.
func add_sprite(x: float, y: float, rotation_rad: float, size: float, color: Color, cell: float, span: float = 1.0, extra: float = 0.0) -> void:
	if count >= capacity:
		return
	var o := count * STRIDE
	var c := cos(rotation_rad) * size
	var s := sin(rotation_rad) * size
	buf[o] = c
	buf[o + 1] = -s
	buf[o + 3] = x
	buf[o + 4] = s
	buf[o + 5] = c
	buf[o + 7] = y
	buf[o + 8] = color.r
	buf[o + 9] = color.g
	buf[o + 10] = color.b
	buf[o + 11] = color.a
	buf[o + 12] = cell
	buf[o + 13] = extra
	buf[o + 14] = span
	buf[o + 15] = 0.0
	count += 1


## Sprite stretched between two points (beams, lightning segments).
func add_segment(x0: float, y0: float, x1: float, y1: float, width: float, color: Color, cell: float, extra: float = 0.0) -> void:
	if count >= capacity:
		return
	var dx := x1 - x0
	var dy := y1 - y0
	var length := sqrt(dx * dx + dy * dy)
	if length < 0.001:
		return
	var ux := dx / length
	var uy := dy / length
	var o := count * STRIDE
	buf[o] = ux * length
	buf[o + 1] = -uy * width
	buf[o + 3] = (x0 + x1) * 0.5
	buf[o + 4] = uy * length
	buf[o + 5] = ux * width
	buf[o + 7] = (y0 + y1) * 0.5
	buf[o + 8] = color.r
	buf[o + 9] = color.g
	buf[o + 10] = color.b
	buf[o + 11] = color.a
	buf[o + 12] = cell
	buf[o + 13] = extra
	buf[o + 14] = 1.0
	buf[o + 15] = 0.0
	count += 1


## Unrotated quad with free custom data (ring shader).
func add_raw(x: float, y: float, size: float, color: Color, c0: float, c1: float, c2: float, c3: float) -> void:
	if count >= capacity:
		return
	var o := count * STRIDE
	buf[o] = size
	buf[o + 1] = 0.0
	buf[o + 3] = x
	buf[o + 4] = 0.0
	buf[o + 5] = size
	buf[o + 7] = y
	buf[o + 8] = color.r
	buf[o + 9] = color.g
	buf[o + 10] = color.b
	buf[o + 11] = color.a
	buf[o + 12] = c0
	buf[o + 13] = c1
	buf[o + 14] = c2
	buf[o + 15] = c3
	count += 1


func commit() -> void:
	multimesh.visible_instance_count = count
	if count > 0:
		multimesh.buffer = buf
