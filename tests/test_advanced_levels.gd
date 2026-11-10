extends SceneTree
## Content verification through the real rules, not an independent solver.

const Board = preload("res://core/board_state.gd")
const Codec = preload("res://core/level_codec.gd")
const Catalog = preload("res://core/object_catalog.gd")
const Replay = preload("res://core/replay_proof.gd")
const View = preload("res://features/play/board_view.gd")
const DIRECTIONS := {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}
const PATHS := [
	"res://content/levels/09_borrowed_brake.json",
	"res://content/levels/10_cross_circuit.json",
	"res://content/levels/11_second_shift.json",
]
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var campaign_hash := FileAccess.get_sha256("res://content/levels/campaign.json")
	var definitions_hash := FileAccess.get_sha256(Catalog.DEFINITIONS_PATH)
	_check(Catalog.get_type("bag").punch_distance == 2, "campaign bags still use the familiar two-cell default")
	for path: String in PATHS:
		await _verify_level(path)
	_check(FileAccess.get_sha256("res://content/levels/campaign.json") == campaign_hash, "advanced verification never edits campaign manifest")
	_check(FileAccess.get_sha256(Catalog.DEFINITIONS_PATH) == definitions_hash, "advanced verification never edits type definitions")
	var report := {"checks": checks, "failures": failures, "levels": results}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/advanced_levels"))
	var file := FileAccess.open("res://.tools/advanced_levels/verification.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ", true) + "\n")
		file.close()
	print("ADVANCED_LEVELS_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: " + label)


func _verify_level(path: String) -> void:
	var level := Codec.load_file(path)
	_check(not level.is_empty(), "strict authoring structure: " + path)
	if level.is_empty():
		return
	var id: String = level.id
	var commands: Array[String] = []
	for command: String in level.metadata.solution:
		commands.append(command)
	var inherited_rules := true
	for item: Dictionary in level.objects:
		inherited_rules = inherited_rules and item.type in ["wood", "bag", "plate", "door"] and item.get("params", {}).is_empty()
	_check(inherited_rules, id + " has no unannounced per-object rule changes")
	_check(level.metadata.get("hint", "").is_empty(), id + " has no added text hint")
	var proof := Replay.build(level, commands)
	_check(proof.valid and Replay.verify(level, proof).valid, id + " recorded commands actually replay to a win")
	var state := Board.new()
	state.setup(level)
	var initial := state.snapshot()
	_check(not state.is_won(), id + " is not already solved")
	var facts := {"brakes": [], "goal_vacated": [], "powered_sources": {}, "held_gate": false, "low_crossing": false, "service_locked": false, "service_access": false, "service_recovery": false, "checkpoints": {}}
	var seen: Dictionary = {_state_key(state): true}
	var no_loops := true
	var effective_commands := true
	var history_exact := true
	var no_early_win := true
	for index: int in range(commands.size()):
		var before := state.snapshot()
		var result := _apply(state, commands[index])
		var after := state.snapshot()
		effective_commands = effective_commands and (result.changed or before.facing != after.facing)
		no_early_win = no_early_win and (not state.is_won() or index == commands.size() - 1)
		var key := _state_key(state)
		no_loops = no_loops and not seen.has(key)
		seen[key] = true
		_observe(id, state, before, result, index + 1, facts)
		history_exact = history_exact and state.undo() and state.snapshot() == before
		_apply(state, commands[index])
		history_exact = history_exact and state.snapshot() == after
	_check(effective_commands, id + " keeps only state-changing movement or necessary facing commands")
	_check(no_loops, id + " has no repeated full board-and-facing state in its recorded solution")
	_check(no_early_win and state.is_won(), id + " completes at its last effective command")
	_check(history_exact, id + " every movement, facing turn and device transition undoes and redoes exactly")
	_check(state.moves == proof.moves and state.punches == proof.punches, id + " live replay reproduces proof counters")
	var final_state := state.snapshot()
	var rewound := true
	for ignored: int in range(commands.size()):
		rewound = state.undo() and rewound
	_check(rewound and state.snapshot() == initial and not state.undo(), id + " complete undo returns to initial layout and empty history")
	for command: String in commands:
		_apply(state, command)
	state.restart()
	_check(state.snapshot() == initial and not state.undo(), id + " restart restores exact initial state and clears history")
	var prefix := commands.duplicate()
	prefix.pop_back()
	_check(not Replay.build(level, prefix).valid, id + " a truncated recording is not accepted as a winning proof")
	_check_facts(id, facts)
	var view := View.new()
	root.add_child(view)
	view.size = Vector2(816, 432)
	view.set_level_preview(level)
	view.fit_view()
	await process_frame
	var fitted := true
	var available := Rect2(Vector2.ZERO, view.size)
	for raw: Array in level.floor:
		fitted = fitted and available.encloses(view.cell_to_rect(Vector2i(raw[0], raw[1])))
	_check(fitted and view.cell_size >= 32.0, id + " whole layout fits a conservative 816x432 board area at readable integer pixel scale")
	results.append({"id": id, "path": path, "width": level.width, "height": level.height, "inputs": commands.size(), "actions": final_state.moves, "punches": final_state.punches, "cell_pixels_at_816x432": view.cell_size, "brakes": facts.brakes, "goal_vacated": facts.goal_vacated, "checkpoints": facts.checkpoints})
	view.free()


func _apply(state: BoardState, command: String) -> Dictionary:
	return state.punch() if command == "P" else state.step(DIRECTIONS[command])


func _observe(id: String, state: BoardState, before: Dictionary, result: Dictionary, input_index: int, facts: Dictionary) -> void:
	for object_id: String in state.objects:
		var previous: Dictionary = before.objects[object_id]
		if previous.behavior in ["wood", "bag"] and state.goals.has(previous.cell) and not state.goals.has(state.objects[object_id].cell) and not facts.goal_vacated.has(object_id):
			facts.goal_vacated.append(object_id)
	if result.event == "punch" and result.changed:
		var distance: int = abs(result.to.x - result.from.x) + abs(result.to.y - result.from.y)
		if distance == 1:
			var stop_cell: Vector2i = result.to + state.facing
			for object_id: String in before.objects:
				var other: Dictionary = before.objects[object_id]
				if other.behavior in ["wood", "bag"] and other.cell == stop_cell:
					var pair: String = str(result.object_id) + "<" + object_id
					if not facts.brakes.has(pair):
						facts.brakes.append(pair)
	var high := _device(state, "gate_high")
	if high.get("powered", false):
		for source: String in high.powered_by:
			facts.powered_sources[source] = true
	facts.held_gate = facts.held_gate or high.get("held_open", false)
	if id == "round_09":
		if state.objects.wood_brake.cell == Vector2i(10, 3) and state.objects.bag_main.cell == Vector2i(8, 3):
			_checkpoint(facts, "brake_ready", input_index, state)
		if high.get("powered_by", []) == ["plate_east"]:
			_checkpoint(facts, "bag_holds_both_gates", input_index, state)
	elif id == "round_10":
		if state.objects.bag_follow.cell == Vector2i(9, 6):
			_checkpoint(facts, "lower_power_ready", input_index, state)
		if result.event == "push" and result.object_id == "wood_brake" and result.to == Vector2i(7, 7):
			facts.low_crossing = state.objects.bag_lead.cell == Vector2i(10, 4) and _device(state, "gate_low").get("powered_by", []) == ["plate_lower"]
			_checkpoint(facts, "crate_uses_lower_route", input_index, state)
	else:
		var service := _device(state, "gate_service")
		if state.objects.wood_east.cell == Vector2i(9, 8) and state.objects.bag_follow.cell == Vector2i(9, 6):
			facts.service_locked = not service.open and not _reachable(state, Vector2i(8, 8))
			_checkpoint(facts, "service_bay_still_locked", input_index, state)
		if state.objects.wood_east.cell == Vector2i(9, 8) and state.objects.bag_follow.cell == Vector2i(9, 7):
			facts.service_access = service.open and _reachable(state, Vector2i(8, 8))
			_checkpoint(facts, "lower_bag_opens_service_bay", input_index, state)
		if result.event == "push" and result.object_id == "wood_east" and result.from == Vector2i(9, 8) and result.to == Vector2i(10, 8):
			facts.service_recovery = before.player == Vector2i(8, 8) and service.get("powered_by", []) == ["plate_lower"] and state.objects.bag_follow.cell == Vector2i(9, 7)
			_checkpoint(facts, "brake_recovered_through_gate", input_index, state)


func _check_facts(id: String, facts: Dictionary) -> void:
	if id == "round_09":
		_check(facts.brakes.has("bag_main<wood_brake"), id + " the scored crate really supplies the bag's one-cell brake")
		_check(facts.goal_vacated.has("wood_brake"), id + " the crate leaves its own goal before returning at completion")
		_check(facts.powered_sources.has("plate_west") and facts.powered_sources.has("plate_east"), id + " power actually transfers from west crate to east bag")
		_check(facts.held_gate, id + " final bag departure exercises occupied-gate release instead of trapping the puncher")
	elif id == "round_10":
		for pair: String in ["bag_lead<bag_follow", "bag_follow<wood_brake", "bag_follow<bag_lead", "bag_lead<wood_brake"]:
			_check(facts.brakes.has(pair), id + " actual coupled brake: " + pair)
		_check(facts.low_crossing, id + " lower bag supplies the crate route while lead bag still occupies the upper route")
		_check(facts.goal_vacated.has("wood_brake"), id + " finishing the crate early must be reconsidered to finish the lead bag")
	else:
		_check(facts.goal_vacated.has("bag_lead") and facts.goal_vacated.has("wood_east"), id + " both initially completed workstations are reclaimed")
		_check(facts.brakes.has("bag_follow<wood_east") and facts.brakes.has("bag_lead<wood_west"), id + " east and west crates provide distinct final alignment brakes")
		_check(facts.service_locked and facts.service_access, id + " actual lower-plate activation changes reachability of the service bay")
		_check(facts.service_recovery, id + " east crate is physically recovered from the gate-side push station")
		_check(facts.powered_sources.has("plate_west") and facts.powered_sources.has("plate_upper") and facts.powered_sources.has("plate_lower"), id + " upper passage has the full crate-to-bag-to-bag power handoff")


func _device(state: BoardState, id: String) -> Dictionary:
	for item: Dictionary in state.device_debug():
		if item.id == id:
			return item
	return {}


func _reachable(state: BoardState, target: Vector2i) -> bool:
	var queue: Array[Vector2i] = [state.player]
	var seen: Dictionary = {state.player: true}
	var index := 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		if current == target:
			return true
		for direction: Vector2i in DIRECTIONS.values():
			var next := current + direction
			if not seen.has(next) and state.can_enter(next):
				seen[next] = true
				queue.append(next)
	return false


func _checkpoint(facts: Dictionary, label: String, input_index: int, state: BoardState) -> void:
	if facts.checkpoints.has(label):
		return
	var positions: Dictionary = {}
	for id: String in state.objects:
		if state.objects[id].behavior in ["wood", "bag"]:
			positions[id] = [state.objects[id].cell.x, state.objects[id].cell.y]
	facts.checkpoints[label] = {"input": input_index, "player": [state.player.x, state.player.y], "objects": positions}


func _state_key(state: BoardState) -> String:
	var items: Array = []
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: String in ids:
		var item: Dictionary = state.objects[id]
		items.append([id, item.cell.x, item.cell.y, item.get("open", false), item.get("pressed", false)])
	return JSON.stringify([state.player.x, state.player.y, state.facing.x, state.facing.y, items])
