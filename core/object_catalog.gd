@tool
class_name ObjectCatalog
extends RefCounted
## Shared authoring and presentation definitions. Callers receive independent copies.

const DEFINITIONS_PATH := "res://content/definitions/objects.json"
static var last_errors: Array[String] = []
static var _definitions: Dictionary = {}
static var _document: Dictionary = {}
static var _loaded_path: String = ""
static var _loaded: bool = false


static func all_types() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for definition: Dictionary in _definitions.values():
		result.append(definition.duplicate(true))
	return result


static func get_type(type_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(type_id, {}).duplicate(true)


static func reload_catalog(path: String = DEFINITIONS_PATH) -> Array[String]:
	last_errors.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_errors.append("Cannot read object definitions '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return last_errors.duplicate()
	if file.get_length() > 2 * 1024 * 1024:
		last_errors.append("Object definitions exceed the 2 MiB limit.")
		file.close()
		return last_errors.duplicate()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		last_errors.append("Invalid object definitions JSON: %s" % parser.get_error_message())
		return last_errors.duplicate()
	last_errors = _validate_document(parser.data)
	if not last_errors.is_empty():
		return last_errors.duplicate()
	_install_document(_normalize_document(parser.data), path)
	return last_errors.duplicate()


static func _ensure_loaded() -> void:
	if not _loaded and last_errors.is_empty():
		reload_catalog()


static func reload(path: String = DEFINITIONS_PATH) -> Array[String]:
	# On a preloaded Script resource, .reload is a Godot built-in. Static callers
	# must use reload_catalog; this alias only preserves instance-call compatibility.
	return reload_catalog(path)


static func catalog_document() -> Dictionary:
	_ensure_loaded()
	return _document.duplicate(true)


static func parameter_schema(type_id: String) -> Array[Dictionary]:
	var definition := get_type(type_id)
	return _schema_for_behavior(str(definition.get("behavior", "")))


static func validate_parameters(instance: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var type_id := str(instance.get("type", ""))
	var definition := get_type(type_id)
	if definition.is_empty():
		errors.append("object '%s': unknown type '%s'." % [str(instance.get("id", "?")), type_id])
		return errors
	var parameters: Variant = instance.get("params", {})
	if not parameters is Dictionary:
		errors.append("object '%s'.params: expected an object." % str(instance.get("id", "?")))
		return errors
	var fields: Dictionary = {}
	for field: Dictionary in _schema_for_behavior(str(definition["behavior"])):
		fields[field["id"]] = field
	for key: Variant in parameters:
		if not key is String or not fields.has(key):
			errors.append("object '%s'.params: unknown parameter '%s' for '%s'." % [str(instance.get("id", "?")), str(key), type_id])
			continue
		var issue := _parameter_error(fields[key], parameters[key])
		if not issue.is_empty():
			errors.append("object '%s'.params.%s: %s" % [str(instance.get("id", "?")), key, issue])
	return errors


static func resolve_instance(instance: Dictionary) -> Dictionary:
	if not validate_parameters(instance).is_empty():
		return {}
	var definition := get_type(str(instance.get("type", "")))
	var parameters: Dictionary = instance.get("params", {})
	for field: Dictionary in _schema_for_behavior(str(definition["behavior"])):
		var key: String = field["id"]
		if parameters.has(key):
			definition[key] = int(parameters[key]) if field["type"] == "int" else parameters[key]
	return definition


static func create_variant(source_id: String, new_id: String, label: String, overrides: Dictionary, path: String = DEFINITIONS_PATH) -> Error:
	_ensure_loaded()
	last_errors.clear()
	if not _definitions.has(source_id):
		last_errors.append("Cannot create variant: unknown source type '%s'." % source_id)
		return ERR_INVALID_DATA
	if _definitions.has(new_id):
		last_errors.append("Cannot create variant: type '%s' already exists." % new_id)
		return ERR_ALREADY_EXISTS
	var parameter_errors := validate_parameters({"id": new_id, "type": source_id, "params": overrides})
	if not parameter_errors.is_empty():
		last_errors = parameter_errors
		return ERR_INVALID_DATA
	var variant := resolve_instance({"type": source_id, "params": overrides})
	variant["id"] = new_id
	variant["label"] = label
	variant["editor_label"] = label
	var document := catalog_document()
	document["types"].append(variant)
	return write_definition_document(document, path)


static func write_definition_document(document: Dictionary, path: String = DEFINITIONS_PATH) -> Error:
	last_errors = _validate_document(document)
	if not last_errors.is_empty():
		return ERR_INVALID_DATA
	if path.strip_edges().is_empty():
		last_errors.append("Choose an object definitions output path.")
		return ERR_FILE_BAD_PATH
	var normalized := _normalize_document(document)
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		last_errors.append("Cannot create definitions folder: %s" % error_string(directory_error))
		return directory_error
	var temporary := absolute + ".tmp-%d" % Time.get_ticks_usec()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		last_errors.append("Cannot write definitions: %s" % error_string(open_error))
		return open_error
	file.store_string(JSON.stringify(normalized, "  ", true) + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		last_errors.append("Could not finish writing definitions: %s" % error_string(write_error))
		return write_error
	var rename_error := DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		last_errors.append("Could not replace definitions: %s" % error_string(rename_error))
		return rename_error
	if _loaded_path.is_empty() or ProjectSettings.globalize_path(_loaded_path) == absolute:
		_install_document(normalized, path)
	return OK


static func _validate_document(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if document.get("schema_version") != 1 or not document.get("types") is Array:
		errors.append("Object definitions require schema_version 1 and a types array.")
		return errors
	var ids: Dictionary = {}
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]{0,63}$")
	for raw: Variant in document["types"]:
		if not raw is Dictionary:
			errors.append("Object definition must be an object.")
			continue
		var type_id := str(raw.get("id", ""))
		var behavior := str(raw.get("behavior", ""))
		if not raw.get("id") is String or id_pattern.search(type_id) == null or ids.has(type_id):
			errors.append("Invalid or duplicate type ID '%s'; use lowercase letters, digits and underscores." % type_id)
		ids[type_id] = true
		if not raw.get("label") is String or str(raw.get("label", "")).strip_edges().is_empty():
			errors.append("Type '%s' needs a non-empty label." % type_id)
		if behavior not in ["wood", "bag", "plate", "door"]:
			errors.append("Unsupported behavior '%s' for '%s'." % [behavior, type_id])
			continue
		if not raw.get("pushable", false) is bool or not raw.get("punchable", false) is bool:
			errors.append("Capabilities must be booleans: %s" % type_id)
		var distance: Variant = raw.get("punch_distance", 2 if behavior == "bag" else 0)
		if not _integer(distance) or int(distance) < 0 or int(distance) > 16:
			errors.append("Punch distance must be an integer from 0 to 16: %s" % type_id)
		elif raw.get("punchable", false) and int(distance) == 0:
			errors.append("Punchable object needs a positive punch distance: %s" % type_id)
		for field: Dictionary in _schema_for_behavior(behavior):
			var key: String = field["id"]
			var fallback: Variant = 2 if key == "punch_distance" else "all" if key == "activation_filter" else "any"
			var issue := _parameter_error(field, raw.get(key, fallback))
			if not issue.is_empty():
				errors.append("Type '%s'.%s: %s" % [type_id, key, issue])
	if ids.is_empty():
		errors.append("Object definitions must include at least one type.")
	return errors


static func _normalize_document(document: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	result["schema_version"] = 1
	for item: Dictionary in result["types"]:
		var behavior := str(item["behavior"])
		item["pushable"] = item.get("pushable", false)
		item["punchable"] = item.get("punchable", false)
		item["punch_distance"] = int(item.get("punch_distance", 2 if behavior == "bag" else 0))
		if behavior == "plate":
			item["activation_filter"] = item.get("activation_filter", "all")
		elif behavior == "door":
			item["gate_logic"] = item.get("gate_logic", "any")
	return result


static func _install_document(document: Dictionary, path: String) -> void:
	var replacement: Dictionary = {}
	for item: Dictionary in document["types"]:
		replacement[str(item["id"])] = item.duplicate(true)
	_definitions = replacement
	_document = document.duplicate(true)
	_loaded_path = path
	_loaded = true
	last_errors.clear()


static func _schema_for_behavior(behavior: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match behavior:
		"bag":
			result.append({"id": "punch_distance", "label": "击退距离", "type": "int", "min": 1, "max": 16, "options": [], "description": "一次拳击最多移动的格数；遇障碍提前停止。"})
		"plate":
			result.append({"id": "activation_filter", "label": "触发对象", "type": "enum", "min": 0, "max": 0, "options": ["all", "player", "boxes"], "description": "all：玩家或箱子；player：仅玩家；boxes：仅木箱或沙袋。"})
		"door":
			result.append({"id": "gate_logic", "label": "压板组合", "type": "enum", "min": 0, "max": 0, "options": ["any", "all"], "description": "any：任一关联压板触发；all：所有关联压板同时触发。占门时仍保持开启。"})
	return result


static func _parameter_error(field: Dictionary, value: Variant) -> String:
	if field["type"] == "int":
		if not _integer(value) or int(value) < int(field["min"]) or int(value) > int(field["max"]):
			return "expected an integer from %d to %d." % [field["min"], field["max"]]
	elif field["type"] == "enum":
		if not value is String or value not in field["options"]:
			return "expected one of %s." % str(field["options"])
	return ""


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
