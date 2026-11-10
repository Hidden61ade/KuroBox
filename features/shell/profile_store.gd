class_name ProfileStore
extends RefCounted

const SAVE_PATH := "user://profile.json"
var save_path: String = SAVE_PATH
var completed: Dictionary = {}
var settings: Dictionary = {"sound": 0.65, "music": 0.35, "shake": true, "fullscreen": false}
var last_error: String = ""
var _blocked_version: bool = false

func _init(path: String = SAVE_PATH) -> void:
	save_path = path

func read() -> void:
	last_error = ""
	_blocked_version = false
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
			last_error = "进度文件无法读取，正在尝试备份。"
			continue
		var data: Dictionary = parser.data
		var declared_version: Variant = data.get("schema_version")
		if path == save_path and (declared_version is int or declared_version is float) and float(declared_version) >= 2.0:
			_blocked_version = true
		if data.get("schema_version") != 1 or not data.get("completed", {}) is Dictionary or not data.get("settings", {}) is Dictionary:
			last_error = "进度文件版本或结构不受支持。"
			continue
		var records: Dictionary = data.get("completed", {})
		if not _valid_records(records):
			last_error = "进度记录损坏，正在尝试备份。"
			continue
		completed = records.duplicate(true)
		for record: Dictionary in completed.values():
			record.actions = int(record.actions)
			record.punches = int(record.punches)
		var stored: Dictionary = data.get("settings", {})
		for key: String in settings:
			if stored.has(key) and typeof(stored[key]) == typeof(settings[key]):
				settings[key] = stored[key]
		settings.sound = clampf(float(settings.sound), 0.0, 1.0)
		settings.music = clampf(float(settings.music), 0.0, 1.0)
		if path.ends_with(".bak"):
			last_error = "主进度文件无法读取，已恢复上一份备份。"
		return

func _valid_records(records: Dictionary) -> bool:
	for key: Variant in records:
		if not key is String or str(key).is_empty() or not records[key] is Dictionary:
			return false
		var record: Dictionary = records[key]
		for field: String in ["actions", "punches"]:
			var value: Variant = record.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) != floorf(float(value)):
				return false
		if int(record.punches) > int(record.actions):
			return false
	return true

func complete(level_id: String, actions: int, fists: int) -> Error:
	var best: Dictionary = completed.get(level_id, {})
	if best.is_empty() or actions < int(best.get("actions", 2147483647)):
		completed[level_id] = {"actions": actions, "punches": fists}
	return write()

func write() -> Error:
	last_error = ""
	if _blocked_version:
		last_error = "进度文件来自不支持的版本，已保留原文件。"
		return ERR_UNAVAILABLE
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入进度：" + error_string(FileAccess.get_open_error())
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema_version": 1, "completed": completed, "settings": settings}, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "写入进度失败：" + error_string(write_error)
		return write_error
	var primary := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path) and _valid_primary_for_backup():
		var backup_error := DirAccess.copy_absolute(primary, primary + ".bak")
		if backup_error != OK:
			last_error = "无法备份进度：" + error_string(backup_error)
			return backup_error
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), primary)
	if rename_error != OK:
		last_error = "无法保存进度：" + error_string(rename_error)
	return rename_error

func _valid_primary_for_backup() -> bool:
	# A recovered backup must never be overwritten by the corrupt primary it replaced.
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(save_path)) != OK or not parser.data is Dictionary:
		return false
	var data: Dictionary = parser.data
	return data.get("schema_version") == 1 and data.get("completed") is Dictionary and data.get("settings") is Dictionary and _valid_records(data.completed)
