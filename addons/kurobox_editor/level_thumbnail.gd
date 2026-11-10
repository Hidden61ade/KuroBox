@tool
extends Control

var level: Dictionary = {}

func set_level(value: Dictionary) -> void:
	level = value.duplicate(true)
	queue_redraw()

func _draw() -> void:
	if level.is_empty():
		return
	var width := maxi(1, int(level.get("width", 8)))
	var height := maxi(1, int(level.get("height", 6)))
	var cell := maxf(1.0, floorf(minf(size.x / width, size.y / height)))
	var origin := ((size - Vector2(width, height) * cell) * 0.5).floor()
	for raw: Array in level.get("floor", []):
		var at := Vector2(int(raw[0]), int(raw[1]))
		draw_rect(Rect2(origin + at * cell, Vector2.ONE * cell), Color("176d4c") if (int(raw[0]) + int(raw[1])) % 2 == 0 else Color("335c62"))
	for raw: Array in level.get("walls", []):
		draw_rect(Rect2(origin + Vector2(raw[0], raw[1]) * cell, Vector2.ONE * cell), Color("7a829a"))
	for raw: Array in level.get("goals", []):
		draw_rect(Rect2(origin + Vector2(raw[0], raw[1]) * cell + Vector2.ONE, Vector2.ONE * maxf(1, cell - 2)), Color("ead48c"), false, 1)
	for item: Dictionary in level.get("objects", []):
		var definition := ObjectCatalog.get_type(str(item.get("type", "")))
		var raw: Array = item.get("cell", [-1,-1])
		var color := Color(str(definition.get("color", "ffffff")))
		draw_rect(Rect2(origin + Vector2(raw[0],raw[1]) * cell + Vector2.ONE, Vector2.ONE * maxf(1,cell-2)), color)
