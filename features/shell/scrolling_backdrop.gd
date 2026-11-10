class_name ScrollingBackdrop
extends Control
## The original 48px stripe repeat and alpha atmosphere layers, with configurable drift.
@export var drift := Vector2(5.0, 5.0)
var _phase := Vector2.ZERO
var _stripe: Texture2D = preload("res://assets/ui/circuit_stripes.png")
var _pink: Texture2D = preload("res://assets/ui/circuit_background.png")
var _blue: Texture2D = preload("res://assets/ui/circuit_background2.png")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_phase += drift * delta
	_phase = Vector2(fposmod(_phase.x, 48.0), fposmod(_phase.y, 48.0))
	queue_redraw()

func _draw() -> void:
	var scale_factor := maxf(1.0, floorf(minf(size.x / 320.0, size.y / 180.0)))
	var area := size / scale_factor
	draw_set_transform(-_phase * scale_factor, 0.0, Vector2.ONE * scale_factor)
	draw_texture_rect(_stripe, Rect2(-96, -96, area.x + 240, area.y + 240), true)
	draw_set_transform(Vector2.ZERO)
	var center := size * 0.5
	draw_texture_rect(_pink, Rect2(center + Vector2(-160, -38) * scale_factor, Vector2(320, 128) * scale_factor), false, Color(1, 1, 1, 76.0 / 255.0))
	draw_texture_rect(_blue, Rect2(center + Vector2(-160, -90) * scale_factor, Vector2(320, 128) * scale_factor), false, Color(1, 1, 1, 37.0 / 255.0))
