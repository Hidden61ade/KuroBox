@tool
class_name KuroAuthoringDocument
extends Resource
## Editor history targets this data object; it never owns editor or gameplay nodes.

signal snapshot_changed(document: KuroAuthoringDocument)

var data: Dictionary = {}
var saved: Dictionary = {}
var draft_hash: String = ""
var published_hash: String = ""

func initialize(level: Dictionary, entry: Dictionary = {}) -> void:
	data = level.duplicate(true)
	saved = data.duplicate(true)
	draft_hash = str(entry.get("draft_hash", ""))
	published_hash = str(entry.get("published_hash", ""))
	resource_name = str(data.get("title", "关卡"))

func apply_snapshot(snapshot: Dictionary) -> void:
	data = snapshot.duplicate(true)
	resource_name = str(data.get("title", "关卡"))
	snapshot_changed.emit(self)

func dirty() -> bool:
	return data != saved

func find_instance(instance_id: String) -> Dictionary:
	for instance: Dictionary in data.get("objects", []):
		if str(instance.get("id", "")) == instance_id:
			return instance.duplicate(true)
	return {}

func set_parameters(instance_id: String, parameters: Dictionary) -> bool:
	var copy := data.duplicate(true)
	for instance: Dictionary in copy.get("objects", []):
		if str(instance.get("id", "")) != instance_id:
			continue
		instance["params"] = parameters.duplicate(true)
		if parameters.is_empty():
			instance.erase("params")
		if not ObjectCatalog.validate_parameters(instance).is_empty():
			return false
		copy.get("metadata", {}).erase("verified_proof")
		if copy.get("metadata") is Dictionary:
			copy.metadata.solution = []
		apply_snapshot(copy)
		return true
	return false

func mark_saved(hash_value: String) -> void:
	saved = data.duplicate(true)
	draft_hash = hash_value
	snapshot_changed.emit(self)
