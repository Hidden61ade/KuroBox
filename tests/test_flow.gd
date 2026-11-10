extends SceneTree
## Integration proof exercises actual scene instances, signals and input dispatch.
## Published-content loading is checked first. Subsequent UI flow uses isolated
## fixtures; its captures are never evidence for the authored campaign content.
const FLOW_FIXTURE_COUNT := 8
var failures: Array[String] = []
var checks: int = 0
var app: Control
var capture: bool = false
var published_level_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	app = load("res://features/shell/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.profile = ProfileStore.new("user://flow_test_profile.json")
	app._apply_settings()
	await process_frame
	var published_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels/campaign.json"))
	var manifest_valid := published_manifest is Dictionary and published_manifest.get("levels") is Array
	_check(manifest_valid, "actual published manifest has a level list")
	if manifest_valid:
		published_level_count = published_manifest["levels"].size()
		_check(app.campaign.size() == published_level_count, "shell loads every actual published level regardless of count or order")
	# Two RIGHT inputs are a contract of this fixture, not of a user's first
	# published level. Never rewrite content or depend on campaign sort order.
	app.campaign = _flow_campaign()
	app.show_menu()
	_check(app.current_screen == "menu", "initial menu")
	await _shot("menu")
	var start_button := app.find_child("StartButton", true, false) as BaseButton
	_check(start_button != null, "start button is present")
	start_button.pressed.emit()
	if app._transition.busy:
		await app._transition.finished
	await process_frame
	_check(app.current_screen == "play" and app.current_index == 0, "start signal opens first uncompleted level")
	_check(app.board.moves == 0, "fresh board")
	var initial: Dictionary = app.board.snapshot()
	await _key(KEY_RIGHT)
	_check(app.board.moves == 1, "real key input moves and pushes")
	await _key(KEY_Z)
	_check(app.board.snapshot() == initial, "UI undo restores full board")
	await _key(KEY_ESCAPE)
	_check(app._modal != null, "Escape opens pause")
	var paused: Dictionary = app.board.snapshot()
	await _key(KEY_RIGHT)
	_check(app.board.snapshot() == paused, "modal blocks gameplay input")
	await _shot("pause")
	app.show_settings()
	await process_frame
	_check(app._modal.find_children("*", "HSlider", true, false).size() == 2, "settings owns sound sliders")
	app._close_modal()
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	_check(app.board.is_won(), "input completes first round")
	_check(app._modal != null, "completion modal")
	await _key(KEY_ESCAPE)
	_check(app._modal != null and app._modal_kind == "completion", "Escape retains completion and next-round entry")
	_check(app.profile.completed.has("round_01"), "completion persists by stable level id")
	await _shot("complete")
	app.undo_action()
	_check(not app.board.is_won(), "completion can be undone")
	app.restart_level()
	_check(app.board.snapshot() == initial, "UI restart resets board")
	app.show_level_select()
	await process_frame
	await process_frame
	_check(app.find_child("Round%02d" % app.campaign.size(), true, false) != null, "all isolated fixture level buttons are available")
	await _shot("select")
	var preview_index := mini(4, app.campaign.size() - 1)
	app.start_level(app.campaign[preview_index], preview_index)
	await process_frame
	await _shot("play")
	app.show_menu()
	app.open_editor()
	await process_frame
	await process_frame
	var held_editor: Control = app.editor
	var original_document: Dictionary = held_editor.get_level()
	_check(app.current_screen == "editor", "editor enters from menu")
	_check(LevelCodec.validate(original_document).is_empty(), "editor starts with valid editable sample")
	await _shot("editor")
	app.editor.test_requested.emit(app.editor.get_level())
	await process_frame
	_check(app.testing_editor and app.current_screen == "play", "editor signal enters shared play scene")
	await _key(KEY_RIGHT)
	_check(app.board.moves == 1, "editor test uses same input and simulation")
	app.return_to_editor()
	await process_frame
	_check(app.editor == held_editor, "editor instance preserved across play test")
	_check(app.editor.get_level() == original_document, "play test leaves author document unchanged")
	app.show_menu()
	app.open_editor()
	await process_frame
	_check(app.editor == held_editor, "editor reentry retains document instance")
	_check(app.editor.get_level() == original_document, "menu roundtrip retains document")
	app.show_menu()
	await process_frame
	root.size = Vector2i(960, 640)
	await process_frame
	await process_frame
	await _shot("menu_960")
	app.open_editor()
	await process_frame
	await process_frame
	await _shot("editor_960")
	var reloaded := ProfileStore.new("user://flow_test_profile.json")
	reloaded.read()
	_check(reloaded.completed.has("round_01"), "progress file round trip")
	reloaded.complete("round_01", 1, 0)
	var improved := ProfileStore.new("user://flow_test_profile.json")
	improved.read()
	_check(int(improved.completed.round_01.actions) == 1, "progress atomic overwrite and personal best")
	for suffix: String in ["", ".bak", ".tmp"]:
		var test_path := ProjectSettings.globalize_path("user://flow_test_profile.json" + suffix)
		if FileAccess.file_exists(test_path):
			DirAccess.remove_absolute(test_path)
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "screenshots": capture, "published_levels_loaded": published_level_count, "flow_fixture_count": app.campaign.size(), "content_source": "isolated_flow_fixtures", "capture_scope": "UI flow and responsive layout using test fixtures; not authored campaign content"}
	var file := FileAccess.open("res://evidence/flow_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FLOW_RESULT ", JSON.stringify(report))
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)

func _key(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.23).timeout
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _shot(name: String) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	screenshot.save_webp("res://evidence/flow_fixture_" + name + ".webp", false, 0.9)


func _flow_campaign() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var floor_cells: Array = []
	for y: int in range(1, 5):
		for x: int in range(1, 6):
			floor_cells.append([x, y])
	for index: int in range(FLOW_FIXTURE_COUNT):
		result.append({"schema_version": 1, "id": "round_01" if index == 0 else "flow_fixture_%02d" % (index + 1), "title": "FLOW FIXTURE %02d" % (index + 1), "width": 7, "height": 6, "floor": floor_cells.duplicate(true), "walls": [], "goals": [[5, 2]], "player": [2, 2], "facing": [1, 0], "objects": [{"id": "fixture_wood", "type": "wood", "cell": [3, 2], "targets": []}], "metadata": {"solution": ["R", "R"], "source": "isolated_flow_fixture"}})
	return result
