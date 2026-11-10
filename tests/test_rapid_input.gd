extends SceneTree
## Real key events exercise command order, release and UI cancellation together.
const Store = preload("res://features/shell/profile_store.gd")
const Buffer = preload("res://features/play/command_buffer.gd")
var app: Control
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var _profile_path := ""
var _original_mute := false
var _original_window_mode := DisplayServer.WINDOW_MODE_WINDOWED

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	_original_mute = AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	_original_window_mode = DisplayServer.window_get_mode()
	_profile_path = "user://rapid_input_%d.json" % Time.get_ticks_usec()
	app = load("res://features/shell/main.tscn").instantiate()
	root.add_child(app)
	await _frames(2)
	app.profile = Store.new(_profile_path)
	app.profile.settings.fullscreen = false
	app.profile.settings.muted = true
	app._apply_settings()
	await _fresh(_fixture())
	for ignored in range(3):
		_tap(KEY_RIGHT)
		await create_timer(0.02).timeout
	await _idle()
	_check(app.board.moves == 3 and app.board.player == Vector2i(4,2), "three real RIGHT taps at 20ms intervals all execute")
	cases.append({"case":"three_rapid_taps", "expected_moves":3, "actual_moves":app.board.moves, "player":str(app.board.player)})
	_check(not app._busy and app._commands.size() == 0, "busy stays active until the accepted sequence drains")
	await _fresh(_combo())
	_tap(KEY_RIGHT)
	_tap(KEY_SPACE)
	await _idle()
	var keyboard_combo: Dictionary = app.board.snapshot()
	_check(app.board.player == Vector2i(2,2) and app.board.objects.bag_01.cell == Vector2i(5,2), "rapid direction then punch preserves command order")
	_check(app.board.moves == 2 and app.board.punches == 1, "queued keyboard punch executes once")
	await _fresh(_combo())
	_tap(KEY_RIGHT)
	app._hud_footer.action_buttons[&"punch"].pressed.emit()
	await _idle()
	_check(app.board.snapshot() == keyboard_combo, "HUD and keyboard punch share the buffered entry point")
	await _fresh(_fixture())
	for ignored in range(20):
		_tap(KEY_RIGHT)
	await _frames(1)
	_check(app._commands.size() <= Buffer.CAPACITY, "discrete overload has a finite pending capacity")
	await _idle()
	_check(app.board.moves == Buffer.CAPACITY + 1, "overload retains the accepted FIFO prefix without unlimited backlog")
	_tap(KEY_LEFT)
	await _idle()
	_check(app.board.player == Vector2i(Buffer.CAPACITY + 1,2), "input remains responsive after saturation")
	await _fresh(_fixture())
	_key(KEY_RIGHT, true)
	await create_timer(0.02).timeout
	for ignored in range(30):
		_key(KEY_RIGHT, true, true)
	await _frames(1)
	_check(app._commands.size() <= 1, "OS echo gets at most one waiting repeat")
	_key(KEY_RIGHT, false)
	await _frames(1)
	var moves_on_release: int = app.board.moves
	_check(app._commands.size() == 0, "release removes unexecuted repeats")
	await create_timer(0.5).timeout
	_check(app.board.moves == moves_on_release, "released movement cannot run from stale echoes")
	_key(KEY_RIGHT, true, true)
	_key(KEY_RIGHT, false)
	await create_timer(0.2).timeout
	_check(app.board.moves == moves_on_release, "echo after release cannot start movement")
	await _fresh(_fixture())
	_key(KEY_RIGHT, true)
	for ignored in range(5):
		await create_timer(0.08).timeout
		_key(KEY_RIGHT, true, true)
	_key(KEY_RIGHT, false)
	await _frames(1)
	moves_on_release = app.board.moves
	_check(moves_on_release > 1 and moves_on_release <= 6, "held direction produces paced repeated movement")
	await create_timer(0.4).timeout
	_check(app.board.moves == moves_on_release, "held repeat stops without a release tail")
	await _fresh(_fixture())
	_key(KEY_RIGHT, true)
	_key(KEY_RIGHT, true, true)
	_tap(KEY_DOWN)
	_key(KEY_RIGHT, true, true)
	_key(KEY_RIGHT, false)
	await _idle()
	_check(app.board.player == Vector2i(2,3), "new discrete direction supersedes held repetition")
	await _fresh(_fixture())
	var initial: Dictionary = app.board.snapshot()
	_burst()
	app._hud_footer.action_buttons[&"undo"].pressed.emit()
	await create_timer(0.6).timeout
	_check(app.board.snapshot() == initial and app._commands.size() == 0, "HUD undo clears pending commands and restores committed move")
	_burst()
	_tap(KEY_R)
	await create_timer(0.6).timeout
	_check(app.board.snapshot() == initial and not app._busy, "restart invalidates queue and old animation callback")
	await _fresh(_fixture())
	_burst()
	_tap(KEY_ESCAPE)
	await _frames(1)
	_check(app._modal != null and app._modal_kind == "pause", "pause can open during movement animation")
	var paused: Dictionary = app.board.snapshot()
	_check(app._commands.size() == 0 and not app._busy, "pause clears pending commands")
	await create_timer(0.5).timeout
	_check(app.board.snapshot() == paused, "expired animation cannot move paused board")
	app._close_modal()
	await create_timer(0.3).timeout
	_check(app.board.snapshot() == paused, "resume does not replay discarded commands")
	_tap(KEY_RIGHT)
	await _idle()
	_check(app.board.moves == int(paused.moves) + 1, "fresh command works after resume")
	await _fresh(_fixture())
	_burst()
	app.show_menu()
	await create_timer(0.4).timeout
	_check(app.current_screen == "menu" and app._commands.size() == 0, "menu navigation clears the old session")
	await _fresh(_combo())
	await create_timer(0.4).timeout
	_check(app.board.moves == 0 and app.board.objects.bag_01.cell == Vector2i(3,2), "old timer cannot drain into new level")
	_burst()
	app.start_level(_fixture())
	await create_timer(0.4).timeout
	_check(app.board.moves == 0 and app.board.player == Vector2i(1,2), "direct level switch invalidates queued commands")
	_burst()
	_tap(KEY_Q)
	await _frames(1)
	_check(app._commands.size() == 0 and app._transition.busy, "back clears commands before transition completes")
	_tap(KEY_RIGHT)
	await create_timer(1.05).timeout
	_check(app.current_screen == "select", "wipe finishes without movement input")
	await _fresh(_fixture())
	await create_timer(0.3).timeout
	_check(app.board.moves == 0, "transition input cannot bleed into next play session")
	var blocked := _fixture()
	blocked["objects"] = [{"id":"bag_01","type":"bag","cell":[2,2],"targets":[]}]
	blocked["walls"] = [[4,2]]
	blocked["facing"] = [0,-1]
	await _fresh(blocked)
	_tap(KEY_RIGHT)
	_tap(KEY_SPACE)
	await _idle()
	_check(app.board.moves == 1 and app.board.punches == 1 and app.board.objects.bag_01.cell == Vector2i(3,2), "blocked direction turns before following punch")
	_tap(KEY_Z)
	await _frames(1)
	_check(app.board.moves == 0 and app.board.facing == Vector2i.RIGHT, "undo restores punch after facing-only command")
	_tap(KEY_Z)
	await _frames(1)
	_check(app.board.facing == Vector2i.UP, "facing-only collision preserves core undo semantics")
	var wall := _fixture()
	wall["walls"] = [[2,2]]
	await _fresh(wall)
	for ignored in range(12):
		_tap(KEY_RIGHT)
	await _frames(1)
	_check(app.board.moves == 0 and app._commands.size() == 0 and not app._busy, "unchanged collisions settle without artificial lock")
	_tap(KEY_LEFT)
	await _idle()
	_check(app.board.moves == 1 and app.board.player == Vector2i(0,2), "valid input works immediately after blocked attempts")
	app.start_level(app.campaign[0], 0)
	await _frames(2)
	for ignored in range(4):
		_tap(KEY_RIGHT)
	await create_timer(0.45).timeout
	_check(app.board.is_won() and app._modal_kind == "completion", "rapid input reaches normal completion")
	_check(app.board.moves == 2 and app._commands.size() == 0, "win discards all remaining commands")
	var next: BaseButton
	for candidate: Node in app._modal.find_children("*", "BaseButton", true, false):
		if candidate.tooltip_text == "下一关":
			next = candidate
	_check(next != null, "completion retains the real next-level control")
	if next != null:
		next.pressed.emit()
	await create_timer(1.1).timeout
	_check(app.current_index == 1 and app.board.moves == 0, "winning queue never moves the next campaign level")
	for ignored in range(4):
		await _fresh(_fixture())
		_burst()
		app.show_menu()
		await _frames(1)
	await _fresh(_fixture())
	_check(app._hud_footer.action_requested.get_connections().size() == 1, "cancelled UI lifecycle does not duplicate HUD handlers")
	_tap(KEY_RIGHT)
	await _idle()
	_check(app.board.moves == 1, "new UI executes once after repeated teardown")
	var report := {"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"capacity":Buffer.CAPACITY,"repeat_waiting_limit":1,"cases":cases,"baseline_evidence":"evidence/rapid_input_before.json","profile_isolated":true}
	var file := FileAccess.open("res://evidence/rapid_input_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ") + "\n")
	file.close()
	print("RAPID_INPUT_RESULT ",JSON.stringify(report))
	app.audio.shutdown()
	app.queue_free()
	await _frames(2)
	await create_timer(0.3).timeout
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _original_mute)
	DisplayServer.window_set_mode(_original_window_mode)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_profile_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_profile_path + suffix))
	quit(0 if failures.is_empty() else 1)

func _fresh(level: Dictionary) -> void:
	app.start_level(level)
	await _frames(2)

func _burst() -> void:
	_tap(KEY_RIGHT)
	_tap(KEY_DOWN)
	_tap(KEY_RIGHT)

func _tap(key: int) -> void:
	_key(key,true)
	_key(key,false)

func _key(key: int, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _frames(count: int) -> void:
	for ignored in range(count):
		await process_frame

func _idle() -> void:
	await _frames(1)
	var deadline := Time.get_ticks_msec() + 2000
	while app._busy or app._commands.size() > 0:
		if Time.get_ticks_msec() > deadline:
			_check(false,"accepted queue drains within its finite budget")
			return
		await create_timer(0.02).timeout
	await _frames(1)

func _combo() -> Dictionary:
	var level := _fixture()
	level["objects"] = [{"id":"bag_01","type":"bag","cell":[3,2],"targets":[]}]
	level["facing"] = [0,-1]
	return level

func _fixture() -> Dictionary:
	var floors: Array = []
	for y in range(6):
		for x in range(16):
			floors.append([x,y])
	return {"schema_version":1,"id":"rapid_input_fixture","title":"INPUT TEST","width":16,"height":6,"floor":floors,"walls":[],"goals":[[14,4]],"player":[1,2],"facing":[1,0],"objects":[{"id":"wood_01","type":"wood","cell":[12,4],"targets":[]}],"metadata":{"solution":[]}}
