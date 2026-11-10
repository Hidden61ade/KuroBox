extends SceneTree
## Run: Godot --headless --path <project> --script res://tests/test_core.gd

const Board = preload("res://core/board_state.gd")
const Codec = preload("res://core/level_codec.gd")
const Catalog = preload("res://core/object_catalog.gd")
var checks := 0
var failures: Array[String] = []
var campaign_results: Array[Dictionary] = []


func _init() -> void:
	_test_catalog()
	_test_rules()
	_test_devices()
	_test_initial_layers()
	_test_validation()
	_test_files()
	_test_campaign()
	print(JSON.stringify({"engine": Engine.get_version_info()["string"], "checks": checks, "failures": failures, "campaign": campaign_results}, "  "))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)


func _fixture() -> Dictionary:
	var floor_list: Array = []
	for y: int in range(5):
		for x: int in range(7):
			floor_list.append([x, y])
	return {"schema_version": 1, "id": "test_room", "title": "TEST", "width": 7, "height": 5, "floor": floor_list, "walls": [], "goals": [[4, 2]], "player": [1, 2], "facing": [1, 0], "objects": [_object("bag", "bag", [2, 2])], "metadata": {"solution": []}}


func _object(instance_id: String, type_id: String, cell: Array, targets: Array = []) -> Dictionary:
	return {"id": instance_id, "type": type_id, "cell": cell, "targets": targets}


func _board(data: Dictionary) -> Board:
	var state := Board.new()
	state.setup(data)
	_check(state.setup_errors.is_empty(), "fixture is valid: %s" % str(state.setup_errors))
	return state


func _test_catalog() -> void:
	_check(Catalog.all_types().size() == 4, "four shared object types load")
	_check(Catalog.get_type("missing").is_empty(), "unknown type does not fall back")
	var wood: Dictionary = Catalog.get_type("wood")
	wood["pushable"] = false
	_check(Catalog.get_type("wood")["pushable"], "catalog callers cannot mutate definitions")
	_check(Catalog.get_type("bag")["punch_distance"] == 2, "bag distance is data-defined")


func _test_rules() -> void:
	var data := _fixture()
	var state := _board(data)
	var initial := state.snapshot()
	_check(state.preview_punch() == Vector2i(4, 2), "punch preview predicts two cells")
	var result := state.punch()
	_check(result["event"] == "punch" and result["changed"], "bag receives punch")
	_check(state.player == Vector2i(1, 2) and state.objects["bag"]["cell"] == Vector2i(4, 2), "punch leaves player stationary")
	_check(state.moves == 1 and state.punches == 1 and state.is_won(), "successful punch counts and wins")
	_check(state.undo() and state.snapshot() == initial, "punch undo restores all state")
	data["goals"] = [[3, 2]]
	state = _board(data)
	state.punch()
	_check(state.objects["bag"]["cell"] == Vector2i(4, 2) and not state.is_won(), "goal does not brake a bag")
	data["walls"] = [[4, 2]]
	state = _board(data)
	state.punch()
	_check(state.objects["bag"]["cell"] == Vector2i(3, 2), "second cell obstruction brakes after one cell")
	data["walls"] = [[3, 2]]
	data["goals"] = [[4, 1]]
	state = _board(data)
	result = state.punch()
	_check(not result["changed"] and state.moves == 0 and state.punches == 0, "first cell obstruction blocks without counting")
	data = _fixture()
	data["objects"].append(_object("other_bag", "bag", [3, 2]))
	state = _board(data)
	state.punch()
	_check(state.objects["bag"]["cell"] == Vector2i(2, 2) and state.objects["other_bag"]["cell"] == Vector2i(3, 2), "no chain impulses")
	data = _fixture()
	data["objects"] = [_object("wood", "wood", [2, 2])]
	state = _board(data)
	_check(not state.punch()["changed"], "wood cannot be punched")
	result = state.step(Vector2i.RIGHT)
	_check(result["event"] == "push" and state.player == Vector2i(2, 2) and state.objects["wood"]["cell"] == Vector2i(3, 2), "wood pushes one cell and player follows")
	data["objects"].append(_object("wood_2", "wood", [3, 2]))
	state = _board(data)
	_check(not state.step(Vector2i.RIGHT)["changed"], "wood does not chain-push")
	state = _board(_fixture())
	_check(not state.step(Vector2i.RIGHT)["changed"] and state.player == Vector2i(1, 2), "bag cannot be pushed")
	initial = state.snapshot()
	state.step(Vector2i.UP)
	state.punch()
	state.restart()
	_check(state.snapshot() == initial and not state.undo(), "restart resets counters, objects, direction and undo history")
	state.step(Vector2i(-2, 0))
	_check(state.snapshot() == initial, "non-cardinal commands cannot mutate state")
	var detached := state.snapshot()
	detached["objects"]["bag"]["cell"] = Vector2i(6, 4)
	_check(state.objects["bag"]["cell"] == Vector2i(2, 2), "snapshot object data is independent")
	data = _fixture()
	data["walls"] = [[1, 1]]
	state = _board(data)
	initial = state.snapshot()
	result = state.step(Vector2i.UP)
	_check(not result["changed"] and state.facing == Vector2i.UP and state.moves == 0, "blocked move may face without spending a move")
	_check(state.undo() and state.snapshot() == initial, "undo restores blocked-facing change")
	data = _fixture()
	data["floor"].erase([4, 2])
	data["goals"] = [[3, 2]]
	state = _board(data)
	state.punch()
	_check(state.objects["bag"]["cell"] == Vector2i(3, 2), "irregular floor edge brakes safely")


func _test_devices() -> void:
	var data := _fixture()
	data["player"] = [0, 2]
	data["objects"] = [_object("plate", "plate", [1, 2], ["door"]), _object("door", "door", [3, 2]), _object("wood", "wood", [2, 2])]
	data["goals"] = [[5, 2]]
	var state := _board(data)
	var initial := state.snapshot()
	_check(not state.objects["door"]["open"], "gate begins closed")
	state.step(Vector2i.RIGHT)
	_check(state.objects["plate"]["pressed"] and state.objects["door"]["open"], "player pressure opens linked gate")
	state.step(Vector2i.RIGHT)
	_check(not state.objects["plate"]["pressed"] and state.objects["door"]["open"] and state.objects["wood"]["cell"] == Vector2i(3, 2), "box occupying gate keeps it open after plate releases")
	state.step(Vector2i.RIGHT)
	_check(state.player == Vector2i(3, 2) and state.objects["door"]["open"], "player occupying gate keeps it open")
	state.step(Vector2i.RIGHT)
	_check(not state.objects["door"]["open"], "gate closes after final occupant leaves")
	_check(state.undo() and state.objects["door"]["open"] and state.player == Vector2i(3, 2), "undo restores occupied gate and device flags")
	while state.undo():
		pass
	_check(state.snapshot() == initial, "all gate operations fully undo")
	data = _fixture()
	data["objects"].append(_object("plate", "plate", [3, 2], ["door"]))
	data["objects"].append(_object("door", "door", [6, 2]))
	state = _board(data)
	state.punch()
	_check(not state.objects["plate"]["pressed"] and not state.objects["door"]["open"], "crossed plate uses final occupation, not intermediate animation cells")
	data["objects"][1]["cell"] = [4, 2]
	data["objects"].append(_object("plate_2", "plate", [0, 1], ["door"]))
	state = _board(data)
	state.punch()
	_check(state.objects["plate"]["pressed"] and not state.objects["plate_2"]["pressed"] and state.objects["door"]["open"], "multiple plates linked to a gate use OR")


func _test_validation() -> void:
	var baseline := _fixture()
	_check(Codec.validate(baseline).is_empty(), "valid wire document accepted")
	var too_large := baseline.duplicate(true)
	too_large.width = 25
	_check(not Codec.validate(too_large).is_empty(), "import refuses a board larger than the supported editor and viewport range")
	too_large.width = 24
	_check(Codec.validate(too_large).is_empty(), "largest supported width remains valid")
	var variants: Array[Dictionary] = []
	var bad := baseline.duplicate(true)
	bad["schema_version"] = 2
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["width"] = 7.5
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["player"] = [1.5, 2]
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"][0]["type"] = "unknown"
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(bad["objects"][0].duplicate(true))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(_object("overlap", "wood", [2, 2]))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"][0]["cell"] = [99, 2]
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["goals"].append([6, 2])
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(_object("plate", "plate", [0, 1], ["missing"]))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(_object("plate", "plate", [0, 1], ["bag"]))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(_object("door", "door", [0, 1]))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["metadata"] = {"solution": ["X"]}
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["facing"] = [1, 1]
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["floor"].append([0, 0])
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"][0]["cell"] = bad["player"].duplicate()
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(_object("plate", "plate", [0, 1], ["door"]))
	bad["objects"].append(_object("door", "door", [0, 1]))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["objects"].append(_object("plate", "plate", [0, 1], ["door"]))
	bad["objects"].append(_object("plate_2", "plate", [0, 1], ["door"]))
	bad["objects"].append(_object("door", "door", [6, 2]))
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["walls"] = [[4, 2]]
	variants.append(bad)
	bad = baseline.duplicate(true)
	bad["walls"] = [[2, 2]]
	variants.append(bad)
	for index: int in range(variants.size()):
		_check(not Codec.validate(variants[index]).is_empty(), "invalid variant %d is rejected" % index)
	var state := Board.new()
	state.setup(variants[0])
	_check(not state.setup_errors.is_empty() and state.level.is_empty() and not state.is_won(), "invalid setup cannot produce a playable fallback")
	var defaults := baseline.duplicate(true)
	defaults.erase("facing")
	defaults.erase("metadata")
	defaults["objects"][0].erase("targets")
	var normalized := Codec.normalize(defaults)
	_check(normalized["facing"] == [1, 0] and normalized["objects"][0]["targets"] == [] and normalized["metadata"]["solution"] == [], "normalization supplies only documented optional defaults")


func _test_files() -> void:
	var path := "res://tests/.core_roundtrip_test.json"
	var malformed_path := "res://tests/.core_bad_test.json"
	var data := _fixture()
	_check(Codec.save_file(path, data) == OK, "atomic level save succeeds")
	var loaded := Codec.load_file(path)
	_check(not loaded.is_empty() and Codec.normalize(data) == loaded, "wire roundtrip preserves complete level")
	data["title"] = "REPLACED"
	_check(Codec.save_file(path, data) == OK and Codec.load_file(path)["title"] == "REPLACED", "atomic save can replace existing file")
	var bad := data.duplicate(true)
	bad["schema_version"] = 999
	_check(Codec.save_file(path, bad) == ERR_INVALID_DATA and not Codec.last_errors.is_empty(), "invalid save reports errors before writing")
	_check(Codec.load_file(path)["title"] == "REPLACED", "rejected save preserves previous valid file")
	var file := FileAccess.open(malformed_path, FileAccess.WRITE)
	file.store_string("{ broken json")
	file.close()
	_check(Codec.load_file(malformed_path).is_empty() and not Codec.last_errors.is_empty(), "malformed JSON yields visible parse error")
	file = FileAccess.open(malformed_path, FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	_check(Codec.load_file(malformed_path).is_empty() and not Codec.last_errors.is_empty(), "non-object JSON root rejected")
	_check(Codec.load_file("res://tests/does_not_exist.json").is_empty() and not Codec.last_errors.is_empty(), "missing file yields visible error")
	var layered := _fixture()
	layered["objects"].append(_object("plate", "plate", [2, 2], ["door"]))
	layered["objects"].append(_object("door", "door", [6, 2]))
	layered["goals"] = [[2, 2]]
	_check(Codec.save_file(path, layered) == OK, "atomic save accepts a box on a plate and target")
	var loaded_layered := Codec.load_file(path)
	_check(not loaded_layered.is_empty() and loaded_layered == Codec.normalize(layered), "roundtrip preserves layered entities, devices and target cells")
	var layered_board := _board(loaded_layered)
	_check(layered_board.is_won() and layered_board.objects["plate"]["pressed"] and layered_board.objects["door"]["open"], "loaded layered level starts solved, pressed and powered without a dummy command")
	layered_board.punch()
	_check(loaded_layered["objects"][0]["cell"] == [2, 2] and loaded_layered["objects"][1]["cell"] == [2, 2], "runtime movement does not modify loaded layered authoring data")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))


func _test_initial_layers() -> void:
	var data := _fixture()
	data["objects"].append(_object("plate", "plate", data["player"].duplicate(), ["door"]))
	data["objects"].append(_object("door", "door", [6, 2]))
	var state := _board(data)
	var initial := state.snapshot()
	_check(state.objects["plate"]["pressed"] and state.objects["door"]["open"], "player may spawn on a plate and immediately power its gate")
	state.step(Vector2i.UP)
	_check(not state.objects["plate"]["pressed"] and not state.objects["door"]["open"], "leaving an initial player plate releases power")
	_check(state.undo() and state.snapshot() == initial, "undo returns to initial player-on-plate device state")
	for type_id: String in ["wood", "bag"]:
		data = _fixture()
		data["objects"] = [_object("box", type_id, [2, 2]), _object("plate", "plate", [2, 2], ["door"]), _object("door", "door", [6, 2])]
		data["goals"] = [[5, 2]]
		state = _board(data)
		initial = state.snapshot()
		_check(state.objects["plate"]["pressed"] and state.objects["door"]["open"], "%s may begin on a plate and immediately power its gate" % type_id)
		_check(state.object_at(Vector2i(2, 2)) == "box" and state.object_at(Vector2i(2, 2), true) == "box", "entity lookup retains the %s above its device" % type_id)
		if type_id == "wood":
			state.step(Vector2i.RIGHT)
			_check(state.objects["plate"]["pressed"] and state.objects["door"]["open"], "player takes over plate after pushing its initial wood box")
			state.step(Vector2i.UP)
		else:
			state.punch()
		_check(not state.objects["plate"]["pressed"] and not state.objects["door"]["open"], "%s movement settles plate from final occupancy" % type_id)
		state.restart()
		_check(state.snapshot() == initial, "%s restart preserves initial device occupancy" % type_id)
	# Gate policy mirrors regular end-of-command settling: any occupying entity
	# holds the gate open, even when its linked pressure plate is unpowered.
	data = _fixture()
	data["player"] = [3, 2]
	data["objects"] = [_object("bag", "bag", [2, 3]), _object("plate", "plate", [0, 1], ["door"]), _object("door", "door", [3, 2])]
	state = _board(data)
	initial = state.snapshot()
	_check(not state.objects["plate"]["pressed"] and state.objects["door"]["open"], "player may spawn in an unpowered gate and hold it open")
	state.step(Vector2i.RIGHT)
	_check(not state.objects["door"]["open"], "initial held gate closes after player exits")
	_check(state.undo() and state.snapshot() == initial, "gate-spawn undo restores initial held-open state")
	for type_id: String in ["wood", "bag"]:
		data = _fixture()
		data["objects"] = [_object("box", type_id, [2, 2]), _object("plate", "plate", [0, 1], ["door"]), _object("door", "door", [2, 2])]
		state = _board(data)
		_check(not state.objects["plate"]["pressed"] and state.objects["door"]["open"], "%s may start in an unpowered gate and hold it open" % type_id)
		if type_id == "wood":
			state.step(Vector2i.RIGHT)
			_check(state.objects["door"]["open"], "player replaces wood as gate occupant")
			state.step(Vector2i.UP)
		else:
			state.punch()
		_check(not state.objects["door"]["open"], "initial held gate closes after %s and player clear it" % type_id)


func _test_campaign() -> void:
	var manifest_file := FileAccess.open("res://content/levels/campaign.json", FileAccess.READ)
	_check(manifest_file != null, "campaign manifest exists")
	if manifest_file == null:
		return
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	_check(manifest["levels"].size() == 8, "campaign contains eight explicit ordered levels")
	var seen_ids: Dictionary = {}
	for path: String in manifest["levels"]:
		var data := Codec.load_file(path)
		_check(not data.is_empty(), "campaign document loads: %s %s" % [path, str(Codec.last_errors)])
		if data.is_empty():
			continue
		_check(not seen_ids.has(data["id"]), "campaign has unique stable level IDs: %s" % data["id"])
		seen_ids[data["id"]] = true
		var state := _board(data)
		var initial := state.snapshot()
		var commands: Array = data["metadata"]["solution"]
		_check(not commands.is_empty(), "campaign solution is recorded: %s" % data["id"])
		for command: String in commands:
			match command:
				"U": state.step(Vector2i.UP)
				"D": state.step(Vector2i.DOWN)
				"L": state.step(Vector2i.LEFT)
				"R": state.step(Vector2i.RIGHT)
				"P": state.punch()
		_check(state.is_won(), "recorded solution wins in actual rules: %s" % data["id"])
		campaign_results.append({"id": data["id"], "commands": commands.size(), "moves": state.moves, "punches": state.punches, "won": state.is_won()})
		var safety := 0
		while state.undo() and safety < commands.size() + 1:
			safety += 1
		_check(state.snapshot() == initial, "campaign full undo equals initial snapshot: %s" % data["id"])
		state.step(Vector2i.DOWN)
		state.restart()
		_check(state.snapshot() == initial and not state.undo(), "campaign restart restores pristine board: %s" % data["id"])
