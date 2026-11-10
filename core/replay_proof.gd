@tool
class_name ReplayProof
extends RefCounted
## A revision identifies the rule input. A valid proof additionally requires
## executing its commands through the same BoardState used by the game.

const Codec = preload("res://core/level_codec.gd")
const Catalog = preload("res://core/object_catalog.gd")
const Board = preload("res://core/board_state.gd")
const RULESET_VERSION := 1
const MAX_COMMANDS := 100000


static func revision(level: Dictionary) -> String:
	if not Codec.validate(level).is_empty():
		return ""
	var source := Codec.normalize(level)
	var instances: Array[Dictionary] = []
	for item: Dictionary in source["objects"]:
		var targets: Array = item.get("targets", []).duplicate()
		targets.sort()
		var defaults := Catalog.get_type(str(item["type"]))
		var effective := Catalog.resolve_instance(item)
		var parameters: Dictionary = {}
		# Removing an Inspector override and explicitly setting its current default
		# are the same rule input. Retain only semantically different overrides.
		for field: Dictionary in Catalog.parameter_schema(str(item["type"])):
			var key: String = field["id"]
			if effective.get(key) != defaults.get(key):
				parameters[key] = effective[key]
		instances.append({"id": str(item["id"]), "type": str(item["type"]), "cell": item["cell"], "targets": targets, "params": parameters, "type_defaults": _rule_fields(defaults), "effective": _rule_fields(effective)})
	instances.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left["id"]) < str(right["id"]))
	var payload := {"ruleset_version": RULESET_VERSION, "schema_version": source["schema_version"], "id": source["id"], "width": source["width"], "height": source["height"], "floor": _sorted_cells(source["floor"]), "walls": _sorted_cells(source["walls"]), "goals": _sorted_cells(source["goals"]), "player": source["player"], "facing": source["facing"], "objects": instances}
	return JSON.stringify(payload, "", true).sha256_text()


static func build(level: Dictionary, commands: Array[String]) -> Dictionary:
	return _replay(level, commands)


static func verify(level: Dictionary, proof: Dictionary) -> Dictionary:
	var commands: Variant = proof.get("commands", [])
	if not commands is Array:
		return _report(revision(level), [], 0, 0, ["Proof commands must be an array."])
	var result := _replay(level, commands)
	var errors: Array = result["errors"]
	if not proof.get("revision") is String or proof.get("revision", "") != result["revision"]:
		errors.append("Proof revision does not match the current layout, instance parameters or type rules.")
	if proof.get("proof_version", 1) != 1:
		errors.append("Unsupported replay proof version.")
	for field: String in ["moves", "punches"]:
		if proof.has(field):
			if not _integer(proof[field]) or int(proof[field]) != int(result[field]):
				errors.append("Proof %s does not match the actual replay." % field)
	result["valid"] = errors.is_empty()
	return result


static func _replay(level: Dictionary, raw_commands: Array) -> Dictionary:
	var errors: Array[String] = Codec.validate(level)
	var current_revision := revision(level) if errors.is_empty() else ""
	var commands: Array[String] = []
	if raw_commands.size() > MAX_COMMANDS:
		errors.append("Replay exceeds the %d command limit." % MAX_COMMANDS)
	for index: int in range(mini(raw_commands.size(), MAX_COMMANDS)):
		var command: Variant = raw_commands[index]
		if not command is String or command not in ["U", "D", "L", "R", "P"]:
			errors.append("Replay command %d is not U, D, L, R or P." % index)
		else:
			commands.append(command)
	if not errors.is_empty():
		return _report(current_revision, commands, 0, 0, errors)
	var state := Board.new()
	state.setup(level)
	if not state.setup_errors.is_empty():
		return _report(current_revision, commands, 0, 0, state.setup_errors)
	for command: String in commands:
		match command:
			"U": state.step(Vector2i.UP)
			"D": state.step(Vector2i.DOWN)
			"L": state.step(Vector2i.LEFT)
			"R": state.step(Vector2i.RIGHT)
			"P": state.punch()
	if not state.is_won():
		errors.append("Replay did not finish with every target occupied.")
	return _report(current_revision, commands, state.moves, state.punches, errors)


static func _report(current_revision: String, commands: Array, moves: int, punches: int, errors: Array) -> Dictionary:
	return {"proof_version": 1, "valid": errors.is_empty(), "revision": current_revision, "commands": commands.duplicate(), "moves": moves, "punches": punches, "errors": errors.duplicate()}


static func _rule_fields(definition: Dictionary) -> Dictionary:
	var behavior := str(definition.get("behavior", ""))
	var result := {"behavior": behavior, "pushable": bool(definition.get("pushable", false)), "punchable": bool(definition.get("punchable", false)), "punch_distance": int(definition.get("punch_distance", 0))}
	if behavior == "plate":
		result["activation_filter"] = str(definition.get("activation_filter", "all"))
	elif behavior == "door":
		result["gate_logic"] = str(definition.get("gate_logic", "any"))
	return result


static func _sorted_cells(raw: Array) -> Array:
	var result: Array = raw.duplicate(true)
	result.sort_custom(func(left: Array, right: Array) -> bool: return int(left[1]) < int(right[1]) if int(left[1]) != int(right[1]) else int(left[0]) < int(right[0]))
	return result


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
