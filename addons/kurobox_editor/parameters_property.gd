@tool
extends EditorProperty
## One dictionary property makes native Undo restore override absence as well as values.

var _schema: Array[Dictionary] = []
var _defaults: Dictionary = {}
var _controls: Dictionary = {}
var _checks: Dictionary = {}
var _errors: Dictionary = {}
var _refreshing := false

func configure(schema: Array[Dictionary], defaults: Dictionary) -> void:
	_schema = schema
	_defaults = defaults
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	set_bottom_editor(column)
	var help := Label.new()
	help.text = "未覆盖时跟随类型默认值；勾选后仅影响此实例。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 12)
	column.add_child(help)
	if schema.is_empty():
		help.text = "此类型没有可覆盖参数。"
	for field: Dictionary in schema:
		var id := str(field.id)
		var row := VBoxContainer.new()
		column.add_child(row)
		var check := CheckBox.new()
		check.text = str(field.get("label", id))
		check.tooltip_text = str(field.get("description", ""))
		check.toggled.connect(_override_changed.bind(id))
		row.add_child(check)
		_checks[id] = check
		if str(field.get("type", "")) == "int":
			var spin := SpinBox.new()
			spin.min_value = float(field.get("min", 0))
			spin.max_value = float(field.get("max", 16))
			spin.step = 1
			spin.suffix = "格"
			spin.value_changed.connect(_number_changed.bind(id))
			row.add_child(spin)
			_controls[id] = spin
		else:
			var picker := OptionButton.new()
			var options: Array = field.get("options", [])
			for option: Variant in options:
				var option_value := str(option.get("value", "")) if option is Dictionary else str(option)
				var translated := {"all":"全部 / 所有", "any":"任一压板", "player":"仅玩家", "boxes":"仅箱子"}.get(option_value, option_value)
				var option_label := str(option.get("label", translated)) if option is Dictionary else str(translated)
				picker.add_item(option_label)
				picker.set_item_metadata(picker.item_count - 1, option_value)
			picker.item_selected.connect(_option_changed.bind(id))
			row.add_child(picker)
			_controls[id] = picker
		var error := Label.new()
		error.text = "当前覆盖无效；请改值或取消覆盖。"
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error.visible = false
		row.add_child(error)
		_errors[id] = error

func _update_property() -> void:
	if get_edited_object() == null:
		return
	_refreshing = true
	var parameters: Dictionary = get_edited_object().get(get_edited_property())
	for field: Dictionary in _schema:
		var id := str(field.id)
		var value: Variant = parameters.get(id, _defaults.get(id))
		_checks[id].set_pressed_no_signal(parameters.has(id))
		var control: Control = _controls[id]
		if control is SpinBox:
			var valid_number: bool = (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= control.min_value and float(value) <= control.max_value
			control.set_value_no_signal(float(value) if valid_number else float(_defaults.get(id, control.min_value)))
			_errors[id].visible = not valid_number
		else:
			var matched := false
			for index in range(control.item_count):
				if control.get_item_metadata(index) == _defaults.get(id):
					control.select(index)
				if control.get_item_metadata(index) == value:
					control.select(index)
					matched = true
					break
			_errors[id].visible = not matched
	_refreshing = false

func _override_changed(enabled: bool, id: String) -> void:
	if _refreshing:
		return
	var parameters: Dictionary = get_edited_object().get(get_edited_property()).duplicate(true)
	if enabled:
		parameters[id] = _defaults.get(id)
	else:
		parameters.erase(id)
	get_edited_object().request_parameters(parameters)

func _number_changed(value: float, id: String) -> void:
	_set_value(id, int(value))

func _option_changed(index: int, id: String) -> void:
	_set_value(id, _controls[id].get_item_metadata(index))

func _set_value(id: String, value: Variant) -> void:
	if _refreshing:
		return
	var parameters: Dictionary = get_edited_object().get(get_edited_property()).duplicate(true)
	parameters[id] = value
	get_edited_object().request_parameters(parameters)
