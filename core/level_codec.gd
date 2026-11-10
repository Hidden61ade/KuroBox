@tool
class_name LevelCodec
extends RefCounted
## Wire format boundary. Validation precedes normalization, simulation and disk writes.

const Catalog = preload("res://core/object_catalog.gd")
const SCHEMA_VERSION := 1
const MIN_SIDE := 4
const MAX_SIDE := 24
const MAX_FILE_BYTES := 8 * 1024 * 1024
static var last_errors: Array[String] = []


static func normalize(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	# Godot's JSON parser reads numbers as floats. Canonicalize only validated
	# integer wire fields; never round or truncate malformed authoring input.
	for field: String in ["schema_version", "width", "height"]:
		if _integer(result.get(field)):
			result[field] = int(result[field])
	for field: String in ["floor", "walls", "goals"]:
		if result.get(field) is Array:
			for index: int in range(result[field].size()):
				if _is_cell(result[field][index]):
					result[field][index] = [int(result[field][index][0]), int(result[field][index][1])]
	for field: String in ["player", "facing"]:
		if _is_cell(result.get(field)):
			result[field] = [int(result[field][0]), int(result[field][1])]
	if not result.has("facing"):
		result["facing"] = [1, 0]
	if not result.has("metadata"):
		result["metadata"] = {}
	if result.get("metadata") is Dictionary:
		if not result["metadata"].has("solution"):
			result["metadata"]["solution"] = []
	if result.get("objects") is Array:
		for item: Variant in result["objects"]:
			if item is Dictionary:
				if not item.has("targets"):
					item["targets"] = []
				if _is_cell(item.get("cell")):
					item["cell"] = [int(item["cell"][0]), int(item["cell"][1])]
				if item.get("params") is Dictionary and _integer(item["params"].get("punch_distance")):
					item["params"]["punch_distance"] = int(item["params"]["punch_distance"])
	return result


static func validate(data: Dictionary) -> Array[String]:
	return _validate(data, false)


static func validate_draft(data: Dictionary) -> Array[String]:
	return _validate(data, true)


static func _validate(data: Dictionary, draft: bool) -> Array[String]:
	var errors: Array[String] = []
	if not _integer(data.get("schema_version")) or int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("schema_version: only version 1 is supported.")
	if not data.get("id") is String or str(data.get("id", "")).strip_edges().is_empty():
		errors.append("id: a non-empty stable level ID is required.")
	if not data.get("title") is String:
		errors.append("title: expected text.")
	var dimensions_valid := true
	for field: String in ["width", "height"]:
		if not _integer(data.get(field)) or int(data.get(field, 0)) < MIN_SIDE or int(data.get(field, 0)) > MAX_SIDE:
			errors.append("%s: expected an integer from %d to %d." % [field, MIN_SIDE, MAX_SIDE])
			dimensions_valid = false
	var size := Vector2i(int(data.get("width", 0)) if _integer(data.get("width")) else 0, int(data.get("height", 0)) if _integer(data.get("height")) else 0)
	var layer_maps: Dictionary = {}
	for field: String in ["floor", "walls", "goals"]:
		var mapped: Dictionary = {}
		if not data.get(field) is Array:
			errors.append("%s: expected a cell array." % field)
		else:
			for index: int in range(data[field].size()):
				var raw: Variant = data[field][index]
				if not _is_cell(raw):
					errors.append("%s[%d]: expected two integer coordinates." % [field, index])
					continue
				var cell := Vector2i(int(raw[0]), int(raw[1]))
				if dimensions_valid and not _in_bounds(cell, size):
					errors.append("%s[%d]: cell %s is outside the map." % [field, index, cell])
				if mapped.has(cell):
					errors.append("%s: duplicate cell %s." % [field, cell])
				mapped[cell] = true
		layer_maps[field] = mapped
	var floors: Dictionary = layer_maps["floor"]
	var blocked: Dictionary = layer_maps["walls"]
	if floors.is_empty() and not draft:
		errors.append("floor: draw at least one floor cell.")
	for field: String in ["walls", "goals"]:
		for cell: Vector2i in layer_maps[field]:
			if not floors.has(cell) and not draft:
				errors.append("%s: cell %s needs floor beneath it." % [field, cell])
			if field == "goals" and blocked.has(cell):
				errors.append("goals: cell %s overlaps a wall." % cell)
	if layer_maps["goals"].is_empty() and not draft:
		errors.append("goals: place at least one target.")
	var player_valid := _is_cell(data.get("player"))
	var spawn := Vector2i(-1, -1)
	var missing_spawn := not data.has("player") or data.get("player") == null or (player_valid and int(data["player"][0]) == -1 and int(data["player"][1]) == -1)
	if draft and missing_spawn:
		player_valid = false
	elif not player_valid:
		errors.append("player: expected one spawn cell with integer coordinates.")
	else:
		spawn = Vector2i(int(data["player"][0]), int(data["player"][1]))
		if dimensions_valid and not _in_bounds(spawn, size):
			errors.append("player: spawn is outside the map.")
		if (not floors.has(spawn) and not draft) or blocked.has(spawn):
			errors.append("player: spawn must be on clear floor.")
	var direction: Variant = data.get("facing", [1, 0])
	if not _is_cell(direction) or (abs(int(direction[0])) + abs(int(direction[1])) != 1):
		errors.append("facing: expected one cardinal unit direction.")
	var ids: Dictionary = {}
	# An entity (player/box) may stand on one device (plate/gate). Keep the
	# authoring layers identical to BoardState._solids and _devices. An occupied
	# gate starts held open, powered or not, and closes when empty if unpowered.
	var solid_cells: Dictionary = {}
	var device_cells: Dictionary = {}
	var movable_count := 0
	var raw_objects: Variant = data.get("objects")
	if not raw_objects is Array:
		errors.append("objects: expected an array.")
	else:
		for index: int in range(raw_objects.size()):
			var item: Variant = raw_objects[index]
			if not item is Dictionary:
				errors.append("objects[%d]: expected an object." % index)
				continue
			var item_id: String = str(item.get("id", ""))
			if not item.get("id") is String or item_id.strip_edges().is_empty():
				errors.append("objects[%d].id: a stable instance ID is required." % index)
			elif ids.has(item_id):
				errors.append("objects: duplicate ID '%s'." % item_id)
			else:
				ids[item_id] = item
			var definition: Dictionary = Catalog.get_type(str(item.get("type", "")))
			var behavior: String = str(definition.get("behavior", ""))
			if definition.is_empty():
				errors.append("objects[%d].type: unknown type '%s'." % [index, str(item.get("type", ""))])
			elif behavior in ["wood", "bag"]:
				movable_count += 1
			if not definition.is_empty():
				errors.append_array(Catalog.validate_parameters(item))
			if not _is_cell(item.get("cell")):
				errors.append("objects[%d].cell: expected two integer coordinates." % index)
			else:
				var cell := Vector2i(int(item["cell"][0]), int(item["cell"][1]))
				if dimensions_valid and not _in_bounds(cell, size):
					errors.append("objects[%d]: '%s' is outside the map." % [index, item_id])
				if (not floors.has(cell) and not draft) or blocked.has(cell):
					errors.append("objects[%d]: '%s' needs clear floor." % [index, item_id])
				if behavior in ["wood", "bag"]:
					if solid_cells.has(cell):
						errors.append("entities: box '%s' overlaps box '%s' at %s." % [item_id, solid_cells[cell], cell])
					if player_valid and cell == spawn:
						errors.append("entities: box '%s' overlaps the player spawn." % item_id)
					solid_cells[cell] = item_id
				elif behavior in ["plate", "door"]:
					if device_cells.has(cell):
						errors.append("devices: '%s' overlaps device '%s' at %s." % [item_id, device_cells[cell], cell])
					device_cells[cell] = item_id
			if not item.get("targets", []) is Array:
				errors.append("objects[%d].targets: expected an array of gate IDs." % index)
	if movable_count < layer_maps["goals"].size() and not draft:
		errors.append("goals: %d targets need at least %d boxes; only %d exist." % [layer_maps["goals"].size(), layer_maps["goals"].size(), movable_count])
	var linked_doors: Dictionary = {}
	for item_id: String in ids:
		var item: Dictionary = ids[item_id]
		var definition: Dictionary = Catalog.get_type(str(item.get("type", "")))
		var links: Variant = item.get("targets", [])
		if not links is Array:
			continue
		if definition.get("behavior") == "plate":
			if links.is_empty() and not draft:
				errors.append("plate '%s': link at least one gate." % item_id)
			var seen: Dictionary = {}
			for target: Variant in links:
				if not target is String:
					errors.append("plate '%s': gate references must be strings." % item_id)
					continue
				if seen.has(target):
					errors.append("plate '%s': duplicate gate reference '%s'." % [item_id, target])
				seen[target] = true
				if not ids.has(target):
					if not draft:
						errors.append("plate '%s': missing gate reference '%s'." % [item_id, target])
					continue
				var target_definition: Dictionary = Catalog.get_type(str(ids[target].get("type", "")))
				if target_definition.get("behavior") != "door":
					errors.append("plate '%s': target '%s' is not a gate." % [item_id, target])
				else:
					linked_doors[target] = true
		elif not links.is_empty():
			errors.append("object '%s': only pressure plates may define targets." % item_id)
	for item_id: String in ids:
		var definition: Dictionary = Catalog.get_type(str(ids[item_id].get("type", "")))
		if definition.get("behavior") == "door" and not linked_doors.has(item_id) and not draft:
			errors.append("gate '%s': no pressure plate links to it." % item_id)
	if data.has("metadata") and not data["metadata"] is Dictionary:
		errors.append("metadata: expected an object.")
	elif data.get("metadata", {}).has("solution"):
		var solution: Variant = data["metadata"]["solution"]
		if not solution is Array:
			errors.append("metadata.solution: expected an array of U/D/L/R/P commands.")
		else:
			for command: Variant in solution:
				if not command is String or command not in ["U", "D", "L", "R", "P"]:
					errors.append("metadata.solution: unknown command '%s'." % str(command))
	return errors


static func load_file(path: String) -> Dictionary:
	last_errors.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_errors.append("Cannot open '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	if file.get_length() > MAX_FILE_BYTES:
		last_errors.append("Level file exceeds the 8 MiB safety limit.")
		file.close()
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		last_errors.append("JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		last_errors.append("The level file root must be an object.")
		return {}
	last_errors = validate(parser.data)
	if not last_errors.is_empty():
		return {}
	return normalize(parser.data)


static func save_file(path: String, data: Dictionary) -> Error:
	last_errors = validate(data)
	if not last_errors.is_empty():
		return ERR_INVALID_DATA
	if path.strip_edges().is_empty():
		last_errors.append("Choose an output path.")
		return ERR_FILE_BAD_PATH
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		last_errors.append("Cannot create output folder: %s" % error_string(directory_error))
		return directory_error
	var temporary_path := absolute_path + ".tmp-%d" % Time.get_ticks_usec()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		last_errors.append("Cannot write temporary level file: %s" % error_string(open_error))
		return open_error
	file.store_string(JSON.stringify(normalize(data), "  ", true) + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		last_errors.append("Could not finish writing level: %s" % error_string(write_error))
		return write_error
	var rename_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		last_errors.append("Could not replace level file: %s" % error_string(rename_error))
	return rename_error


static func cells(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value: Variant in raw:
		if _is_cell(value):
			result.append(Vector2i(int(value[0]), int(value[1])))
	return result


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func _is_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1])


static func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y
