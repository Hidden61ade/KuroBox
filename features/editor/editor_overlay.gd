@tool
class_name KuroEditorOverlay
extends Control

const Catalog = preload("res://core/object_catalog.gd")
var editor: Control

func _draw() -> void:
	if editor == null or editor._board == null:
		return
	var view: Control = editor._board
	var selection: Rect2i = editor._selection
	if editor._drag_start.x >= 0 and editor._tool in ["rect", "select"]:
		selection = editor._rect_between(editor._drag_start, editor._drag_cell)
	if selection.has_area():
		var first: Rect2 = view.cell_to_rect(selection.position)
		var last: Rect2 = view.cell_to_rect(selection.end - Vector2i.ONE)
		var box := Rect2(first.position, last.end - first.position)
		draw_rect(box, Color(1.0, 0.84, 0.25, 0.14), true)
		draw_rect(box.grow(-1.0), Color("ffd541"), false, 2.0)
	if editor._focus_cell.x >= 0:
		draw_rect(view.cell_to_rect(editor._focus_cell).grow(-3.0), Color("fff1b8"), false, 3.0)
	for object: Dictionary in editor.document.get("objects", []):
		if str(Catalog.get_type(str(object.get("type", ""))).get("behavior", "")) != "plate":
			continue
		var from: Vector2 = view.cell_to_rect(editor._vec(object.get("cell", [-1, -1]))).get_center()
		for target_id in object.get("targets", []):
			var target: Dictionary = editor._find_object(str(target_id))
			if target.is_empty():
				continue
			var to: Vector2 = view.cell_to_rect(editor._vec(target.get("cell", [-1, -1]))).get_center()
			var color := Color(0.89, 0.68, 0.29, 0.65)
			if str(object.get("id", "")) == editor._selected_id:
				color = Color("fff1b8")
			draw_line(from, to, color, 2.0, true)
			draw_circle(from, 4.0, color)
			draw_circle(to, 4.0, color)
