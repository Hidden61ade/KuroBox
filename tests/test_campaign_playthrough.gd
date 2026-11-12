extends SceneTree
## Real shell/input/render coverage of the published campaign, never UI fixtures.

var app: Control
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var played: Array[Dictionary] = []
var capture := false
var _profile_path := ""
var _finished := false
var _camera_smoothed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not FileAccess.file_exists("res://.kuro_gameplay_validation_workspace"):
		_check(false, "campaign playthrough requires the isolated project from tools/test_campaign_playthrough.ps1")
		await _finish()
		return
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	create_timer(180.0).timeout.connect(_timeout)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	app = load("res://features/shell/main.tscn").instantiate()
	root.add_child(app)
	await _frames(3)
	_profile_path = "user://campaign_playthrough_%d.json" % Time.get_ticks_usec()
	app.profile = ProfileStore.new(_profile_path)
	app.profile.settings.shake = false
	app._apply_settings()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	_check(not app.campaign.is_empty(), "actual published campaign loads")
	app.show_level_select()
	await _frames(3)
	_check(app.find_child("Round%02d" % app.campaign.size(), true, false) != null, "level select includes the final published challenge")
	await _shot("campaign_level_select")
	for index in range(app.campaign.size()):
		var level: Dictionary = app.campaign[index]
		app.start_level(level, index)
		await _frames(3)
		var initial: Dictionary = app.board.snapshot()
		var initial_origin: Vector2 = app.board_view.board_origin
		_camera_smoothed = false
		_check_layout(str(level.id), Vector2i(1280, 720))
		if index in [4, 6, 7] or index >= 8:
			await _shot("campaign_%02d_start" % (index + 1))
		var brake_seen := false
		var closed_seen := false
		var transfer_seen := false
		var opened_seen := _any_gate_open()
		var player_visible := true
		var follow_captured := false
		for raw: Variant in level.get("metadata", {}).get("solution", []):
			var command := str(raw)
			if index == 4 and not brake_seen and command == "P" and _wood_brakes_next_punch():
				await _shot("campaign_05_mobile_brake")
				brake_seen = true
			await _command(command)
			var view: BoardView = app.board_view
			player_visible = player_visible and Rect2(Vector2.ZERO, view.size).encloses(view.cell_to_rect(app.board.player))
			if index == app.campaign.size() - 1 and not follow_captured and view.board_origin.distance_to(initial_origin) >= 64.0 and not app.board.is_won():
				await _shot("campaign_final_follow")
				follow_captured = true
			if index == 6 and opened_seen and not closed_seen and _all_gates_unpowered_closed():
				await _shot("campaign_07_released_gate")
				closed_seen = true
			if index == 7 and not transfer_seen and not app.board.is_won() and _bag_powers_gate_without_wood():
				await _shot("campaign_08_handoff")
				transfer_seen = true
			opened_seen = opened_seen or _any_gate_open()
		_check(app.board.is_won(), "%s wins via real keyboard input through the shell" % level.id)
		_check(player_visible, "%s keeps the player visible through its solution" % level.id)
		if index >= 8:
			_check(_camera_smoothed, "%s pans through intermediate camera positions during a move" % level.id)
		_check(app._modal_kind == "completion", "%s creates its completion menu after the final animation" % level.id)
		played.append({"id":level.id, "commands":level.metadata.solution.size(), "moves":app.board.moves, "punches":app.board.punches, "won":app.board.is_won(), "viewport":[1280,720], "cell_pixels":app.board_view.cell_size, "smooth_camera_observed":_camera_smoothed})
		if index == 4:
			_check(brake_seen, "round_05 replay actually uses a wood box to stop the next punch")
		if index == 6:
			_check(closed_seen, "round_07 visibly releases all plates and closes an unoccupied gate")
		if index == 7:
			_check(transfer_seen, "round_08 reaches a playable bag-powered handoff state before completion")
		app.undo_action()
		_check(not app.board.is_won(), "%s final action is reversible from completion" % level.id)
		app.restart_level()
		_check(app.board.snapshot() == initial, "%s restart restores all initial devices and pieces" % level.id)
		_check(app.board_view.board_origin == initial_origin, "%s restart restores its starting framing" % level.id)
	root.size = Vector2i(960, 640)
	root.content_scale_size = Vector2i(960, 640)
	await _frames(3)
	for index in range(app.campaign.size()):
		app.start_level(app.campaign[index], index)
		await _frames(3)
		_check_layout(str(app.campaign[index].id), Vector2i(960, 640))
		if index == app.campaign.size() - 1:
			await _shot("campaign_final_960")
	await _finish()

func _check_layout(id: String, viewport: Vector2i) -> void:
	var view: Control = app.board_view
	var floor_bounds := Rect2()
	for raw: Array in app.board.level.floor:
		var rect: Rect2 = view.cell_to_rect(Vector2i(raw[0], raw[1]))
		floor_bounds = floor_bounds.merge(rect) if floor_bounds.has_area() else rect
	var frame := floor_bounds.grow(BoardView.Rim.PADDING_TILES * view.cell_size)
	var visible := Rect2(Vector2.ZERO, view.size)
	if frame.size.x <= view.size.x and frame.size.y <= view.size.y:
		_check(visible.grow(1.0).encloses(frame), "%s centers the full frame when it fits %s" % [id, viewport])
	else:
		_check(visible.encloses(view.cell_to_rect(app.board.player)), "%s frames the player at %s" % [id, viewport])
	var footer: Rect2 = app._hud_footer.get_global_rect()
	_check(Rect2(Vector2.ZERO, Vector2(viewport)).encloses(footer), "%s footer fits %s" % [id, viewport])
	_check(is_equal_approx(view.cell_size, BoardView.PLAY_CELL_SIZE), "%s keeps fixed play scale at %s" % [id, viewport])

func _wood_brakes_next_punch() -> bool:
	var board: BoardState = app.board
	var bag_id := board.object_at(board.player + board.facing)
	if bag_id.is_empty() or board.objects[bag_id].behavior != "bag":
		return false
	var landing: Vector2i = board.preview_punch()
	if landing == board.player + board.facing:
		return false
	var travelled: int = absi(landing.x - board.objects[bag_id].cell.x) + absi(landing.y - board.objects[bag_id].cell.y)
	if travelled >= int(board.objects[bag_id]._definition.punch_distance):
		return false
	var blocker := board.object_at(landing + board.facing)
	return not blocker.is_empty() and board.objects[blocker].behavior == "wood"

func _all_gates_unpowered_closed() -> bool:
	var has_gate := false
	for item: Dictionary in app.board.objects.values():
		if item.behavior == "plate" and item.get("pressed", false):
			return false
		if item.behavior == "door":
			has_gate = true
			if item.get("open", false):
				return false
	return has_gate

func _any_gate_open() -> bool:
	for item: Dictionary in app.board.objects.values():
		if item.behavior == "door" and item.get("open", false):
			return true
	return false

func _bag_powers_gate_without_wood() -> bool:
	for gate: Dictionary in app.board.device_debug():
		if gate.behavior != "door" or not gate.get("open", false) or not gate.get("powered", false) or gate.get("held_open", false):
			continue
		if gate.get("powered_by", []).is_empty():
			continue
		var only_bags := true
		for plate_id: String in gate.powered_by:
			var plate: Dictionary = app.board.objects[plate_id]
			var occupant: String = app.board.object_at(plate.cell)
			if app.board.player == plate.cell or occupant.is_empty() or app.board.objects[occupant].behavior != "bag":
				only_bags = false
		if only_bags:
			return true
	return false

func _command(command: String) -> void:
	var last_origin: Vector2 = app.board_view.board_origin
	var camera_changes := 0
	var key: Key = {"U":KEY_UP,"D":KEY_DOWN,"L":KEY_LEFT,"R":KEY_RIGHT,"P":KEY_SPACE}[command]
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	Input.parse_input_event(event)
	await process_frame
	var deadline := Time.get_ticks_msec() + 3000
	while app._busy and Time.get_ticks_msec() < deadline:
		await process_frame
		if app.board_view.board_origin != last_origin:
			camera_changes += 1
			last_origin = app.board_view.board_origin
	_camera_smoothed = _camera_smoothed or camera_changes > 1
	_check(not app._busy, "animation command settles within its runtime budget")
	await process_frame

func _frames(count: int) -> void:
	for index in range(count):
		await process_frame

func _shot(stem: String) -> void:
	if not capture:
		return
	await _frames(2)
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var path := "res://evidence/" + stem + ".webp"
	_check(screenshot.save_webp(path, false, 0.95) == OK, "actual game screenshot saved: " + stem)
	captures.append(path)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"display_driver":DisplayServer.get_name(),"published_campaign":played,"screenshots":captures,"input_source":"Input.parse_input_event through the actual main scene","isolated_profile":true}
	var output := FileAccess.open("res://evidence/campaign_playthrough_report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("CAMPAIGN_PLAYTHROUGH_RESULT ", JSON.stringify(report))
	if is_instance_valid(app):
		app.audio.shutdown()
		app.queue_free()
		await process_frame
	await create_timer(0.3).timeout
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_profile_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_profile_path + suffix))
	quit(0 if failures.is_empty() else 1)

func _timeout() -> void:
	if not _finished:
		_check(false, "real campaign playthrough timed out")
		_finish()
