@tool
extends Node
## Runs in the real Editor process, through real Inspector/Undo APIs and plugin controls.

const Catalog = preload("res://core/object_catalog.gd")
const Proof = preload("res://core/replay_proof.gd")
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var plugin: EditorPlugin
var panel: Control
var _finished := false

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run(host: EditorPlugin) -> void:
	plugin = host
	panel = host.panel
	if not FileAccess.file_exists("res://.kuro_native_smoke_workspace"):
		_check(false, "native UI test requires the isolated workspace created by tools/test_native_editor.ps1")
		_finish()
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	get_tree().create_timer(60.0).timeout.connect(_timeout)
	await _frames(12)
	EditorInterface.set_main_screen_editor("KuroBox")
	await _frames(4)
	_check(Engine.is_editor_hint(), "test is running in the native Godot Editor")
	_check(panel.get_parent() == EditorInterface.get_editor_main_screen(), "workbench belongs to the editor main screen")
	_check(panel.entries.size() >= 8, "published sample library loaded")
	_check(plugin.get_undo_redo() is EditorUndoRedoManager, "native editor history is available")
	panel._dialog_mode = "duplicate"
	panel.open_level("round_03")
	panel._new_id.text = "workshop_punch_3"
	panel._new_title.text = "三格沙袋 · 制作示例"
	panel._create_from_dialog()
	_check(str(panel.active_document.data.id) == "workshop_punch_3", "real duplicate callback opens a saved draft")
	if str(panel.active_document.data.id) != "workshop_punch_3":
		await _finish()
		return
	var bag_id := ""
	for item: Dictionary in panel.active_document.data.objects:
		if Catalog.get_type(str(item.type)).get("behavior") == "bag":
			bag_id = str(item.id)
	_check(not bag_id.is_empty(), "duplicate retains bag behavior and assigns instance identity")
	var old_goal: Array = panel.active_document.data.goals[0]
	panel.editor._select_palette("goals")
	panel.editor._on_cell_pressed(Vector2i(old_goal[0],old_goal[1]), MOUSE_BUTTON_RIGHT)
	panel.editor._finish_edit()
	panel.editor._on_cell_pressed(Vector2i(6,2), MOUSE_BUTTON_LEFT)
	panel.editor._finish_edit()
	_check(panel.active_document.data.goals == [[6,2]], "canvas edits reach authoritative document")
	panel.editor.focus_instance(bag_id)
	await _frames(5)
	var selected_cell: Array = panel.active_document.find_instance(bag_id).cell
	_check(panel.editor.get("_board").cell_to_rect(Vector2i(selected_cell[0],selected_cell[1])).get_center().is_equal_approx(panel.editor.get("_board").size * 0.5), "Inspector locate centers the selected cell in the authoring view")
	var property := _find_property(EditorInterface.get_inspector())
	_check(property != null, "native Inspector created the custom parameter EditorProperty")
	if property == null:
		await _finish()
		return
	var spin: SpinBox = property.get("_controls")["punch_distance"]
	spin.value = 3
	await _frames(4)
	_check(int(Catalog.resolve_instance(panel.active_document.find_instance(bag_id)).punch_distance) == 3, "real SpinBox change reaches the simulation parameter")
	_check(panel.active_document.dirty(), "Inspector change marks document dirty")
	var manager := plugin.get_undo_redo()
	var history_id := manager.get_object_history_id(panel.get("_undo_context"))
	_check(history_id == EditorUndoRedoManager.GLOBAL_HISTORY, "authoring operations explicitly use global resource history")
	print("NATIVE_HISTORY ",history_id," params_before_undo=",panel.active_document.find_instance(bag_id).get("params",{}))
	manager.get_history_undo_redo(history_id).undo()
	await _frames(3)
	_check(not panel.active_document.find_instance(bag_id).get("params", {}).has("punch_distance"), "native Undo restores absence of an override")
	manager.get_history_undo_redo(history_id).redo()
	await _frames(3)
	_check(int(Catalog.resolve_instance(panel.active_document.find_instance(bag_id)).punch_distance) == 3, "native Redo restores the override")
	_check(panel.save_current_draft(), "draft saves through the actual toolbar callback")
	var document_a: Resource = panel.active_document
	panel.open_level("round_01")
	panel.editor.select_instance("wood_01")
	await _frames(3)
	manager.get_history_undo_redo(history_id).undo()
	await _frames(3)
	_check(panel.active_document == document_a, "cross-document native Undo activates the affected document")
	_check(panel.current_proxy == null or panel.current_proxy.document == document_a, "Inspector cannot remain bound to another level after Undo")
	manager.get_history_undo_redo(history_id).redo()
	await _frames(3)
	panel.editor.select_instance(bag_id)
	_check(panel.save_current_draft(), "restored draft can be saved")
	panel._show_variant_dialog(false)
	for index in range(panel._variant_source.item_count):
		if panel._variant_source.get_item_metadata(index) == "bag":
			panel._variant_source.select(index)
	panel._build_variant_parameters()
	var registered_type_id := "qa_bag_%d" % Time.get_ticks_usec()
	panel._variant_id.text = registered_type_id
	panel._variant_title.text = "三格变体"
	panel._variant_controls["punch_distance"].value = 3
	_check(Catalog.get_type(registered_type_id).is_empty(), "type registration starts from a genuinely new identity")
	panel._create_variant()
	_check(Catalog.get_type(registered_type_id).get("punch_distance") == 3, "native type-variant form registers a three-cell default")
	_check(panel.editor.get("_palette_buttons").has("object:" + registered_type_id), "new type appears in the actual palette")
	await _shot("native_editor_parameters")
	panel._begin_test()
	await _frames(4)
	var test_panel: StyleBox = panel.editor.get("_standalone_layer").get_theme_stylebox("panel")
	_check(test_panel is StyleBoxFlat and is_equal_approx(test_panel.bg_color.a, 1.0), "native test canvas has an opaque theme background over authoring controls")
	var test_view: Control = panel.editor.get("_standalone_board")
	test_view.grab_focus()
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().create_timer(0.3).timeout
	press = InputEventKey.new()
	press.keycode = KEY_SPACE
	press.physical_keycode = KEY_SPACE
	press.pressed = false
	Input.parse_input_event(press)
	_check(panel.editor.get("_standalone_state").is_won(), "real editor Space input wins the three-cell draft")
	_check(panel.last_proof.get("valid", false), "winning emits a recorded proof to the workbench")
	_check(Proof.verify(panel.active_document.data, panel.last_proof).valid, "stored proof replays with actual current rules")
	panel.editor.resume_after_test()
	_check(panel.publish_current(), "real publish callback validates and registers the level")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels/campaign.json"))
	_check(manifest.levels.size() == 9, "publishing adds the new level to the actual manifest")
	var original_order: Array[String] = panel._pending_order.duplicate()
	panel._move_order(-1)
	_check(bool(panel.get("_order_dirty")) and panel._pending_order != original_order, "library order edits remain staged before save")
	panel.save_order()
	_check(not bool(panel.get("_order_dirty")), "saving order clears the staged-order flag")
	panel._pending_order = original_order
	panel._order_dirty = true
	panel.save_order()
	await _shot("native_editor_published")
	panel.editor._title_edit.text = "三格沙袋 · 制作示例（保留草稿）"
	panel.editor._commit_text()
	_check(panel.active_document.dirty(), "title edit remains pending before withdrawal")
	panel.unpublish_current()
	_check(str(panel.active_document.data.title).contains("保留草稿"), "withdrawal preserves pending in-memory authoring changes")
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels/campaign.json"))
	_check(manifest.levels.size() == 8, "withdrawal removes only the test publication")
	_check(not str(panel._entry("workshop_punch_3").draft_path).is_empty(), "withdrawal keeps an editable draft")
	_check(Proof.verify(panel.active_document.data, panel.last_proof).valid, "display-title changes do not invalidate a rule proof")
	panel.open_level("round_08")
	panel._replay()
	await get_tree().create_timer(3.6).timeout
	_check(panel.editor.get("_standalone_state").is_won(), "native editor replays the complex published sample")
	_check(panel._debug.text.contains("gate_mid") and panel._debug.text.contains("供电"), "mechanism debug displays real gate causality")
	await _shot("native_editor_mechanisms")
	panel.editor.resume_after_test()
	panel.open_level("workshop_punch_3")
	panel.editor.select_instance(bag_id)
	await _frames(4)
	await _shot("native_editor_library")
	_check(FileAccess.get_sha256("res://content/levels/campaign.json") != "", "manifest remains readable after round trip")
	var invalid_snapshot: Dictionary = panel.active_document.data.duplicate(true)
	for item: Dictionary in invalid_snapshot.objects:
		if str(item.id) == bag_id:
			item["params"] = {"punch_distance": [3]}
	panel.active_document.apply_snapshot(invalid_snapshot)
	panel.editor.select_instance(bag_id)
	await _frames(4)
	property = _find_property(EditorInterface.get_inspector(), panel.current_proxy)
	if property == null or not property.get("_controls").has("punch_distance"):
		_check(false, "current bag Inspector parameter control exists after restoring invalid data")
		await _finish()
		return
	_check(property != null and property.get("_errors")["punch_distance"].visible, "invalid recovered parameter is displayed as a repairable error")
	_check(panel.active_document.find_instance(bag_id).params.punch_distance == [3], "Inspector display never overwrites an invalid recovered value")
	property.get("_controls")["punch_distance"].value = 3
	await _frames(3)
	_check(Catalog.resolve_instance(panel.active_document.find_instance(bag_id)).punch_distance == 3, "Inspector can repair an invalid recovered parameter through native history")
	manager.get_history_undo_redo(history_id).undo()
	await _frames(3)
	_check(panel.active_document.find_instance(bag_id).params.punch_distance == [3], "native Undo preserves invalid original data when reverting a parameter repair")
	manager.get_history_undo_redo(history_id).redo()
	await _frames(3)
	_check(Catalog.resolve_instance(panel.active_document.find_instance(bag_id)).punch_distance == 3, "native Redo reapplies the validated parameter repair")
	await _finish()

func _find_property(node: Node, target: Object = null) -> EditorProperty:
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("parameters_property.gd") and node.is_visible_in_tree() and (target == null or node.get_edited_object() == target):
		return node as EditorProperty
	for child: Node in node.get_children():
		var found := _find_property(child, target)
		if found != null:
			return found
	return null

func _frames(count: int) -> void:
	for index in range(count):
		await get_tree().process_frame

func _shot(stem: String) -> void:
	EditorInterface.set_main_screen_editor("KuroBox")
	await _frames(3)
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	var path := "res://evidence/" + stem + ".png"
	var result := image.save_png(path)
	_check(result == OK and image.get_width() > 1000, "actual editor viewport screenshot saved: " + stem)
	screenshots.append(path)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {"engine":Engine.get_version_info().string,"native_editor":Engine.is_editor_hint(),"checks":checks,"failures":failures,"screenshots":screenshots,"workspace":"isolated copy of the project"}
	var file := FileAccess.open("res://evidence/native_editor_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("NATIVE_EDITOR_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func _timeout() -> void:
	if not _finished:
		_check(false, "native editor verification timed out")
		_finish()
