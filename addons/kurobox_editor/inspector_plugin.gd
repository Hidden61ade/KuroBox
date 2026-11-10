@tool
extends EditorInspectorPlugin

const Proxy = preload("res://addons/kurobox_editor/instance_proxy.gd")
const ParameterProperty = preload("res://addons/kurobox_editor/parameters_property.gd")

func _can_handle(object: Object) -> bool:
	return object is Proxy

func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name != "params":
		return false
	var property := ParameterProperty.new()
	property.label = "实例参数覆盖"
	property.configure(object.schema(), object.defaults())
	add_property_editor(name, property)
	return true

func _parse_end(object: Object) -> void:
	var row := VBoxContainer.new()
	var locate := Button.new()
	locate.text = "在棋盘定位"
	locate.pressed.connect(func() -> void: object.locate_requested.emit(object.instance_id))
	row.add_child(locate)
	if ObjectCatalog.get_type(str(object.instance().get("type", ""))).get("behavior") == "plate":
		var link := Button.new()
		link.text = "点击棋盘上的门以连线"
		link.pressed.connect(func() -> void: object.link_requested.emit(object.instance_id))
		row.add_child(link)
	add_custom_control(row)
