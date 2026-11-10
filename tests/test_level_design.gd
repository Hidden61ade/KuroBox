extends SceneTree
## Checks teaching behaviors in the actual simulation, not a prescribed layout
## or one unique solution. Counterfactual search must exhaust its reachable graph;
## a search reaching the state budget is inconclusive and fails this check.

const Board = preload("res://core/board_state.gd")
const Codec = preload("res://core/level_codec.gd")
const SEARCH_LIMIT := 120000
const DIRECTIONS := {"U":Vector2i.UP, "D":Vector2i.DOWN, "L":Vector2i.LEFT, "R":Vector2i.RIGHT}
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}


func _init() -> void:
	var fifth := _load("05_make_a_stop.json")
	var seventh := _load("07_hold_the_gate.json")
	var eighth := _load("08_tag_team.json")
	if not fifth.is_empty() and not seventh.is_empty() and not eighth.is_empty():
		_test_movable_brake(fifth)
		_test_continuous_power(seventh)
		_test_handoff(seventh, eighth)
	print("LEVEL_DESIGN_RESULT ", JSON.stringify({"engine":Engine.get_version_info().string, "checks":checks, "failures":failures, "state_limit_per_search":SEARCH_LIMIT, "evidence":evidence}))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _load(filename: String) -> Dictionary:
	var level := Codec.load_file("res://content/levels/" + filename)
	_check(not level.is_empty(), "published design level passes shared validation: " + filename)
	return level


func _recorded_run(level: Dictionary) -> Dictionary:
	var state := Board.new()
	state.setup(level)
	var initial := state.snapshot()
	var trace: Array[Dictionary] = [_frame(state, 0)]
	var brake_indices: Array[int] = []
	var commands: Array = level["metadata"]["solution"]
	for index: int in range(commands.size()):
		if commands[index] == "P" and _movable_brake(state):
			brake_indices.append(index + 1)
		_command(state, commands[index])
		trace.append(_frame(state, index + 1))
	_check(state.is_won(), "recorded commands actually win: " + str(level.id))
	var moves := state.moves
	var punches := state.punches
	var undone := 0
	while state.undo() and undone <= commands.size():
		undone += 1
	_check(state.snapshot() == initial, "full undo restores all actors, direction and devices: " + str(level.id))
	for command: String in commands:
		_command(state, command)
	state.restart()
	_check(state.snapshot() == initial and not state.undo(), "restart restores the pristine board and empty history: " + str(level.id))
	return {"trace":trace, "movable_brake_indices":brake_indices, "commands":"".join(commands), "moves":moves, "punches":punches}


func _test_movable_brake(level: Dictionary) -> void:
	var run := _recorded_run(level)
	_check(not run.movable_brake_indices.is_empty(), "round 05 solution uses a movable object to shorten a bag punch")
	var search := _search(level, "no_movable_brake")
	_check(not search.won and search.exhausted and not search.limited, "round 05 has no winning path in the fully explored no-movable-brake counterfactual")
	evidence["round_05"] = {"recorded_commands":run.commands, "moves":run.moves, "punches":run.punches, "brake_command_indices":run.movable_brake_indices, "counterfactual":search}
	print("LEVEL_DESIGN_PROGRESS round_05 ", JSON.stringify(evidence["round_05"]))


func _test_continuous_power(level: Dictionary) -> void:
	var run := _recorded_run(level)
	var initial: Dictionary = run.trace[0]
	_check(initial.gate.get("open", false) and initial.left.get("powered_by", []) == ["player"], "round 07 begins with visible player-powered opening")
	var closure_index := -1
	var supported_index := -1
	for frame: Dictionary in run.trace:
		if closure_index < 0 and frame.all_released_closed:
			closure_index = int(frame.index)
		if closure_index >= 0 and supported_index < 0 and frame.box_supported_open:
			supported_index = int(frame.index)
	_check(closure_index > 0 and supported_index > closure_index, "round 07 first shows a fully released unoccupied gate closing, then box-powered reopening")
	for direction: String in ["U", "D", "L", "R"]:
		var state := Board.new()
		state.setup(level)
		var before := state.snapshot()
		_command(state, direction)
		_check(_all_released_closed(state), "every initial movement demonstrates release closing: " + direction)
		_check(state.undo() and state.snapshot() == before, "the initial closure is safely undoable: " + direction)
		var recovery := _search(level, "", direction)
		_check(recovery.won and not recovery.limited, "each first movement still has a winning continuation without restart: " + direction)
	var counterfactual := _search(level, "no_release_closure")
	_check(not counterfactual.won and counterfactual.exhausted and not counterfactual.limited, "round 07 cannot be completed while avoiding the release-closing observation")
	evidence["round_07"] = {"recorded_commands":run.commands, "moves":run.moves, "punches":run.punches, "closure_command_index":closure_index, "box_support_command_index":supported_index, "counterfactual":counterfactual}
	print("LEVEL_DESIGN_PROGRESS round_07 ", JSON.stringify(evidence["round_07"]))


func _test_handoff(previous: Dictionary, level: Dictionary) -> void:
	_check(previous.width == level.width and previous.height == level.height and _same_cells(previous.floor, level.floor) and _same_cells(previous.walls, level.walls), "rounds 07 and 08 share their room geometry")
	var earlier := Board.new()
	earlier.setup(previous)
	var reached_setup := false
	for command: String in previous["metadata"]["solution"]:
		_command(earlier, command)
		if _box_supported_open(earlier):
			reached_setup = true
			break
	var next := Board.new()
	next.setup(level)
	var same_setup := reached_setup and next.player == earlier.player
	for id: String in earlier.objects:
		same_setup = same_setup and next.objects.has(id) and next.objects[id].cell == earlier.objects[id].cell
	_check(same_setup, "round 08 starts at round 07's solved power setup rather than repeating the preparation walk")
	var run := _recorded_run(level)
	var handoff_index := -1
	for frame: Dictionary in run.trace:
		if frame.handoff and not frame.won:
			handoff_index = int(frame.index)
			break
	_check(handoff_index >= 0, "round 08 requires right-hand power to replace left-hand power before the level is won")
	var counterfactual := _search(level, "no_handoff")
	_check(not counterfactual.won and counterfactual.exhausted and not counterfactual.limited, "round 08 has no winning path while avoiding a non-final handoff state")
	evidence["round_08"] = {"recorded_commands":run.commands, "moves":run.moves, "punches":run.punches, "handoff_command_index":handoff_index, "counterfactual":counterfactual}
	print("LEVEL_DESIGN_PROGRESS round_08 ", JSON.stringify(evidence["round_08"]))


func _frame(state: Board, index: int) -> Dictionary:
	return {"index":index, "player":state.player, "objects":state.objects.duplicate(true), "gate":_device(state, "gate_mid"), "left":_device(state, "plate_left"), "right":_device(state, "plate_right"), "all_released_closed":_all_released_closed(state), "box_supported_open":_box_supported_open(state), "handoff":_handoff(state), "won":state.is_won()}


func _device(state: Board, id: String) -> Dictionary:
	for row: Dictionary in state.device_debug():
		if row.id == id:
			return row
	return {}


func _all_released_closed(state: Board) -> bool:
	var gate := _device(state, "gate_mid")
	if gate.is_empty() or gate.get("open", false) or gate.get("held_open", false) or not gate.get("occupants", []).is_empty():
		return false
	for row: Dictionary in state.device_debug():
		if row.behavior == "plate" and row.get("pressed", false):
			return false
	return true


func _box_supported_open(state: Board) -> bool:
	var gate := _device(state, "gate_mid")
	if not gate.get("powered", false) or not gate.get("open", false):
		return false
	for id: String in gate.get("powered_by", []):
		var plate := _device(state, id)
		for occupant: String in plate.get("powered_by", []):
			if state.objects.has(occupant) and state.objects[occupant].behavior == "wood":
				return true
	return false


func _handoff(state: Board) -> bool:
	var gate := _device(state, "gate_mid")
	var left := _device(state, "plate_left")
	var right := _device(state, "plate_right")
	return not left.is_empty() and not right.is_empty() and not left.get("pressed", false) and right.get("pressed", false) and gate.get("open", false) and gate.get("powered_by", []).has("plate_right") and not gate.get("held_open", false)


func _movable_brake(state: Board) -> bool:
	var front := state.player + state.facing
	var id := state.object_at(front)
	if id.is_empty() or not state.objects[id]["_definition"].get("punchable", false):
		return false
	var landing := state.preview_punch()
	var distance := absi(landing.x - front.x) + absi(landing.y - front.y)
	if landing == state.player or distance <= 0 or distance >= int(state.objects[id]["_definition"].get("punch_distance", 0)):
		return false
	var blocker := state.object_at(landing + state.facing)
	return not blocker.is_empty() and state.objects[blocker]["_definition"].get("pushable", false)


func _same_cells(left: Array, right: Array) -> bool:
	var first: Dictionary = {}
	var second: Dictionary = {}
	for cell: Array in left:
		first[Vector2i(int(cell[0]), int(cell[1]))] = true
	for cell: Array in right:
		second[Vector2i(int(cell[0]), int(cell[1]))] = true
	return first == second


func _command(state: Board, command: String) -> void:
	if command == "P":
		state.punch()
	else:
		state.step(DIRECTIONS[command])


func _state_key(state: Board) -> String:
	var values := PackedStringArray([str(state.player), str(state.facing)])
	var ids := state.objects.keys()
	ids.sort()
	for id: String in ids:
		var item: Dictionary = state.objects[id]
		values.append(id + ":" + str(item.cell) + ":" + str(item.get("open", false)) + ":" + str(item.get("pressed", false)))
	return "|".join(values)


func _search(level: Dictionary, forbidden: String, prefix: String = "") -> Dictionary:
	var state := Board.new()
	state.setup(level)
	for command: String in prefix:
		_command(state, command)
	var queue: Array[Dictionary] = [{"snapshot":state.snapshot(), "path":prefix}]
	var seen: Dictionary = {_state_key(state):true}
	var index := 0
	while index < queue.size():
		var entry: Dictionary = queue[index]
		queue[index] = {}
		index += 1
		state._restore(entry.snapshot)
		state._history.clear()
		if state.is_won():
			return {"won":true, "exhausted":false, "limited":false, "states":seen.size(), "commands":entry.path, "moves":state.moves, "punches":state.punches}
		for command: String in ["U", "D", "L", "R", "P"]:
			state._restore(entry.snapshot)
			state._history.clear()
			if forbidden == "no_movable_brake" and command == "P" and _movable_brake(state):
				continue
			_command(state, command)
			if forbidden == "no_release_closure" and _all_released_closed(state):
				continue
			if forbidden == "no_handoff" and _handoff(state) and not state.is_won():
				continue
			var key := _state_key(state)
			if seen.has(key):
				continue
			seen[key] = true
			queue.append({"snapshot":state.snapshot(), "path":str(entry.path) + command})
		if seen.size() >= SEARCH_LIMIT:
			return {"won":false, "exhausted":false, "limited":true, "states":seen.size()}
	return {"won":false, "exhausted":true, "limited":false, "states":seen.size()}
