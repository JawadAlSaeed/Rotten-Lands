class_name RingLayer
extends Control
## Draws the training rings (DESIGN.md 3.7): circles that shrink onto a target and close exactly
## at impact. The TimedSequenceRunner sets them every frame in HUD canvas pixels.

const LABEL_SIZE: int = 30
const LABEL_OUTLINE: int = 8
const LABEL_GAP: float = 10.0
const SEGMENTS: int = 64

## Each ring: {pos: Vector2, radius: float, color: Color, label: String}.
var _rings: Array[Dictionary] = []
var _width: float = 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_rings(rings: Array[Dictionary], width: float) -> void:
	if rings.is_empty() and _rings.is_empty():
		return
	_rings = rings
	_width = width
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for ring: Dictionary in _rings:
		var pos: Vector2 = ring.pos
		var radius := float(ring.radius)
		var color: Color = ring.color
		draw_arc(pos, radius + _width * 0.5, 0.0, TAU, SEGMENTS, HudStyle.OUTLINE_COLOR, _width * 0.5, true)
		draw_arc(pos, radius, 0.0, TAU, SEGMENTS, color, _width, true)
		var text := String(ring.get("label", ""))
		if text.is_empty():
			continue
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var at := pos + Vector2(-text_size.x * 0.5, -radius - LABEL_GAP)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_OUTLINE, HudStyle.OUTLINE_COLOR)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
