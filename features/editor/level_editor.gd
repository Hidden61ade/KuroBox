class_name LevelEditor
extends Control
## The authored document is independent of both the preview and play-test state.

signal test_requested(level: Dictionary)
signal exit_requested
signal sound_requested(event: String)

const Catalog = preload("res://core/object_catalog.gd")
const Codec = preload("res://core/level_codec.gd")
const View = preload("res://features/play/board_view.gd")
const State = preload("res://core/board_state.gd")
const Backdrop = preload("res://features/shell/scrolling_backdrop.gd")
const MIN_SIDE := 4
const MAX_SIDE := 24
const HISTORY_LIMIT := 200
const INK := Color("d5d8dc")
const PAPER := Color("333941")
const ACCENT := Color("ffd541")

var document: Dictionary = {}
var _saved_document: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _stroke_before: Dictionary = {}
var _clipboard: Dictionary = {}
var _tool := "brush"
var _palette := "floor"
var _drag_start := Vector2i(-1, -1)
var _drag_cell := Vector2i(-1, -1)
var _selection := Rect2i()
var _focus_cell := Vector2i(-1, -1)
var _selected_id := ""
var _link_source := ""
var _pending_action := ""
var _path := ""
var _built := false
var _refreshing := false
var _standalone_state: RefCounted
var _standalone_layer: Control
var _standalone_board: Control
var _standalone_label: Label
var _standalone_won := false
var _local_audio: Node

var _board: Control
var _overlay: Control
var _document_label: Label
var _status: Label
var _title_edit: LineEdit
var _id_edit: LineEdit
var _width_spin: SpinBox
var _height_spin: SpinBox
var _tool_picker: OptionButton
var _palette_buttons: Dictionary = {}
var _undo_button: Button
var _redo_button: Button
var _inspector: VBoxContainer
var _errors: ItemList
var _error_cells: Array[Vector2i] = []
var _file_dialog: FileDialog
var _confirm_dialog: ConfirmationDialog


class EditorOverlay extends Control:
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if theme == null and ResourceLoader.exists("res://features/shell/ui_kit.gd"):
		theme = load("res://features/shell/ui_kit.gd").make_theme()
	if theme != null:
		var compact: Theme = theme.duplicate()
		compact.default_font_size = 16
		for type_name in ["Button", "OptionButton", "LineEdit"]:
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				if compact.has_stylebox(state, type_name):
					var style: StyleBox = compact.get_stylebox(state, type_name).duplicate()
					style.content_margin_left = 10
					style.content_margin_right = 10
					style.content_margin_top = 6
					style.content_margin_bottom = 6
					if style is StyleBoxFlat:
						style.set_border_width_all(1)
						style.set_corner_radius_all(0)
						if state == "normal":
							style.bg_color = Color("292f38")
						elif state == "pressed":
							style.bg_color = Color("40525e")
							style.border_color = ACCENT
					compact.set_stylebox(state, type_name, style)
		theme = compact
	_build_ui()
	if document.is_empty():
		setup()
	else:
		_refresh()


func _exit_tree() -> void:
	if is_instance_valid(_local_audio) and _local_audio.has_method("stop_all"):
		_local_audio.stop_all()


func setup(level: Dictionary = {}) -> void:
	document = _new_level() if level.is_empty() else Codec.normalize(level.duplicate(true))
	_saved_document = document.duplicate(true)
	_undo.clear()
	_redo.clear()
	_stroke_before.clear()
	_selection = Rect2i()
	_focus_cell = Vector2i(-1, -1)
	_selected_id = ""
	_link_source = ""
	_path = ""
	if _built:
		_refresh()


func get_level() -> Dictionary:
	_finish_edit()
	return document.duplicate(true)


func is_dirty() -> bool:
	return JSON.stringify(document) != JSON.stringify(_saved_document)


func resume_after_test() -> void:
	visible = true
	if _standalone_layer != null:
		_standalone_layer.queue_free()
		_standalone_layer = null
	_standalone_state = null
	_standalone_board = null
	_standalone_won = false
	# Deliberately do not reload or replace the authored document / selection.
	if _built:
		_status.text = ""
		_board.queue_redraw()
		_overlay.queue_redraw()


func _build_ui() -> void:
	var background := Backdrop.new()
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	_document_label = Label.new()
	_document_label.text = "关卡工坊"
	_document_label.add_theme_font_size_override("font_size", 22)
	_document_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_document_label)
	_button(top, "新建", func(): _ask_action("new"))
	_button(top, "导入", func(): _ask_action("import"))
	_button(top, "导出", _request_export)
	_button(top, "▶ 测试", _request_test)
	_button(top, "返回", func(): _ask_action("exit"))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size.x = 238
	side_panel.add_theme_stylebox_override("panel", _panel_style(PAPER))
	body.add_child(side_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 7)
	scroll.add_child(side)
	_section(side, "关卡")
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "关卡名称"
	_title_edit.tooltip_text = "关卡选择界面显示的名称"
	side.add_child(_title_edit)
	_title_edit.text_submitted.connect(func(_text: String): _commit_text())
	_title_edit.focus_exited.connect(_commit_text)
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "稳定 ID，例如 workshop_01"
	_id_edit.tooltip_text = "存档和关卡引用使用的稳定标识；改标题无需改 ID"
	side.add_child(_id_edit)
	_id_edit.text_submitted.connect(func(_text: String): _commit_text())
	_id_edit.focus_exited.connect(_commit_text)
	var dimensions := HBoxContainer.new()
	side.add_child(dimensions)
	var width_label := _small_label(dimensions, "宽")
	width_label.add_theme_color_override("font_color", INK)
	_width_spin = _spin(dimensions)
	var height_label := _small_label(dimensions, "高")
	height_label.add_theme_color_override("font_color", INK)
	_height_spin = _spin(dimensions)
	_width_spin.value_changed.connect(_resize_changed)
	_height_spin.value_changed.connect(_resize_changed)
	_section(side, "工具")
	_tool_picker = OptionButton.new()
	for name in ["画笔  B", "擦除  E", "矩形  R", "填充  F", "框选  S", "移动选区  M", "粘贴  V"]:
		_tool_picker.add_item(name)
	_tool_picker.item_selected.connect(func(index: int): _select_tool(["brush", "erase", "rect", "fill", "select", "move", "paste"][index]))
	side.add_child(_tool_picker)
	var edit_row := HBoxContainer.new()
	side.add_child(edit_row)
	_undo_button = _button(edit_row, "↶ 撤销", undo_edit)
	_redo_button = _button(edit_row, "↷ 重做", redo_edit)
	var clip_row := HBoxContainer.new()
	side.add_child(clip_row)
	_button(clip_row, "复制选区", copy_selection)
	_button(clip_row, "粘贴", func(): _select_tool("paste"))
	_section(side, "图块 / 物件")
	var palette_grid := GridContainer.new()
	palette_grid.columns = 2
	side.add_child(palette_grid)
	_palette_button(palette_grid, "地板", "floor")
	_palette_button(palette_grid, "墙", "walls")
	_palette_button(palette_grid, "目标格", "goals")
	_palette_button(palette_grid, "出生点", "spawn")
	for definition: Dictionary in Catalog.all_types():
		_palette_button(palette_grid, str(definition.get("editor_label", definition.get("label", definition.get("id", "?")))), "object:" + str(definition.get("id", "")))
	_section(side, "选中 / 属性")
	_inspector = VBoxContainer.new()
	side.add_child(_inspector)
	var board_column := VBoxContainer.new()
	board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(board_column)
	var board_container := PanelContainer.new()
	board_container.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT))
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(board_container)
	_board = View.new()
	_board.editor_mode = true
	_board.tooltip_text = "左键绘制 · 右键擦除当前层 · Ctrl+Z 撤销 / Ctrl+Y 重做"
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_container.add_child(_board)
	_board.cell_pressed.connect(_on_cell_pressed)
	_board.cell_dragged.connect(_on_cell_dragged)
	_overlay = EditorOverlay.new()
	_overlay.editor = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(_overlay)
	_board.resized.connect(func(): _overlay.queue_redraw())
	var errors_title := HBoxContainer.new()
	board_column.add_child(errors_title)
	_small_label(errors_title, "检查结果")
	_button(errors_title, "检查关卡", validate_document)
	_errors = ItemList.new()
	_errors.custom_minimum_size.y = 64
	_errors.add_theme_stylebox_override("panel", _panel_style(Color("29313be8")))
	_errors.add_theme_font_size_override("font_size", 13)
	_errors.item_selected.connect(_focus_error)
	board_column.add_child(_errors)
	_status = Label.new()
	_status.text = ""
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	root.add_child(_status)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.kuro.json,*.json ; KuroBox 关卡"])
	_file_dialog.size = Vector2i(820, 560)
	_file_dialog.file_selected.connect(_file_selected)
	add_child(_file_dialog)
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "尚未导出"
	_confirm_dialog.dialog_text = "当前修改尚未导出。离开会丢弃这些修改。"
	_confirm_dialog.ok_button_text = "丢弃并继续"
	_confirm_dialog.cancel_button_text = "继续编辑"
	_confirm_dialog.confirmed.connect(_execute_pending)
	add_child(_confirm_dialog)
	_built = true


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.set_corner_radius_all(0)
	return style


func _button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 34
	var icon_keys := {"新建":"new", "导入":"import", "导出":"export", "▶ 测试":"play", "返回":"back", "↶ 撤销":"undo", "↷ 重做":"redo", "复制选区":"copy", "粘贴":"paste", "检查关卡":"check"}
	if icon_keys.has(text):
		var icon_path: String = "res://assets/ui/icon_" + str(icon_keys[text]) + ".png"
		if ResourceLoader.exists(icon_path):
			result.icon = load(icon_path)
			result.expand_icon = true
			result.add_theme_constant_override("icon_max_width", 20)
	result.pressed.connect(func():
		_play_sound("ui_confirm")
		action.call())
	parent.add_child(result)
	return result


func _section(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func _small_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _spin(parent: Node) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = MIN_SIDE
	result.max_value = MAX_SIDE
	result.step = 1
	result.custom_minimum_size.x = 76
	parent.add_child(result)
	return result


func _palette_button(parent: Node, text: String, key: String) -> void:
	var button := _button(parent, text, func(): _select_palette(key))
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sprite_path: String = {"floor":"res://assets/ui/floor_even.png", "walls":"res://assets/sprites/ref_wall.png", "goals":"res://assets/sprites/sokoban_goal.png", "spawn":"res://assets/sprites/boxing_player_down.png"}.get(key, "")
	if key.begins_with("object:"):
		sprite_path = str(Catalog.get_type(key.trim_prefix("object:")).get("sprite", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		button.icon = load(sprite_path)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
	_palette_buttons[key] = button


func _select_palette(key: String) -> void:
	_palette = key
	_link_source = ""
	for entry in _palette_buttons:
		_palette_buttons[entry].button_pressed = entry == key
	_status.text = ""


func _select_tool(key: String) -> void:
	_finish_edit()
	_tool = key
	_link_source = ""
	_drag_start = Vector2i(-1, -1)
	var index: int = ["brush", "erase", "rect", "fill", "select", "move", "paste"].find(key)
	if index >= 0 and _built:
		_tool_picker.select(index)
		_status.text = ""
	_overlay.queue_redraw()


func _refresh() -> void:
	if not _built:
		return
	_refreshing = true
	_title_edit.text = str(document.get("title", ""))
	_id_edit.text = str(document.get("id", ""))
	_width_spin.value = int(document.get("width", 8))
	_height_spin.value = int(document.get("height", 6))
	_refreshing = false
	_board.set_level_preview(document)
	_overlay.queue_redraw()
	_undo_button.disabled = _undo.is_empty()
	_redo_button.disabled = _redo.is_empty()
	_document_label.text = "关卡工坊" + ("  ●" if is_dirty() else "")
	for entry in _palette_buttons:
		_palette_buttons[entry].button_pressed = entry == _palette
	_refresh_inspector()


func _commit_text() -> void:
	if _refreshing or document.is_empty():
		return
	_begin_edit()
	document["title"] = _title_edit.text.strip_edges()
	document["id"] = _id_edit.text.strip_edges()
	_finish_edit()


func _resize_changed(_value: float) -> void:
	if _refreshing:
		return
	resize_document(int(_width_spin.value), int(_height_spin.value))


func resize_document(width: int, height: int) -> void:
	_begin_edit()
	document["width"] = clampi(width, MIN_SIDE, MAX_SIDE)
	document["height"] = clampi(height, MIN_SIDE, MAX_SIDE)
	var removed := 0
	for layer in ["floor", "walls", "goals"]:
		var kept: Array = []
		for cell in document.get(layer, []):
			if _inside(_vec(cell)):
				kept.append(cell)
			else:
				removed += 1
		document[layer] = kept
	var objects: Array = []
	var removed_ids: Array[String] = []
	for object: Dictionary in document.get("objects", []):
		if _inside(_vec(object.get("cell", [-1, -1]))):
			objects.append(object)
		else:
			removed_ids.append(str(object.get("id", "")))
			removed += 1
	document["objects"] = objects
	_remove_target_refs(removed_ids)
	if not _inside(_vec(document.get("player", [-1, -1]))):
		document["player"] = [-1, -1]
		removed += 1
	_selection = Rect2i()
	_finish_edit()
	if _built:
		_status.text = "地图尺寸已更新" if removed == 0 else "已裁去 %d 项越界内容 · 可撤销恢复；请重新检查出生点" % removed


func _begin_edit() -> void:
	if _stroke_before.is_empty():
		_stroke_before = document.duplicate(true)


func _finish_edit() -> void:
	if _stroke_before.is_empty():
		return
	if JSON.stringify(document) != JSON.stringify(_stroke_before):
		# A stored solution only describes the previous authored revision.
		if document.get("metadata") is Dictionary:
			document["metadata"]["solution"] = []
		_undo.append(_stroke_before)
		if _undo.size() > HISTORY_LIMIT:
			_undo.pop_front()
		_redo.clear()
		_play_sound("place")
	_stroke_before = {}
	_refresh()


func undo_edit() -> void:
	_finish_edit()
	if _undo.is_empty():
		return
	_redo.append(document.duplicate(true))
	document = _undo.pop_back()
	_play_sound("undo")
	_refresh()


func redo_edit() -> void:
	_finish_edit()
	if _redo.is_empty():
		return
	_undo.append(document.duplicate(true))
	document = _redo.pop_back()
	_play_sound("undo")
	_refresh()


func _on_cell_pressed(cell: Vector2i, button: int) -> void:
	if not _inside(cell) or _standalone_state != null:
		return
	_finish_edit()
	_focus_cell = cell
	if _link_source != "":
		_link_at(cell)
		return
	_select_object_at(cell)
	if _tool == "paste":
		paste_clipboard(cell)
		return
	if _tool == "move":
		move_selection(cell)
		return
	if _tool in ["rect", "select"] and button == MOUSE_BUTTON_LEFT:
		_drag_start = cell
		_drag_cell = cell
		_overlay.queue_redraw()
		return
	if _tool == "fill":
		fill_cells(cell, button == MOUSE_BUTTON_RIGHT)
		return
	_begin_edit()
	_paint_cell(cell, button == MOUSE_BUTTON_RIGHT or _tool == "erase")
	_preview_change()


func _on_cell_dragged(cell: Vector2i, button: int) -> void:
	if not _inside(cell) or _standalone_state != null:
		return
	if _tool in ["rect", "select"] and _drag_start.x >= 0:
		_drag_cell = cell
		_overlay.queue_redraw()
	elif _tool in ["brush", "erase"] and _link_source == "":
		_begin_edit()
		_paint_cell(cell, button == MOUSE_BUTTON_RIGHT or _tool == "erase")
		_preview_change()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _standalone_state != null:
		_handle_standalone_input(event)
		return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _drag_start.x >= 0:
			var area := _rect_between(_drag_start, _drag_cell)
			if _tool == "rect":
				paint_rectangle(area, false)
			elif _tool == "select":
				_selection = area
				_select_object_at(_drag_cell)
			_drag_start = Vector2i(-1, -1)
			_overlay.queue_redraw()
		_finish_edit()
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _file_dialog.visible or _confirm_dialog.visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_Z:
				redo_edit() if event.shift_pressed else undo_edit()
			KEY_Y:
				redo_edit()
			KEY_C:
				copy_selection()
			KEY_V:
				_select_tool("paste")
			KEY_S:
				_request_export()
		return
	match event.keycode:
		KEY_B: _select_tool("brush")
		KEY_E: _select_tool("erase")
		KEY_R: _select_tool("rect")
		KEY_F: _select_tool("fill")
		KEY_S: _select_tool("select")
		KEY_M: _select_tool("move")
		KEY_V: _select_tool("paste")
		KEY_F5: _request_test()
		KEY_ESCAPE:
			if _link_source != "":
				_link_source = ""
				_refresh_inspector()
			else:
				_ask_action("exit")


func _paint_cell(cell: Vector2i, erase: bool) -> void:
	if not _inside(cell):
		return
	if _palette in ["floor", "walls", "goals"]:
		_set_layer_cell(_palette, cell, not erase)
	elif _palette == "spawn":
		if not erase:
			document["player"] = _array(cell)
		elif _vec(document.get("player", [-1, -1])) == cell:
			document["player"] = [-1, -1]
	elif _palette.begins_with("object:"):
		var type_id := _palette.trim_prefix("object:")
		var definition: Dictionary = Catalog.get_type(type_id)
		var device := str(definition.get("behavior", "")) in ["plate", "door"]
		var removed_ids: Array[String] = []
		var keep: Array = []
		for object: Dictionary in document.get("objects", []):
			var old_device := str(Catalog.get_type(str(object.get("type", ""))).get("behavior", "")) in ["plate", "door"]
			if _vec(object.get("cell", [-1, -1])) == cell and old_device == device:
				if not erase and str(object.get("type", "")) == type_id:
					_selected_id = str(object.get("id", ""))
					return
				removed_ids.append(str(object.get("id", "")))
			else:
				keep.append(object)
		document["objects"] = keep
		_remove_target_refs(removed_ids)
		if not erase:
			var object_id := _unique_id(type_id)
			var object := {"id": object_id, "type": type_id, "cell": _array(cell), "targets": []}
			document["objects"].append(object)
			_selected_id = object_id


func _set_layer_cell(layer: String, cell: Vector2i, enabled: bool) -> void:
	var entries: Array = document.get(layer, [])
	var index := -1
	for i in range(entries.size()):
		if _vec(entries[i]) == cell:
			index = i
			break
	if enabled and index < 0:
		entries.append(_array(cell))
	elif not enabled and index >= 0:
		entries.remove_at(index)
	document[layer] = entries


func paint_rectangle(area: Rect2i, erase: bool = false) -> void:
	_begin_edit()
	if _palette == "spawn":
		_paint_cell(area.position, erase)
	else:
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				_paint_cell(Vector2i(x, y), erase)
	_finish_edit()


func fill_cells(start: Vector2i, erase: bool = false) -> void:
	if _palette not in ["floor", "walls", "goals"]:
		if _built:
			_status.text = "填充用于地板、墙、目标格；物件请用画笔或矩形"
		return
	var occupied: Dictionary = {}
	for raw in document.get(_palette, []):
		occupied[_vec(raw)] = true
	var source_has: bool = occupied.has(start)
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary = {}
	_begin_edit()
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if not _inside(cell) or seen.has(cell):
			continue
		seen[cell] = true
		if occupied.has(cell) != source_has:
			continue
		_paint_cell(cell, erase)
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			queue.append(cell + delta)
	_finish_edit()


func _preview_change() -> void:
	if _built:
		_board.set_level_preview(document)
		_overlay.queue_redraw()
		_refresh_inspector()


func copy_selection() -> void:
	if not _selection.has_area():
		if _built:
			_status.text = "先用框选工具选中区域"
		return
	_clipboard = _capture_region(_selection)
	if _built:
		_status.text = "已复制 %d × %d 选区 · 选择粘贴后点击左上角" % [_selection.size.x, _selection.size.y]


func _capture_region(area: Rect2i) -> Dictionary:
	var result := {"size": _array(area.size), "floor": [], "walls": [], "goals": [], "objects": []}
	for layer in ["floor", "walls", "goals"]:
		for raw in document.get(layer, []):
			var cell := _vec(raw)
			if area.has_point(cell):
				result[layer].append(_array(cell - area.position))
	for object: Dictionary in document.get("objects", []):
		if area.has_point(_vec(object.get("cell", [-1, -1]))):
			var copy := object.duplicate(true)
			copy["cell"] = _array(_vec(copy["cell"]) - area.position)
			result["objects"].append(copy)
	var spawn := _vec(document.get("player", [-1, -1]))
	if area.has_point(spawn):
		result["player"] = _array(spawn - area.position)
	return result


func paste_clipboard(destination: Vector2i) -> void:
	if _clipboard.is_empty():
		if _built:
			_status.text = "剪贴板为空 · 先框选并复制"
		return
	var area := Rect2i(destination, _vec(_clipboard["size"]))
	if not _region_inside(area):
		if _built:
			_status.text = "选区超出地图，未粘贴"
		return
	_begin_edit()
	_clear_region(area)
	_insert_region(_clipboard, destination, true)
	_selection = area
	_finish_edit()


func move_selection(destination: Vector2i) -> void:
	if not _selection.has_area():
		if _built:
			_status.text = "先框选要移动的区域，再点击目标左上角"
		return
	var area := Rect2i(destination, _selection.size)
	if not _region_inside(area):
		if _built:
			_status.text = "选区超出地图，未移动"
		return
	var content := _capture_region(_selection)
	_begin_edit()
	# Clear both areas before insertion, which also makes overlapping moves safe.
	_clear_region(_selection, false)
	_clear_region(area, false)
	_insert_region(content, destination, false)
	_remove_broken_targets()
	_selection = area
	_finish_edit()


func _clear_region(area: Rect2i, clean_links: bool = true) -> void:
	for layer in ["floor", "walls", "goals"]:
		var keep: Array = []
		for raw in document.get(layer, []):
			if not area.has_point(_vec(raw)):
				keep.append(raw)
		document[layer] = keep
	var removed_ids: Array[String] = []
	var keep_objects: Array = []
	for object: Dictionary in document.get("objects", []):
		if area.has_point(_vec(object.get("cell", [-1, -1]))):
			removed_ids.append(str(object.get("id", "")))
		else:
			keep_objects.append(object)
	document["objects"] = keep_objects
	if area.has_point(_vec(document.get("player", [-1, -1]))):
		document["player"] = [-1, -1]
	if clean_links:
		_remove_target_refs(removed_ids)


func _insert_region(content: Dictionary, destination: Vector2i, copy_ids: bool) -> void:
	for layer in ["floor", "walls", "goals"]:
		for raw in content.get(layer, []):
			_set_layer_cell(layer, _vec(raw) + destination, true)
	var remap: Dictionary = {}
	var copies: Array[Dictionary] = []
	for object: Dictionary in content.get("objects", []):
		var copy := object.duplicate(true)
		var original_id := str(copy.get("id", ""))
		if copy_ids:
			copy["id"] = _unique_id(str(copy.get("type", "object")), remap.values())
		remap[original_id] = str(copy["id"])
		copy["cell"] = _array(_vec(copy["cell"]) + destination)
		copies.append(copy)
	for copy: Dictionary in copies:
		var targets: Array = []
		for target in copy.get("targets", []):
			targets.append(remap.get(str(target), str(target)))
		copy["targets"] = targets
		document["objects"].append(copy)
	if content.has("player"):
		document["player"] = _array(_vec(content["player"]) + destination)


func _select_object_at(cell: Vector2i) -> void:
	_selected_id = ""
	for object: Dictionary in document.get("objects", []):
		if _vec(object.get("cell", [-1, -1])) == cell:
			_selected_id = str(object.get("id", ""))
	_refresh_inspector()


func _refresh_inspector() -> void:
	if not _built:
		return
	for child in _inspector.get_children():
		_inspector.remove_child(child)
		child.queue_free()
	var cell_text := "未选择格子" if _focus_cell.x < 0 else "格子 (%d, %d)" % [_focus_cell.x, _focus_cell.y]
	var location := _small_label(_inspector, cell_text)
	location.add_theme_color_override("font_color", INK)
	var objects_here: Array[Dictionary] = []
	for object: Dictionary in document.get("objects", []):
		if _vec(object.get("cell", [-1, -1])) == _focus_cell:
			objects_here.append(object)
	if objects_here.size() > 1:
		var picker := OptionButton.new()
		for object: Dictionary in objects_here:
			picker.add_item(str(object.get("id", "")))
			if str(object.get("id", "")) == _selected_id:
				picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int):
			_selected_id = str(objects_here[index].get("id", ""))
			_refresh_inspector())
		_inspector.add_child(picker)
	var selected := _find_object(_selected_id)
	if not selected.is_empty():
		var identity := _small_label(_inspector, str(selected.get("id", "")))
		identity.add_theme_color_override("font_color", INK)
		identity.add_theme_font_size_override("font_size", 13)
		var definition: Dictionary = Catalog.get_type(str(selected.get("type", "")))
		var description := Label.new()
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = str(definition.get("editor_label", definition.get("label", selected.get("type", ""))))
		description.add_theme_color_override("font_color", INK)
		_inspector.add_child(description)
		if str(definition.get("behavior", "")) == "plate":
			var link_button := _button(_inspector, "取消连线" if _link_source == _selected_id else "连线到门", _toggle_link)
			link_button.tooltip_text = "点击后，点选棋盘上的门来连接或断开；Esc 结束"
			var doors := 0
			for object: Dictionary in document.get("objects", []):
				if str(Catalog.get_type(str(object.get("type", ""))).get("behavior", "")) != "door":
					continue
				doors += 1
				var door_id := str(object.get("id", ""))
				var check := CheckBox.new()
				check.text = door_id
				check.add_theme_color_override("font_color", INK)
				check.button_pressed = selected.get("targets", []).has(door_id)
				check.toggled.connect(func(_enabled: bool): _toggle_target(_selected_id, door_id))
				_inspector.add_child(check)
			if doors == 0:
				var hint := _small_label(_inspector, "先摆放一扇门")
				hint.add_theme_color_override("font_color", INK)
		_button(_inspector, "删除这个实例", _delete_selected)
	if _palette == "spawn" or _vec(document.get("player", [-1, -1])) == _focus_cell:
		var facing := OptionButton.new()
		for label in ["出生朝向 →", "出生朝向 ↓", "出生朝向 ←", "出生朝向 ↑"]:
			facing.add_item(label)
		var vectors := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
		facing.select(maxi(0, vectors.find(_vec(document.get("facing", [1, 0])))))
		facing.item_selected.connect(func(index: int):
			_begin_edit()
			document["facing"] = _array(vectors[index])
			_finish_edit())
		_inspector.add_child(facing)
	if _selection.has_area():
		var selection_label := _small_label(_inspector, "选区 %d × %d" % [_selection.size.x, _selection.size.y])
		selection_label.add_theme_color_override("font_color", INK)
	_overlay.queue_redraw()


func _delete_selected() -> void:
	_begin_edit()
	var keep: Array = []
	for object: Dictionary in document.get("objects", []):
		if str(object.get("id", "")) != _selected_id:
			keep.append(object)
	document["objects"] = keep
	_remove_target_refs([_selected_id])
	_selected_id = ""
	_link_source = ""
	_finish_edit()


func _toggle_link() -> void:
	_link_source = "" if _link_source == _selected_id else _selected_id
	_status.text = "点击门以连接 / 断开；Esc 结束连线" if _link_source != "" else "连线结束"
	_refresh_inspector()


func _link_at(cell: Vector2i) -> void:
	for object: Dictionary in document.get("objects", []):
		if _vec(object.get("cell", [-1, -1])) == cell and str(Catalog.get_type(str(object.get("type", ""))).get("behavior", "")) == "door":
			_toggle_target(_link_source, str(object.get("id", "")))
			return
	_status.text = "请选择门 · Esc 结束连线"


func _toggle_target(source_id: String, door_id: String) -> void:
	var object := _find_object(source_id)
	if object.is_empty():
		return
	_begin_edit()
	var targets: Array = object.get("targets", []).duplicate()
	if targets.has(door_id):
		targets.erase(door_id)
	else:
		targets.append(door_id)
	object["targets"] = targets
	_finish_edit()


func validate_document() -> Array[String]:
	_finish_edit()
	var messages: Array[String] = Codec.validate(document)
	messages.append_array(_editor_limits(document))
	if _built:
		_errors.clear()
		_error_cells.clear()
		if messages.is_empty():
			_errors.add_item("✓ 结构检查通过 · 可测试 / 导出（不代表已证明可解）")
			_error_cells.append(Vector2i(-1, -1))
		else:
			for message: String in messages:
				_errors.add_item(message)
				_error_cells.append(_error_cell(message))
		_status.text = "检查通过" if messages.is_empty() else "%d 项配置问题 · 点击结果定位" % messages.size()
	return messages


func _editor_limits(level: Dictionary) -> Array[String]:
	var messages: Array[String] = []
	for field in ["width", "height"]:
		var value := int(level.get(field, 0))
		if value < MIN_SIDE or value > MAX_SIDE:
			messages.append("编辑范围：%s 必须在 %d–%d 格之间" % [field, MIN_SIDE, MAX_SIDE])
	return messages


func _error_cell(message: String) -> Vector2i:
	for object: Dictionary in document.get("objects", []):
		if message.contains(str(object.get("id", "__no_instance_id__"))):
			return _vec(object.get("cell", [-1, -1]))
	var pattern := RegEx.new()
	pattern.compile("[\\(\\[]\\s*(-?\\d+)\\s*,\\s*(-?\\d+)\\s*[\\)\\]]")
	var match_result := pattern.search(message)
	if match_result:
		return Vector2i(int(match_result.get_string(1)), int(match_result.get_string(2)))
	if message.to_lower().contains("player") or message.contains("出生"):
		return _vec(document.get("player", [-1, -1]))
	return Vector2i(-1, -1)


func _focus_error(index: int) -> void:
	if index >= 0 and index < _error_cells.size():
		_focus_cell = _error_cells[index]
		_select_object_at(_focus_cell)
		_overlay.queue_redraw()


func _request_export() -> void:
	_commit_text()
	if not validate_document().is_empty():
		return
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = "导出关卡"
	_file_dialog.current_file = str(document.get("id", "workshop")) + ".kuro.json"
	if _path != "":
		_file_dialog.current_path = _path
	_file_dialog.popup_centered(Vector2i(820, 560))


func _file_selected(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		var imported: Dictionary = Codec.load_file(path)
		if imported.is_empty() or imported.has("error") or imported.has("_error"):
			_errors.clear()
			_error_cells.clear()
			for message: String in Codec.last_errors:
				_errors.add_item("导入失败 · " + message)
				_error_cells.append(Vector2i(-1, -1))
			_status.text = "导入失败，当前关卡保持不变；原因见检查结果"
			return
		var messages: Array[String] = Codec.validate(imported)
		messages.append_array(_editor_limits(imported))
		# Keep the last valid document on malformed or incompatible imports.
		if not messages.is_empty():
			_errors.clear()
			_error_cells.clear()
			for message: String in messages:
				_errors.add_item("导入失败 · " + message)
				_error_cells.append(Vector2i(-1, -1))
			_status.text = "文件有 %d 项问题，当前关卡保持不变" % messages.size()
			return
		setup(imported)
		_path = path
		_status.text = "已导入 " + path.get_file()
	else:
		if not path.to_lower().ends_with(".json"):
			path += ".kuro.json"
		var error: Error = Codec.save_file(path, document)
		if error != OK:
			_status.text = "导出失败：" + error_string(error)
			return
		_path = path
		_saved_document = document.duplicate(true)
		_refresh()
		_status.text = "已导出 " + path.get_file()


func _ask_action(action: String) -> void:
	_commit_text()
	_finish_edit()
	_pending_action = action
	if is_dirty():
		_confirm_dialog.popup_centered()
	else:
		_execute_pending()


func _execute_pending() -> void:
	var action := _pending_action
	_pending_action = ""
	match action:
		"new":
			setup()
			_status.text = "新关卡"
		"import":
			_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.title = "导入关卡"
			_file_dialog.popup_centered(Vector2i(820, 560))
		"exit":
			if is_dirty():
				document = _saved_document.duplicate(true)
				_undo.clear()
				_redo.clear()
				_selection = Rect2i()
				_selected_id = ""
				_refresh()
			if exit_requested.get_connections().is_empty():
				get_tree().quit()
			else:
				exit_requested.emit()


func _request_test() -> void:
	_commit_text()
	if not validate_document().is_empty():
		return
	var level := get_level()
	if test_requested.get_connections().is_empty():
		_start_standalone_test(level)
	else:
		test_requested.emit(level)


func _start_standalone_test(level: Dictionary) -> void:
	_standalone_state = State.new()
	_standalone_state.setup(level.duplicate(true))
	_standalone_won = false
	_standalone_layer = PanelContainer.new()
	_standalone_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_standalone_layer.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT))
	add_child(_standalone_layer)
	_standalone_layer.add_child(Backdrop.new())
	var column := VBoxContainer.new()
	_standalone_layer.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_standalone_label = Label.new()
	_standalone_label.text = "TEST"
	_standalone_label.tooltip_text = "方向键 / WASD 移动 · Space 出拳 · Z 撤销 · R 重开"
	_standalone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_standalone_label)
	_button(top, "返回编辑  Esc", resume_after_test)
	_standalone_board = View.new()
	_standalone_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_standalone_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_standalone_board)
	_standalone_board.set_board(_standalone_state)


func _handle_standalone_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var before: Dictionary = _standalone_state.snapshot()
	var result: Dictionary = {}
	match event.keycode:
		KEY_ESCAPE:
			resume_after_test()
			get_viewport().set_input_as_handled()
			return
		KEY_Z, KEY_BACKSPACE:
			_standalone_state.undo()
			_standalone_won = false
		KEY_R:
			_standalone_state.restart()
			_standalone_won = false
		KEY_SPACE:
			if not _standalone_won:
				result = _standalone_state.punch()
		KEY_LEFT, KEY_A:
			if not _standalone_won:
				result = _standalone_state.step(Vector2i.LEFT)
		KEY_RIGHT, KEY_D:
			if not _standalone_won:
				result = _standalone_state.step(Vector2i.RIGHT)
		KEY_UP, KEY_W:
			if not _standalone_won:
				result = _standalone_state.step(Vector2i.UP)
		KEY_DOWN, KEY_S:
			if not _standalone_won:
				result = _standalone_state.step(Vector2i.DOWN)
		_:
			return
	_standalone_board.set_board(_standalone_state)
	if not result.is_empty():
		_standalone_board.animate_result(result, before)
		if result.get("changed", false):
			_play_sound("punch" if result.get("event", "") == "punch" else "place")
	_standalone_won = _standalone_state.is_won()
	if _standalone_won:
		_play_sound("goal")
	_standalone_label.text = "✓" if _standalone_won else "%d / %d" % [_standalone_state.moves, _standalone_state.punches]
	get_viewport().set_input_as_handled()


func _find_object(object_id: String) -> Dictionary:
	for object: Dictionary in document.get("objects", []):
		if str(object.get("id", "")) == object_id:
			return object
	return {}


func _play_sound(event: String) -> void:
	if not _built:
		return
	if not sound_requested.get_connections().is_empty():
		sound_requested.emit(event)
		return
	if _local_audio == null and ResourceLoader.exists("res://features/shell/audio_service.gd"):
		_local_audio = load("res://features/shell/audio_service.gd").new()
		_local_audio.music_volume = 0.0
		add_child(_local_audio)
	if _local_audio != null:
		_local_audio.play_event(event)


func _unique_id(prefix: String, reserved: Array = []) -> String:
	var number := 1
	while not _find_object("%s_%02d" % [prefix, number]).is_empty() or reserved.has("%s_%02d" % [prefix, number]):
		number += 1
	return "%s_%02d" % [prefix, number]


func _remove_target_refs(removed_ids: Array) -> void:
	for object: Dictionary in document.get("objects", []):
		var targets: Array = []
		for target in object.get("targets", []):
			if not removed_ids.has(str(target)):
				targets.append(target)
		object["targets"] = targets


func _remove_broken_targets() -> void:
	for object: Dictionary in document.get("objects", []):
		var targets: Array = []
		for target in object.get("targets", []):
			if not _find_object(str(target)).is_empty():
				targets.append(target)
		object["targets"] = targets


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(document.get("width", 0)) and cell.y < int(document.get("height", 0))


func _region_inside(area: Rect2i) -> bool:
	return area.has_area() and _inside(area.position) and _inside(area.end - Vector2i.ONE)


func _rect_between(first: Vector2i, last: Vector2i) -> Rect2i:
	var start := Vector2i(mini(first.x, last.x), mini(first.y, last.y))
	var end := Vector2i(maxi(first.x, last.x), maxi(first.y, last.y))
	return Rect2i(start, end - start + Vector2i.ONE)


func _vec(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


func _array(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


func _new_level() -> Dictionary:
	var floor_cells: Array = []
	for y in range(1, 7):
		for x in range(1, 9):
			floor_cells.append([x, y])
	return {"schema_version": 1, "id": "workshop_01", "title": "NEW ROUND", "width": 10, "height": 8,
		"floor": floor_cells, "walls": [], "goals": [[7, 3]], "player": [2, 3], "facing": [1, 0],
		"objects": [{"id": "wood_01", "type": "wood", "cell": [4, 3], "targets": []}],
		"metadata": {"chapter": 1, "hint": "", "solution": []}}
