@tool
extends EditorPlugin

const Workbench = preload("res://addons/kurobox_editor/workbench.gd")
const Inspector = preload("res://addons/kurobox_editor/inspector_plugin.gd")
var panel: Control
var inspector_extension: EditorInspectorPlugin

func _enter_tree() -> void:
	inspector_extension = Inspector.new()
	add_inspector_plugin(inspector_extension)
	panel = Workbench.new()
	panel.name = "KuroBoxWorkbench"
	panel.host_plugin = self
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	add_tool_menu_item("KuroBox 关卡工作台", _open_workbench)
	if "--kuro-workbench" in OS.get_cmdline_user_args():
		_open_workbench.call_deferred()
	if "--kuro-native-smoke" in OS.get_cmdline_user_args():
		var runner: Node = load("res://tests/test_native_plugin.gd").new()
		add_child(runner)
		runner.run.call_deferred(self)

func _exit_tree() -> void:
	remove_tool_menu_item("KuroBox 关卡工作台")
	var inspector: Object = EditorInterface.get_inspector()
	if inspector.has_method("get_edited_object") and inspector.call("get_edited_object") is KuroInstanceProxy:
		EditorInterface.inspect_object(null)
	if is_instance_valid(panel):
		panel.save_recovery()
		panel.queue_free()
	if inspector_extension != null:
		remove_inspector_plugin(inspector_extension)

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "KuroBox"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMap", "EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = value

func _open_workbench() -> void:
	EditorInterface.set_main_screen_editor("KuroBox")

func _get_unsaved_status(for_scene: String) -> String:
	if is_instance_valid(panel):
		var titles: PackedStringArray = panel.unsaved_titles()
		if not titles.is_empty():
			return "KuroBox 未保存草稿：" + "、".join(titles)
	return ""

func _save_external_data() -> void:
	if is_instance_valid(panel):
		panel.save_all_drafts()
