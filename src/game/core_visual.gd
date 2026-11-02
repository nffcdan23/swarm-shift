class_name CoreVisual
extends Node2D
## The player's core as a stack of animated layers, built from a skin's `visual`
## block in meta.json: a glow, an optional aura, orbiting armour plates, a ring,
## the body, a pulsing reactor and a few motes of light.
##
## The same node draws the core in a run, in the lobby and in the Arsenal, so a
## skin looks the same everywhere. It is decoration only: nothing here reads the
## simulation or its random numbers, and nothing in the simulation reads it. The
## hit radius belongs to PlayerUnit and never depends on the skin.
##
## Layer sizes are in units of the body: scale the node to size the whole core.

const BODY_SIZE := 256.0

var _body: Sprite2D
var _glow: Sprite2D
var _ring: Sprite2D
var _aura: Sprite2D
var _reactor: Sprite2D
var _plates: Array[Sprite2D] = []
var _motes: Array[Sprite2D] = []
var _flash_material: ShaderMaterial
var _additive: CanvasItemMaterial

var _t := 0.0
var _body_spin := -0.63
var _ring_spin := 1.8
var _ring_scale := 1.48
var _aura_spin := 0.0
var _aura_scale := 1.0
var _plate_radius := 1.0
var _plate_speed := 0.6
var _plate_wobble := 0.0
var _plate_scale := 0.3
var _mote_radius := 1.5
var _mote_speed := 1.6
var _glow_scale := 6.3
var _pulse := 6.0
var _reactor_scale := 0.2
var _widen := 1.0


## Rebuilds the layers for `skin`. `core_color` is what a skin with no colour of
## its own is tinted with (the factory skin takes the core's colour).
func build(skin: Dictionary, core_color: Color) -> void:
	for child in get_children():
		child.queue_free()
	_plates.clear()
	_motes.clear()
	_aura = null
	_reactor = null
	_additive = CanvasItemMaterial.new()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var main := GameData.color(skin, "color", core_color)
	var v := GameData.dict(skin, "visual")

	var glow := GameData.dict(v, "glow")
	_glow = _sprite("res://assets/sprites/atlas/glow.png", true)
	var glow_color := GameData.color(glow, "color", main)
	_glow.modulate = Color(glow_color.r, glow_color.g, glow_color.b, GameData.num(glow, "alpha", 0.55))
	_glow_scale = GameData.num(glow, "scale", 6.3)
	_pulse = GameData.num(glow, "pulse", 6.0)

	var aura := GameData.dict(v, "aura")
	if not aura.is_empty():
		_aura = _sprite("res://assets/sprites/skins/%s.png" % GameData.text(aura, "sprite"), true)
		var aura_color := GameData.color(aura, "color", main)
		_aura.modulate = Color(aura_color.r, aura_color.g, aura_color.b, GameData.num(aura, "alpha", 0.8))
		_aura_scale = GameData.num(aura, "scale", 2.0)
		_aura.scale = Vector2.ONE * _aura_scale
		_aura_spin = GameData.num(aura, "speed", 0.4)

	var ring := GameData.dict(v, "ring")
	var ring_sprite := GameData.text(ring, "sprite")
	_ring = _sprite("res://assets/sprites/player_ring.png" if ring_sprite.is_empty() else "res://assets/sprites/skins/%s.png" % ring_sprite, true)
	_ring.modulate = GameData.color(ring, "color", main)
	_ring_spin = GameData.num(ring, "speed", 1.8)
	_ring_scale = GameData.num(ring, "scale", 1.48)

	var plates := GameData.dict(v, "plates")
	if not plates.is_empty():
		var texture := "res://assets/sprites/skins/%s.png" % GameData.text(plates, "sprite")
		var plate_color := GameData.color(plates, "color", main)
		_plate_radius = GameData.num(plates, "radius", 1.0) * BODY_SIZE * 0.5
		_plate_speed = GameData.num(plates, "speed", 0.6)
		_plate_wobble = GameData.num(plates, "wobble", 0.0)
		_plate_scale = GameData.num(plates, "scale", 0.5)
		for k in GameData.integer(plates, "count", 4):
			var plate := _sprite(texture, false)
			plate.modulate = plate_color
			plate.scale = Vector2.ONE * _plate_scale
			_plates.append(plate)

	var body_name := GameData.text(v, "body")
	_body = _sprite("res://assets/sprites/player_core.png" if body_name.is_empty() else "res://assets/sprites/skins/%s.png" % body_name, false)
	# A full-colour body keeps its own colours; the factory one is tinted.
	_body.modulate = main if body_name.is_empty() else Color.WHITE
	_body_spin = GameData.num(v, "spin", -0.63)
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = load("res://assets/shaders/flash.gdshader")
	_body.material = _flash_material

	var reactor := GameData.dict(v, "reactor")
	_reactor = _sprite("res://assets/sprites/atlas/orb.png", true)
	_reactor.modulate = Color(GameData.color(reactor, "color", Color.WHITE), GameData.num(reactor, "alpha", 0.9))
	_reactor_scale = GameData.num(reactor, "scale", 0.89)

	var motes := GameData.dict(v, "motes")
	if not motes.is_empty():
		var mote_color := GameData.color(motes, "color", main)
		_mote_radius = GameData.num(motes, "radius", 1.5) * BODY_SIZE * 0.5
		_mote_speed = GameData.num(motes, "speed", 1.6)
		for k in GameData.integer(motes, "count", 3):
			var mote := _sprite("res://assets/sprites/atlas/orb.png", true)
			mote.modulate = mote_color
			mote.scale = Vector2.ONE * 0.55
			_motes.append(mote)
	animate(0.0)


func _sprite(path: String, additive: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	if additive:
		sprite.material = _additive
	add_child(sprite)
	return sprite


## Advances the animation. `widen` spreads the ring (Phase Shift in a run).
func animate(delta: float, widen: float = 1.0) -> void:
	_t += delta
	_widen = widen
	_glow.scale = Vector2.ONE * _glow_scale * (1.0 + 0.06 * sin(_t * _pulse))
	_body.rotation = _t * _body_spin
	_ring.rotation = _t * _ring_spin
	_ring.scale = Vector2.ONE * _ring_scale * _widen
	_reactor.scale = Vector2.ONE * _reactor_scale * (1.0 + 0.16 * sin(_t * _pulse))
	if _aura != null:
		_aura.rotation = _t * _aura_spin
		_aura.scale = Vector2.ONE * _aura_scale * (1.0 + 0.04 * sin(_t * 2.1))
	var plate_count := float(_plates.size())
	for k in _plates.size():
		var angle := _t * _plate_speed + TAU * float(k) / plate_count
		var radius := _plate_radius * (1.0 + _plate_wobble * sin(_t * 2.6 + float(k) * 1.9))
		_plates[k].position = Vector2.from_angle(angle) * radius
		_plates[k].rotation = angle + PI * 0.5
	var mote_count := float(_motes.size())
	for k in _motes.size():
		var angle := _t * _mote_speed + TAU * float(k) / mote_count
		_motes[k].position = Vector2.from_angle(angle) * _mote_radius * (1.0 + 0.12 * sin(_t * 3.3 + float(k)))


## Lights the body up when the core takes a hit.
func set_flash(amount: float) -> void:
	_flash_material.set_shader_parameter("flash", amount)


## Tints an already-built core (a skin with no colour of its own).
func set_tint(color: Color) -> void:
	_ring.modulate = color
	_body.modulate = color
	_glow.modulate = Color(color.r, color.g, color.b, 0.55)
