class_name Telegraphs
extends Node2D
## Ground warnings: dash lanes, boss charge lines, laser sweeps. Immediate mode -
## callers re-submit a shape every frame it should be visible. There are only
## ever a handful, so plain canvas drawing is the right tool.

var _lines := PackedFloat32Array()
var _line_colors: Array[Color] = []
var _had_content := false


func begin() -> void:
	_lines.clear()
	_line_colors.clear()


## A lane from (x0,y0) to (x1,y1). `progress` 0..1 brightens it as the attack nears.
func lane(x0: float, y0: float, x1: float, y1: float, width: float, color: Color, progress: float) -> void:
	_lines.append_array(PackedFloat32Array([x0, y0, x1, y1, width, progress]))
	_line_colors.append(color)


func commit() -> void:
	if _line_colors.is_empty() and not _had_content:
		return
	_had_content = not _line_colors.is_empty()
	queue_redraw()


func _draw() -> void:
	for i in _line_colors.size():
		var o := i * 6
		var a := Vector2(_lines[o], _lines[o + 1])
		var b := Vector2(_lines[o + 2], _lines[o + 3])
		var width := _lines[o + 4]
		var progress := _lines[o + 5]
		var color := _line_colors[i]
		# Wide faint body that fills in, plus a crisp centre line.
		draw_line(a, b, Color(color.r, color.g, color.b, 0.07 + 0.2 * progress), width)
		draw_line(a, b, Color(color.r, color.g, color.b, 0.35 + 0.5 * progress), maxf(width * 0.08, 2.0))
