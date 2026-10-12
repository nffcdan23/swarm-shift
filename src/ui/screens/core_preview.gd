class_name CorePreview
extends Control
## Animated showcase of the selected core on the home screen: the same sprites
## used in a run, with a few swarmers circling at a wary distance.

var _pivot: Node2D
var _glow: Sprite2D
var _ring: Sprite2D
var _core: Sprite2D
var _swarm: Array[Sprite2D] = []
var _t := 0.0
var _display_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 300)
	_pivot = Node2D.new()
	add_child(_pivot)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/sprites/atlas/glow.png")
	_glow.material = additive
	_pivot.add_child(_glow)

	var swarmer: Texture2D = load("res://assets/sprites/atlas/enemy_swarmer.png")
	for i in 7:
		var s := Sprite2D.new()
		s.texture = swarmer
		s.modulate = Color(1, 1, 1, 0.55)
		_pivot.add_child(s)
		_swarm.append(s)

	_ring = Sprite2D.new()
	_ring.texture = load("res://assets/sprites/player_ring.png")
	_ring.material = additive
	_pivot.add_child(_ring)
	_core = Sprite2D.new()
	_core.texture = load("res://assets/sprites/player_core.png")
	_pivot.add_child(_core)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_pivot.position = size * 0.5
	_display_scale = clampf(size.y / 300.0, 0.6, 1.5)


func set_color(color: Color) -> void:
	_glow.modulate = Color(color.r, color.g, color.b, 0.6)
	_ring.modulate = color
	_core.modulate = color


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var s := _display_scale
	_ring.rotation = _t * 1.2
	_ring.scale = Vector2(0.86, 0.86) * s
	_core.rotation = -_t * 0.4
	_core.scale = Vector2(0.58, 0.58) * s * (1.0 + 0.03 * sin(_t * 3.0))
	_glow.scale = Vector2(4.4, 4.4) * s * (1.0 + 0.06 * sin(_t * 2.0))
	for i in _swarm.size():
		var angle := _t * 0.35 + TAU * float(i) / float(_swarm.size())
		var radius := (168.0 + 14.0 * sin(_t * 1.3 + float(i) * 1.7)) * s
		var sprite := _swarm[i]
		sprite.position = Vector2(cos(angle), sin(angle)) * radius
		# Face along the orbit, nose slightly in towards the core.
		sprite.rotation = angle + PI * 0.5 + 0.35
		sprite.scale = Vector2(0.36, 0.36) * s
