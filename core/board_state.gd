@tool
class_name BoardState
extends RefCounted
## Deterministic command model. Rendering, audio and input never own puzzle state.

const Codec = preload("res://core/level_codec.gd")
const Catalog = preload("res://core/object_catalog.gd")
var level: Dictionary = {}
var player := Vector2i.ZERO
var facing := Vector2i.RIGHT
var objects: Dictionary = {}
var floor_cells: Dictionary[Vector2i, bool] = {}
var walls: Dictionary[Vector2i, bool] = {}
var goals: Dictionary[Vector2i, bool] = {}
var moves := 0
var punches := 0
var setup_errors: Array[String] = []
var _solids: Dictionary[Vector2i, String] = {}
var _devices: Dictionary[Vector2i, String] = {}
var _history: Array[Dictionary] = []
var _initial_snapshot: Dictionary = {}
var _device_debug: Array[Dictionary] = []


func setup(source: Dictionary) -> void:
	level.clear()
	objects.clear()
	floor_cells.clear()
	walls.clear()
	goals.clear()
	_history.clear()
	_initial_snapshot.clear()
	_solids.clear()
	_devices.clear()
	_device_debug.clear()
	player = Vector2i.ZERO
	facing = Vector2i.RIGHT
	moves = 0
	punches = 0
	setup_errors = Codec.validate(source)
	if not setup_errors.is_empty():
		return
	level = Codec.normalize(source)
	for cell: Vector2i in Codec.cells(level["floor"]):
		floor_cells[cell] = true
	for cell: Vector2i in Codec.cells(level["walls"]):
		walls[cell] = true
	for cell: Vector2i in Codec.cells(level["goals"]):
		goals[cell] = true
	player = _cell(level["player"])
	facing = _cell(level["facing"])
	for raw: Dictionary in level["objects"]:
		var runtime := raw.duplicate(true)
		runtime["cell"] = _cell(raw["cell"])
		# Freeze the checked effective rules for this run. Catalog edits affect the
		# next setup/replay rather than changing an animation's outcome mid-command.
		runtime["_definition"] = Catalog.resolve_instance(raw)
		runtime["behavior"] = runtime["_definition"].get("behavior", "")
		if runtime["behavior"] == "door":
			runtime["open"] = false
		elif runtime["behavior"] == "plate":
			runtime["pressed"] = false
		objects[str(raw["id"])] = runtime
	_reindex()
	_settle_devices()
	_initial_snapshot = snapshot()


func step(direction: Vector2i) -> Dictionary:
	if level.is_empty() or absi(direction.x) + absi(direction.y) != 1:
		return _result(false, "blocked", "", player, player)
	var before := snapshot()
	facing = direction
	var destination := player + direction
	if not _terrain_open(destination):
		_remember_facing(before)
		return _result(false, "blocked", "", player, destination)
	var item_id := object_at(destination)
	if not item_id.is_empty():
		var definition: Dictionary = objects[item_id]["_definition"]
		var next_cell := destination + direction
		if not definition.get("pushable", false) or not can_enter(next_cell):
			_remember_facing(before)
			return _result(false, "blocked", item_id, destination, destination)
		_history.append(before)
		objects[item_id]["cell"] = next_cell
		player = destination
		moves += 1
		_reindex()
		_settle_devices()
		return _result(true, "push", item_id, destination, next_cell)
	_history.append(before)
	var previous := player
	player = destination
	moves += 1
	_settle_devices()
	return _result(true, "walk", "", previous, destination)


func punch() -> Dictionary:
	if level.is_empty():
		return _result(false, "blocked", "", player, player)
	var adjacent := player + facing
	var item_id := object_at(adjacent)
	if item_id.is_empty():
		return _result(false, "blocked", "", adjacent, adjacent)
	var definition: Dictionary = objects[item_id]["_definition"]
	if not definition.get("punchable", false):
		return _result(false, "blocked", item_id, adjacent, adjacent)
	var landing := preview_punch()
	if landing == adjacent:
		return _result(false, "blocked", item_id, adjacent, adjacent)
	_history.append(snapshot())
	objects[item_id]["cell"] = landing
	moves += 1
	punches += 1
	_reindex()
	_settle_devices()
	return _result(true, "punch", item_id, adjacent, landing)


func preview_punch() -> Vector2i:
	var adjacent := player + facing
	var item_id := object_at(adjacent)
	if item_id.is_empty():
		return player
	var definition: Dictionary = objects[item_id]["_definition"]
	if not definition.get("punchable", false):
		return player
	var landing := adjacent
	for ignored: int in range(int(definition.get("punch_distance", 2))):
		var candidate := landing + facing
		if not can_enter(candidate):
			break
		landing = candidate
	return landing


func object_at(cell: Vector2i, include_devices: bool = false) -> String:
	if _solids.has(cell):
		return _solids[cell]
	return _devices.get(cell, "") if include_devices else ""


func can_enter(cell: Vector2i) -> bool:
	return _terrain_open(cell) and not _solids.has(cell)


func undo() -> bool:
	if _history.is_empty():
		return false
	_restore(_history.pop_back())
	return true


func restart() -> void:
	if _initial_snapshot.is_empty():
		return
	_restore(_initial_snapshot)
	_history.clear()


func snapshot() -> Dictionary:
	return {"player": player, "facing": facing, "objects": objects.duplicate(true), "moves": moves, "punches": punches}


func is_won() -> bool:
	if goals.is_empty() or level.is_empty():
		return false
	for cell: Vector2i in goals:
		if not _solids.has(cell):
			return false
	return true


func _terrain_open(cell: Vector2i) -> bool:
	if not floor_cells.has(cell) or walls.has(cell):
		return false
	var device_id: String = _devices.get(cell, "")
	if not device_id.is_empty() and objects[device_id]["behavior"] == "door":
		return bool(objects[device_id].get("open", false))
	return true


func _settle_devices() -> void:
	_device_debug.clear()
	var incoming: Dictionary = {}
	var powered: Dictionary = {}
	for item_id: String in objects:
		var item: Dictionary = objects[item_id]
		if item["behavior"] != "plate":
			continue
		var cell: Vector2i = item["cell"]
		var filter: String = item["_definition"].get("activation_filter", "all")
		var occupants: Array[String] = []
		var pressed_by: Array[String] = []
		if player == cell:
			occupants.append("player")
			if filter in ["all", "player"]:
				pressed_by.append("player")
		if _solids.has(cell):
			occupants.append(_solids[cell])
			if filter in ["all", "boxes"]:
				pressed_by.append(_solids[cell])
		item["pressed"] = not pressed_by.is_empty()
		for target: String in item.get("targets", []):
			if not incoming.has(target):
				incoming[target] = []
			if not powered.has(target):
				powered[target] = []
			incoming[target].append(item_id)
			if item["pressed"]:
				powered[target].append(item_id)
		var reason := "Pressed by %s (filter: %s)." % [", ".join(pressed_by), filter] if item["pressed"] else "Not pressed: %s; filter: %s." % ["empty" if occupants.is_empty() else "occupant excluded", filter]
		_device_debug.append({"id": item_id, "behavior": "plate", "pressed": item["pressed"], "filter": filter, "activation_filter": filter, "powered_by": pressed_by, "occupants": occupants, "targets": item.get("targets", []).duplicate(), "held_open": false, "reason": reason})
	for item_id: String in objects:
		var item: Dictionary = objects[item_id]
		if item["behavior"] == "door":
			var cell: Vector2i = item["cell"]
			var linked: Array = incoming.get(item_id, [])
			var active: Array = powered.get(item_id, [])
			linked.sort()
			active.sort()
			var logic: String = item["_definition"].get("gate_logic", "any")
			var receives_power := not linked.is_empty() and (active.size() == linked.size() if logic == "all" else not active.is_empty())
			var occupants: Array[String] = []
			if player == cell:
				occupants.append("player")
			if _solids.has(cell):
				occupants.append(_solids[cell])
			var held := not occupants.is_empty() and not receives_power
			item["open"] = receives_power or not occupants.is_empty()
			var reason := "Held open by %s; %d/%d plates active (%s)." % [", ".join(occupants), active.size(), linked.size(), logic] if held else "%s: %d/%d plates active (%s)." % ["Powered" if receives_power else "Closed", active.size(), linked.size(), logic]
			_device_debug.append({"id": item_id, "behavior": "door", "open": item["open"], "powered": receives_power, "logic": logic, "gate_logic": logic, "linked_plates": linked.duplicate(), "powered_by": active.duplicate(), "active_inputs": active.size(), "required_inputs": linked.size(), "held_open": held, "held_by": occupants if held else [], "occupants": occupants, "reason": reason})
	_device_debug.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left["id"]) < str(right["id"]))


func device_debug() -> Array[Dictionary]:
	return _device_debug.duplicate(true)


func _reindex() -> void:
	_solids.clear()
	_devices.clear()
	for item_id: String in objects:
		var item: Dictionary = objects[item_id]
		if item["behavior"] in ["wood", "bag"]:
			_solids[item["cell"]] = item_id
		else:
			_devices[item["cell"]] = item_id


func _restore(saved: Dictionary) -> void:
	player = saved["player"]
	facing = saved["facing"]
	objects = saved["objects"].duplicate(true)
	moves = int(saved["moves"])
	punches = int(saved["punches"])
	_reindex()
	_settle_devices()


func _remember_facing(before: Dictionary) -> void:
	if before["facing"] != facing:
		_history.append(before)


func _result(changed: bool, event: String, object_id: String, origin: Vector2i, destination: Vector2i) -> Dictionary:
	return {"changed": changed, "event": event, "object_id": object_id, "from": origin, "to": destination, "won": is_won(), "facing": facing}


static func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))
