class_name SpriteAtlas
extends RefCounted
## Packs the individual sprite PNGs listed in sprites.json into one texture at
## startup, so the whole battlefield draws from a single atlas while the source
## art stays as separate, replaceable files.
##
## Layout is a uniform grid. A sprite the size of one cell takes one cell; a
## sprite twice that size takes a 2x2 block. Instances address a sprite by its
## top-left cell index plus span.

const DIR := "res://assets/sprites/atlas/"

var texture: ImageTexture
var grid := 8
var cell := 128

var _cell_index: Dictionary = {}
var _span: Dictionary = {}


func build(data: GameData) -> void:
	cell = GameData.integer(data.sprites, "cell", 128)
	grid = GameData.integer(data.sprites, "grid", 8)
	var names: Array = GameData.list(data.sprites, "atlas")
	var sheet := Image.create_empty(grid * cell, grid * cell, false, Image.FORMAT_RGBA8)
	var used := PackedByteArray()
	used.resize(grid * grid)

	var images: Dictionary = {}
	for sprite_name: String in names:
		images[sprite_name] = _load_image(sprite_name)

	# Large sprites first so they can claim aligned 2x2 blocks.
	for pass_span: int in [2, 1]:
		for sprite_name: String in names:
			var img: Image = images[sprite_name]
			var span := 2 if (img != null and img.get_width() > cell) else 1
			if span != pass_span:
				continue
			var slot := _claim(used, span)
			if slot < 0:
				push_error("SpriteAtlas: no room for '%s' - raise 'grid' in sprites.json" % sprite_name)
				continue
			_cell_index[sprite_name] = float(slot)
			_span[sprite_name] = float(span)
			if img == null:
				continue
			var target := span * cell
			if img.get_width() != target or img.get_height() != target:
				img.resize(target, target, Image.INTERPOLATE_LANCZOS)
			@warning_ignore("integer_division")
			sheet.blit_rect(img, Rect2i(0, 0, target, target), Vector2i((slot % grid) * cell, (slot / grid) * cell))
	sheet.generate_mipmaps()
	texture = ImageTexture.create_from_image(sheet)


func _load_image(sprite_name: String) -> Image:
	var path := DIR + sprite_name + ".png"
	if not ResourceLoader.exists(path):
		push_error("SpriteAtlas: missing " + path)
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _claim(used: PackedByteArray, span: int) -> int:
	var step := span
	for cy in range(0, grid - span + 1, step):
		for cx in range(0, grid - span + 1, step):
			var free := true
			for dy in span:
				for dx in span:
					if used[(cy + dy) * grid + cx + dx] != 0:
						free = false
			if free:
				for dy in span:
					for dx in span:
						used[(cy + dy) * grid + cx + dx] = 1
				return cy * grid + cx
	return -1


func cell_of(sprite_name: String) -> float:
	return float(_cell_index.get(sprite_name, 0.0))


func span_of(sprite_name: String) -> float:
	return float(_span.get(sprite_name, 1.0))


func has(sprite_name: String) -> bool:
	return _cell_index.has(sprite_name)
