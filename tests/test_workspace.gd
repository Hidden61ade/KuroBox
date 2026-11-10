extends SceneTree
## Isolated content-file tests. All writes stay under res://.tools/workspace_tests.

const Workspace = preload("res://features/editor/services/level_workspace.gd")
const Codec = preload("res://core/level_codec.gd")
const Replay = preload("res://core/replay_proof.gd")
var checks := 0
var failures: Array[String] = []
var test_root := ""
var original_campaign_hash := ""

class FaultWorkspace extends Workspace:
	var rejected_installs: Dictionary = {}
	var install_counts: Dictionary = {}
	var rejected_remove := ""

	func _install_staged(temporary: String, destination: String) -> Error:
		var count: int = int(install_counts.get(destination, 0)) + 1
		install_counts[destination] = count
		if count == int(rejected_installs.get(destination, -1)):
			return ERR_FILE_CANT_WRITE
		return super._install_staged(temporary, destination)

	func _remove_file(path: String) -> Error:
		if path == rejected_remove:
			rejected_remove = ""
			return ERR_FILE_CANT_WRITE
		return super._remove_file(path)


class ExternalCreateWorkspace extends Workspace:
	var inject_on_id := ""
	var external_document: Dictionary = {}

	func save_draft(level: Dictionary, expected_hash: String = "") -> Error:
		if level.get("id") == inject_on_id:
			inject_on_id = ""
			DirAccess.make_dir_recursive_absolute(draft_dir)
			var file := FileAccess.open(draft_dir.path_join(str(level.id) + ".json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(external_document, "  ", true) + "\n")
			file.close()
		return super.save_draft(level, expected_hash)


func _init() -> void:
	original_campaign_hash = FileAccess.get_sha256("res://content/levels/campaign.json")
	test_root = ProjectSettings.globalize_path("res://.tools/workspace_tests/run_%d" % Time.get_ticks_usec())
	_test_library_and_drafts()
	_test_duplicate()
	_test_memory_fork()
	_test_publish_and_order()
	_test_conflicts()
	_test_failed_publish()
	_test_unpublish()
	_test_recovery_copy()
	_check(FileAccess.get_sha256("res://content/levels/campaign.json") == original_campaign_hash, "real eight-level manifest is untouched")
	print(JSON.stringify({"checks": checks, "failures": failures, "temporary_root": test_root, "real_campaign_unchanged": FileAccess.get_sha256("res://content/levels/campaign.json") == original_campaign_hash}, "  "))
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: " + label)


func _config(name: String, initial: Array[Dictionary] = []) -> Dictionary:
	var directory := test_root.path_join(name)
	var config := {"campaign_path": directory.path_join("campaign.json"), "published_dir": directory.path_join("published"), "draft_dir": directory.path_join("drafts"), "proof_dir": directory.path_join("proofs")}
	var paths: Array = []
	for level: Dictionary in initial:
		var path: String = str(config.published_dir).path_join(str(level.id) + ".json")
		_write(path, level)
		paths.append(path)
	_write(config.campaign_path, {"levels": paths, "author_note": "keep manifest metadata"})
	return config


func _fixture(id: String = "level_a") -> Dictionary:
	var floor_cells: Array = []
	for y: int in range(5):
		for x: int in range(7):
			floor_cells.append([x, y])
	return {"schema_version": 1, "id": id, "title": "关卡 " + id, "width": 7, "height": 5, "floor": floor_cells, "walls": [], "goals": [[4, 2]], "player": [1, 2], "facing": [1, 0], "objects": [{"id": "bag_01", "type": "bag", "cell": [2, 2], "targets": []}], "metadata": {"solution": []}}


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "isolated fixture must be writable")
	file.store_string(JSON.stringify(data, "  ", true) + "\n")
	file.close()


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _entry(workspace: Workspace, id: String) -> Dictionary:
	for record: Dictionary in workspace.list_levels():
		if record.id == id:
			return record
	return {}


func _proof(level: Dictionary) -> Dictionary:
	var commands: Array[String] = ["P"]
	var result := Replay.build(level, commands)
	_check(result.valid, "fixture proof actually wins: " + str(level.id))
	return result


func _test_library_and_drafts() -> void:
	var config := _config("library", [_fixture("alpha"), _fixture("beta")])
	var workspace := Workspace.new()
	workspace.configure(config)
	var records := workspace.list_levels()
	_check(records.size() == 2 and records[0].id == "alpha" and records[1].id == "beta", "published list follows manifest order")
	_check(records[0].status == "published" and not records[0].published_hash.is_empty(), "published entries expose status and source hash")
	var published_path: String = records[0].published_path
	var old_hash := workspace.source_hash(published_path)
	var level := workspace.load_level("alpha")
	level.title = "只改标题，不改稳定 ID"
	_check(workspace.save_draft(level) == OK, "existing published level can acquire an independent draft")
	_check(workspace.source_hash(published_path) == old_hash, "draft save never overwrites published content")
	_check(workspace.load_level("alpha").title == level.title, "load prefers saved draft")
	_check(_entry(workspace, "alpha").status == "modified", "draft title change is marked modified")
	level = _fixture("alpha")
	level.metadata.solution = ["P"]
	_check(workspace.save_draft(level) == OK and _entry(workspace, "alpha").status == "published", "solution bookkeeping alone does not mark layout modified")
	var created := workspace.new_level("draft_only", "未完成草稿", 6, 4)
	_check(not created.is_empty() and created.goals.is_empty() and created.player == [-1, -1], "new level is an unfinished authoring document")
	_check(Codec.validate_draft(created).is_empty() and not Codec.validate(created).is_empty(), "draft gate differs from playable gate")
	_check(_entry(workspace, "draft_only").status == "draft", "draft-only document joins library")
	created.floor.clear()
	_check(workspace.save_draft(created) == OK, "empty-floor draft remains saveable")
	_check(workspace.load_level("draft_only").floor.is_empty(), "unfinished draft round-trips without silent playable repair")
	_check(workspace.new_level("draft_only", "重复").is_empty(), "new stable ID cannot replace an existing draft")
	_check(workspace.new_level("../escape", "错误").is_empty(), "stable ID cannot escape content directories")
	_check(not workspace.last_errors.is_empty(), "invalid operation returns readable diagnostics")
	_check(workspace.new_level("CON", "设备名").is_empty(), "stable ID rejects Windows reserved device names")
	_check(workspace.new_level("bad_size", "错误", 100, 4).is_empty(), "new document dimensions follow shared codec limits")
	var detached := workspace.list_levels()
	detached[0].title = "仅修改返回值"
	_check(workspace.load_level("alpha").title != detached[0].title, "library records do not own mutable authoring state")
	var large := _fixture("large")
	large.metadata.notes = "x".repeat(8 * 1024 * 1024)
	_check(workspace.save_draft(large) != OK and not FileAccess.file_exists(str(config.draft_dir).path_join("large.json")), "workspace cannot write a document its own size limit would reject")


func _test_duplicate() -> void:
	var level := _fixture("source")
	level.objects.append({"id": "plate_01", "type": "plate", "cell": [5, 3], "targets": ["door_01"]})
	level.objects.append({"id": "door_01", "type": "door", "cell": [6, 3], "targets": []})
	level.metadata.solution = ["P"]
	level.metadata.proof = {"valid": true}
	var workspace := Workspace.new()
	workspace.configure(_config("duplicate", [level]))
	workspace.list_levels()
	_check(workspace.save_proof(level, _proof(level)) == OK, "source proof can be persisted")
	var copied := workspace.duplicate_level("source", "copied", "副本标题")
	_check(not copied.is_empty() and copied.id == "copied" and copied.title == "副本标题", "duplicate gets independent stable ID and title")
	_check(copied.metadata.solution.is_empty() and not copied.metadata.has("proof"), "duplicate clears authoring proof and solution fields")
	_check(workspace.load_proof("copied").is_empty(), "duplicate does not inherit external proof file")
	_check(copied.objects[0].id != level.objects[0].id, "duplicated objects receive fresh stable instance IDs")
	var plate: Dictionary = copied.objects.filter(func(item: Dictionary) -> bool: return item.type == "plate")[0]
	var door: Dictionary = copied.objects.filter(func(item: Dictionary) -> bool: return item.type == "door")[0]
	_check(plate.targets == [door.id] and plate.targets != ["door_01"], "internal mechanism links are remapped together")
	_check(Codec.validate_draft(copied).is_empty(), "copied parameter and link structure remains valid")
	_check(workspace.duplicate_level("source", "copied", "覆盖").is_empty(), "duplicate refuses existing destination ID")
	var original_path: String = str(workspace.published_dir).path_join("source.json")
	var legacy_path: String = str(workspace.published_dir).path_join("different_filename.json")
	DirAccess.rename_absolute(original_path, legacy_path)
	_write(workspace.campaign_path, {"levels": [legacy_path]})
	workspace.configure({"campaign_path": workspace.campaign_path, "published_dir": workspace.published_dir, "draft_dir": workspace.draft_dir, "proof_dir": workspace.proof_dir})
	var existing := workspace.load_level("source")
	existing.title = "改标题但不改文件名"
	_check(workspace.publish(existing, _proof(existing)) == OK, "existing published filename may differ from stable level ID")
	_check(_entry(workspace, "source").published_path == legacy_path and not FileAccess.file_exists(original_path), "publication preserves legacy path instead of creating a second file")


func _test_memory_fork() -> void:
	var config := _config("memory_fork")
	var workspace := Workspace.new()
	workspace.configure(config)
	var source := _fixture("conflicted")
	source.objects.append({"id": "plate_old", "type": "plate", "cell": [5, 3], "targets": ["door_old"]})
	source.objects.append({"id": "door_old", "type": "door", "cell": [6, 3], "targets": []})
	_check(workspace.save_draft(source) == OK and workspace.save_proof(source, _proof(source)) == OK, "original document and proof exist before memory-fork conflict")
	var memory := workspace.load_level("conflicted")
	memory.title = "尚未保存的内存编辑"
	memory.goals = []
	memory.player = [-1, -1]
	memory.objects[0].cell = [3, 1]
	memory.objects[0].params = {"punch_distance": 3}
	memory.metadata.author_note = "内存里的修改必须保留"
	memory.metadata.solution = ["P"]
	memory.metadata.proof = {"valid": true}
	var memory_before := memory.duplicate(true)
	var original_path: String = str(config.draft_dir).path_join("conflicted.json")
	var external := source.duplicate(true)
	external.title = "磁盘上的外部版本"
	external.metadata.external_note = "不要覆盖"
	_write(original_path, external)
	var external_bytes := FileAccess.get_file_as_bytes(original_path)
	_check(workspace.save_draft(memory) == ERR_BUSY, "ordinary save detects original draft conflict")
	var copied := workspace.fork_draft(memory, "rescued", "另存恢复副本")
	_check(not copied.is_empty() and copied.id == "rescued" and copied.title == "另存恢复副本", "dirty conflicted memory document can fork directly without saving its original")
	_check(FileAccess.get_file_as_bytes(original_path) == external_bytes, "fork preserves external original bytes exactly")
	_check(memory == memory_before, "fork does not mutate caller's current document")
	_check(copied.player == [-1, -1] and copied.goals.is_empty() and Codec.validate_draft(copied).is_empty(), "memory fork preserves unfinished layout")
	_check(not Codec.validate(copied).is_empty(), "unfinished fork is not presented as playable publication")
	_check(copied.objects[0].cell == [3, 1] and copied.objects[0].params.punch_distance == 3 and copied.metadata.author_note == memory.metadata.author_note, "fork keeps unsaved positions, parameters and author metadata")
	_check(not copied.metadata.has("external_note"), "fork uses memory rather than externally changed disk data")
	_check(copied.metadata.solution.is_empty() and not copied.metadata.has("proof") and workspace.load_proof("rescued").is_empty(), "fork clears inherited solution and proof ownership")
	var plate: Dictionary = copied.objects.filter(func(item: Dictionary) -> bool: return item.type == "plate")[0]
	var door: Dictionary = copied.objects.filter(func(item: Dictionary) -> bool: return item.type == "door")[0]
	_check(plate.id != "plate_old" and door.id != "door_old" and plate.targets == [door.id], "memory-fork mechanism IDs and target references are regenerated together")
	_check(workspace.load_level("rescued") == copied, "forked memory document is actually persisted")
	_check(workspace.fork_draft(memory, "rescued", "不能覆盖").is_empty(), "fork refuses an already existing destination ID")
	_check(workspace.fork_draft(memory, "../escape", "不能越界").is_empty(), "fork applies normal stable-ID path validation")
	var invalid := memory.duplicate(true)
	invalid.objects[0].params.punch_distance = 0
	_check(workspace.fork_draft(invalid, "invalid_fork", "非法参数").is_empty(), "fork cannot save structurally invalid instance parameters")
	var racing := ExternalCreateWorkspace.new()
	racing.configure(config)
	racing.inject_on_id = "external_destination"
	racing.external_document = _fixture("external_destination")
	racing.external_document.title = "检查后由外部新建的目标"
	_check(racing.fork_draft(memory, "external_destination", "不要覆盖别人").is_empty(), "fork detects a destination created after its availability check")
	_check(_read(str(config.draft_dir).path_join("external_destination.json")).title == racing.external_document.title, "fork's hash guard preserves newly created external destination")
	_check(FileAccess.get_file_as_bytes(original_path) == external_bytes, "failed destination fork still never touches original conflict path")


func _test_publish_and_order() -> void:
	var config := _config("publish", [_fixture("first"), _fixture("second")])
	var workspace := Workspace.new()
	workspace.configure(config)
	workspace.list_levels()
	var incomplete := workspace.new_level("new_round", "新关卡")
	var manifest_before := workspace.source_hash(config.campaign_path)
	_check(workspace.publish(incomplete, {"valid": true}) != OK, "unfinished draft cannot publish")
	var level := _fixture("new_round")
	_check(workspace.save_draft(level) == OK, "complete layout replaces its draft")
	var forged := {"valid": true, "revision": Replay.revision(level), "commands": [], "moves": 0, "punches": 0}
	_check(workspace.save_proof(level, forged) != OK and workspace.publish(level, forged) != OK, "proof valid flag and matching hash cannot fake a winning replay")
	_check(workspace.source_hash(config.campaign_path) == manifest_before, "rejected proof leaves campaign bytes unchanged")
	var proof := _proof(level)
	_check(workspace.save_proof(level, proof) == OK, "actual winning proof saves")
	_check(workspace.publish(level, proof) == OK, "winning replay and strict structure permit publication")
	var record := _entry(workspace, "new_round")
	_check(record.status == "published" and record.draft_path.is_empty(), "successful publish clears draft instead of staying modified")
	_check(not FileAccess.file_exists(str(config.draft_dir).path_join("new_round.json")), "published draft is physically removed")
	_check(_read(config.campaign_path).levels.back() == record.published_path, "new publish automatically registers in campaign")
	_check(_read(config.campaign_path).author_note == "keep manifest metadata", "manifest extension fields survive publication")
	_check(_read(record.published_path).metadata.solution == ["P"], "published solution comes from verified commands")
	_check(Replay.verify(workspace.load_level("new_round"), workspace.load_proof("new_round")).valid, "persisted publication proof remains replay-verifiable")
	var original_path: String = record.published_path
	var renamed := workspace.load_level("new_round")
	renamed.title = "更换显示标题"
	_check(workspace.publish(renamed, proof, record.published_hash) == OK, "title-only change preserves valid rule revision")
	_check(_entry(workspace, "new_round").published_path == original_path, "renaming title never renames the published file or stable ID")
	var wrong_rules := renamed.duplicate(true)
	wrong_rules.objects[0].params = {"punch_distance": 1}
	var formal_hash := workspace.source_hash(original_path)
	_check(workspace.publish(wrong_rules, proof) != OK and workspace.source_hash(original_path) == formal_hash, "changed rule parameters invalidate proof without touching formal file")
	var order: Array[String] = ["new_round", "second", "first"]
	_check(workspace.save_order(order) == OK and workspace.list_levels()[0].id == "new_round", "full published ID set can reorder campaign")
	var ordered_hash := workspace.source_hash(config.campaign_path)
	var short_order: Array[String] = ["first"]
	_check(workspace.save_order(short_order) != OK, "order refuses omitted published IDs")
	var repeated_order: Array[String] = ["first", "first", "second"]
	_check(workspace.save_order(repeated_order) != OK, "order refuses duplicate IDs")
	var unknown_order: Array[String] = ["first", "second", "not_published"]
	_check(workspace.save_order(unknown_order) != OK and workspace.source_hash(config.campaign_path) == ordered_hash, "order refuses drafts or unknown IDs without writing")


func _test_conflicts() -> void:
	var config := _config("conflicts", [_fixture("formal")])
	var first := Workspace.new()
	first.configure(config)
	first.list_levels()
	var editing := first.load_level("formal")
	var external := editing.duplicate(true)
	external.title = "外部新建草稿"
	var draft_path: String = str(config.draft_dir).path_join("formal.json")
	_write(draft_path, external)
	first.list_levels()
	_check(first.save_draft(editing) == ERR_BUSY and _read(draft_path).title == external.title, "external new draft cannot be overwritten with an empty expected hash")
	first.load_level("formal")
	var second := Workspace.new()
	second.configure(config)
	second.load_level("formal")
	var old_hash := first.source_hash(draft_path)
	editing.title = "第一位作者"
	_check(first.save_draft(editing, old_hash) == OK, "observed source hash permits an unchanged disk version")
	second.list_levels()
	_check(second.save_draft(external, old_hash) == ERR_BUSY, "second author detects changed draft even after refreshing list")
	var reloaded := second.load_level("formal")
	reloaded.title = "重新载入后编辑"
	_check(second.save_draft(reloaded) == OK, "explicit document reload acknowledges a new disk baseline")
	var fresh := Workspace.new()
	fresh.configure(config)
	_check(fresh.save_draft(reloaded) == ERR_BUSY, "fresh service cannot silently overwrite an unobserved existing draft")
	var published_path: String = _entry(second, "formal").published_path
	var old_formal_hash := second.source_hash(published_path)
	var proof := _proof(editing)
	external = _fixture("formal")
	external.title = "外部正式文件"
	_write(published_path, external)
	second.list_levels()
	_check(second.publish(editing, proof, old_formal_hash) == ERR_BUSY and _read(published_path).title == external.title, "published file CAS rejects external edits")
	var third := Workspace.new()
	third.configure(config)
	third.load_level("formal")
	DirAccess.remove_absolute(draft_path)
	_check(third.save_draft(reloaded) == ERR_BUSY, "external draft deletion also requires explicit reload")
	var manifest := _read(config.campaign_path)
	manifest.external_note = "别的作者编辑清单"
	_write(config.campaign_path, manifest)
	var full_order: Array[String] = ["formal"]
	_check(third.save_order(full_order) == ERR_BUSY and _read(config.campaign_path).has("external_note"), "campaign external modification is not silently overwritten")


func _test_failed_publish() -> void:
	var config := _config("failed_publish", [_fixture("original")])
	var workspace := FaultWorkspace.new()
	workspace.configure(config)
	workspace.list_levels()
	var level := _fixture("candidate")
	_check(workspace.save_draft(level) == OK, "candidate draft saves before failure injection")
	var draft_path: String = str(config.draft_dir).path_join("candidate.json")
	var formal_path: String = str(config.published_dir).path_join("candidate.json")
	var proof_path: String = str(config.proof_dir).path_join("candidate.json")
	var manifest_hash := workspace.source_hash(config.campaign_path)
	var draft_hash := workspace.source_hash(draft_path)
	workspace.rejected_installs[config.campaign_path] = 1
	_check(workspace.publish(level, _proof(level)) != OK, "manifest registration failure is returned")
	_check(not FileAccess.file_exists(formal_path) and not FileAccess.file_exists(proof_path), "failed new publish removes already-installed formal and proof files")
	_check(workspace.source_hash(config.campaign_path) == manifest_hash and workspace.source_hash(draft_path) == draft_hash, "failed later publish step preserves original manifest and draft bytes")
	_check(not workspace.last_errors.is_empty(), "publish recovery reports its failing path")
	_check(workspace.publish(level, _proof(level)) == OK, "publication can retry after compensation completed")
	var blocked_config := _config("blocked_parent")
	var blocked := str(blocked_config.draft_dir)
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("This path is a file, not a directory.")
	file.close()
	var cannot_stage := Workspace.new()
	cannot_stage.configure(blocked_config)
	var original_hash := cannot_stage.source_hash(blocked_config.campaign_path)
	_check(cannot_stage.save_draft(_fixture("blocked")) != OK and cannot_stage.source_hash(blocked_config.campaign_path) == original_hash, "staging IO failure leaves live content unchanged")


func _test_unpublish() -> void:
	var config := _config("withdraw", [_fixture("keep"), _fixture("withdraw")])
	var workspace := FaultWorkspace.new()
	workspace.configure(config)
	workspace.list_levels()
	var level := workspace.load_level("withdraw")
	level.title = "更近的草稿标题"
	_check(workspace.save_draft(level) == OK, "newer authoring draft exists before withdrawal")
	var formal_path: String = _entry(workspace, "withdraw").published_path
	var draft_path: String = _entry(workspace, "withdraw").draft_path
	var before_formal := workspace.source_hash(formal_path)
	var before_draft := workspace.source_hash(draft_path)
	var before_campaign := workspace.source_hash(config.campaign_path)
	workspace.rejected_remove = formal_path
	_check(workspace.unpublish("withdraw", before_formal) != OK, "withdrawal reports failed final removal")
	_check(workspace.source_hash(formal_path) == before_formal and workspace.source_hash(draft_path) == before_draft and workspace.source_hash(config.campaign_path) == before_campaign, "withdrawal compensation restores draft, manifest and formal bytes")
	_check(workspace.unpublish("withdraw", before_formal) == OK, "withdrawal succeeds after IO failure clears")
	_check(_entry(workspace, "withdraw").status == "draft" and workspace.load_level("withdraw").title == level.title, "withdrawal retains newer draft content")
	_check(not FileAccess.file_exists(formal_path) and _read(config.campaign_path).levels.size() == 1, "withdrawal removes only selected formal entry")
	_check(workspace.unpublish("not_published") != OK, "withdrawal refuses non-published ID")
	_check(workspace.publish(level, _proof(level)) == OK and _entry(workspace, "withdraw").status == "published", "withdrawn draft can return through verified publication")


func _test_recovery_copy() -> void:
	var config := _config("recovery_copy", [_fixture("existing")])
	var workspace := FaultWorkspace.new()
	workspace.configure(config)
	workspace.list_levels()
	var level := workspace.load_level("existing")
	var path: String = _entry(workspace, "existing").published_path
	var original := FileAccess.get_file_as_bytes(path)
	level.title = "待发布的新版本"
	workspace.rejected_installs[str(config.proof_dir).path_join("existing.json")] = 1
	workspace.rejected_installs[path] = 2
	_check(workspace.publish(level, _proof(level)) != OK, "simultaneous commit and restoration failure is reported")
	var preserved := false
	for filename: String in DirAccess.get_files_at(config.published_dir):
		var candidate: String = str(config.published_dir).path_join(filename)
		if filename.ends_with(".bak") and FileAccess.get_file_as_bytes(candidate) == original:
			preserved = true
	_check(preserved, "original valid formal bytes remain in a retained recovery copy when OS refuses restoration")
	_check("恢复失败" in " ".join(workspace.last_errors), "manual recovery diagnostic names retained backup")
