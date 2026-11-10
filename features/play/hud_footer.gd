class_name HudFooter
extends HBoxContainer
## Pure presentation: button and key-cap bindings share one action identity.

signal action_requested(action: StringName)

const Kit = preload("res://features/shell/ui_kit.gd")
const ACTIONS := [
	{"id": &"undo", "icon": "undo", "hint": "Z", "label": "撤销 · Z", "node": "UndoButton"},
	{"id": &"restart", "icon": "restart", "hint": "R", "label": "重开 · R", "node": "RestartButton"},
	{"id": &"punch", "icon": "punch", "hint": "SPACE", "label": "出拳 · Space", "node": "PunchButton"},
	{"id": &"fullscreen", "icon": "fullscreen", "hint": "F11", "label": "全屏 · F11", "node": "FullscreenButton"},
	{"id": &"sound", "icon": "volume", "hint": "M", "label": "静音 · M", "node": "SoundButton"},
	{"id": &"back", "icon": "back", "hint": "Q", "label": "返回 · Q", "node": "BackButton"},
]

var action_buttons: Dictionary[StringName, Button] = {}
var _sound_badge: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(400, 80)
	var left := _group(BoxContainer.ALIGNMENT_BEGIN)
	var middle := _group(BoxContainer.ALIGNMENT_CENTER)
	var right := _group(BoxContainer.ALIGNMENT_END)
	for index in range(ACTIONS.size()):
		var group := left if index < 2 else middle if index == 2 else right
		_add_action(group, ACTIONS[index])

func _group(group_alignment: BoxContainer.AlignmentMode) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_stretch_ratio = 1.0
	row.alignment = group_alignment
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	return row

func _add_action(parent: HBoxContainer, definition: Dictionary) -> void:
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 2)
	tile.custom_minimum_size.x = 52 if definition.id != &"punch" else 72
	parent.add_child(tile)
	var center := CenterContainer.new()
	tile.add_child(center)
	var button := Kit.icon_button(definition.icon, definition.label, _request_action.bind(definition.id), 48)
	button.name = definition.node
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("action", definition.id)
	center.add_child(button)
	action_buttons[definition.id] = button
	if definition.id == &"sound":
		_sound_badge = Kit.pixel_label("×", 20, Color("ffd541"))
		_sound_badge.name = "MutedBadge"
		_sound_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_sound_badge.position = Vector2(-16, -3)
		_sound_badge.custom_minimum_size = Vector2(20, 20)
		_sound_badge.visible = false
		button.add_child(_sound_badge)
	var cap := Kit.key_hint(str(definition.hint))
	cap.name = "KeyHint"
	tile.add_child(cap)

func _request_action(action: StringName) -> void:
	action_requested.emit(action)

func sync_options(fullscreen: bool, muted: bool) -> void:
	if action_buttons.is_empty():
		return
	action_buttons[&"fullscreen"].tooltip_text = "退出全屏 · F11" if fullscreen else "全屏 · F11"
	action_buttons[&"sound"].tooltip_text = "开启声音 · M" if muted else "静音 · M"
	_sound_badge.visible = muted
