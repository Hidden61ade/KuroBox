class_name ObjectCatalog
extends RefCounted
## Shared authoring and presentation definitions. Callers receive independent copies.

const DEFINITIONS_PATH := "res://content/definitions/objects.json"
static var last_errors: Array[String] = []
static var _definitions: Dictionary = {}


static func all_types() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for definition: Dictionary in _definitions.values():
		result.append(definition.duplicate(true))
	return result


static func get_type(type_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(type_id, {}).duplicate(true)


static func reload() -> Array[String]:
	_definitions.clear()
	last_errors.clear()
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		last_errors.append("Cannot read object definitions: %s" % error_string(FileAccess.get_open_error()))
		return last_errors.duplicate()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		last_errors.append("Invalid object definitions JSON: %s" % parser.get_error_message())
		return last_errors.duplicate()
	var document: Dictionary = parser.data
	if document.get("schema_version") != 1 or not document.get("types") is Array:
		last_errors.append("Object definitions require schema_version 1 and a types array.")
		return last_errors.duplicate()
	for raw: Variant in document["types"]:
		if not raw is Dictionary:
			last_errors.append("Object definition must be an object.")
			continue
		var type_id: String = str(raw.get("id", ""))
		var behavior: String = str(raw.get("behavior", ""))
		if type_id.is_empty() or _definitions.has(type_id):
			last_errors.append("Missing or duplicate object type: %s" % type_id)
			continue
		if behavior not in ["wood", "bag", "plate", "door"]:
			last_errors.append("Unsupported behavior '%s' for '%s'." % [behavior, type_id])
			continue
		if not raw.get("pushable", false) is bool or not raw.get("punchable", false) is bool:
			last_errors.append("Capabilities must be booleans: %s" % type_id)
			continue
		var distance: Variant = raw.get("punch_distance", 0)
		if not distance is float and not distance is int:
			last_errors.append("Invalid punch distance: %s" % type_id)
			continue
		if float(distance) != floor(float(distance)) or int(distance) < 0 or int(distance) > 16:
			last_errors.append("Punch distance must be an integer from 0 to 16: %s" % type_id)
			continue
		if raw.get("punchable", false) and int(distance) == 0:
			last_errors.append("Punchable object needs a positive punch distance: %s" % type_id)
			continue
		_definitions[type_id] = raw.duplicate(true)
	if not last_errors.is_empty():
		_definitions.clear()
	return last_errors.duplicate()


static func _ensure_loaded() -> void:
	if _definitions.is_empty() and last_errors.is_empty():
		reload()
