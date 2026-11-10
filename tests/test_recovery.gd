extends SceneTree
## Exercises the real workbench recovery and actual embedded drawing widget.
## Only the workspace proof-file adapter is replaced; no user recovery file is touched.

const Widget = preload("res://features/editor/level_editor.gd")
const Thumbnail = preload("res://addons/kurobox_editor/level_thumbnail.gd")
const Codec = preload("res://core/level_codec.gd")
const CASE_DIR := "res://tests/.recovery_probe"
var failures: Array[String] = []
var checks := 0

class RecoveryBench:
	extends "res://addons/kurobox_editor/workbench.gd"
	func _ready() -> void:
		pass

class ProofFiles:
	extends RefCounted
	func load_proof(_id: String) -> Dictionary:
		return {}


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _fixture(id: String) -> Dictionary:
	var cells: Array = []
	for y: int in range(5):
		for x: int in range(7):
			cells.append([x, y])
	return {"schema_version": 1, "id": id, "title": "Original " + id, "width": 7, "height": 5, "floor": cells, "walls": [], "goals": [[4, 2]], "player": [1, 2], "facing": [1, 0], "objects": [{"id": "box", "type": "wood", "cell": [2, 2], "targets": []}], "metadata": {"solution": ["R", "R"]}}


func _record(data: Dictionary, saved: Dictionary) -> Dictionary:
	return {"data": data, "saved": saved, "draft_hash": "previous-draft", "published_hash": "previous-publication"}


func _run() -> void:
	var bench := RecoveryBench.new()
	bench.workspace = ProofFiles.new()
	bench._status = Label.new()
	bench.add_child(bench._status)
	bench._validation = Label.new()
	bench.add_child(bench._validation)
	bench._proof_status = Label.new()
	bench.add_child(bench._proof_status)
	bench._search = LineEdit.new()
	bench.add_child(bench._search)
	bench._list = ItemList.new()
	bench.add_child(bench._list)
	bench._thumbnail = Thumbnail.new()
	bench.add_child(bench._thumbnail)
	bench.editor = Widget.new()
	bench.editor.embedded_mode = true
	bench.editor.native_inspector = true
	bench.editor.use_external_history = true
	bench.add_child(bench.editor)
	root.add_child(bench)
	bench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	bench._built = true
	var baseline := _fixture("wall_conflict")
	var conflict := baseline.duplicate(true)
	conflict["title"] = "UNSAVED entire session"
	conflict["walls"] = [[2, 2], [4, 2]]
	_check(not Codec.validate_draft(conflict).is_empty() and bench._recovery_shape_safe(conflict), "wall-on-box/goal is repairable authoring data, not an unsafe shape")
	var unknown := _fixture("obsolete_type")
	unknown["objects"][0]["type"] = "type_removed_from_catalog"
	unknown["objects"][0]["params"] = {"legacy_setting": {"source": "preserve verbatim"}}
	_check(not Codec.validate_draft(unknown).is_empty() and bench._recovery_shape_safe(unknown), "obsolete type and its parameter payload remain recoverable")
	var bad_parameters := _fixture("obsolete_parameter")
	bad_parameters["objects"][0]["type"] = "bag"
	bad_parameters["objects"][0]["params"] = {"punch_distance": {"old_value": 99}}
	_check(not Codec.validate_draft(bad_parameters).is_empty() and bench._recovery_shape_safe(bad_parameters), "invalid current parameter value is preserved as authoring data")
	var unfinished := _fixture("unfinished")
	unfinished["player"] = [-1, -1]
	unfinished["goals"] = []
	_check(bench._recovery_shape_safe(unfinished), "missing spawn sentinel and missing goals are safe recovery content")
	var unsafe := _fixture("unsafe_coordinate")
	unsafe["objects"][0]["cell"] = ["bad", 2]
	_check(not bench._recovery_shape_safe(unsafe), "coordinate types remain a recovery safety boundary")
	var invalid_size := _fixture("unsafe_size")
	invalid_size["width"] = 100000
	_check(not bench._recovery_shape_safe(invalid_size), "unsafe dimensions remain rejected")
	var payload: Array = [_record(conflict, baseline), _record(unknown, _fixture("obsolete_type")), _record(bad_parameters, _fixture("obsolete_parameter")), _record(unfinished, _fixture("unfinished")), _record(unsafe, _fixture("unsafe_coordinate")), 42]
	var path := CASE_DIR.path_join("recovery.json")
	_check(bench._write_recovery(path, payload) == OK, "isolated recovery fixture is written through the actual atomic writer")
	var original_hash := FileAccess.get_sha256(path)
	bench._restore_recovery(path)
	await process_frame
	await process_frame
	var recovery_warning := str(bench._status.text)
	var decoded_payload: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(bench.documents.size() == 4 and bench.documents.has("wall_conflict"), "all four safe documents restore despite semantic validation failures")
	_check(bench.documents["wall_conflict"].data == Codec.normalize(conflict), "dirty wall-conflict document is restored in full, including every prior edit")
	_check(bench.documents["wall_conflict"].saved == Codec.normalize(baseline) and bench.documents["wall_conflict"].dirty(), "saved baseline and unsaved status survive recovery")
	_check(bench.documents["obsolete_type"].data["objects"][0]["params"] == unknown["objects"][0]["params"], "unknown-type parameter payload is not sanitized away")
	_check(bench.documents["obsolete_parameter"].data["objects"][0]["params"] == decoded_payload[2]["data"]["objects"][0]["params"], "invalid parameter source value is not clamped or deleted")
	_check(bench.editor.get_level() == Codec.normalize(conflict), "actual embedded editor.setup accepts and retains the recoverable conflicted document")
	bench._activate(bench.documents["obsolete_parameter"], false)
	await process_frame
	_check(bench.editor.get_level() == Codec.normalize(decoded_payload[2]["data"]), "actual embedded editor.apply_document retains invalid parameter source values")
	bench.editor.begin_test()
	_check(bench.editor.get("_standalone_state") == null, "recovery never bypasses strict validation to play an invalid document")
	_check(recovery_warning.contains("原文") and recovery_warning.contains("不能试玩或发布") and recovery_warning.contains("隔离"), "recovery visibly explains preserved conflicts and isolated unsafe records")
	var rejected_path: String = bench._last_rejected_recovery_path
	_check(not rejected_path.is_empty() and FileAccess.file_exists(rejected_path), "unsafe records are saved to a separate recovery rejection file")
	var rejected: Variant = JSON.parse_string(FileAccess.get_file_as_string(rejected_path))
	_check(rejected is Array and rejected.size() == 2 and rejected[0]["record"]["data"]["objects"][0]["cell"][0] == "bad" and rejected[1]["record"] == 42, "quarantine preserves each rejected record's original value and diagnostics")
	_check(FileAccess.get_sha256(path) == original_hash, "restoring and quarantining do not overwrite the original recovery file")
	bench._activate(bench.documents["unfinished"], true)
	_check(bench.editor.get_level()["player"] == [-1, -1], "parsed missing-spawn sentinel reaches the embedded editor")
	bench.queue_free()
	await process_frame
	await process_frame
	for filename: String in DirAccess.get_files_at(CASE_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CASE_DIR.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CASE_DIR))
	print("RECOVERY_RESULT ", JSON.stringify({"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
