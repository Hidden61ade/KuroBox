@tool
class_name LevelWorkspace
extends RefCounted
## Content-file ownership for the native editor. No EditorInterface or UI state.

const Codec = preload("res://core/level_codec.gd")
const Replay = preload("res://core/replay_proof.gd")
const DEFAULT_CONFIG := {
	"campaign_path": "res://content/levels/campaign.json",
	"published_dir": "res://content/levels",
	"draft_dir": "res://content/workshop/drafts",
	"proof_dir": "res://content/workshop/proofs",
}
const MAX_BYTES := 8 * 1024 * 1024

var last_errors: Array[String] = []
var campaign_path: String = DEFAULT_CONFIG.campaign_path
var published_dir: String = DEFAULT_CONFIG.published_dir
var draft_dir: String = DEFAULT_CONFIG.draft_dir
var proof_dir: String = DEFAULT_CONFIG.proof_dir
var _configured := false
var _configuration_valid := true
var _observed_hashes: Dictionary = {}


func configure(config: Dictionary = {}) -> void:
	last_errors.clear()
	_observed_hashes.clear()
	_configuration_valid = true
	for field: String in DEFAULT_CONFIG:
		var value: Variant = config.get(field, DEFAULT_CONFIG[field])
		if not value is String or str(value).strip_edges().is_empty():
			last_errors.append("工作区配置 %s 需要非空路径。" % field)
			_configuration_valid = false
			continue
		set(field, str(value).trim_suffix("/"))
	_configured = true
	if _configuration_valid:
		_observe(campaign_path, true)


func source_hash(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


func list_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _begin():
		return result
	var index := _scan(true)
	var order: Array = index.order.duplicate()
	var draft_ids: Array = index.drafts.keys()
	draft_ids.sort()
	for id: String in draft_ids:
		if not order.has(id):
			order.append(id)
	for id: String in order:
		var published: Dictionary = index.published.get(id, {})
		var draft: Dictionary = index.drafts.get(id, {})
		var current: Dictionary = draft.get("level", published.get("level", {}))
		if current.is_empty():
			continue
		var published_path: String = published.get("path", "")
		var draft_path: String = draft.get("path", "")
		var status := "draft" if published.is_empty() else "published"
		if not published.is_empty() and not draft.is_empty() and _comparable(draft.level) != _comparable(published.level):
			status = "modified"
		result.append({
			"id": id, "title": current.get("title", id), "status": status,
			"published_path": published_path, "draft_path": draft_path,
			"revision": Replay.revision(current),
			"published_hash": source_hash(published_path), "draft_hash": source_hash(draft_path),
		})
	return result


func load_level(id: String) -> Dictionary:
	if not _begin() or not _check_id(id):
		return {}
	var index := _scan()
	if not last_errors.is_empty():
		return {}
	var published: Dictionary = index.published.get(id, {})
	var draft: Dictionary = index.drafts.get(id, {})
	# Track the absent draft too, so an external new draft cannot be overwritten.
	_observe(str(draft.get("path", _draft_path(id))), true)
	_observe(str(published.get("path", _published_path(id))), true)
	if not draft.is_empty():
		return draft.level.duplicate(true)
	if not published.is_empty():
		return published.level.duplicate(true)
	last_errors.append("没有找到关卡“%s”。" % id)
	return {}


func new_level(id: String, title: String, width: int = 10, height: int = 8) -> Dictionary:
	if not _begin() or not _check_id(id):
		return {}
	var index := _scan()
	if not last_errors.is_empty() or not _id_available(id, index):
		return {}
	var floor_cells: Array = []
	if width < Codec.MIN_SIDE or width > Codec.MAX_SIDE or height < Codec.MIN_SIDE or height > Codec.MAX_SIDE:
		last_errors.append("地图宽高必须在 %d–%d 格之间。" % [Codec.MIN_SIDE, Codec.MAX_SIDE])
		return {}
	for y: int in range(height):
		for x: int in range(width):
			floor_cells.append([x, y])
	var level := {
		"schema_version": 1, "id": id, "title": title, "width": width, "height": height,
		"floor": floor_cells, "walls": [], "goals": [], "objects": [],
		"player": [-1, -1], "facing": [1, 0], "metadata": {"solution": []},
	}
	return level.duplicate(true) if save_draft(level) == OK else {}


func duplicate_level(id: String, new_id: String, title: String) -> Dictionary:
	var level := load_level(id)
	if level.is_empty():
		return {}
	return fork_draft(level, new_id, title)


func fork_draft(level: Dictionary, new_id: String, title: String) -> Dictionary:
	# Rescue the caller's in-memory document. Never save or reload its old path.
	if not _begin() or not _check_id(new_id):
		return {}
	var copied := level.duplicate(true)
	copied.id = new_id
	copied.title = title
	_clear_proof_fields(copied)
	var errors: Array[String] = Codec.validate_draft(copied)
	if not errors.is_empty():
		_append_validation("另存草稿结构无效", errors)
		return {}
	var index := _scan()
	if not last_errors.is_empty() or not _id_available(new_id, index):
		return {}
	var remap: Dictionary = {}
	for object: Dictionary in copied.get("objects", []):
		var old_id: String = object.id
		var new_instance_id := "item_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
		remap[old_id] = new_instance_id
		object.id = new_instance_id
	for object: Dictionary in copied.get("objects", []):
		var targets: Array = []
		for target: String in object.get("targets", []):
			targets.append(remap.get(target, target))
		object.targets = targets
	return copied.duplicate(true) if save_draft(copied) == OK else {}


func save_draft(level: Dictionary, expected_hash: String = "") -> Error:
	if not _begin() or not _check_id(str(level.get("id", ""))):
		return ERR_INVALID_PARAMETER
	var errors: Array[String] = Codec.validate_draft(level)
	if not errors.is_empty():
		_append_validation("草稿结构无效", errors)
		return ERR_INVALID_DATA
	var index := _scan()
	if not last_errors.is_empty():
		return ERR_INVALID_DATA
	var id: String = level.id
	var path: String = index.drafts.get(id, {}).get("path", _draft_path(id))
	var expectation := _expect(path, expected_hash)
	if not expectation.valid:
		return ERR_BUSY
	return _commit_changes([{"path": path, "bytes": _json_bytes(Codec.normalize(level))}], {path: expectation.hash})


func save_proof(level: Dictionary, proof: Dictionary) -> Error:
	if not _begin() or not _check_id(str(level.get("id", ""))):
		return ERR_INVALID_PARAMETER
	var checked: Dictionary = Replay.verify(level, proof)
	if not checked.get("valid", false):
		_append_validation("通关记录验证失败", checked.get("errors", []))
		return ERR_INVALID_DATA
	var path := _proof_path(str(level.id))
	var expectation := _expect(path, "", true)
	if not expectation.valid:
		return ERR_BUSY
	checked["level_id"] = level.id
	return _commit_changes([{"path": path, "bytes": _json_bytes(checked)}], {path: expectation.hash})


func load_proof(id: String) -> Dictionary:
	if not _begin() or not _check_id(id):
		return {}
	var path := _proof_path(id)
	_observe(path, true)
	if not FileAccess.file_exists(path):
		return {}
	var proof := _read_json(path, "通关记录")
	if not proof.is_empty() and proof.has("level_id") and proof.level_id != id:
		last_errors.append("通关记录的关卡 ID 与文件不一致：%s。" % path)
		return {}
	return proof


func publish(level: Dictionary, proof: Dictionary, expected_published_hash: String = "") -> Error:
	if not _begin() or not _check_id(str(level.get("id", ""))):
		return ERR_INVALID_PARAMETER
	var errors: Array[String] = Codec.validate(level)
	if not errors.is_empty():
		_append_validation("关卡尚不满足发布条件", errors)
		return ERR_INVALID_DATA
	var checked: Dictionary = Replay.verify(level, proof)
	if not checked.get("valid", false):
		_append_validation("发布需要有效的实际通关重放", checked.get("errors", []))
		return ERR_INVALID_DATA
	var index := _scan()
	if not last_errors.is_empty():
		return ERR_INVALID_DATA
	var id: String = level.id
	var path: String = index.published.get(id, {}).get("path", _published_path(id))
	var draft_path: String = index.drafts.get(id, {}).get("path", _draft_path(id))
	var proof_path := _proof_path(id)
	var expected: Dictionary = {}
	for request: Array in [[path, expected_published_hash, false], [draft_path, "", false], [campaign_path, "", false], [proof_path, "", true]]:
		var expectation := _expect(request[0], request[1], request[2])
		if not expectation.valid:
			return ERR_BUSY
		expected[request[0]] = expectation.hash
	var published_level := Codec.normalize(level)
	if not published_level.get("metadata") is Dictionary:
		published_level.metadata = {}
	published_level.metadata.solution = checked.get("commands", []).duplicate()
	checked["level_id"] = id
	var changes: Array[Dictionary] = [
		{"path": path, "bytes": _json_bytes(published_level)},
		{"path": proof_path, "bytes": _json_bytes(checked)},
	]
	if not index.published.has(id):
		var manifest: Dictionary = index.campaign.duplicate(true)
		manifest.levels.append(path)
		changes.append({"path": campaign_path, "bytes": _json_bytes(manifest)})
	if FileAccess.file_exists(draft_path):
		changes.append({"path": draft_path, "delete": true})
	return _commit_changes(changes, expected)


func save_order(ids: Array[String]) -> Error:
	if not _begin():
		return ERR_INVALID_PARAMETER
	var index := _scan()
	if not last_errors.is_empty():
		return ERR_INVALID_DATA
	var published: Dictionary = index.published
	var seen: Dictionary = {}
	var paths: Array = []
	for id: String in ids:
		if seen.has(id) or not published.has(id):
			return _fail("排序只能包含全部已发布关卡，不能重复或加入草稿：%s。" % id, ERR_INVALID_DATA)
		seen[id] = true
		paths.append(published[id].path)
	if seen.size() != published.size():
		return _fail("排序必须包含全部 %d 个已发布关卡，不能漏项。" % published.size(), ERR_INVALID_DATA)
	var expectation := _expect(campaign_path)
	if not expectation.valid:
		return ERR_BUSY
	var manifest: Dictionary = index.campaign.duplicate(true)
	manifest.levels = paths
	return _commit_changes([{"path": campaign_path, "bytes": _json_bytes(manifest)}], {campaign_path: expectation.hash})


func unpublish(id: String, expected_published_hash: String = "") -> Error:
	if not _begin() or not _check_id(id):
		return ERR_INVALID_PARAMETER
	var index := _scan()
	if not last_errors.is_empty():
		return ERR_INVALID_DATA
	if not index.published.has(id):
		return _fail("关卡尚未发布，不能撤回：%s。" % id, ERR_DOES_NOT_EXIST)
	var published: Dictionary = index.published[id]
	var draft: Dictionary = index.drafts.get(id, {})
	var draft_path: String = draft.get("path", _draft_path(id))
	var expected: Dictionary = {}
	for request: Array in [[published.path, expected_published_hash], [draft_path, ""], [campaign_path, ""]]:
		var expectation := _expect(request[0], request[1])
		if not expectation.valid:
			return ERR_BUSY
		expected[request[0]] = expectation.hash
	var retained: Dictionary = draft.get("level", published.level).duplicate(true)
	var manifest: Dictionary = index.campaign.duplicate(true)
	manifest.levels.erase(published.path)
	return _commit_changes([
		{"path": draft_path, "bytes": _json_bytes(retained)},
		{"path": campaign_path, "bytes": _json_bytes(manifest)},
		{"path": published.path, "delete": true},
	], expected)


func _scan(record_observations: bool = false) -> Dictionary:
	var index := {"campaign": {"levels": []}, "order": [], "published": {}, "drafts": {}}
	if FileAccess.file_exists(campaign_path):
		index.campaign = _read_json(campaign_path, "正式关卡清单")
	if not index.campaign.get("levels") is Array:
		last_errors.append("正式关卡清单需要 levels 路径数组。")
		return index
	var seen_paths: Dictionary = {}
	for raw: Variant in index.campaign.levels:
		if not raw is String or not _inside(str(raw), published_dir) or not str(raw).ends_with(".json"):
			last_errors.append("清单中的关卡路径必须位于发布目录：%s。" % str(raw))
			continue
		var path: String = raw
		if seen_paths.has(_absolute(path)):
			last_errors.append("正式关卡清单重复引用文件：%s。" % path)
			continue
		seen_paths[_absolute(path)] = true
		var level := _read_level(path)
		if level.is_empty():
			continue
		var id: String = level.id
		if index.published.has(id):
			last_errors.append("正式清单包含重复的稳定关卡 ID：%s。" % id)
			continue
		index.published[id] = {"path": path, "level": level}
		index.order.append(id)
		if record_observations:
			_observe(path)
	if DirAccess.dir_exists_absolute(_absolute(draft_dir)):
		var directory := DirAccess.open(draft_dir)
		if directory == null:
			last_errors.append("无法读取草稿目录：%s。" % draft_dir)
			return index
		for name: String in directory.get_files():
			if not name.ends_with(".json"):
				continue
			var path := draft_dir.path_join(name)
			var level := _read_level(path)
			if level.is_empty():
				continue
			var id: String = level.id
			if index.drafts.has(id):
				last_errors.append("草稿目录包含重复的稳定关卡 ID：%s。" % id)
				continue
			index.drafts[id] = {"path": path, "level": level}
			if record_observations:
				_observe(path)
	return index


func _read_level(path: String) -> Dictionary:
	var level := _read_json(path, "关卡")
	if level.is_empty():
		if last_errors.is_empty():
			last_errors.append("关卡文件不能为空对象：%s。" % path)
		return {}
	var errors: Array[String] = Codec.validate_draft(level)
	if not errors.is_empty():
		_append_validation("关卡文件结构无效（%s）" % path, errors)
		return {}
	return Codec.normalize(level)


func _read_json(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_errors.append("无法打开%s文件 %s：%s。" % [label, path, error_string(FileAccess.get_open_error())])
		return {}
	if file.get_length() > MAX_BYTES:
		file.close()
		last_errors.append("%s文件超过 8 MiB：%s。" % [label, path])
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		last_errors.append("%s文件 JSON 无效（%s，第 %d 行）：%s。" % [label, path, parser.get_error_line(), parser.get_error_message()])
		return {}
	return parser.data


func _expect(path: String, explicit_hash: String = "", allow_untracked_existing: bool = false) -> Dictionary:
	var absolute := _absolute(path)
	var current := source_hash(path)
	var expected := explicit_hash
	if expected.is_empty():
		if _observed_hashes.has(absolute):
			expected = _observed_hashes[absolute]
		elif not current.is_empty() and not allow_untracked_existing:
			last_errors.append("文件已存在但尚未载入，请先重新载入后保存：%s。" % path)
			return {"valid": false, "hash": ""}
		else:
			expected = current
	if current != expected:
		last_errors.append("文件已被外部修改或删除，已停止覆盖；请重新载入工作区并核对修改：%s。" % path)
		return {"valid": false, "hash": expected}
	return {"valid": true, "hash": current}


func _commit_changes(changes: Array[Dictionary], expected: Dictionary) -> Error:
	# Stage every new file and recovery copy before changing any live path.
	# Individual renames are atomic; this is compensating multi-file recovery,
	# not a cross-file ACID transaction or a power-loss journal.
	var prepared: Array[Dictionary] = []
	for change: Dictionary in changes:
		var path: String = change.path
		if expected.has(path) and source_hash(path) != expected[path]:
			_cleanup(prepared)
			return _fail("提交前发现外部修改，未覆盖文件：%s。" % path, ERR_BUSY)
		var entry := {"path": path, "delete": change.get("delete", false), "backup": "", "staged": "", "existed": FileAccess.file_exists(path), "old_hash": source_hash(path)}
		if entry.existed:
			var original := _read_bytes(path)
			if original.error != OK:
				_cleanup(prepared)
				return original.error
			var backup := _stage_bytes(path, original.bytes, ".bak")
			if backup.error != OK:
				_cleanup(prepared)
				return backup.error
			entry.backup = backup.path
		if not entry.delete:
			var staged := _stage_bytes(path, change.bytes, ".tmp")
			if staged.error != OK:
				prepared.append(entry)
				_cleanup(prepared)
				return staged.error
			entry.staged = staged.path
		prepared.append(entry)
	var applied: Array[Dictionary] = []
	for entry: Dictionary in prepared:
		var error: Error = OK
		if source_hash(entry.path) != entry.old_hash:
			error = _fail("发布提交期间发现外部修改：%s。" % entry.path, ERR_BUSY)
		elif entry.delete:
			error = _remove_file(entry.path)
		else:
			error = _install_staged(entry.staged, entry.path)
		if error != OK:
			last_errors.append("写入步骤失败，正在恢复发布前的文件：%s（%s）。" % [entry.path, error_string(error)])
			_restore(applied)
			_cleanup(prepared)
			return error
		applied.append(entry)
	for entry: Dictionary in prepared:
		_observe(entry.path, true)
	_cleanup(prepared)
	return OK


func _read_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		last_errors.append("无法备份原内容文件 %s：%s。" % [path, error_string(error)])
		return {"error": error, "bytes": PackedByteArray()}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"error": _fail("原文件超过 8 MiB，未开始替换：%s。" % path, ERR_FILE_CANT_READ), "bytes": PackedByteArray()}
	var bytes := file.get_buffer(file.get_length())
	var error := file.get_error()
	file.close()
	if error != OK:
		last_errors.append("原文件读取不完整，未开始替换：%s。" % path)
	return {"error": error, "bytes": bytes}


func _stage_bytes(path: String, bytes: PackedByteArray, suffix: String) -> Dictionary:
	if bytes.size() > MAX_BYTES:
		return {"error": _fail("内容超过 8 MiB，未写入文件：%s。" % path, ERR_INVALID_DATA), "path": ""}
	var absolute := _absolute(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		last_errors.append("无法创建内容目录 %s：%s。" % [absolute.get_base_dir(), error_string(directory_error)])
		return {"error": directory_error, "path": ""}
	var temporary := "%s.workspace-%d-%s%s" % [absolute, Time.get_ticks_usec(), Crypto.new().generate_random_bytes(4).hex_encode(), suffix]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		var error := FileAccess.get_open_error()
		last_errors.append("无法写入临时内容文件 %s：%s。" % [temporary, error_string(error)])
		return {"error": error, "path": ""}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		last_errors.append("临时内容文件写入不完整：%s。" % temporary)
		return {"error": error, "path": ""}
	return {"error": OK, "path": temporary}


func _install_staged(temporary: String, destination: String) -> Error:
	return DirAccess.rename_absolute(temporary, _absolute(destination))


func _remove_file(path: String) -> Error:
	return DirAccess.remove_absolute(_absolute(path))


func _restore(applied: Array[Dictionary]) -> void:
	for index: int in range(applied.size() - 1, -1, -1):
		var entry: Dictionary = applied[index]
		var error: Error = OK
		if entry.existed:
			error = _install_staged(entry.backup, entry.path)
			if error == OK:
				entry.backup = ""
		else:
			error = _remove_file(entry.path)
		if error != OK:
			# Keep the recovery copy when the OS also refuses restoration.
			entry["keep_backup"] = true
			last_errors.append("恢复失败，请保留并手动恢复备份 %s 到 %s：%s。" % [entry.backup, entry.path, error_string(error)])


func _cleanup(prepared: Array[Dictionary]) -> void:
	for entry: Dictionary in prepared:
		for key: String in ["staged", "backup"]:
			var path: String = entry.get(key, "")
			if key == "backup" and entry.get("keep_backup", false):
				continue
			if not path.is_empty() and FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _observe(path: String, refresh: bool = false) -> void:
	var absolute := _absolute(path)
	if refresh or not _observed_hashes.has(absolute):
		_observed_hashes[absolute] = source_hash(path)


func _begin() -> bool:
	if not _configured:
		configure()
	last_errors.clear()
	if not _configuration_valid:
		last_errors.append("工作区路径配置无效，请重新配置。")
	return _configuration_valid


func _check_id(id: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
	if pattern.search(id) == null:
		last_errors.append("关卡 ID 需为 1–128 位英文字母、数字、下划线或连字符，且以字母或数字开头。")
		return false
	if id.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
		last_errors.append("关卡 ID 是 Windows 保留设备名，请换一个稳定 ID：%s。" % id)
		return false
	return true


func _id_available(id: String, index: Dictionary) -> bool:
	if index.published.has(id) or index.drafts.has(id) or FileAccess.file_exists(_published_path(id)) or FileAccess.file_exists(_draft_path(id)):
		last_errors.append("稳定关卡 ID 已存在：%s。" % id)
		return false
	return true


func _clear_proof_fields(level: Dictionary) -> void:
	if not level.get("metadata") is Dictionary:
		level.metadata = {}
	level.metadata.solution = []
	for key: String in ["proof", "replay_proof", "replay", "verified_revision", "verified_at"]:
		level.erase(key)
		level.metadata.erase(key)


func _comparable(level: Dictionary) -> Dictionary:
	var result := level.duplicate(true)
	_clear_proof_fields(result)
	return result


func _append_validation(context: String, errors: Array) -> void:
	if errors.is_empty():
		last_errors.append(context + "。")
	for error: Variant in errors:
		last_errors.append("%s：%s" % [context, str(error)])


func _fail(message: String, error: Error) -> Error:
	last_errors.append(message)
	return error


func _json_bytes(document: Dictionary) -> PackedByteArray:
	return (JSON.stringify(document, "  ", true) + "\n").to_utf8_buffer()


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()


func _inside(path: String, directory: String) -> bool:
	return _absolute(path).to_lower().begins_with(_absolute(directory).trim_suffix("/").to_lower() + "/")


func _draft_path(id: String) -> String:
	return draft_dir.path_join(id + ".json")


func _published_path(id: String) -> String:
	return published_dir.path_join(id + ".json")


func _proof_path(id: String) -> String:
	return proof_dir.path_join(id + ".json")
