extends SceneTree

const Catalog = preload("res://core/object_catalog.gd")
const Codec = preload("res://core/level_codec.gd")
const Board = preload("res://core/board_state.gd")
const TEMP_CATALOG := "res://tests/.parameters_catalog.json"
const BAD_CATALOG := "res://tests/.parameters_bad_catalog.json"
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	var original_hash := FileAccess.get_file_as_string(Catalog.DEFINITIONS_PATH).sha256_text()
	_test_schema_and_validation()
	_test_effective_punch()
	_test_plate_filters()
	_test_gate_logic_and_debug()
	_test_drafts()
	_test_catalog_transactions()
	_check(Catalog.reload_catalog().is_empty(), "canonical catalog reloads after isolated tests")
	_check(FileAccess.get_file_as_string(Catalog.DEFINITIONS_PATH).sha256_text() == original_hash, "tests never modify the real catalog")
	for path: String in [TEMP_CATALOG, BAD_CATALOG]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PARAMETERS_RESULT ", JSON.stringify({"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _fixture() -> Dictionary:
	var floor_list: Array = []
	for y: int in range(5):
		for x: int in range(8):
			floor_list.append([x, y])
	return {"schema_version": 1, "id": "parameter_fixture", "title": "PARAMETERS", "width": 8, "height": 5, "floor": floor_list, "walls": [], "goals": [[4, 2]], "player": [1, 2], "facing": [1, 0], "objects": [_object("bag", "bag", [2, 2])], "metadata": {"solution": []}}


func _object(instance_id: String, type_id: String, cell: Array, params: Dictionary = {}, targets: Array = []) -> Dictionary:
	return {"id": instance_id, "type": type_id, "cell": cell, "params": params, "targets": targets}


func _state(data: Dictionary) -> Board:
	var state := Board.new()
	state.setup(data)
	_check(state.setup_errors.is_empty(), "test fixture passes shared validation: %s" % str(state.setup_errors))
	return state


func _debug(state: Board, instance_id: String) -> Dictionary:
	for row: Dictionary in state.device_debug():
		if row["id"] == instance_id:
			return row
	return {}


func _test_schema_and_validation() -> void:
	_check(Catalog.parameter_schema("wood").is_empty(), "wood has no unsupported configurable behavior")
	for type_id: String in ["bag", "plate", "door"]:
		var schema := Catalog.parameter_schema(type_id)
		_check(schema.size() == 1, "%s exposes its actual parameter" % type_id)
		for field: Dictionary in schema:
			_check(field.has_all(["id", "label", "type", "min", "max", "options", "description"]) and not field.has("default"), "%s schema describes the field without duplicating its default" % type_id)
	_check(Catalog.resolve_instance({"type": "bag"})["punch_distance"] == 2, "legacy bag inherits distance two")
	_check(Catalog.resolve_instance({"type": "plate"})["activation_filter"] == "all", "legacy plate accepts all occupants")
	_check(Catalog.resolve_instance({"type": "door"})["gate_logic"] == "any", "legacy gate uses OR")
	var resolved := Catalog.resolve_instance({"type": "bag", "params": {"punch_distance": 3}})
	_check(resolved["punch_distance"] == 3 and Catalog.get_type("bag")["punch_distance"] == 2, "instance override does not mutate its type default")
	for value: Variant in [0, 17, 1.5, "2", true]:
		var instance := _object("bad", "bag", [2, 2], {"punch_distance": value})
		_check(not Catalog.validate_parameters(instance).is_empty() and Catalog.resolve_instance(instance).is_empty(), "invalid distance is rejected rather than clamped: %s" % str(value))
		var data := _fixture()
		data["objects"] = [instance]
		_check(not Codec.validate(data).is_empty(), "wire validator rejects invalid distance %s" % str(value))
	_check(not Catalog.validate_parameters({"type": "bag", "params": {"unknown": 4}}).is_empty(), "unknown instance parameter is rejected")
	_check(not Catalog.validate_parameters({"type": "wood", "params": {"punch_distance": 2}}).is_empty(), "parameters cannot invent capabilities for another behavior")
	_check(not Catalog.validate_parameters({"type": "plate", "params": {"activation_filter": "enemies"}}).is_empty(), "unknown activation filter is rejected")
	_check(not Catalog.validate_parameters({"type": "door", "params": {"gate_logic": "xor"}}).is_empty(), "unknown gate logic is rejected")
	_check(not Catalog.validate_parameters({"type": "bag", "params": []}).is_empty(), "params must be a dictionary")


func _test_effective_punch() -> void:
	for distance: int in [1, 3]:
		var data := _fixture()
		data["objects"][0]["params"] = {"punch_distance": distance}
		data["goals"] = [[2 + distance, 2]]
		var state := _state(data)
		_check(state.preview_punch() == Vector2i(2 + distance, 2), "preview consumes effective distance %d" % distance)
		state.punch()
		_check(state.objects["bag"]["cell"] == Vector2i(2 + distance, 2) and state.is_won(), "simulation consumes effective distance %d" % distance)
		_check(state.undo() and state.objects["bag"]["cell"] == Vector2i(2, 2), "parameterized punch remains fully undoable")
	var data := _fixture()
	data["objects"][0]["params"] = {"punch_distance": 3}
	data["walls"] = [[4, 2]]
	data["goals"] = [[3, 2]]
	var state := _state(data)
	state.punch()
	_check(state.is_won() and state.objects["bag"]["cell"] == Vector2i(3, 2), "long punch still stops before first obstruction")


func _test_plate_filters() -> void:
	for filter: String in ["all", "player", "boxes"]:
		var data := _fixture()
		data["objects"].append(_object("plate", "plate", [1, 2], {"activation_filter": filter}, ["door"]))
		data["objects"].append(_object("door", "door", [6, 3]))
		var state := _state(data)
		_check(state.objects["plate"]["pressed"] == (filter != "boxes") and state.objects["door"]["open"] == (filter != "boxes"), "player activation obeys '%s' filter" % filter)
		var debug := _debug(state, "plate")
		_check(debug["filter"] == filter and debug["occupants"] == ["player"] and not str(debug["reason"]).is_empty(), "plate debug reports the real player/filter cause")
		for type_id: String in ["wood", "bag"]:
			data = _fixture()
			data["objects"] = [_object("box", type_id, [2, 2]), _object("plate", "plate", [2, 2], {"activation_filter": filter}, ["door"]), _object("door", "door", [6, 3])]
			state = _state(data)
			_check(state.objects["plate"]["pressed"] == (filter != "player") and state.objects["door"]["open"] == (filter != "player"), "%s activation obeys '%s' filter" % [type_id, filter])


func _test_gate_logic_and_debug() -> void:
	for logic: String in ["any", "all"]:
		var data := _fixture()
		data["player"] = [2, 2]
		data["goals"] = [[5, 1]]
		data["objects"] = [_object("wood", "wood", [0, 1]), _object("plate_a", "plate", [0, 1], {}, ["door"]), _object("plate_b", "plate", [3, 2], {}, ["door"]), _object("door", "door", [6, 2], {"gate_logic": logic})]
		var state := _state(data)
		var initial := state.snapshot()
		_check(state.objects["door"]["open"] == (logic == "any"), "one of two plates obeys gate '%s' logic" % logic)
		var debug := _debug(state, "door")
		_check(debug["powered_by"] == ["plate_a"] and debug["linked_plates"] == ["plate_a", "plate_b"] and debug["logic"] == logic, "gate debug distinguishes linked and active sources")
		state.step(Vector2i.RIGHT)
		_check(state.objects["door"]["open"] and _debug(state, "door")["active_inputs"] == 2, "both plates power an AND gate too")
		_check(state.undo() and state.snapshot() == initial and _debug(state, "door")["active_inputs"] == 1, "undo recomputes matching debug information")
	var data := _fixture()
	data["player"] = [6, 2]
	data["objects"].append(_object("plate_a", "plate", [0, 0], {}, ["door"]))
	data["objects"].append(_object("plate_b", "plate", [0, 1], {}, ["door"]))
	data["objects"].append(_object("door", "door", [6, 2], {"gate_logic": "all"}))
	var state := _state(data)
	var debug := _debug(state, "door")
	_check(debug["open"] and not debug["powered"] and debug["held_open"] and debug["held_by"] == ["player"], "unpowered AND gate correctly reports occupancy as its opening cause")
	state.step(Vector2i.RIGHT)
	_check(not state.objects["door"]["open"] and not _debug(state, "door")["held_open"], "unpowered AND gate closes when its occupant leaves")
	var copy := state.device_debug()
	copy[0]["reason"] = "tampered"
	_check(state.device_debug()[0]["reason"] != "tampered", "debug consumers cannot mutate model data")


func _test_drafts() -> void:
	var data := _fixture()
	data["player"] = [-1, -1]
	data["goals"] = []
	data["objects"] = [_object("plate", "plate", [2, 2]), _object("door", "door", [6, 2])]
	_check(Codec.validate_draft(data).is_empty() and not Codec.validate(data).is_empty(), "unfinished spawn/goals/links can be saved as a draft, never played")
	data["objects"][1]["params"] = {"gate_logic": "bad"}
	_check(not Codec.validate_draft(data).is_empty(), "draft storage still rejects bad rule parameters")
	data["objects"][1]["params"] = {}
	data["objects"][1]["cell"] = [99, 2]
	_check(not Codec.validate_draft(data).is_empty(), "draft storage rejects out-of-bounds coordinates")
	data["objects"][1]["cell"] = [6, 2]
	data["objects"][1]["id"] = "plate"
	_check(not Codec.validate_draft(data).is_empty(), "draft storage rejects duplicate stable IDs")
	data["schema_version"] = 999
	_check(not Codec.validate_draft(data).is_empty(), "draft storage rejects unknown schemas")


func _test_catalog_transactions() -> void:
	var source := Catalog.catalog_document()
	_check(Catalog.write_definition_document(source, TEMP_CATALOG) == OK, "checked definitions can be written to isolated path")
	_check(Catalog.reload_catalog(TEMP_CATALOG).is_empty(), "isolated catalog loads")
	_check(Catalog.create_variant("bag", "bag_long", "远击沙袋", {"punch_distance": 4}, TEMP_CATALOG) == OK, "variant creation saves valid defaults atomically")
	_check(Catalog.get_type("bag_long")["punch_distance"] == 4 and Catalog.get_type("bag")["punch_distance"] == 2, "variant is a distinct definition, not a mutation of its source")
	var data := _fixture()
	data["objects"][0]["type"] = "bag_long"
	data["goals"] = [[6, 2]]
	var state := _state(data)
	state.punch()
	_check(state.is_won(), "saved variant drives the shared simulation")
	var before := FileAccess.get_file_as_string(TEMP_CATALOG).sha256_text()
	_check(Catalog.create_variant("bag", "bad_bag", "坏参数", {"punch_distance": 99}, TEMP_CATALOG) == ERR_INVALID_DATA, "bad variant rejected before writing")
	_check(FileAccess.get_file_as_string(TEMP_CATALOG).sha256_text() == before and not Catalog.get_type("bag_long").is_empty(), "failed variant preserves both file and loaded catalog")
	var bad := Catalog.catalog_document()
	bad["types"].append(bad["types"][0].duplicate(true))
	_check(Catalog.write_definition_document(bad, TEMP_CATALOG) == ERR_INVALID_DATA, "invalid document rejected before writing")
	_check(FileAccess.get_file_as_string(TEMP_CATALOG).sha256_text() == before and Catalog.get_type("bag_long")["punch_distance"] == 4, "bad document cannot clear known-good definitions")
	var file := FileAccess.open(BAD_CATALOG, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	_check(not Catalog.reload_catalog(BAD_CATALOG).is_empty() and Catalog.get_type("bag_long")["punch_distance"] == 4, "failed reload leaves the active catalog intact")
	_check(Catalog.reload_catalog(TEMP_CATALOG).is_empty(), "valid reload clears the previous diagnostic")
	var frozen_level := _fixture()
	var frozen := _state(frozen_level)
	var updated := Catalog.catalog_document()
	for item: Dictionary in updated["types"]:
		if item["id"] == "bag":
			item["punch_distance"] = 3
	_check(Catalog.write_definition_document(updated, TEMP_CATALOG) == OK, "type default can be changed through checked isolated save")
	frozen.punch()
	_check(frozen.objects["bag"]["cell"] == Vector2i(4, 2), "an existing run keeps its frozen checked rules")
	var refreshed := _state(frozen_level)
	refreshed.punch()
	_check(refreshed.objects["bag"]["cell"] == Vector2i(5, 2), "new runs consume the changed type default")
