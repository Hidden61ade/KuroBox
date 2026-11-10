@tool
extends VBoxContainer
## Native editor coordinator. The document resource owns data; the widget proposes edits.

const Workspace = preload("res://features/editor/services/level_workspace.gd")
const EditorWidget = preload("res://features/editor/level_editor.gd")
const Document = preload("res://addons/kurobox_editor/authoring_document.gd")
const Proxy = preload("res://addons/kurobox_editor/instance_proxy.gd")
const Thumbnail = preload("res://addons/kurobox_editor/level_thumbnail.gd")
const Proof = preload("res://core/replay_proof.gd")

var host_plugin: EditorPlugin
var workspace: RefCounted
var editor: Control
var active_document: KuroAuthoringDocument
var documents: Dictionary[String, KuroAuthoringDocument] = {}
var entries: Array[Dictionary] = []
var current_proxy: KuroInstanceProxy
var last_proof: Dictionary = {}

var _list: ItemList
var _search: LineEdit
var _status: Label
var _validation: Label
var _proof_status: Label
var _debug: RichTextLabel
var _thumbnail: Control
var _pending_order: Array[String] = []
var _display_ids: Array[String] = []
var _dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_title: LineEdit
var _dialog_mode: String = "new"
var _variant_dialog: ConfirmationDialog
var _variant_source: OptionButton
var _variant_id: LineEdit
var _variant_title: LineEdit
var _variant_parameters: VBoxContainer
var _variant_controls: Dictionary = {}
var _built := false
var _refreshing := false
var _recovery: Timer
var _screenshot_dialog: FileDialog
var _undo_context := RefCounted.new()
var _proxy_cache: Dictionary[String, KuroInstanceProxy] = {}
var _variant_source_hash := ""
var _order_dirty := false
var _recovery_write_blocked := false
var _last_rejected_recovery_path := ""

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace = Workspace.new()
	workspace.configure()
	_build_ui()
	_built = true
	_refresh_library()
	_restore_recovery()
	if active_document == null and not entries.is_empty():
		open_level(str(entries[0].id))

func _build_ui() -> void:
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	_button(toolbar, "保存草稿", save_current_draft).name = "SaveDraft"
	_button(toolbar, "检查", _check_current).name = "ValidateDraft"
	_button(toolbar, "即时试关", _begin_test).name = "TestDraft"
	_button(toolbar, "回放验证", _replay).name = "ReplayProof"
	_button(toolbar, "发布", publish_current).name = "PublishDraft"
	_button(toolbar, "类型变体", _show_variant_dialog).name = "TypeVariant"
	_button(toolbar, "刷新类型", refresh_types)
	_button(toolbar, "重载磁盘", reload_current)
	_button(toolbar, "截图", _show_screenshot_dialog)
	_validation = Label.new()
	_validation.text = "结构：待检查"
	toolbar.add_child(_validation)
	_proof_status = Label.new()
	_proof_status.text = "通关：未验证"
	toolbar.add_child(_proof_status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 225
	add_child(split)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 190
	split.add_child(library)
	var title := Label.new()
	title.text = "关卡库"
	title.add_theme_font_size_override("font_size", 20)
	library.add_child(title)
	_search = LineEdit.new()
	_search.name = "LevelSearch"
	_search.placeholder_text = "搜索名称 / ID"
	_search.text_changed.connect(func(_value: String) -> void: _render_list())
	library.add_child(_search)
	_list = ItemList.new()
	_list.name = "LevelLibrary"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 180
	_list.max_text_lines = 2
	_list.item_selected.connect(_list_selected)
	library.add_child(_list)
	_thumbnail = Thumbnail.new()
	_thumbnail.custom_minimum_size = Vector2(150, 100)
	library.add_child(_thumbnail)
	var actions := HFlowContainer.new()
	library.add_child(actions)
	_button(actions, "新建", _show_new_dialog.bind("new"))
	_button(actions, "复制", _show_new_dialog.bind("duplicate"))
	_button(actions, "↑", _move_order.bind(-1))
	_button(actions, "↓", _move_order.bind(1))
	_button(library, "保存正式顺序", save_order)
	_button(library, "撤回为草稿", unpublish_current)
	editor = EditorWidget.new()
	editor.name = "AuthoringCanvas"
	editor.embedded_mode = true
	editor.native_inspector = true
	editor.use_external_history = true
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(editor)
	editor.document_changed.connect(_widget_transaction)
	editor.selection_changed.connect(_selection_changed)
	editor.proof_recorded.connect(_proof_recorded)
	editor.test_state_changed.connect(_test_debug)
	editor.undo_requested.connect(_native_undo)
	editor.redo_requested.connect(_native_redo)
	editor.save_requested.connect(save_current_draft)
	_debug = RichTextLabel.new()
	_debug.name = "MechanismDebug"
	_debug.custom_minimum_size.y = 76
	_debug.fit_content = false
	_debug.text = "试关后在此查看压板、门与开门原因。"
	add_child(_debug)
	_status = Label.new()
	_status.name = "WorkbenchStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_build_dialogs()
	_recovery = Timer.new()
	_recovery.one_shot = true
	_recovery.wait_time = 1.0
	_recovery.timeout.connect(save_recovery)
	add_child(_recovery)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 30
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button

func _build_dialogs() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = "创建关卡"
	_dialog.ok_button_text = "创建"
	var form := VBoxContainer.new()
	_dialog.add_child(form)
	_new_id = LineEdit.new()
	_new_id.placeholder_text = "稳定 ID，例如 training_09"
	_new_id.custom_minimum_size.x = 360
	form.add_child(_new_id)
	_new_title = LineEdit.new()
	_new_title.placeholder_text = "显示名称"
	form.add_child(_new_title)
	_dialog.confirmed.connect(_create_from_dialog)
	add_child(_dialog)
	_variant_dialog = ConfirmationDialog.new()
	_variant_dialog.title = "从已有行为建立类型变体"
	_variant_dialog.ok_button_text = "登记类型"
	var variant_form := VBoxContainer.new()
	_variant_dialog.add_child(variant_form)
	_variant_source = OptionButton.new()
	_variant_source.item_selected.connect(func(_index: int) -> void: _build_variant_parameters())
	variant_form.add_child(_variant_source)
	_variant_id = LineEdit.new()
	_variant_id.placeholder_text = "新类型 ID，例如 bag_3"
	_variant_id.custom_minimum_size.x = 380
	variant_form.add_child(_variant_id)
	_variant_title = LineEdit.new()
	_variant_title.placeholder_text = "显示名称，例如 三格沙袋"
	variant_form.add_child(_variant_title)
	_variant_parameters = VBoxContainer.new()
	variant_form.add_child(_variant_parameters)
	_variant_dialog.confirmed.connect(_create_variant)
	add_child(_variant_dialog)
	_screenshot_dialog = FileDialog.new()
	_screenshot_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_screenshot_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_screenshot_dialog.filters = PackedStringArray(["*.png ; PNG 截图"])
	_screenshot_dialog.file_selected.connect(capture_report)
	add_child(_screenshot_dialog)

func _show_screenshot_dialog() -> void:
	_screenshot_dialog.current_path = ProjectSettings.globalize_path("res://evidence/native_editor_%d.png" % Time.get_unix_time_from_system())
	_screenshot_dialog.popup_centered_ratio(0.65)

func capture_report(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(path)
	_status.text = "截图已保存：" + path.get_file() if result == OK else "截图未保存：" + error_string(result)

func _refresh_library() -> void:
	entries.assign(workspace.list_levels())
	var published_ids: Array[String] = []
	for entry: Dictionary in entries:
		if not str(entry.get("published_path", "")).is_empty():
			published_ids.append(str(entry.id))
	var retained: Array[String] = []
	if _order_dirty:
		for id: String in _pending_order:
			if published_ids.has(id):
				retained.append(id)
	for id: String in published_ids:
		if not retained.has(id):
			retained.append(id)
	_pending_order = retained
	_render_list()

func _render_list() -> void:
	if not _built:
		return
	_refreshing = true
	_list.clear()
	_display_ids.clear()
	var query := _search.text.strip_edges().to_lower()
	var ordered: Array[Dictionary] = []
	for id: String in _pending_order:
		for entry: Dictionary in entries:
			if str(entry.id) == id:
				ordered.append(entry)
	for entry: Dictionary in entries:
		if not _pending_order.has(str(entry.id)):
			ordered.append(entry)
	for entry: Dictionary in ordered:
		var id := str(entry.id)
		var display_title := str(documents[id].data.get("title", entry.title)) if documents.has(id) else str(entry.title)
		if not query.is_empty() and not (id + display_title).to_lower().contains(query):
			continue
		var status: String = {"published":"已发布", "draft":"草稿", "modified":"发布后有草稿"}.get(str(entry.status), str(entry.status))
		var dirty := documents.has(id) and documents[id].dirty()
		_list.add_item(("● " if dirty else "") + status + " · " + display_title)
		_list.set_item_tooltip(_list.item_count - 1, id + "\n" + display_title + "\n" + status)
		_display_ids.append(id)
		if active_document != null and str(active_document.data.get("id", "")) == id:
			_list.select(_list.item_count - 1)
	_refreshing = false

func _list_selected(index: int) -> void:
	if not _refreshing and index < _display_ids.size():
		open_level(_display_ids[index])

func open_level(id: String) -> void:
	if documents.has(id):
		_activate(documents[id], true)
		return
	var level: Dictionary = workspace.load_level(id)
	if level.is_empty():
		_error("载入失败")
		return
	var document := Document.new()
	document.initialize(level, _entry(id))
	documents[id] = document
	document.snapshot_changed.connect(_document_changed)
	_activate(document, true)

func _activate(document: KuroAuthoringDocument, reset_view: bool) -> void:
	active_document = document
	if reset_view:
		editor.setup(document.data)
	else:
		editor.apply_document(document.data)
	editor._id_edit.editable = false
	last_proof = workspace.load_proof(str(document.data.id))
	if last_proof.is_empty() and not document.data.get("metadata", {}).get("solution", []).is_empty():
		var commands: Array[String] = []
		commands.assign(document.data.metadata.solution)
		last_proof = Proof.build(document.data, commands)
	editor.set_last_proof(last_proof)
	_selection_changed("")
	_refresh_status()
	_render_list()

func _entry(id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.id) == id:
			return entry
	return {}

func _widget_transaction(before: Dictionary, after: Dictionary, label: String) -> void:
	if active_document == null or before == after:
		return
	var manager := host_plugin.get_undo_redo()
	manager.create_action("KuroBox · " + label, UndoRedo.MERGE_DISABLE, _undo_context, false, false)
	# Transient authoring resources have no scene path. They belong to this
	# explicit global context, not to whichever .tscn happens to be selected.
	manager.force_fixed_history()
	manager.add_do_method(active_document, &"apply_snapshot", after)
	manager.force_fixed_history()
	manager.add_undo_method(active_document, &"apply_snapshot", before)
	manager.commit_action(false)
	active_document.apply_snapshot(after)

func _document_changed(document: KuroAuthoringDocument) -> void:
	if not is_instance_valid(editor):
		return
	if active_document != document:
		_activate(document, true)
	else:
		editor.apply_document(document.data)
	_refresh_status()
	_render_list()
	if current_proxy != null:
		current_proxy.emit_changed()
	if is_instance_valid(_recovery) and _recovery.is_inside_tree():
		_recovery.start()

func _selection_changed(instance_id: String) -> void:
	if active_document == null:
		return
	if instance_id.is_empty():
		if current_proxy != null:
			EditorInterface.inspect_object(null)
		current_proxy = null
		return
	if current_proxy != null and current_proxy.document == active_document and current_proxy.instance_id == instance_id:
		current_proxy.emit_changed()
		return
	var key := str(active_document.data.id) + "/" + instance_id
	if _proxy_cache.has(key):
		current_proxy = _proxy_cache[key]
	else:
		current_proxy = Proxy.new()
		current_proxy.bind_document(active_document, instance_id)
		current_proxy.locate_requested.connect(func(id: String) -> void: editor.focus_instance(id))
		current_proxy.link_requested.connect(func(id: String) -> void: editor.begin_link(id))
		current_proxy.parameters_requested.connect(_inspector_parameters_requested)
		_proxy_cache[key] = current_proxy
	EditorInterface.edit_resource(current_proxy)

func _inspector_parameters_requested(proxy: KuroInstanceProxy, parameters: Dictionary) -> void:
	if proxy.get("params") == parameters:
		return
	var before := proxy.document.data.duplicate(true)
	var after := before.duplicate(true)
	for instance: Dictionary in after.get("objects", []):
		if str(instance.get("id", "")) != proxy.instance_id:
			continue
		if parameters.is_empty():
			instance.erase("params")
		else:
			instance["params"] = parameters.duplicate(true)
		var errors := ObjectCatalog.validate_parameters(instance)
		if not errors.is_empty():
			_status.text = "参数未修改：" + "；".join(errors)
			return
	if after.get("metadata") is Dictionary:
		after.metadata.erase("verified_proof")
		after.metadata.solution = []
	var manager := host_plugin.get_undo_redo()
	manager.create_action("KuroBox · 实例参数覆盖", UndoRedo.MERGE_DISABLE, _undo_context, false, false)
	manager.force_fixed_history()
	manager.add_do_method(proxy.document, &"apply_snapshot", after)
	manager.force_fixed_history()
	manager.add_undo_method(proxy.document, &"apply_snapshot", before)
	manager.commit_action()

func _native_undo() -> void:
	host_plugin.get_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY).undo()

func _native_redo() -> void:
	host_plugin.get_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY).redo()

func save_current_draft() -> bool:
	if active_document == null:
		return false
	var result: Error = workspace.save_draft(active_document.data, active_document.draft_hash)
	if result != OK:
		_error("草稿未保存")
		return false
	_refresh_library()
	active_document.mark_saved(str(_entry(str(active_document.data.id)).get("draft_hash", "")))
	editor.mark_document_saved()
	_status.text = "草稿已保存 · 正式流程保持独立"
	save_recovery()
	EditorInterface.get_resource_filesystem().scan()
	return true

func _check_current() -> void:
	if active_document == null:
		return
	var errors: Array[String] = editor.validate_document()
	_validation.text = "结构：通过" if errors.is_empty() else "结构：%d 项问题" % errors.size()
	_refresh_proof_status()

func _begin_test() -> void:
	if active_document == null:
		return
	editor.begin_test()

func _proof_recorded(proof: Dictionary) -> void:
	if active_document == null:
		return
	last_proof = proof.duplicate(true)
	if workspace.save_proof(active_document.data, proof) != OK:
		_error("通关记录未保存")
		return
	_refresh_proof_status()
	_status.text = "通关记录已绑定当前规则版本，可回放并发布。"

func _replay() -> void:
	if active_document == null:
		return
	if not editor.set_last_proof(last_proof) or not editor.play_verified_replay():
		_status.text = "当前版本没有有效的通关记录，请先试关完成。"

func _test_debug(states: Array[Dictionary], summary: Dictionary) -> void:
	var lines := PackedStringArray(["试玩 · %s 步 / %s 拳" % [summary.get("moves", 0), summary.get("punches", 0)]])
	for state: Dictionary in states:
		if str(state.get("behavior", "")) == "plate":
			lines.append("压板 %s · %s · 触发对象 %s" % [state.id, "已按下" if state.get("pressed", false) else "未按下", state.get("filter", "all")])
		else:
			lines.append("门 %s · %s · 供电 %s · 占用保持 %s · %s" % [state.id, "开启" if state.get("open", false) else "关闭", str(state.get("powered_by", [])), "是" if state.get("held_open", false) else "否", state.get("logic", "any")])
	_debug.text = "\n".join(lines)

func publish_current() -> bool:
	if active_document == null or not save_current_draft():
		return false
	var error: Error = workspace.publish(active_document.data, last_proof, active_document.published_hash)
	if error != OK:
		_error("发布失败")
		return false
	_refresh_library()
	var id := str(active_document.data.id)
	active_document.initialize(workspace.load_level(id), _entry(id))
	editor.apply_document(active_document.data)
	editor.mark_document_saved()
	_refresh_status()
	_status.text = "已发布并登记正式清单 · " + id
	EditorInterface.get_resource_filesystem().scan()
	return true

func _refresh_status() -> void:
	if active_document == null:
		return
	_thumbnail.set_level(active_document.data)
	var issues := LevelCodec.validate(active_document.data)
	_validation.text = "结构：通过" if issues.is_empty() else "结构：%d 项待完成" % issues.size()
	_refresh_proof_status()
	_status.text = ("● 尚未保存，切换关卡会保留当前会话。" if active_document.dirty() else "草稿已保存。") + " 选中物件后在右侧 Inspector 编辑参数。"

func _refresh_proof_status() -> void:
	if active_document == null:
		return
	var result: Dictionary = Proof.verify(active_document.data, last_proof)
	_proof_status.text = "通关：已验证" if result.get("valid", false) else "通关：未验证 / 已失效"

func _show_new_dialog(mode: String) -> void:
	_dialog_mode = mode
	_dialog.title = "创建关卡"
	_dialog.dialog_text = ""
	_dialog.ok_button_text = "创建"
	_new_id.show()
	_new_title.show()
	_new_id.text = ""
	_new_title.text = str(active_document.data.get("title", "")) + " 副本" if mode == "duplicate" and active_document != null else "新关卡"
	_dialog.popup_centered(Vector2i(430, 190))
	_new_id.grab_focus()

func _create_from_dialog() -> void:
	if _dialog_mode == "reload":
		_force_reload()
		return
	var level: Dictionary
	if _dialog_mode == "duplicate" and active_document != null:
		level = workspace.fork_draft(active_document.data, _new_id.text, _new_title.text)
	else:
		level = workspace.new_level(_new_id.text, _new_title.text)
	if level.is_empty():
		_error("创建失败")
		return
	_refresh_library()
	open_level(str(level.id))

func _move_order(direction: int) -> void:
	if active_document == null:
		return
	var index := _pending_order.find(str(active_document.data.id))
	var destination := index + direction
	if index < 0 or destination < 0 or destination >= _pending_order.size():
		_status.text = "草稿先发布后才能调整正式顺序。"
		return
	var other := _pending_order[destination]
	_pending_order[destination] = _pending_order[index]
	_pending_order[index] = other
	_order_dirty = true
	_render_list()
	_status.text = "顺序待保存；关卡 ID 和存档关联保持稳定。"

func save_order() -> void:
	if workspace.save_order(_pending_order) != OK:
		_error("顺序未保存")
		return
	_order_dirty = false
	_status.text = "正式顺序已保存。"
	EditorInterface.get_resource_filesystem().scan()

func unpublish_current() -> void:
	if active_document == null:
		return
	if active_document.dirty() and not save_current_draft():
		return
	if not workspace.has_method("unpublish"):
		_status.text = "此关卡可以继续保存草稿。"
		return
	if workspace.unpublish(str(active_document.data.id), active_document.published_hash) != OK:
		_error("撤回失败")
		return
	_refresh_library()
	active_document.initialize(workspace.load_level(str(active_document.data.id)), _entry(str(active_document.data.id)))
	editor.apply_document(active_document.data)
	_refresh_status()
	_status.text = "已从正式流程撤回，内容保留为草稿。"

func reload_current() -> void:
	if active_document == null:
		return
	if active_document.dirty() or _order_dirty:
		_dialog_mode = "reload"
		_dialog.title = "重新载入磁盘版本"
		_dialog.dialog_text = "当前修改与待保存顺序会先保留为恢复副本，再载入磁盘版本。\n也可取消后用“复制”将当前关卡另存。"
		_dialog.ok_button_text = "保留恢复副本并重载"
		_new_id.hide()
		_new_title.hide()
		_dialog.popup_centered(Vector2i(460, 160))
		return
	_force_reload()

func _force_reload() -> void:
	if active_document == null:
		return
	if active_document.dirty() or _order_dirty:
		var backup := "res://.godot/kurobox_editor/discarded_%d.json" % Time.get_unix_time_from_system()
		if _write_recovery(backup, [{"data":active_document.data,"saved":active_document.saved,"editor_order":_pending_order}]) != OK:
			_status.text = "未能保留恢复副本，已停止重载。"
			return
	var id := str(active_document.data.id)
	var level: Dictionary = workspace.load_level(id)
	if level.is_empty():
		_error("重载失败")
		return
	_order_dirty = false
	_pending_order.clear()
	_refresh_library()
	active_document.initialize(level, _entry(id))
	_activate(active_document, false)
	_status.text = "已载入磁盘版本；旧的未保存修改保存在编辑器恢复目录。"

func _show_variant_dialog(show_popup: bool = true) -> void:
	if not ObjectCatalog.reload_catalog().is_empty():
		_status.text = "类型目录无法载入：" + "; ".join(ObjectCatalog.last_errors)
		return
	_variant_source_hash = FileAccess.get_sha256(ObjectCatalog.DEFINITIONS_PATH)
	_variant_source.clear()
	for definition: Dictionary in ObjectCatalog.all_types():
		_variant_source.add_item(str(definition.get("editor_label", definition.id)))
		_variant_source.set_item_metadata(_variant_source.item_count - 1, str(definition.id))
	_variant_id.text = ""
	_variant_title.text = ""
	_build_variant_parameters()
	if show_popup:
		_variant_dialog.popup_centered(Vector2i(450, 340))

func refresh_types() -> void:
	editor.refresh_catalog()
	if not ObjectCatalog.last_errors.is_empty():
		_status.text = "类型目录载入失败，继续保留当前可用定义：" + "；".join(ObjectCatalog.last_errors)
		return
	if current_proxy != null:
		current_proxy.notify_property_list_changed()
	_refresh_status()
	_status.text = "类型与资源映射已刷新；规则变更后的通关证明需要重新验证。"

func _build_variant_parameters() -> void:
	for child: Node in _variant_parameters.get_children():
		_variant_parameters.remove_child(child)
		child.queue_free()
	_variant_controls.clear()
	if _variant_source.item_count == 0:
		return
	var type_id := str(_variant_source.get_selected_metadata())
	var definition := ObjectCatalog.get_type(type_id)
	for field: Dictionary in ObjectCatalog.parameter_schema(type_id):
		var label := Label.new()
		label.text = str(field.get("label", field.id))
		_variant_parameters.add_child(label)
		if str(field.type) == "int":
			var spin := SpinBox.new()
			spin.min_value = field.get("min", 1)
			spin.max_value = field.get("max", 16)
			spin.step = 1
			spin.value = definition.get(field.id, 2)
			_variant_parameters.add_child(spin)
			_variant_controls[str(field.id)] = spin
		else:
			var picker := OptionButton.new()
			for option: String in field.get("options", []):
				picker.add_item({"all":"全部", "any":"任一", "player":"仅玩家", "boxes":"仅箱子"}.get(option, option))
				picker.set_item_metadata(picker.item_count - 1, option)
				if option == definition.get(field.id):
					picker.select(picker.item_count - 1)
			_variant_parameters.add_child(picker)
			_variant_controls[str(field.id)] = picker

func _create_variant() -> void:
	if FileAccess.get_sha256(ObjectCatalog.DEFINITIONS_PATH) != _variant_source_hash:
		_status.text = "类型目录已被外部修改，请重新打开类型变体窗口。"
		return
	var overrides: Dictionary = {}
	for field: String in _variant_controls:
		var control: Control = _variant_controls[field]
		overrides[field] = int(control.value) if control is SpinBox else control.get_selected_metadata()
	if ObjectCatalog.create_variant(str(_variant_source.get_selected_metadata()), _variant_id.text, _variant_title.text, overrides) != OK:
		_status.text = "类型未登记：" + "; ".join(ObjectCatalog.last_errors)
		return
	editor.refresh_catalog()
	_status.text = "类型已登记，图块面板已刷新：" + _variant_id.text
	EditorInterface.get_resource_filesystem().scan()

func _error(prefix: String) -> void:
	_status.text = prefix + "：" + "；".join(workspace.last_errors)

func save_recovery() -> void:
	if not _built:
		return
	if _recovery_write_blocked:
		_status.text = "恢复隔离文件未能保存，原恢复文件保持不变。请先检查写入权限或磁盘空间。"
		return
	var pending: Array[Dictionary] = []
	for document: KuroAuthoringDocument in documents.values():
		if document.dirty():
			pending.append({"data":document.data,"saved":document.saved,"draft_hash":document.draft_hash,"published_hash":document.published_hash})
	if _order_dirty:
		pending.append({"editor_order":_pending_order})
	if _write_recovery("res://.godot/kurobox_editor/recovery.json", pending) != OK:
		_status.text = "未能写入编辑恢复文件，请保存草稿或另存当前内容。"

func _write_recovery(path: String, payload: Array) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		return result
	if FileAccess.file_exists(path) and JSON.parse_string(FileAccess.get_file_as_string(path)) is Array:
		result = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
		if result != OK:
			return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))

func _restore_recovery(path: String = "res://.godot/kurobox_editor/recovery.json") -> void:
	var pending: Variant = null
	var rejected: Array[Dictionary] = []
	for candidate: String in [path, path + ".bak"]:
		if FileAccess.file_exists(candidate):
			var raw_text := FileAccess.get_file_as_string(candidate)
			pending = JSON.parse_string(raw_text)
			if pending is Array:
				break
			rejected.append({"source": candidate, "record_index": -1, "errors": ["恢复文件根节点必须是数组。"], "raw_text": raw_text})
	var restored := 0
	var needs_repair := 0
	if pending is Array:
		for index: int in range(pending.size()):
			var raw: Variant = pending[index]
			var errors := _recovery_record_errors(raw)
			if raw is Dictionary and raw.get("data") is Dictionary and documents.has(str(raw.data.get("id", ""))):
				errors.append("恢复记录重复了已保留的关卡 ID。")
			if not errors.is_empty():
				rejected.append({"source": path, "record_index": index, "errors": errors, "record": raw})
				continue
			var record: Dictionary = raw
			if record.get("editor_order") is Array:
				_pending_order.assign(record.editor_order)
				_order_dirty = true
			if not record.get("data") is Dictionary:
				continue
			var document := Document.new()
			document.initialize(LevelCodec.normalize(record.data))
			document.saved = LevelCodec.normalize(record.saved) if record.get("saved") is Dictionary and not record.saved.is_empty() else {}
			document.draft_hash = str(record.get("draft_hash", ""))
			document.published_hash = str(record.get("published_hash", ""))
			document.snapshot_changed.connect(_document_changed)
			documents[str(document.data.id)] = document
			restored += 1
			if not LevelCodec.validate_draft(document.data).is_empty():
				needs_repair += 1
	if not documents.is_empty():
		_activate(documents.values()[0], true)
	var messages := PackedStringArray()
	if restored > 0:
		messages.append("已完整恢复 %d 份未保存编辑，磁盘关卡尚未覆盖。" % restored)
	if needs_repair > 0:
		messages.append("其中 %d 份有叠层、类型或参数问题，原文已保留；修复前不能试玩或发布。" % needs_repair)
	if _order_dirty:
		messages.append("已恢复待保存的正式顺序。")
	if not rejected.is_empty():
		_last_rejected_recovery_path = path.get_base_dir().path_join("recovery_rejected_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
		if _write_recovery(_last_rejected_recovery_path, rejected) == OK:
			messages.append("%d 条记录因不安全结构未自动载入，原文及原因已隔离保存：%s" % [rejected.size(), _last_rejected_recovery_path])
		else:
			_recovery_write_blocked = true
			messages.append("无法保存隔离记录，已停止覆盖原恢复文件；请检查磁盘或权限：%s" % path)
	if not messages.is_empty():
		_status.text = "\n".join(messages)

func _recovery_record_errors(raw: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not raw is Dictionary:
		errors.append("恢复记录必须是字典。")
		return errors
	if not raw.has("data") and not raw.has("editor_order"):
		errors.append("恢复记录缺少关卡内容或顺序。")
	if raw.has("data"):
		if not raw.data is Dictionary:
			errors.append("关卡内容必须是字典。")
		else:
			errors.append_array(_recovery_shape_errors(raw.data))
	if raw.has("saved"):
		if not raw.saved is Dictionary:
			errors.append("已保存基线必须是字典。")
		elif not raw.saved.is_empty():
			for issue: String in _recovery_shape_errors(raw.saved):
				errors.append("已保存基线：" + issue)
	for field: String in ["draft_hash", "published_hash"]:
		if raw.has(field) and not raw[field] is String:
			errors.append(field + " 必须是字符串。")
	if raw.has("editor_order"):
		if not raw.editor_order is Array:
			errors.append("正式顺序必须是字符串数组。")
		else:
			for id: Variant in raw.editor_order:
				if not id is String or str(id).is_empty():
					errors.append("正式顺序包含非字符串或空 ID。")
	return errors

func _recovery_shape_safe(data: Dictionary) -> bool:
	return _recovery_shape_errors(data).is_empty()

func _recovery_shape_errors(data: Dictionary) -> Array[String]:
	# Recovery is authoring data, not a playable level. Semantic conflicts and
	# obsolete catalog parameters must remain editable rather than being dropped.
	var errors: Array[String] = []
	if not _recovery_integer(data.get("schema_version")) or int(data.get("schema_version", 0)) != 1:
		errors.append("不支持此恢复数据版本。")
	for field: String in ["id", "title"]:
		if not data.get(field) is String or (field == "id" and str(data.get(field, "")).is_empty()):
			errors.append(field + " 必须是字符串，关卡 ID 不能为空。")
	for field: String in ["width", "height"]:
		if not _recovery_integer(data.get(field)) or int(data.get(field, 0)) < 1 or int(data.get(field, 0)) > LevelCodec.MAX_SIDE:
			errors.append(field + " 必须是有效地图尺寸。")
	if not errors.is_empty():
		return errors
	var bounds := Vector2i(int(data.width), int(data.height))
	for field: String in ["floor", "walls", "goals"]:
		if not data.get(field) is Array:
			errors.append(field + " 必须是坐标数组。")
			continue
		for cell: Variant in data[field]:
			if not _recovery_cell_safe(cell, bounds):
				errors.append(field + " 包含不安全坐标。")
	if data.has("player") and data.player != null:
		if not (_recovery_pair_safe(data.player) and int(data.player[0]) == -1 and int(data.player[1]) == -1) and not _recovery_cell_safe(data.player, bounds):
			errors.append("出生位置必须是界内坐标或 [-1,-1]。")
	if data.has("facing") and not _recovery_pair_safe(data.facing):
		errors.append("朝向必须由两个整数组成。")
	if not data.get("objects") is Array:
		errors.append("objects 必须是数组。")
	else:
		for instance: Variant in data.objects:
			if not instance is Dictionary:
				errors.append("物件必须是字典。")
				continue
			for field: String in ["id", "type"]:
				if not instance.get(field) is String or str(instance.get(field, "")).is_empty():
					errors.append("物件的 " + field + " 必须是非空字符串。")
			if not _recovery_cell_safe(instance.get("cell"), bounds):
				errors.append("物件包含不安全坐标。")
			if instance.has("params") and not instance.params is Dictionary:
				errors.append("物件 params 必须是字典。")
			if instance.has("targets"):
				if not instance.targets is Array:
					errors.append("物件 targets 必须是字符串数组。")
				else:
					for target: Variant in instance.targets:
						if not target is String:
							errors.append("物件关联 ID 必须是字符串。")
	if data.has("metadata"):
		if not data.metadata is Dictionary:
			errors.append("metadata 必须是字典。")
		elif data.metadata.has("solution"):
			if not data.metadata.solution is Array:
				errors.append("solution 必须是字符串数组。")
			else:
				for command: Variant in data.metadata.solution:
					if not command is String:
						errors.append("solution 命令必须是字符串。")
	return errors

func _recovery_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 2147483647.0 and float(value) == floor(float(value))

func _recovery_pair_safe(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _recovery_integer(value[0]) and _recovery_integer(value[1])

func _recovery_cell_safe(value: Variant, bounds: Vector2i) -> bool:
	return _recovery_pair_safe(value) and int(value[0]) >= 0 and int(value[1]) >= 0 and int(value[0]) < bounds.x and int(value[1]) < bounds.y

func unsaved_titles() -> PackedStringArray:
	var result := PackedStringArray()
	for document: KuroAuthoringDocument in documents.values():
		if document.dirty():
			result.append(str(document.data.get("title", document.data.get("id", "关卡"))))
	if _order_dirty:
		result.append("正式顺序")
	return result

func save_all_drafts() -> void:
	var saved_documents: Array[KuroAuthoringDocument] = []
	for document: KuroAuthoringDocument in documents.values():
		if document.dirty() and workspace.save_draft(document.data, document.draft_hash) == OK:
			saved_documents.append(document)
	_refresh_library()
	for document: KuroAuthoringDocument in saved_documents:
		document.mark_saved(str(_entry(str(document.data.id)).get("draft_hash", "")))
	if _order_dirty:
		save_order()
	save_recovery()
