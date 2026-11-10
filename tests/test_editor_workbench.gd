extends SceneTree

const Editor = preload("res://features/editor/level_editor.gd")
const Catalog = preload("res://core/object_catalog.gd")
const Codec = preload("res://core/level_codec.gd")
const Proof = preload("res://core/replay_proof.gd")

var checks := 0
var failures: Array[String] = []
var transactions: Array[Dictionary] = []
var selections: Array[String] = []
var proofs: Array[Dictionary] = []
var summaries: Array[Dictionary] = []
var debug_rows: Array[Dictionary] = []
var history_requests := {"undo": 0, "redo": 0, "save": 0, "sound": 0, "external_test": 0}


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1100, 760)
	root.content_scale_size = root.size
	var editor := Editor.new()
	editor.embedded_mode = true
	editor.native_inspector = true
	editor.use_external_history = true
	editor.document_changed.connect(func(before: Dictionary, after: Dictionary, label: String): transactions.append({"before": before, "after": after, "label": label}))
	editor.selection_changed.connect(func(instance_id: String): selections.append(instance_id))
	editor.proof_recorded.connect(func(proof: Dictionary): proofs.append(proof))
	editor.test_state_changed.connect(func(rows: Array[Dictionary], summary: Dictionary):
		debug_rows.assign(rows)
		summaries.append(summary))
	editor.undo_requested.connect(func(): history_requests.undo += 1)
	editor.redo_requested.connect(func(): history_requests.redo += 1)
	editor.save_requested.connect(func(): history_requests.save += 1)
	editor.sound_requested.connect(func(_event: String): history_requests.sound += 1)
	editor.test_requested.connect(func(_level: Dictionary): history_requests.external_test += 1)
	root.add_child(editor)
	await _frames(3)
	var source := _fixture()
	editor.setup(source)
	_check(Codec.validate(source).is_empty(), "workbench fixture is a complete valid puzzle")
	_check(editor.get_script().is_tool() and editor._board.get_script().is_tool(), "editor and canvas scripts run as native tool scripts")
	_check(editor._overlay.get_script().is_tool(), "selection overlay is a real tool script")
	_check(editor.theme == null, "embedded workbench inherits the Godot editor theme")
	_check(not editor._inspector.visible, "native Inspector mode hides the duplicate runtime inspector")
	_check(editor._local_audio == null, "embedded workbench creates no game audio service")
	var game_backgrounds := 0
	for child in editor.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("scrolling_backdrop.gd"):
			game_backgrounds += 1
	_check(game_backgrounds == 0, "embedded workbench has no game backdrop")

	editor._palette = "walls"
	editor.paint_rectangle(Rect2i(7, 5, 1, 1), false)
	_check(transactions.size() == 1, "one drawing gesture publishes one external history transaction")
	_check(editor._undo.is_empty() and editor._redo.is_empty(), "external history never duplicates local undo stacks")
	_check(transactions[0].before == source and transactions[0].after == editor.get_level(), "transaction snapshots contain the complete before and after documents")
	editor.apply_document(transactions[0].before)
	_check(transactions.size() == 1 and editor.get_level() == source, "native undo restoration does not publish another history action")
	editor.undo_edit()
	editor.redo_edit()
	_check(history_requests.undo == 1 and history_requests.redo == 1, "undo and redo delegate to the native history owner")
	editor.select_instance("bag_01")
	_check(selections.back() == "bag_01", "selection publishes a stable instance ID for the native Inspector")
	var transaction_count := transactions.size()
	_check(editor.apply_instance_parameter("bag_01", "punch_distance", 3, false), "native Inspector can apply a constrained instance override")
	_check(transactions.size() == transaction_count, "Inspector-owned changes do not create a second drawing history action")
	_check(Catalog.resolve_instance(editor._find_object("bag_01")).punch_distance == 3, "instance parameter changes the effective rule input")
	var parameter_document := editor.get_level()
	_check(not editor.apply_instance_parameter("bag_01", "punch_distance", 0, false), "invalid parameter values are rejected")
	_check(editor.get_level() == parameter_document, "invalid parameter edit leaves the authored document unchanged")
	_check(editor.clear_instance_parameter("bag_01", "punch_distance", false), "native Inspector can remove an override")
	_check(not editor._find_object("bag_01").has("params"), "removing the last override restores absence, not a copied default")
	_check(editor.apply_instance_parameter("bag_01", "punch_distance", 4), "runtime controls can request their own parameter history transaction")
	_check(transactions.size() == transaction_count + 1, "runtime parameter edit publishes one history transaction")
	editor.apply_document(source)
	editor.mark_document_saved()
	_check(not editor.is_dirty(), "saving a draft synchronizes the widget's saved revision")
	_check(editor.begin_link("plate_01") and editor._link_source == "plate_01", "native toolbar can enter the shared plate-link tool")
	_check(not editor.begin_link("bag_01"), "link tool rejects non-device sources")
	editor._link_source = ""

	# Use actual canvas input events and verify both drawing and hit testing after navigation.
	var view: Control = editor._board
	var anchor: Vector2 = view.cell_to_rect(Vector2i(3, 2)).get_center()
	var logical_before: Vector2 = (anchor - view.board_origin) / view.cell_size
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = anchor
	view._gui_input(wheel)
	_check(float(view.get_view_state().zoom) > 1.0, "mouse wheel zooms the actual authoring canvas")
	_check(((anchor - view.board_origin) / view.cell_size).is_equal_approx(logical_before), "zoom keeps the point beneath the cursor fixed")
	_check(view.screen_to_cell(anchor) == Vector2i(3, 2), "zoom preserves transformed cell hit testing")
	var origin_before: Vector2 = view.board_origin
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	view._gui_input(middle)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	drag.relative = Vector2(47, -21)
	view._gui_input(drag)
	_check(view.board_origin.is_equal_approx(origin_before + drag.relative), "middle mouse drag pans the canvas")
	middle.pressed = false
	view._gui_input(middle)
	var held_view: Dictionary = view.get_view_state()
	editor.apply_document(source)
	_check(view.get_view_state() == held_view, "external undo restoration preserves the navigation state")
	var restored_cell := Vector2i(4, 4)
	_check(view.screen_to_cell(view.cell_to_rect(restored_cell).get_center()) == restored_cell, "overlay rectangles and hit testing share the same view transform")

	# A visible workbench must not hijack shortcuts in another editor panel.
	var unrelated := LineEdit.new()
	root.add_child(unrelated)
	unrelated.grab_focus()
	editor._tool = "rect"
	await _key(KEY_B)
	_check(editor._tool == "rect", "canvas shortcuts do not consume keys in another editor panel")
	view.grab_focus()
	await _key(KEY_B)
	_check(editor._tool == "brush", "canvas-focused shortcuts still select authoring tools")
	await _key(KEY_S, true)
	_check(history_requests.save == 1 and not editor._file_dialog.visible, "embedded Ctrl+S delegates to workspace save without opening a runtime dialog")

	editor._request_test()
	_check(editor._standalone_state != null and history_requests.external_test == 0, "embedded test runs shared simulation internally instead of launching the game scene")
	_check(debug_rows.size() == 2 and editor._test_debug_label.text.contains("plate_01") and editor._test_debug_label.text.contains("door_01"), "test debug panel displays real plate and door state")
	var powered := false
	for row: Dictionary in debug_rows:
		if row.get("id") == "door_01":
			powered = row.get("open", false) and row.get("powered_by", []).has("plate_01")
	_check(powered, "debug output explains which pressure plate powers the door")
	editor._execute_test_command("U")
	_check(editor._test_commands.is_empty(), "ineffective blocked commands with unchanged facing are not recorded")
	editor._execute_test_command("R")
	_check(editor._test_commands == ["R"] and editor._standalone_state.moves == 0, "necessary facing-only commands are recorded without incrementing moves")
	editor._execute_test_command("P")
	_check(editor._standalone_state.is_won(), "the shared test simulation reaches the goal")
	var proof: Dictionary = editor.get_last_proof()
	_check(proof.get("valid", false) and proof.get("commands", []) == ["R", "P"], "winning produces a proof with the actual effective command sequence")
	_check(Proof.verify(source, proof).get("valid", false), "recorded proof really replays through production rules")
	_check(not proofs.is_empty(), "successful test emits proof_recorded for workspace persistence")
	editor._execute_test_command("UNDO")
	_check(editor._test_commands == ["R"] and not editor._standalone_state.is_won(), "test undo removes the corresponding command from the recording")
	editor._execute_test_command("UNDO")
	_check(editor._test_commands.is_empty() and editor._standalone_state.facing == Vector2i.UP, "undo restores the initial facing-only state and command history")
	editor._execute_test_command("R")
	editor._execute_test_command("RESTART")
	_check(editor._test_commands.is_empty() and editor._standalone_state.moves == 0, "test restart clears both rule history and recording")
	editor.resume_after_test()
	_check(editor.get_level() == source and view.get_view_state() == held_view, "returning from test preserves authored content and view state")
	_check(editor.set_last_proof(proof), "saved proof can be restored after workspace load")
	_check(editor.play_verified_replay(), "verified proof starts a real visual replay")
	await create_timer(0.65).timeout
	_check(editor._standalone_state != null and editor._standalone_state.is_won() and not editor._replaying, "visual replay executes the saved commands and finishes won")
	editor.resume_after_test()
	var renamed := source.duplicate(true)
	renamed["title"] = "A NEW DISPLAY NAME"
	editor.apply_document(renamed)
	_check(not editor.get_last_proof().is_empty(), "display-title edits retain valid rule proof")
	editor.apply_instance_parameter("bag_01", "punch_distance", 3, false)
	_check(editor.get_last_proof().is_empty() and not editor.play_verified_replay(), "rule parameter edits invalidate prior proof and block stale replay")
	view.fit_view()
	_check(view.get_view_state().zoom == 1.0 and view.get_view_state().pan == Vector2.ZERO, "fit_view resets zoom and pan")
	_check(history_requests.sound == 0 and editor._local_audio == null, "native workbench editing and testing never starts game audio")
	unrelated.queue_free()
	editor.queue_free()
	await _frames(2)
	await create_timer(0.3).timeout
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var file := FileAccess.open("res://evidence/editor_workbench_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("EDITOR_WORKBENCH_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _frames(count: int) -> void:
	for ignored in range(count):
		await process_frame


func _key(key: int, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.ctrl_pressed = control
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(1)


func _fixture() -> Dictionary:
	var floors: Array = []
	for y in range(6):
		for x in range(8):
			floors.append([x, y])
	return Codec.normalize({"schema_version": 1, "id": "workbench_fixture", "title": "WORKBENCH TEST", "width": 8, "height": 6,
		"floor": floors, "walls": [[1, 1]], "goals": [[4, 2]], "player": [1, 2], "facing": [0, -1],
		"objects": [{"id": "bag_01", "type": "bag", "cell": [2, 2], "targets": []},
			{"id": "wood_01", "type": "wood", "cell": [5, 4], "targets": []},
			{"id": "plate_01", "type": "plate", "cell": [5, 4], "targets": ["door_01"]},
			{"id": "door_01", "type": "door", "cell": [6, 4], "targets": []}], "metadata": {"solution": []}})
