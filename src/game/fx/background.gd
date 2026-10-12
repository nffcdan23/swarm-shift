class_name ArenaBackground
extends CanvasLayer
## Full-screen procedural floor behind the action (see background.gdshader).
## Also used, without a camera, behind the menus.

var _rect: ColorRect
var _material: ShaderMaterial
var _time := 0.0
var _danger := 0.0
var _danger_target := 0.0


func _init() -> void:
	layer = -10
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/background.gdshader")
	_rect.material = _material
	add_child(_rect)


func set_theme_colors(grid: Color, accent: Color) -> void:
	_material.set_shader_parameter("u_grid", grid)
	_material.set_shader_parameter("u_accent", accent)


func set_detail(high: bool) -> void:
	_material.set_shader_parameter("u_detail", 1.0 if high else 0.0)


## 0..1 red edge wash; eased so it never pops.
func set_danger(amount: float) -> void:
	_danger_target = clampf(amount, 0.0, 1.0)


func track(world_center: Vector2, zoom: float, delta: float) -> void:
	_time += delta
	_danger = lerpf(_danger, _danger_target, 1.0 - exp(-delta * 6.0))
	_material.set_shader_parameter("u_offset", world_center)
	_material.set_shader_parameter("u_zoom", zoom)
	_material.set_shader_parameter("u_time", _time)
	_material.set_shader_parameter("u_danger", _danger)
	_material.set_shader_parameter("u_view", _rect.size)
