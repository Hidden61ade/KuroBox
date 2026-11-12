@tool
class_name BoardView
extends Control

const Rim = preload("res://features/play/board_rim.gd")
const PLAY_CELL_SIZE := 64.0
const CAMERA_RESPONSE := 13.0

signal cell_pressed(cell: Vector2i, button: int)
signal cell_dragged(cell: Vector2i, button: int)
signal view_changed

var editor_mode: bool = false
var use_play_camera: bool = false
var cell_size: float = 48.0
var board_origin: Vector2 = Vector2.ZERO
var board: BoardState
var shake_enabled: bool = true
var _preview: Dictionary = {}
var _textures: Dictionary = {}
var _before: Dictionary = {}
var _result: Dictionary = {}
var _phase: float = 1.0
var _tween: Tween
var _last_cell := Vector2i(-100, -100)
var _display_width: int = 8
var _display_height: int = 6
var _zoom: float = 1.0
var _pan := Vector2.ZERO
var _fit_cell_size: float = 48.0
var _panning: bool = false
var _drawing: Node2D
var _rim := Rim.new()
var _floor_bounds := Rect2i()
var _camera_origin := Vector2.ZERO

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	custom_minimum_size = Vector2(200, 200)
	# Control clipping applies to children, so the scrolling map draws here.
	_drawing = Node2D.new()
	_drawing.name = "BoardDrawing"
	add_child(_drawing)
	_drawing.draw.connect(_draw_board)
	set_process(false)
	resized.connect(_layout_board)
	_load_textures()
	_layout_board()

func _load_textures() -> void:
	_textures.clear()
	for sprite: String in ["floor", "wall", "goal", "wood", "bag", "plate", "door", "door_open", "player_down", "player_up", "player_left", "player_right", "player_punch_down", "player_punch_up", "player_punch_left", "player_punch_right"]:
		var path := "res://assets/sprites/" + sprite + ".png"
		var reference_path := "res://assets/sprites/ref_" + sprite + ".png"
		if ResourceLoader.exists(reference_path):
			path = reference_path
		if sprite.begins_with("player_"):
			var boxing_path := "res://assets/sprites/boxing_" + sprite + ".png"
			if ResourceLoader.exists(boxing_path):
				path = boxing_path
		if ResourceLoader.exists(path):
			_textures[sprite] = load(path)
	for definition: Dictionary in ObjectCatalog.all_types():
		for field: String in ["sprite", "sprite_open"]:
			var path: String = str(definition.get(field, ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				_textures[path] = load(path)
	_textures["floor_even"] = preload("res://assets/ui/floor_even.png")
	_textures["floor_odd"] = preload("res://assets/ui/floor_odd.png")
	_textures["goal"] = preload("res://assets/sprites/sokoban_goal.png")
	for index in range(6):
		var path := "res://assets/effects/ref_punch_arc_%d.png" % index
		if ResourceLoader.exists(path):
			_textures["punch_arc_%d" % index] = load(path)

func refresh_catalog() -> void:
	_load_textures()
	refresh_drawing()

func set_board(state: BoardState) -> void:
	var new_level := board != state
	board = state
	_preview = {}
	if new_level:
		_cache_floor_geometry()
	stop_animation()
	_layout_board()

func set_level_preview(level: Dictionary) -> void:
	board = null
	_preview = level
	_cache_floor_geometry()
	stop_animation()
	_layout_board()

func _cache_floor_geometry() -> void:
	_floor_bounds = Rect2i()
	if editor_mode:
		return
	var floor_cells: Array = _level().get("floor", [])
	_rim.setup(floor_cells)
	if floor_cells.is_empty():
		return
	var first := _cell(floor_cells[0])
	_floor_bounds = Rect2i(first, Vector2i.ONE)
	for raw: Variant in floor_cells:
		var cell := _cell(raw)
		_floor_bounds = _floor_bounds.expand(cell).expand(cell + Vector2i.ONE)

func _layout_board() -> void:
	var data := _level()
	_display_width = maxi(1, int(data.get("width", 8)))
	_display_height = maxi(1, int(data.get("height", 6)))
	if _has_play_camera():
		cell_size = PLAY_CELL_SIZE
		_camera_origin = _camera_target()
		_set_origin(_camera_origin.round())
		set_process(_phase < 1.0)
		refresh_drawing()
		return
	var fit := minf((size.x - 48.0) / _display_width, (size.y - 48.0) / _display_height)
	# Original ground is 16px and authored boxing sprites are 32px.
	# Keep ground pixels at an integer scale at every supported board size.
	_fit_cell_size = maxf(16.0, floorf(minf(fit, 64.0) / 16.0) * 16.0)
	cell_size = maxf(4.0, _fit_cell_size * _zoom)
	_set_origin((size - Vector2(_display_width, _display_height) * cell_size) * 0.5 + _pan)
	refresh_drawing()

func _has_play_camera() -> bool:
	return use_play_camera and not editor_mode and board != null and _floor_bounds.has_area()

func _set_origin(value: Vector2) -> void:
	board_origin = value
	if is_instance_valid(_drawing):
		_drawing.position = board_origin
	view_changed.emit()

func _camera_target() -> Vector2:
	var bounds := Rect2(Vector2(_floor_bounds.position) * cell_size, Vector2(_floor_bounds.size) * cell_size)
	bounds = bounds.grow(Rim.PADDING_TILES * cell_size)
	var center := (_animated_player_cell() + Vector2.ONE * 0.5) * cell_size
	var target := size * 0.5 - center
	for axis: int in range(2):
		if bounds.size[axis] <= size[axis]:
			target[axis] = (size[axis] - bounds.size[axis]) * 0.5 - bounds.position[axis]
		else:
			target[axis] = clampf(target[axis], size[axis] - bounds.end[axis], -bounds.position[axis])
	return target

func _process(delta: float) -> void:
	if not _has_play_camera():
		set_process(false)
		return
	var target := _camera_target()
	_camera_origin = _camera_origin.lerp(target, 1.0 - exp(-CAMERA_RESPONSE * delta))
	if _phase >= 1.0 and _camera_origin.distance_squared_to(target) < 0.25:
		_camera_origin = target
		set_process(false)
	var snapped := _camera_origin.round()
	if snapped != board_origin:
		_set_origin(snapped)

func refresh_drawing() -> void:
	if is_instance_valid(_drawing):
		_drawing.queue_redraw()

func fit_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_layout_board()

func get_view_state() -> Dictionary:
	return {"zoom": _zoom, "pan": _pan}

func restore_view_state(state: Dictionary) -> void:
	_zoom = clampf(float(state.get("zoom", 1.0)), 0.25, 8.0)
	var value: Variant = state.get("pan", Vector2.ZERO)
	_pan = value if value is Vector2 else Vector2(float(value[0]), float(value[1])) if value is Array and value.size() == 2 else Vector2.ZERO
	_layout_board()

func zoom_at(factor: float, local_position: Vector2) -> void:
	if factor <= 0.0 or not is_finite(factor):
		return
	var cell_position := (local_position - board_origin) / cell_size
	_zoom = clampf(_zoom * factor, 0.25, 8.0)
	cell_size = maxf(4.0, _fit_cell_size * _zoom)
	var centered := (size - Vector2(_display_width, _display_height) * cell_size) * 0.5
	_pan = local_position - cell_position * cell_size - centered
	_layout_board()

func pan_by(delta: Vector2) -> void:
	_pan += delta
	_layout_board()

func focus_cell(cell: Vector2i) -> void:
	pan_by(size * 0.5 - cell_to_rect(cell).get_center())

func _level() -> Dictionary:
	return board.level if board != null else _preview

func screen_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(((local_position - board_origin) / cell_size).floor())

func cell_to_rect(cell: Vector2i) -> Rect2:
	return Rect2(board_origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size)

func _drawing_cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size)

func _gui_input(event: InputEvent) -> void:
	if not editor_mode:
		if event is InputEventMouseButton and event.pressed:
			grab_focus()
		return
	var canvas_rect := Rect2(Vector2.ZERO, size)
	if event is InputEventMouseButton:
		if event.pressed and not canvas_rect.has_point(event.position):
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			grab_focus()
			zoom_at(1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, event.position)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			grab_focus()
			_panning = event.pressed
			accept_event()
			return
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				grab_focus()
			_last_cell = screen_to_cell(event.position)
			if event.pressed:
				cell_pressed.emit(_last_cell, event.button_index)
			else:
				_last_cell = Vector2i(-100, -100)
			accept_event()
	elif event is InputEventMouseMotion:
		if _panning and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan_by(event.relative)
			accept_event()
			return
		if not canvas_rect.has_point(event.position):
			return
		var cell := screen_to_cell(event.position)
		if cell != _last_cell:
			var button := MOUSE_BUTTON_LEFT if event.button_mask & MOUSE_BUTTON_MASK_LEFT else MOUSE_BUTTON_RIGHT if event.button_mask & MOUSE_BUTTON_MASK_RIGHT else 0
			if button != 0:
				cell_dragged.emit(cell, button)
				_last_cell = cell

func stop_animation() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_phase = 1.0
	_before = {}
	_result = {}
	set_process(_has_play_camera())
	refresh_drawing()

func animate_result(result: Dictionary, before: Dictionary) -> void:
	stop_animation()
	_before = before
	_result = result
	_phase = 0.0
	_tween = create_tween()
	_tween.tween_method(_animate_phase, 0.0, 1.0, 0.18 if result.get("event") == "punch" else 0.105).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _animate_phase(value: float) -> void:
	_phase = value
	refresh_drawing()

func _animated_player_cell() -> Vector2:
	var cell := Vector2(board.player if board != null else _cell(_level().get("player", [1, 1])))
	if _phase < 1.0 and _before.has("player"):
		return Vector2(_before.player).lerp(cell, _phase)
	return cell

func _draw_board() -> void:
	var level := _level()
	if level.is_empty():
		return
	var origin_shift := Vector2.ZERO
	if shake_enabled and _result.get("event") == "punch" and _phase < 1.0:
		origin_shift = Vector2(sin(_phase * 28.0), cos(_phase * 22.0)) * (1.0 - _phase) * 2.0
	_drawing.draw_set_transform(origin_shift)
	if not editor_mode:
		_rim.draw_rim(_drawing, Vector2.ZERO, cell_size)
	var floors: Array = level.get("floor", [])
	var walls_raw: Array = level.get("walls", [])
	var goals_raw: Array = level.get("goals", [])
	var floor_lookup: Dictionary = {}
	for raw: Variant in floors:
		var cell := _cell(raw)
		if editor_mode:
			floor_lookup[cell] = true
		var rect := _drawing_cell_rect(cell)
		var key := "floor_even" if (cell.x + cell.y) % 2 == 0 else "floor_odd"
		var tint := Color.WHITE
		if _textures.has(key):
			_drawing.draw_texture_rect(_textures[key], rect, false, tint)
		else:
			_drawing.draw_rect(rect, Color("b9b9aa") * tint)
			_drawing.draw_rect(rect, Color("969d94"), false, 1.0)
	if editor_mode:
		for y in range(_display_height):
			for x in range(_display_width):
				var cell := Vector2i(x, y)
				if not floor_lookup.has(cell):
					_drawing.draw_rect(_drawing_cell_rect(cell), Color("292f34"))
				_drawing.draw_rect(_drawing_cell_rect(cell), Color("485052"), false, 1.0)
	for raw: Variant in goals_raw:
		var cell := _cell(raw)
		_draw_sprite("goal", Vector2(cell), Color("cf9c4c"))
	var objects: Array[Dictionary] = []
	if board != null:
		for item: Dictionary in board.objects.values():
			objects.append(item)
	else:
		for raw: Dictionary in level.get("objects", []):
			var item: Dictionary = raw.duplicate(true)
			item.cell = _cell(raw.get("cell", [0, 0]))
			objects.append(item)
	for item: Dictionary in objects:
		var definition := ObjectCatalog.get_type(str(item.get("type", "")))
		if definition.get("behavior", item.get("type")) == "plate":
			_draw_sprite(str(definition.get("sprite", "plate")), Vector2(item.cell), Color("6f9292"), Color.WHITE if not item.get("pressed", false) else Color("ffe7aa"))
	for raw: Variant in walls_raw:
		_draw_sprite("wall", Vector2(_cell(raw)), Color("566772"))
	objects.sort_custom(_device_first)
	for item: Dictionary in objects:
		var definition := ObjectCatalog.get_type(str(item.get("type", "")))
		var behavior: String = definition.get("behavior", str(item.type))
		if behavior == "plate":
			continue
		var position_in_cells := Vector2(item.cell)
		if _phase < 1.0 and _before.has("objects") and _before.objects.has(item.id):
			var original: Dictionary = _before.objects[item.id]
			position_in_cells = Vector2(original.cell).lerp(position_in_cells, _phase)
		var key: String = str(definition.get("sprite", item.type))
		if behavior == "door":
			if item.get("open", false):
				key = str(definition.get("sprite_open", "door_open"))
		var color := Color(str(definition.get("color", "d2a469")))
		_draw_sprite(key, position_in_cells, color)
		if board != null and behavior in ["wood", "bag"] and board.goals.has(item.cell):
			var mark := _drawing_cell_rect(item.cell).grow(-3.0)
			_drawing.draw_rect(mark, Color("ffd541"), false, 2.0)
	var player_cell := _animated_player_cell()
	var direction: Vector2i = board.facing if board != null else _cell(level.get("facing", [1, 0]))
	var suffix := "right" if direction.x > 0 else "left" if direction.x < 0 else "down" if direction.y > 0 else "up"
	var player_sprite := "player_" + suffix
	var lunge := Vector2.ZERO
	if _result.get("event") == "punch" and _phase < 0.8:
		if _textures.has("player_punch_" + suffix):
			player_sprite = "player_punch_" + suffix
		lunge = Vector2(direction) * sin(_phase * PI) * 0.15
	_draw_sprite(player_sprite, player_cell + lunge, Color("e56b50"))
	if board != null and _phase >= 1.0 and not board.is_won():
		var front_id: String = board.object_at(board.player + board.facing)
		if not front_id.is_empty() and ObjectCatalog.get_type(str(board.objects[front_id].type)).get("punchable", false):
			var landing: Vector2i = board.preview_punch()
			var landing_rect := _drawing_cell_rect(landing).grow(-cell_size * 0.23)
			_drawing.draw_rect(landing_rect, Color(1.0, 0.94, 0.66, 0.85), false, 2.0)
			var a := _drawing_cell_rect(board.player + board.facing).get_center()
			var b := _drawing_cell_rect(landing).get_center()
			_drawing.draw_line(a, b, Color(1.0, 0.94, 0.66, 0.55), 2.0)
	if _result.get("event") == "punch" and _phase < 1.0:
		var impact: Vector2 = _drawing_cell_rect(Vector2i(player_cell) + direction).get_center()
		var arc_key := "punch_arc_%d" % mini(5, int(_phase * 6))
		if _textures.has(arc_key):
			_drawing.draw_set_transform(impact + origin_shift, Vector2(direction).angle())
			_drawing.draw_texture_rect(_textures[arc_key], Rect2(Vector2.ONE * -cell_size * 0.65, Vector2.ONE * cell_size * 1.3), false)
	_drawing.draw_set_transform(Vector2.ZERO)

func _draw_sprite(key: String, cell: Vector2, fallback: Color, tint: Color = Color.WHITE) -> void:
	var rect := Rect2(cell * cell_size, Vector2.ONE * cell_size)
	if _textures.has(key):
		_drawing.draw_texture_rect(_textures[key], rect, false, tint)
	else:
		var inset := rect.grow(-cell_size * 0.14)
		_drawing.draw_rect(Rect2(inset.position + Vector2(2, 3), inset.size), Color(0.1, 0.12, 0.13, 0.45))
		_drawing.draw_rect(inset, fallback)
		_drawing.draw_rect(inset, Color("30333a"), false, 2.0)
		if key == "wood":
			_drawing.draw_line(inset.position, inset.end, Color("746044"), 3.0)
			_drawing.draw_line(Vector2(inset.end.x, inset.position.y), Vector2(inset.position.x, inset.end.y), Color("746044"), 3.0)
		elif key == "goal":
			_drawing.draw_rect(inset.grow(-4), Color("fff0b0"), false, 2.0)

func _cell(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO

func _device_first(first: Dictionary, second: Dictionary) -> bool:
	var a: String = str(ObjectCatalog.get_type(str(first.type)).get("behavior", ""))
	var b: String = str(ObjectCatalog.get_type(str(second.type)).get("behavior", ""))
	return (0 if a in ["plate", "door"] else 1) < (0 if b in ["plate", "door"] else 1)
