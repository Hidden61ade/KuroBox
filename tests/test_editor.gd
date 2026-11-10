extends SceneTree
## Exercises authored-document behavior, rather than reproducing puzzle rules.

const Editor = preload("res://features/editor/level_editor.gd")
const Codec = preload("res://core/level_codec.gd")
const State = preload("res://core/board_state.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(960, 640)
	root.content_scale_size = Vector2i(960, 640)
	var editor := Editor.new()
	root.add_child(editor)
	await process_frame
	_expect(editor._board.size.x >= 360 and editor._board.size.y >= 280, "960x640 keeps an editable board visible")
	_expect(editor._board.get_global_rect().end.x <= 960.0, "editor board remains inside the viewport")
	var sound_events: Array[String] = []
	editor.sound_requested.connect(func(event: String): sound_events.append(event))
	var source := _fixture()
	editor.setup(source)
	_expect(Codec.validate(editor.get_level()).is_empty(), "fixture structurally valid")

	# Layers are authored independently. A bad combination is visible to validation.
	editor._palette = "floor"
	editor.paint_rectangle(Rect2i(6, 3, 1, 1), true)
	_expect(editor.document["goals"].has([6, 3]), "erasing floor preserves goal layer")
	_expect(not Codec.validate(editor.get_level()).is_empty(), "missing goal floor is reported")
	editor.undo_edit()
	_expect(editor.get_level() == source, "rectangle undo restores whole document")
	editor.redo_edit()
	_expect(not editor.document["floor"].has([6, 3]), "rectangle redo reapplies edit")
	editor.undo_edit()

	# Copy an internally linked device pair and preserve the source relation.
	editor._selection = Rect2i(2, 2, 2, 1)
	editor.copy_selection()
	editor.paste_clipboard(Vector2i(5, 5))
	var copied_plate: Dictionary = _object_at(editor.document, Vector2i(5, 5))
	var copied_door: Dictionary = _object_at(editor.document, Vector2i(6, 5))
	_expect(copied_plate.get("id", "") != "plate_01", "pasted plate has unique ID")
	_expect(copied_door.get("id", "") != "door_01", "pasted door has unique ID")
	_expect(copied_plate.get("targets", []) == [copied_door.get("id", "")], "copied link targets copied door")
	_expect(editor._find_object("plate_01").get("targets", []) == ["door_01"], "source device link preserved")
	editor.undo_edit()
	_expect(editor.get_level() == source, "paste is one undoable command")

	# An overlapping move keeps IDs and external links after temporary removal.
	editor._selection = Rect2i(2, 2, 2, 1)
	editor.move_selection(Vector2i(3, 2))
	_expect(editor._find_object("plate_01").get("cell", []) == [3, 2], "overlapping region moved")
	_expect(editor._find_object("door_01").get("cell", []) == [4, 2], "overlapping destination preserved")
	_expect(editor._find_object("plate_01").get("targets", []) == ["door_01"], "move retains stable link")
	_expect(Codec.validate(editor.get_level()).is_empty(), "moved document remains valid")
	editor.undo_edit()
	_expect(editor.get_level() == source, "move undo restores all layers")

	var before := editor.get_level()
	editor._selection = Rect2i(2, 2, 2, 1)
	editor.move_selection(Vector2i(9, 7))
	_expect(editor.get_level() == before, "out-of-bounds move rejected atomically")

	# A drag is one command, and flood-fill follows the current layer only.
	editor._palette = "walls"
	editor._begin_edit()
	editor._paint_cell(Vector2i(7, 6), false)
	editor._paint_cell(Vector2i(8, 6), false)
	editor._finish_edit()
	editor.undo_edit()
	_expect(editor.get_level() == source, "stroke undo restores multiple painted cells")
	editor.resize_document(4, 4)
	_expect(int(editor.document["width"]) == 4, "resize applies dimensions")
	_expect(editor._find_object("wood_01").is_empty(), "resize crops outside objects")
	editor.undo_edit()
	_expect(editor.get_level() == source, "resize undo restores cropped objects and goals")

	# A play state receives a deep copy. Neither stepping nor mutating returned data
	# may overwrite the editor's authored initial positions.
	var play_level := editor.get_level()
	var state := State.new()
	state.setup(play_level)
	state.step(Vector2i.RIGHT)
	play_level["objects"][0]["cell"] = [8, 7]
	_expect(editor.get_level() == source, "test snapshot is isolated from authoring")
	_expect(not editor.is_dirty(), "test snapshot does not mark document dirty")
	editor._selection = Rect2i(2, 2, 2, 1)
	var preserved_selection: Rect2i = editor._selection
	editor._request_test()
	_expect(editor._standalone_state != null, "F6 editor starts a standalone play test")
	var right_key := InputEventKey.new()
	right_key.keycode = KEY_RIGHT
	right_key.pressed = true
	editor._handle_standalone_input(right_key)
	editor.resume_after_test()
	_expect(editor.get_level() == source, "return from live test preserves authored document")
	_expect(editor._selection == preserved_selection, "return from test preserves editing selection")

	# Import/export uses the production codec, never a second editor-only schema.
	var export_path := "res://evidence/editor_test_export.kuro.json"
	_expect(Codec.save_file(export_path, editor.get_level()) == OK, "codec exports authored level")
	var imported: Dictionary = Codec.load_file(export_path)
	_expect(Codec.validate(imported).is_empty(), "export can be loaded by production validator")
	var expected_wire: Dictionary = JSON.parse_string(JSON.stringify(source))
	_expect(JSON.stringify(Codec.normalize(imported)) == JSON.stringify(Codec.normalize(expected_wire)), "JSON roundtrip retains content")
	_expect(not editor.is_dirty(), "read-only roundtrip leaves clean document")

	# FileDialog callbacks must retain a valid document after a malformed import.
	editor._file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	editor._file_selected(export_path)
	_expect(editor._path == export_path and not editor.is_dirty(), "successful export commits the saved revision")
	var invalid_path := "user://editor_invalid_import.json"
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("{broken json")
	invalid_file.close()
	editor._file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	editor._file_selected(invalid_path)
	_expect(editor.get_level() == source, "malformed import preserves current document")
	_expect(editor._errors.item_count > 0, "malformed import exposes detailed codec errors")

	# Test actual event boundaries: one drag, one history entry, no lost final cell.
	editor._palette = "walls"
	editor._on_cell_pressed(Vector2i(7, 6), MOUSE_BUTTON_LEFT)
	editor._on_cell_dragged(Vector2i(8, 6), MOUSE_BUTTON_LEFT)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	editor._input(release)
	_expect(editor.document["walls"].has([7, 6]) and editor.document["walls"].has([8, 6]), "drag event retains all painted cells")
	_expect(editor.is_dirty(), "authored stroke marks revision dirty")
	editor.undo_edit()
	_expect(editor.get_level() == source and not editor.is_dirty(), "one undo restores the last exported revision")
	_expect(sound_events.has("place") and sound_events.has("undo"), "editor publishes presentation sound events")
	var exits: Array[bool] = []
	editor.exit_requested.connect(func(): exits.append(true))
	editor.paint_rectangle(Rect2i(7, 6, 1, 1), false)
	editor._pending_action = "exit"
	editor._execute_pending()
	_expect(exits.size() == 1, "confirmed leave emits the shell handoff")
	_expect(editor.get_level() == source and not editor.is_dirty(), "confirmed discard restores the saved revision")

	# Ground devices and solid objects share a cell without sharing authoring layers.
	editor.setup(source)
	editor._palette = "object:wood"
	editor.paint_rectangle(Rect2i(2, 2, 1, 1), false)
	_expect(editor._find_object("plate_01").get("cell", []) == [2, 2], "painting a box preserves the pressure plate beneath it")
	_expect(editor._find_object("plate_01").get("targets", []) == ["door_01"], "painting a box preserves the plate links")
	_expect(editor.document["objects"].size() == 4, "cross-layer painting keeps both object instances")
	_expect(Codec.validate(editor.get_level()).is_empty(), "box-on-plate authored document passes production validation")
	var layered_path := "user://editor_layered.kuro.json"
	_expect(Codec.save_file(layered_path, editor.get_level()) == OK, "layered authoring exports through the production codec")
	var layered_roundtrip: Dictionary = Codec.load_file(layered_path)
	var shared_cell: Array = layered_roundtrip.get("objects", []).filter(func(object: Dictionary): return object.get("cell", []) == [2, 2])
	_expect(shared_cell.size() == 2 and Codec.validate(layered_roundtrip).is_empty(), "export and reload retain both the plate and box in one cell")
	editor.paint_rectangle(Rect2i(2, 2, 1, 1), true)
	_expect(editor._find_object("plate_01").get("cell", []) == [2, 2], "solid-layer eraser leaves pressure plate intact")
	_expect(editor.document["objects"].size() == 3, "solid-layer eraser removes only the box")
	editor.setup(source)
	editor._palette = "object:plate"
	editor.paint_rectangle(Rect2i(4, 3, 1, 1), false)
	_expect(editor._find_object("wood_01").get("cell", []) == [4, 3], "painting a plate preserves the box above it")
	editor._toggle_target(editor._selected_id, "door_01")
	_expect(Codec.validate(editor.get_level()).is_empty(), "plate painted beneath an existing box validates after linking its gate")
	editor.paint_rectangle(Rect2i(4, 3, 1, 1), true)
	_expect(editor._find_object("wood_01").get("cell", []) == [4, 3], "device-layer eraser leaves the box intact")
	editor.setup(source)
	editor._palette = "spawn"
	editor.paint_rectangle(Rect2i(2, 2, 1, 1), false)
	_expect(editor.document["player"] == [2, 2] and not editor._find_object("plate_01").is_empty(), "spawn placement preserves a pressure plate in the same cell")
	_expect(Codec.validate(editor.get_level()).is_empty(), "spawn-on-plate authored document passes production validation")
	editor.undo_edit()
	_expect(editor.get_level() == source, "undo restores spawn and devices together")

	print("EDITOR_TESTS: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _object_at(level: Dictionary, cell: Vector2i) -> Dictionary:
	for object: Dictionary in level.get("objects", []):
		var raw: Array = object.get("cell", [-1, -1])
		if Vector2i(int(raw[0]), int(raw[1])) == cell:
			return object
	return {}


func _fixture() -> Dictionary:
	var floor_cells: Array = []
	for y in range(8):
		for x in range(10):
			floor_cells.append([x, y])
	return Codec.normalize({"schema_version": 1, "id": "editor_fixture", "title": "EDITOR TEST", "width": 10, "height": 8,
		"floor": floor_cells, "walls": [], "goals": [[6, 3]], "player": [1, 1], "facing": [1, 0],
		"objects": [{"id": "wood_01", "type": "wood", "cell": [4, 3], "targets": []},
			{"id": "plate_01", "type": "plate", "cell": [2, 2], "targets": ["door_01"]},
			{"id": "door_01", "type": "door", "cell": [3, 2], "targets": []}],
		"metadata": {"chapter": 1, "hint": "", "solution": []}})
