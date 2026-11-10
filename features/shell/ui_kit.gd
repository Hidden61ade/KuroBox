class_name UIKIT
extends RefCounted

const INK := Color("333941")
const PAPER := Color("d5d8dc")
const MUTED := Color("a9b0aa")
const ACCENT := Color("ffd541")
const EDGE := Color("494b4a")

static func make_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	result.default_font = font
	result.default_font_size = 18
	for type_name in ["Button", "OptionButton", "CheckButton"]:
		result.set_stylebox("normal", type_name, box(Color("353a3c"), Color("171c1e"), 3))
		result.set_stylebox("hover", type_name, box(Color("4e5654"), PAPER, 3))
		result.set_stylebox("pressed", type_name, box(Color("ab503f"), Color("612f2c"), 3))
		result.set_stylebox("focus", type_name, outline(ACCENT))
		result.set_stylebox("disabled", type_name, box(Color("292d30"), Color("202426"), 2))
		result.set_color("font_color", type_name, PAPER)
		result.set_color("font_hover_color", type_name, Color.WHITE)
		result.set_color("font_disabled_color", type_name, Color("66716d"))
		result.set_constant("h_separation", type_name, 10)
	result.set_stylebox("panel", "PanelContainer", box(Color("292e31"), EDGE, 2))
	result.set_stylebox("panel", "PopupPanel", box(INK, PAPER, 3))
	result.set_stylebox("panel", "AcceptDialog", box(INK, PAPER, 3))
	result.set_stylebox("normal", "LineEdit", box(Color("1c2225"), EDGE, 2))
	result.set_stylebox("focus", "LineEdit", box(Color("1c2225"), ACCENT, 2))
	result.set_color("font_color", "Label", PAPER)
	result.set_color("font_color", "LineEdit", PAPER)
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 12)
	result.set_constant("h_separation", "GridContainer", 16)
	result.set_constant("v_separation", "GridContainer", 16)
	return result

static func box(fill: Color, border: Color, thickness: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(thickness)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func outline(color: Color) -> StyleBoxFlat:
	var style := box(Color.TRANSPARENT, color, 2)
	style.draw_center = false
	style.expand_margin_left = 3
	style.expand_margin_right = 3
	style.expand_margin_top = 3
	style.expand_margin_bottom = 3
	return style

static func label(text: String, font_size: int = 18, color: Color = PAPER) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func button(text: String, callback: Callable, minimum: Vector2 = Vector2(0, 48)) -> Button:
	var node := Button.new()
	node.text = text
	if text.begins_with("‹") and ResourceLoader.exists("res://assets/ui/circuit_Button_small2.png"):
		node.icon = load("res://assets/ui/circuit_Button_small2.png")
		node.expand_icon = true
		node.add_theme_constant_override("icon_max_width", 24)
	node.custom_minimum_size = minimum
	node.pressed.connect(callback)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return node

static func margin(amount: int = 28) -> MarginContainer:
	var node := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		node.add_theme_constant_override("margin_" + side, amount)
	return node

static func pixel_label(text: String, font_size: int = 48, color: Color = PAPER) -> Label:
	var node := label(text, font_size, color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ResourceLoader.exists("res://assets/ui/circuit_awesome9.ttf"):
		node.add_theme_font_override("font", load("res://assets/ui/circuit_awesome9.ttf"))
	return node

static func icon_button(key: String, hint: String, callback: Callable, extent: int = 64) -> Button:
	var node := Button.new()
	node.tooltip_text = hint
	node.custom_minimum_size = Vector2(extent, extent)
	node.expand_icon = true
	node.add_theme_constant_override("icon_max_width", extent)
	var path := "res://assets/ui/icon_" + key + ".png"
	var fallback := {"back":"2", "volume":"4", "fullscreen":"8"}
	if not ResourceLoader.exists(path) and fallback.has(key):
		path = "res://assets/ui/circuit_Button_small%s.png" % fallback[key]
	if ResourceLoader.exists(path):
		node.icon = load(path)
	else:
		node.text = {"play":"▶", "levels":"▦", "workshop":"+", "pause":"Ⅱ", "restart":"↻", "undo":"↶", "next":"▶", "back":"‹", "settings":"⚙", "info":"i", "quit":"×", "check":"✓", "music":"♪", "shake":"↔"}.get(key, "·")
		node.add_theme_font_size_override("font_size", 32)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	node.add_theme_stylebox_override("focus", outline(Color("ffd541")))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.mouse_entered.connect(func() -> void: node.self_modulate = Color(1.2, 1.2, 1.2))
	node.mouse_exited.connect(func() -> void: node.self_modulate = Color.WHITE)
	node.pressed.connect(callback)
	return node
