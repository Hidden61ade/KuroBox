extends SceneTree
## Integration coverage for the public HUD signals and real keyboard dispatch.

const Store = preload("res://features/shell/profile_store.gd")
const ACTIONS: Array[StringName] = [&"undo", &"restart", &"punch", &"fullscreen", &"sound", &"back"]
const BUTTON_NAMES := {&"undo": "UndoButton", &"restart": "RestartButton", &"punch": "PunchButton", &"fullscreen": "FullscreenButton", &"sound": "SoundButton", &"back": "BackButton"}
const SHORTCUTS := {&"undo": "Z", &"restart": "R", &"punch": "SPACE", &"fullscreen": "F11", &"sound": "M", &"back": "Q"}

var checks := 0
var failures: Array[String] = []
var app: Control
var capture := false
var _profile_path := ""
var _original_master_mute := false
var _original_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var _original_viewport_size := Vector2i.ZERO
var _original_content_scale := Vector2i.ZERO
var _layout_evidence: Array[Dictionary] = []
var _screenshots: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_original_master_mute = AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	_original_window_mode = DisplayServer.window_get_mode()
	_original_viewport_size = root.size
	_original_content_scale = root.content_scale_size
	_profile_path = "user://hud_footer_test_%d.json" % Time.get_ticks_usec()
	app = load("res://features/shell/main.tscn").instantiate()
	root.add_child(app)
	await _frames(2)
	# The shell's ordinary startup may read its profile; all test writes use this
	# disposable store. Launch with task-local APPDATA to isolate startup as well.
	app.profile = Store.new(_profile_path)
	app.profile.settings = {"sound": 0.65, "music": 0.35, "shake": true, "fullscreen": false, "muted": false}
	app._apply_settings()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)
	var level := _fixture()
	app.start_level(level)
	await _frames(3)
	if app.get("_hud_footer") == null:
		_check(false, "play screen creates the HudFooter component")
		await _finish()
		return
	_check(app._hud_footer.name == "HudFooter", "footer has a stable scene name")
	_check(app._hud_footer.action_requested.get_connections().size() == 1, "shell connects exactly one footer action handler")
	for action: StringName in ACTIONS:
		var button := _button(action)
		_check(button != null and button.name == BUTTON_NAMES[action], "%s button exists in action_buttons" % action)
		var hint := _hint_for(button)
		_check(hint != null and _hint_text(hint) == SHORTCUTS[action], "%s shortcut label matches actual binding" % action)

	# Space and the button must enter the same puzzle command path.
	var initial: Dictionary = app.board.snapshot()
	await _key(KEY_SPACE)
	var keyboard_punch: Dictionary = app.board.snapshot()
	_check(app.board.punches == 1 and app.board.moves == 1, "real Space dispatch punches the adjacent bag")
	app.start_level(level)
	await _frames(2)
	await _press(&"punch")
	_check(app.board.snapshot() == keyboard_punch, "PunchButton and Space produce identical board state")

	# Keep enough history to distinguish one undo from accidentally duplicated wiring.
	await _key(KEY_RIGHT)
	_check(app.board.moves == 2, "move after punch creates another undo entry")
	await _key(KEY_Z)
	_check(app.board.snapshot() == keyboard_punch, "real Z restores one complete command")
	await _key(KEY_RIGHT)
	await _press(&"undo")
	_check(app.board.snapshot() == keyboard_punch, "UndoButton matches Z and only removes one command")
	await _key(KEY_RIGHT)
	await _key(KEY_R)
	_check(app.board.snapshot() == initial, "real R restarts from authored initial state")
	await _key(KEY_SPACE)
	await _key(KEY_RIGHT)
	await _press(&"restart")
	_check(app.board.snapshot() == initial, "RestartButton matches R")

	# Toggle options through both input routes. Music and sound levels stay intact.
	await _key(KEY_M)
	_check(bool(app.profile.settings.get("muted", false)), "real M sets the persisted master-mute flag")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "real M mutes the AudioServer master bus")
	var muted_badge := app._hud_footer.find_child("MutedBadge", true, false) as Label
	_check(muted_badge != null and muted_badge.visible, "M synchronizes the footer muted indicator")
	await _press(&"sound")
	_check(not bool(app.profile.settings.get("muted", true)), "SoundButton toggles the same mute flag back")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "SoundButton restores the master bus")
	_check(muted_badge != null and not muted_badge.visible, "SoundButton synchronizes the footer muted indicator")
	_check(is_equal_approx(float(app.profile.settings.sound), 0.65) and is_equal_approx(float(app.profile.settings.music), 0.35), "mute toggle preserves individual volume levels")
	await _key(KEY_F11)
	_check(bool(app.profile.settings.fullscreen), "real F11 toggles fullscreen state")
	await _press(&"fullscreen")
	_check(not bool(app.profile.settings.fullscreen), "FullscreenButton toggles the same state back")
	var restored := Store.new(_profile_path)
	restored.read()
	_check(not bool(restored.settings.get("muted", true)) and not bool(restored.settings.fullscreen), "option button changes survive isolated profile reload")

	# A modal must prevent real shortcuts and even programmatic behind-modal signals.
	await _key(KEY_SPACE)
	await _key(KEY_ESCAPE)
	_check(app._modal != null and app._modal_kind == "pause", "Escape opens the actual pause modal")
	# Space intentionally activates a focused Resume button. Move focus to the
	# modal surface to test blocked gameplay, rather than request a real resume.
	app._modal.focus_mode = Control.FOCUS_ALL
	app._modal.grab_focus()
	var paused: Dictionary = app.board.snapshot()
	var paused_settings: Dictionary = app.profile.settings.duplicate(true)
	var paused_mute := AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	for key: int in [KEY_Z, KEY_R, KEY_SPACE, KEY_M, KEY_Q]:
		await _key(key, 0.06)
	for action: StringName in ACTIONS:
		var button := _button(action)
		if button != null:
			button.pressed.emit()
	await create_timer(1.05).timeout
	_check(app.current_screen == "play" and app._modal != null, "pause blocks all footer navigation")
	_check(app.board.snapshot() == paused, "pause blocks behind-modal puzzle commands")
	_check(app.profile.settings == paused_settings and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) == paused_mute, "pause blocks option changes behind the modal")
	app._close_modal()
	await _frames(2)

	# Capture / measure the real component, including its individual KeyHint labels.
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 640)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await _frames(4)
		_check_layout(viewport_size)
		await _shot(viewport_size)

	# Q waits for the same scene transition used by the corresponding footer button.
	await _key(KEY_Q, 1.05)
	_check(app.current_screen == "select", "real Q returns to selection after the stripe transition")
	app.start_level(level)
	await _frames(2)
	await _press(&"back", 1.05)
	_check(app.current_screen == "select", "BackButton matches Q navigation")

	# Re-entering menus replaces the component without accumulating signal handlers.
	for ignored in range(3):
		app.show_menu()
		await _frames(1)
		app.start_level(level)
		await _frames(2)
		_check(app._hud_footer.action_requested.get_connections().size() == 1, "menu reentry retains exactly one footer connection")
		_check(app.find_children("HudFooter", "", true, false).size() == 1, "menu reentry leaves one active footer instance")
	await _key(KEY_SPACE)
	await _key(KEY_RIGHT)
	await _press(&"undo")
	_check(app.board.snapshot() == keyboard_punch, "undo still executes once after repeated menu reentry")

	# Editor text consumes letter shortcuts. A test-play return keeps the same draft.
	app.show_menu()
	app.open_editor()
	await _frames(2)
	var held_editor: Control = app.editor
	held_editor._title_edit.text = "HUD FOOTER DRAFT"
	held_editor._commit_text()
	var authored: Dictionary = held_editor.get_level()
	held_editor._title_edit.grab_focus()
	var before_typing_mute := bool(app.profile.settings.get("muted", false))
	await _key(KEY_M)
	await _key(KEY_Q)
	_check(app.current_screen == "editor" and bool(app.profile.settings.get("muted", false)) == before_typing_mute, "M and Q in editor text do not trigger play shortcuts")
	held_editor._title_edit.release_focus()
	authored = held_editor.get_level()
	held_editor.test_requested.emit(authored)
	await _frames(2)
	_check(app.current_screen == "play" and app.testing_editor, "editor enters actual shared play-test screen")
	await _key(KEY_RIGHT)
	await _key(KEY_Q, 1.05)
	_check(app.current_screen == "editor" and app.editor == held_editor, "Q from a test play returns to the retained editor instance")
	_check(app.editor.get_level() == authored, "Q from a test play preserves the authored draft")
	await _finish()


func _button(action: StringName) -> BaseButton:
	if not is_instance_valid(app) or app.get("_hud_footer") == null:
		return null
	return app._hud_footer.action_buttons.get(action) as BaseButton


func _hint_for(button: BaseButton) -> Control:
	if button == null:
		return null
	var parent: Node = button.get_parent()
	for ignored in range(3):
		if parent == null or parent == app._hud_footer:
			break
		var candidate := parent.find_child("KeyHint", true, false) as Control
		if candidate != null:
			return candidate
		parent = parent.get_parent()
	return null


func _hint_text(hint: Control) -> String:
	var glyph := hint.find_child("Glyph", true, false) as Label
	return glyph.text if glyph != null else ""


func _check_layout(viewport_size: Vector2i) -> void:
	if app.get("_hud_footer") == null:
		_check(false, "play footer exists for %dx%d layout" % [viewport_size.x, viewport_size.y])
		return
	var footer_rect: Rect2 = app._hud_footer.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	_check(viewport_rect.encloses(footer_rect), "footer stays inside %dx%d viewport" % [viewport_size.x, viewport_size.y])
	var labels: Array[Dictionary] = []
	for action: StringName in ACTIONS:
		var button := _button(action)
		var hint := _hint_for(button)
		if button == null or hint == null:
			_check(false, "layout contains %s and its shortcut label" % action)
			continue
		var button_rect: Rect2 = button.get_global_rect()
		var hint_rect: Rect2 = hint.get_global_rect()
		_check(viewport_rect.encloses(button_rect) and viewport_rect.encloses(hint_rect), "%s remains visible at %dx%d" % [action, viewport_size.x, viewport_size.y])
		_check(hint_rect.position.y >= button_rect.end.y - 1.0, "%s shortcut is below its button at %dx%d" % [action, viewport_size.x, viewport_size.y])
		labels.append({"action": str(action), "button": _rect_array(button_rect), "hint": _rect_array(hint_rect)})
	_layout_evidence.append({"viewport": [viewport_size.x, viewport_size.y], "footer": _rect_array(footer_rect), "labels": labels})


func _press(action: StringName, wait_seconds: float = 0.24) -> void:
	var button := _button(action)
	_check(button != null, "%s action is available for signal dispatch" % action)
	if button != null:
		button.pressed.emit()
	await create_timer(wait_seconds).timeout
	await _frames(1)


func _key(key: int, wait_seconds: float = 0.24) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(wait_seconds).timeout
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(1)


func _frames(count: int) -> void:
	for ignored in range(count):
		await process_frame


func _shot(viewport_size: Vector2i) -> void:
	if not capture or DisplayServer.get_name() == "headless" or app.get("_hud_footer") == null:
		return
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var stem := "res://evidence/hud_footer_%dx%d" % [viewport_size.x, viewport_size.y]
	screenshot.save_webp(stem + ".webp", false, 0.95)
	_screenshots.append(stem + ".webp")
	var footer_rect: Rect2 = app._hud_footer.get_global_rect().grow(8.0)
	var region := Rect2i(footer_rect).intersection(Rect2i(Vector2i.ZERO, screenshot.get_size()))
	if region.has_area():
		screenshot.get_region(region).save_png(stem + "_detail.png")
		_screenshots.append(stem + "_detail.png")


func _finish() -> void:
	if is_instance_valid(app):
		app.audio.stop_all()
		app.queue_free()
	await _frames(2)
	await create_timer(0.3).timeout
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _original_master_mute)
	DisplayServer.window_set_mode(_original_window_mode)
	root.size = _original_viewport_size
	root.content_scale_size = _original_content_scale
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := _profile_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "profile_isolated": true, "display_driver": DisplayServer.get_name(), "layouts": _layout_evidence, "screenshots": _screenshots}
	var file := FileAccess.open("res://evidence/hud_footer_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("HUD_FOOTER_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _fixture() -> Dictionary:
	var floor_cells: Array = []
	for y in range(6):
		for x in range(8):
			floor_cells.append([x, y])
	return {"schema_version": 1, "id": "hud_footer_fixture", "title": "HUD TEST", "width": 8, "height": 6,
		"floor": floor_cells, "walls": [], "goals": [[6, 2]], "player": [1, 2], "facing": [1, 0],
		"objects": [{"id": "bag_01", "type": "bag", "cell": [2, 2], "targets": []}],
		"metadata": {"chapter": 1, "hint": "", "solution": []}}
