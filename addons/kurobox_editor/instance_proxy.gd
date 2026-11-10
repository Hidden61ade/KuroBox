@tool
class_name KuroInstanceProxy
extends Resource

signal locate_requested(instance_id: String)
signal link_requested(instance_id: String)
signal parameters_requested(proxy: KuroInstanceProxy, parameters: Dictionary)

var document: KuroAuthoringDocument
var instance_id: String = ""

func bind_document(value: KuroAuthoringDocument, id: String) -> void:
	document = value
	instance_id = id
	var item := instance()
	var definition := ObjectCatalog.get_type(str(item.get("type", "")))
	resource_name = str(definition.get("editor_label", item.get("type", "物件"))) + " · " + id
	notify_property_list_changed()

func instance() -> Dictionary:
	return document.find_instance(instance_id) if document != null else {}

func schema() -> Array[Dictionary]:
	return ObjectCatalog.parameter_schema(str(instance().get("type", "")))

func defaults() -> Dictionary:
	return ObjectCatalog.get_type(str(instance().get("type", "")))

func request_parameters(parameters: Dictionary) -> void:
	parameters_requested.emit(self, parameters.duplicate(true))

func _get_property_list() -> Array[Dictionary]:
	return [
		{"name":"关卡 ID", "type":TYPE_STRING, "usage":PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY},
		{"name":"实例 ID", "type":TYPE_STRING, "usage":PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY},
		{"name":"类型 ID", "type":TYPE_STRING, "usage":PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY},
		{"name":"params", "type":TYPE_DICTIONARY, "usage":PROPERTY_USAGE_EDITOR},
		{"name":"表现贴图", "type":TYPE_OBJECT, "hint":PROPERTY_HINT_RESOURCE_TYPE, "hint_string":"Texture2D", "usage":PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY},
		{"name":"关联门", "type":TYPE_PACKED_STRING_ARRAY, "usage":PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY},
	]

func _get(property: StringName) -> Variant:
	match property:
		&"关卡 ID": return str(document.data.get("id", "")) if document != null else ""
		&"实例 ID": return instance_id
		&"类型 ID": return str(instance().get("type", ""))
		&"params": return instance().get("params", {}).duplicate(true)
		&"表现贴图":
			var path := str(defaults().get("sprite", ""))
			return load(path) if ResourceLoader.exists(path) else null
		&"关联门": return PackedStringArray(instance().get("targets", []))
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property == &"params" and value is Dictionary and document != null:
		var success := document.set_parameters(instance_id, value)
		if success:
			emit_changed()
		return success
	return false
