extends SceneTree
const Store = preload("res://features/shell/profile_store.gd")
var checks := 0
var failures: Array[String] = []
const PATH := "user://profile_validation.json"

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var store := Store.new(PATH)
	_check(store.complete("a", 20, 3) == OK, "initial save")
	_check(store.complete("a", 25, 5) == OK, "overwrite save")
	var restored := Store.new(PATH)
	restored.read()
	_check(int(restored.completed.a.actions) == 20, "personal best retained")
	_check(FileAccess.file_exists(PATH + ".bak"), "previous valid backup exists")
	_write_raw({"schema_version":1, "completed":{"a":0}, "settings":{}})
	restored = Store.new(PATH)
	restored.read()
	_check(restored.completed.has("a") and int(restored.completed.a.actions) == 20, "malformed record falls back to valid backup")
	_check(not restored.last_error.is_empty(), "recovery is visible")
	_write_raw({"schema_version":1, "completed":{"a":{"actions":"bad","punches":0}}, "settings":{}})
	restored = Store.new(PATH)
	restored.read()
	_check(restored.completed.has("a") and int(restored.completed.a.actions) == 20, "invalid metric does not reach UI")
	var backup_before := FileAccess.get_file_as_string(PATH + ".bak")
	_check(restored.complete("a", 18, 2) == OK, "recovered progress can be saved again")
	_check(FileAccess.get_file_as_string(PATH + ".bak") == backup_before, "corrupt primary never replaces the valid recovery backup")
	_write_raw({"schema_version":99, "completed":{}, "settings":{}})
	restored = Store.new(PATH)
	restored.read()
	var future_primary := FileAccess.get_file_as_string(PATH)
	_check(restored.write() != OK, "older game refuses to overwrite an unsupported future save")
	_check(FileAccess.get_file_as_string(PATH) == future_primary, "future save remains intact")
	var no_directory := Store.new("user://directory_that_does_not_exist/profile.json")
	_check(no_directory.write() != OK and not no_directory.last_error.is_empty(), "write failure returns actionable error")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	var report := {"engine":Engine.get_version_info().string, "checks":checks, "failures":failures}
	var file := FileAccess.open("res://evidence/profile_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PROFILE_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _write_raw(data: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
