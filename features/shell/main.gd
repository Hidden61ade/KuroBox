extends Control

const Kit = preload("res://features/shell/ui_kit.gd")
const Profile = preload("res://features/shell/profile_store.gd")
const Sound = preload("res://features/shell/audio_service.gd")
const View = preload("res://features/play/board_view.gd")
const Editor = preload("res://features/editor/level_editor.gd")
const Backdrop = preload("res://features/shell/scrolling_backdrop.gd")
const Transition = preload("res://features/shell/stripe_transition.gd")
const Footer = preload("res://features/play/hud_footer.gd")

var profile: ProfileStore
var audio: AudioService
var campaign: Array[Dictionary] = []
var board: BoardState
var board_view: BoardView
var editor: Control
var current_screen: String = "menu"
var current_index: int = -1
var testing_editor: bool = false
var _content: Control
var _modal: Control
var _modal_kind: String = ""
var _settings_from_play: bool = false
var _actions_label: Label
var _busy: bool = false
var _quitting: bool = false
var _generation: int = 0
var _notice_label: Label
var _import_dialog: FileDialog
var _transition: StripeTransition
var _hud_footer: HudFooter

func _ready() -> void:
	get_tree().auto_accept_quit = false
	theme = Kit.make_theme()
	profile = Profile.new()
	profile.read()
	audio = Sound.new()
	audio.volume = float(profile.settings.sound)
	audio.music_volume = float(profile.settings.music)
	add_child(audio)
	_apply_settings()
	add_child(Backdrop.new())
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_transition = Transition.new()
	add_child(_transition)
	_load_campaign()
	show_menu()
	if "--self-check" in OS.get_cmdline_user_args():
		_release_self_check.call_deferred()
	if not profile.last_error.is_empty():
		show_message("进度", profile.last_error)
	queue_redraw()

func _draw() -> void:
	pass

func _load_campaign() -> void:
	var manifest_path := "res://content/levels/campaign.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("Campaign manifest missing")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		push_error("Campaign manifest is invalid")
		return
	for path: String in manifest.get("levels", []):
		var level := LevelCodec.load_file(path)
		if level.is_empty():
			push_error("Invalid campaign level: " + path)
		else:
			campaign.append(level)

func _clear_content() -> void:
	_close_modal()
	_generation += 1
	_busy = false
	for child: Node in _content.get_children():
		if child == editor:
			_content.remove_child(child)
			child.hide()
		else:
			_content.remove_child(child)
			child.queue_free()
	board_view = null
	_hud_footer = null
	_actions_label = null

func _screen_margin(padding: int = 36) -> MarginContainer:
	var margin := Kit.margin(padding)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(margin)
	return margin

func _button(text: String, callback: Callable, minimum: Vector2 = Vector2(0, 48)) -> Button:
	return Kit.button(text, func() -> void:
		audio.play_event("ui_confirm")
		callback.call(), minimum)

func show_menu() -> void:
	_clear_content()
	current_screen = "menu"
	testing_editor = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	var title := Kit.pixel_label("KURO\nBOX!", 72, Kit.ACCENT)
	title.add_theme_color_override("font_outline_color", Color("333941"))
	title.add_theme_constant_override("outline_size", 6)
	column.add_child(title)
	var breathing_room := Control.new()
	breathing_room.custom_minimum_size = Vector2(0, 90)
	column.add_child(breathing_room)
	var play_row := HBoxContainer.new()
	play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	play_row.add_theme_constant_override("separation", 32)
	column.add_child(play_row)
	play_row.add_child(_icon("levels", "选择关卡", show_level_select, 64, true))
	var play := TextureButton.new()
	play.name = "StartButton"
	play.tooltip_text = "开始训练"
	play.custom_minimum_size = Vector2(104, 80)
	play.ignore_texture_size = true
	play.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	play.texture_normal = load("res://assets/ui/circuit_start_normal.png")
	play.texture_hover = load("res://assets/ui/circuit_start_hover.png")
	play.texture_pressed = load("res://assets/ui/circuit_start_pressed.png")
	play.texture_focused = play.texture_hover
	play.pressed.connect(func() -> void:
		audio.play_event("ui_confirm")
		_navigate(_continue_campaign))
	play_row.add_child(play)
	play_row.add_child(_icon("workshop", "关卡工坊", open_editor, 64, true))
	var lower := HBoxContainer.new()
	lower.alignment = BoxContainer.ALIGNMENT_CENTER
	lower.add_theme_constant_override("separation", 8)
	column.add_child(lower)
	lower.add_child(_icon("fullscreen", "全屏 · F11", _toggle_fullscreen, 48))
	lower.add_child(_icon("music", "声音开关 · M", _toggle_sound, 48))
	lower.add_child(_icon("quit", "退出", request_quit, 48))
	play.grab_focus()
	var corner := HBoxContainer.new()
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	corner.position = Vector2(24, -72)
	_content.add_child(corner)
	corner.add_child(_icon("settings", "设置", show_settings, 40))

func _icon(key: String, hint: String, callback: Callable, extent: int = 64, navigate: bool = false) -> Button:
	return Kit.icon_button(key, hint, func() -> void:
		audio.play_event("ui_confirm")
		if navigate:
			_navigate(callback)
		else:
			callback.call(), extent)

func _navigate(callback: Callable) -> void:
	if _transition != null and not _transition.busy:
		_transition.play(callback)

func _toggle_sound() -> void:
	profile.settings.muted = not bool(profile.settings.muted)
	_apply_settings()
	if profile.write() != OK:
		show_message("设置未保存", profile.last_error)

func _toggle_fullscreen() -> void:
	profile.settings.fullscreen = not bool(profile.settings.fullscreen)
	_apply_settings()
	if profile.write() != OK:
		show_message("设置未保存", profile.last_error)

func _continue_campaign() -> void:
	for index in range(campaign.size()):
		if not profile.completed.has(campaign[index].id):
			start_level(campaign[index], index)
			return
	show_level_select()

func show_level_select() -> void:
	_clear_content()
	current_screen = "select"
	testing_editor = false
	var margin := _screen_margin(36)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(_icon("back", "返回", show_menu, 56, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_icon("import", "导入关卡", import_level, 56))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 36)
	center.add_child(grid)
	for index in range(campaign.size()):
		var level := campaign[index]
		var button := _button("%02d" % (index + 1), func() -> void: _navigate(start_level.bind(level, index)), Vector2(104, 104))
		button.name = "Round%02d" % (index + 1)
		button.tooltip_text = str(level.title)
		var style := StyleBoxTexture.new()
		style.texture = load("res://assets/ui/circuit_num_under.png")
		style.set_texture_margin_all(4)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_font_override("font", load("res://assets/ui/circuit_awesome9.ttf"))
		button.add_theme_font_size_override("font_size", 44)
		button.add_theme_color_override("font_color", Kit.ACCENT if profile.completed.has(level.id) else Kit.PAPER)
		grid.add_child(button)
	if grid.get_child_count() > 0:
		grid.get_child(0).grab_focus()

func start_level(level: Dictionary, index: int = -1, is_editor_test: bool = false) -> void:
	var errors := LevelCodec.validate(level)
	if not errors.is_empty():
		show_message("无法开始", "\n".join(errors))
		return
	_clear_content()
	current_screen = "play"
	current_index = index
	testing_editor = is_editor_test
	board = BoardState.new()
	board.setup(level)
	var margin := _screen_margin(24)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var balance := Control.new()
	balance.custom_minimum_size.x = 52
	header.add_child(balance)
	var title := Kit.pixel_label("%02d" % (index + 1) if index >= 0 else "*", 44)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var pause := _icon("pause", "暂停 · Esc", show_pause, 52)
	pause.name = "PauseButton"
	pause.focus_mode = Control.FOCUS_NONE
	header.add_child(pause)
	board_view = View.new()
	board_view.name = "BoardView"
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.shake_enabled = bool(profile.settings.shake)
	column.add_child(board_view)
	board_view.set_board(board)
	board_view.grab_focus()
	if index in [0, 1]:
		var hint := Kit.pixel_label("W A S D", 18, Kit.MUTED)
		hint.custom_minimum_size.y = 20
		column.add_child(hint)
	var footer_center := CenterContainer.new()
	column.add_child(footer_center)
	_hud_footer = Footer.new()
	_hud_footer.name = "HudFooter"
	footer_center.add_child(_hud_footer)
	_hud_footer.action_requested.connect(_on_hud_action)
	board_view.resized.connect(_resize_hud_footer)
	_resize_hud_footer.call_deferred()
	_sync_hud_options()
	_actions_label = null
	if board.is_won():
		show_completion.call_deferred()

func _resize_hud_footer() -> void:
	if not is_instance_valid(_hud_footer) or not is_instance_valid(board_view) or board == null:
		return
	var board_width := float(board.level.width) * board_view.cell_size
	_hud_footer.custom_minimum_size.x = clampf(board_width, 400.0, maxf(400.0, board_view.size.x - 48.0))

func _sync_hud_options() -> void:
	if is_instance_valid(_hud_footer):
		_hud_footer.sync_options(bool(profile.settings.fullscreen), bool(profile.settings.muted))

func _on_hud_action(action: StringName) -> void:
	if current_screen != "play" or _modal != null or _transition.busy or _quitting:
		return
	match action:
		&"undo": undo_action()
		&"restart": restart_level()
		&"punch": punch_action()
		&"fullscreen": _toggle_fullscreen()
		&"sound": _toggle_sound()
		&"back": _navigate(_leave_play)

func _update_hud() -> void:
	if is_instance_valid(_actions_label) and board != null:
		_actions_label.text = "%02d 步  /  %02d 拳" % [board.moves, board.punches]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if event.echo and key in [KEY_F11, KEY_ESCAPE, KEY_R, KEY_Z, KEY_SPACE, KEY_M, KEY_Q]:
		return
	if key == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_M and current_screen in ["menu", "select", "play"] and _modal == null:
		_toggle_sound()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_ESCAPE:
		if _modal != null:
			if _modal_kind == "settings":
				_finish_settings()
			elif _modal_kind != "completion":
				_close_modal()
				if current_screen == "play" and board != null and board.is_won():
					show_completion()
		elif current_screen == "play":
			show_pause()
		elif current_screen == "select":
			show_menu()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if current_screen != "play" or _modal != null:
		return
	match key:
		KEY_W, KEY_UP: perform_move(Vector2i.UP)
		KEY_S, KEY_DOWN: perform_move(Vector2i.DOWN)
		KEY_A, KEY_LEFT: perform_move(Vector2i.LEFT)
		KEY_D, KEY_RIGHT: perform_move(Vector2i.RIGHT)
		KEY_SPACE: punch_action()
		KEY_Z: undo_action()
		KEY_R: restart_level()
		KEY_Q: _on_hud_action(&"back")
		_: return
	get_viewport().set_input_as_handled()

func perform_move(direction: Vector2i) -> void:
	if not _can_act():
		return
	var before := board.snapshot()
	_perform_result(board.step(direction), before)

func punch_action() -> void:
	if not _can_act():
		return
	var before := board.snapshot()
	_perform_result(board.punch(), before)

func _can_act() -> bool:
	return current_screen == "play" and _modal == null and not _busy and board != null and not board.is_won()

func _perform_result(result: Dictionary, before: Dictionary) -> void:
	board_view.animate_result(result, before)
	_update_hud()
	if result.get("changed", false):
		audio.play_event("punch" if result.get("event") == "punch" else "place")
	_busy = true
	var session := _generation
	await get_tree().create_timer(0.19 if result.get("event") == "punch" else 0.11).timeout
	if session != _generation:
		return
	_busy = false
	if board.is_won() and _modal == null:
		show_completion()

func undo_action() -> void:
	if current_screen != "play" or board == null:
		return
	_close_modal()
	_generation += 1
	_busy = false
	if board.undo():
		board_view.stop_animation()
		_update_hud()
		audio.play_event("undo")
		board_view.grab_focus()

func restart_level() -> void:
	if current_screen != "play" or board == null:
		return
	_close_modal()
	_generation += 1
	_busy = false
	board.restart()
	board_view.stop_animation()
	_update_hud()
	board_view.grab_focus()
	audio.play_event("ui_back")

func _leave_play() -> void:
	if testing_editor:
		return_to_editor()
	else:
		show_level_select()

func _modal_column(minimum_width: int = 430) -> VBoxContainer:
	_close_modal()
	_modal = Control.new()
	_modal.name = "Modal"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.1, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minimum_width
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	center.add_child(panel)
	var margin := Kit.margin(26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	return column

func _close_modal() -> void:
	if is_instance_valid(_modal):
		remove_child(_modal)
		_modal.queue_free()
	_modal = null
	_modal_kind = ""
	if is_instance_valid(board_view):
		board_view.grab_focus()

func show_pause() -> void:
	if current_screen != "play":
		return
	var column := _modal_column(360)
	_modal_kind = "pause"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var resume := _icon("play", "继续", func() -> void:
		_close_modal()
		if board.is_won():
			show_completion(), 64)
	row.add_child(resume)
	row.add_child(_icon("restart", "重来", restart_level, 64))
	row.add_child(_icon("levels", "返回工坊" if testing_editor else "关卡", _leave_play, 64, true))
	row.add_child(_icon("settings", "设置", show_settings, 64))
	resume.grab_focus()

func show_completion() -> void:
	if current_screen != "play" or board == null or not board.is_won():
		return
	var save_error: Error = OK
	if current_index >= 0 and not testing_editor:
		save_error = profile.complete(str(board.level.id), board.moves, board.punches)
	audio.play_event("goal")
	var column := _modal_column(280)
	_modal_kind = "completion"
	column.add_child(Kit.pixel_label("✓", 56, Kit.ACCENT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var next_action: Callable
	if testing_editor:
		next_action = return_to_editor
	elif current_index >= 0 and current_index + 1 < campaign.size():
		next_action = start_level.bind(campaign[current_index + 1], current_index + 1)
	else:
		next_action = show_level_select
	var next := _icon("next", "下一关" if not testing_editor else "返回工坊", next_action, 80, true)
	row.add_child(_icon("undo", "撤销一步", undo_action, 48))
	row.add_child(next)
	row.add_child(_icon("restart", "重新挑战", restart_level, 48))
	next.grab_focus()
	if save_error != OK:
		var status := Kit.label(profile.last_error, 16, Kit.ACCENT)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.custom_minimum_size.x = 280
		column.add_child(status)
		column.add_child(_button("重试保存", show_completion))

func show_settings() -> void:
	_settings_from_play = current_screen == "play"
	var column := _modal_column(500)
	_modal_kind = "settings"
	column.add_child(Kit.label("SETTINGS", 30, Kit.ACCENT))
	for data: Array in [["音效", "sound"], ["音乐", "music"]]:
		column.add_child(Kit.label(data[0], 18))
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(profile.settings[data[1]])
		slider.custom_minimum_size = Vector2(350, 30)
		slider.value_changed.connect(_change_volume.bind(data[1]))
		column.add_child(slider)
	var shake := CheckButton.new()
	shake.text = "拳击震动"
	shake.button_pressed = bool(profile.settings.shake)
	shake.toggled.connect(func(enabled: bool) -> void:
		profile.settings.shake = enabled
		if is_instance_valid(board_view):
			board_view.shake_enabled = enabled)
	column.add_child(shake)
	var fullscreen := CheckButton.new()
	fullscreen.text = "全屏   F11"
	fullscreen.button_pressed = bool(profile.settings.fullscreen)
	fullscreen.toggled.connect(func(enabled: bool) -> void:
		profile.settings.fullscreen = enabled
		_apply_settings())
	column.add_child(fullscreen)
	var done := _button("完成", _finish_settings)
	column.add_child(done)
	done.grab_focus()

func _finish_settings() -> void:
	var error := profile.write()
	_close_modal()
	if _settings_from_play:
		show_pause()
	if error != OK:
		show_message("设置未保存", profile.last_error + "\n本次运行中仍然有效。")

func _change_volume(value: float, key: String) -> void:
	profile.settings[key] = value
	audio.set_levels(float(profile.settings.sound), float(profile.settings.music))

func _apply_settings() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(profile.settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)
	if audio != null:
		audio.set_levels(float(profile.settings.sound), float(profile.settings.music))
		audio.set_muted(bool(profile.settings.muted))
	_sync_hud_options()

func show_message(title: String, message: String) -> void:
	var column := _modal_column(570)
	column.add_child(Kit.label(title, 28, Kit.ACCENT))
	var body := Kit.label(message, 17)
	body.custom_minimum_size = Vector2(480, 60)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	column.add_child(_button("知道了", _close_modal))

func open_editor() -> void:
	_clear_content()
	current_screen = "editor"
	if not is_instance_valid(editor):
		editor = Editor.new()
		editor.name = "LevelEditor"
		editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_content.add_child(editor)
		editor.test_requested.connect(_test_editor_level)
		editor.exit_requested.connect(show_menu)
		editor.sound_requested.connect(audio.play_event)
		var starting: Dictionary = campaign[0].duplicate(true) if not campaign.is_empty() else {}
		if not starting.is_empty():
			starting.id = "custom_round"
			starting.title = "MY ROUND"
			starting.metadata.solution = []
		editor.setup(starting)
	else:
		_content.add_child(editor)
		editor.show()
		editor.resume_after_test()

func _test_editor_level(level: Dictionary) -> void:
	start_level(level, -1, true)

func return_to_editor() -> void:
	_clear_content()
	current_screen = "editor"
	testing_editor = false
	if is_instance_valid(editor):
		_content.add_child(editor)
		editor.show()
		editor.resume_after_test()
	else:
		open_editor()

func import_level() -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.json ; KuroBox level JSON"])
	_import_dialog.title = "导入关卡"
	_import_dialog.file_selected.connect(func(path: String) -> void:
		var imported := LevelCodec.load_file(path)
		if imported.is_empty():
			show_message("导入失败", "\n".join(LevelCodec.last_errors))
		else:
			start_level(imported)
		_import_dialog.queue_free())
	_import_dialog.canceled.connect(_import_dialog.queue_free)
	add_child(_import_dialog)
	_import_dialog.popup_centered_ratio(0.75)

func _exit_tree() -> void:
	if is_instance_valid(editor) and editor.get_parent() == null:
		editor.free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func request_quit() -> void:
	if _quitting:
		return
	if is_instance_valid(editor) and editor.is_dirty():
		var column := _modal_column(480)
		column.add_child(Kit.label("关卡尚未导出", 28, Kit.ACCENT))
		column.add_child(Kit.label("退出后会丢失工坊中的修改。", 18))
		column.add_child(_button("返回工坊", return_to_editor))
		column.add_child(_button("退出", _finish_quit))
	else:
		_finish_quit()

func _finish_quit() -> void:
	_quitting = true
	audio.shutdown()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

func _release_self_check() -> void:
	var failures: Array[String] = []
	var won_count := 0
	for level: Dictionary in campaign:
		var state := BoardState.new()
		state.setup(level)
		for command: String in level.get("metadata", {}).get("solution", []):
			match command:
				"U": state.step(Vector2i.UP)
				"D": state.step(Vector2i.DOWN)
				"L": state.step(Vector2i.LEFT)
				"R": state.step(Vector2i.RIGHT)
				"P": state.punch()
		if state.is_won():
			won_count += 1
		else:
			failures.append(str(level.id))
	if campaign.is_empty():
		failures.append("campaign manifest or JSON export filter")
	open_editor()
	var original: Dictionary = editor.get_level()
	_test_editor_level(original)
	board.step(Vector2i.RIGHT)
	return_to_editor()
	if editor.get_level() != original:
		failures.append("editor/play document isolation")
	audio.shutdown()
	print("RELEASE_SELF_CHECK ", JSON.stringify({"engine":Engine.get_version_info().string, "levels_won":won_count, "editor_preserved":editor.get_level() == original, "failures":failures}))
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
