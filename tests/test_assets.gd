extends SceneTree
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _texture(path: String) -> Texture2D:
	var asset: Resource = load(path)
	_check(asset is Texture2D, "texture loads: " + path)
	return asset as Texture2D

func _run() -> void:
	for definition: Dictionary in ObjectCatalog.all_types():
		_texture(str(definition.sprite))
		if definition.has("sprite_open"):
			_texture(str(definition.sprite_open))
	for direction: String in ["up", "down", "left", "right"]:
		_texture("res://assets/sprites/boxing_player_" + direction + ".png")
		_texture("res://assets/sprites/boxing_player_punch_" + direction + ".png")
	for key: String in ["back", "levels", "workshop", "pause", "undo", "restart", "next", "play", "music", "quit", "punch", "info", "import", "settings"]:
		_texture("res://assets/ui/icon_" + key + ".png")
	for state: String in ["normal", "hover", "pressed"]:
		_texture("res://assets/ui/circuit_start_" + state + ".png")
	var even := _texture("res://assets/ui/floor_even.png").get_image()
	_texture("res://assets/sprites/sokoban_goal.png")
	var odd := _texture("res://assets/ui/floor_odd.png").get_image()
	_check(even.get_pixel(8, 8).to_html(false) == "176d4c", "original even ground color")
	_check(odd.get_pixel(8, 8).to_html(false) == "335c62", "original odd ground color")
	_check(even.get_size() == Vector2i(16,16) and odd.get_size() == Vector2i(16,16), "original native tile size")
	var stripes := _texture("res://assets/ui/circuit_stripes.png").get_image()
	_check(stripes.get_size() == Vector2i(48,96), "original stripe atlas size")
	var repeat_ok := true
	for y in range(48):
		for x in range(48):
			if stripes.get_pixel(x,y) != stripes.get_pixel(x,y+48):
				repeat_ok = false
	_check(repeat_ok, "stripe repeat is seamless at 48px vertical period")
	for event: String in ["ui_confirm", "ui_back", "place", "undo", "punch", "goal", "music"]:
		var stream: Resource = load("res://assets/audio/" + event + ".ogg")
		_check(stream is AudioStream and stream.get_length() > 0.0, "audio decodes: " + event)
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var file := FileAccess.open("res://evidence/assets_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ASSET_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
