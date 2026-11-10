extends SceneTree

const Replay = preload("res://core/replay_proof.gd")
const Catalog = preload("res://core/object_catalog.gd")
const Codec = preload("res://core/level_codec.gd")
const TEMP_CATALOG := "res://tests/.replay_catalog.json"
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	var original_hash := FileAccess.get_file_as_string(Catalog.DEFINITIONS_PATH).sha256_text()
	_test_campaign()
	_test_revision_and_forgery()
	_test_default_revision()
	_check(Catalog.reload_catalog().is_empty(), "canonical catalog reloads after replay tests")
	_check(FileAccess.get_file_as_string(Catalog.DEFINITIONS_PATH).sha256_text() == original_hash, "replay tests never modify actual definitions")
	if FileAccess.file_exists(TEMP_CATALOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_CATALOG))
	print("REPLAY_RESULT ", JSON.stringify({"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _typed(raw: Array) -> Array[String]:
	var result: Array[String] = []
	for command: String in raw:
		result.append(command)
	return result


func _bag_level() -> Dictionary:
	var floor_list: Array = []
	for y: int in range(4):
		for x: int in range(8):
			floor_list.append([x, y])
	return {"schema_version": 1, "id": "proof_bag", "title": "PROOF", "width": 8, "height": 4, "floor": floor_list, "walls": [], "goals": [[4, 2]], "player": [1, 2], "facing": [1, 0], "objects": [{"id": "bag", "type": "bag", "cell": [2, 2], "targets": []}], "metadata": {"solution": []}}


func _test_campaign() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels/campaign.json"))
	for path: String in manifest["levels"]:
		var level := Codec.load_file(path)
		var proof := Replay.build(level, _typed(level["metadata"]["solution"]))
		_check(proof["valid"], "shared simulation builds a winning proof: %s %s" % [level["id"], str(proof["errors"])])
		var verified := Replay.verify(level, proof)
		_check(verified["valid"] and verified["moves"] == proof["moves"] and verified["punches"] == proof["punches"], "proof actually replays and reproduces counts: %s" % level["id"])


func _test_revision_and_forgery() -> void:
	var level := _bag_level()
	var proof := Replay.build(level, _typed(["P"]))
	_check(proof["valid"] and proof["moves"] == 1 and proof["punches"] == 1, "minimal bag proof records computed counts")
	var renamed := level.duplicate(true)
	renamed["title"] = "Different display title"
	renamed["metadata"] = {"hint": "new note", "solution": ["L"]}
	_check(Replay.revision(renamed) == proof["revision"] and Replay.verify(renamed, proof)["valid"], "title and author notes do not invalidate gameplay proof")
	var reordered := level.duplicate(true)
	reordered["floor"].reverse()
	_check(Replay.revision(reordered) == proof["revision"], "equivalent cell order produces a stable revision")
	var changed := level.duplicate(true)
	changed["objects"][0]["params"] = {"punch_distance": 2}
	_check(Replay.revision(changed) == proof["revision"], "explicit current default and inherited default have identical rule revision")
	changed = level.duplicate(true)
	changed["walls"] = [[7, 0]]
	_check(Replay.revision(changed) != proof["revision"] and not Replay.verify(changed, proof)["valid"], "layout modification invalidates prior proof even if the old commands happen to win")
	changed = level.duplicate(true)
	changed["objects"][0]["params"] = {"punch_distance": 1}
	_check(Replay.revision(changed) != proof["revision"] and not Replay.verify(changed, proof)["valid"], "instance parameter changes invalidate and replay differently")
	var forged := proof.duplicate(true)
	forged["commands"] = []
	forged["moves"] = 0
	forged["punches"] = 0
	_check(not Replay.verify(level, forged)["valid"], "matching revision and claimed valid flag cannot replace a winning replay")
	forged = proof.duplicate(true)
	forged["commands"] = ["P", "DELETE"]
	_check(not Replay.verify(level, forged)["valid"], "unknown replay commands are rejected")
	forged = proof.duplicate(true)
	forged["commands"] = "P"
	_check(not Replay.verify(level, forged)["valid"], "malformed command container is rejected")
	forged = proof.duplicate(true)
	forged["moves"] = 99
	_check(not Replay.verify(level, forged)["valid"], "reported counters must agree with replayed counters")
	_check(not Replay.build(level, _typed(["L"]))["valid"], "build cannot certify an unfinished run")
	changed = level.duplicate(true)
	changed["objects"][0]["params"] = {"punch_distance": 99}
	_check(Replay.revision(changed).is_empty() and not Replay.build(changed, _typed(["P"]))["valid"], "invalid level parameters cannot acquire a proof revision")


func _test_default_revision() -> void:
	_check(Catalog.write_definition_document(Catalog.catalog_document(), TEMP_CATALOG) == OK and Catalog.reload_catalog(TEMP_CATALOG).is_empty(), "default tests use an isolated checked catalog")
	var level := _bag_level()
	var proof := Replay.build(level, _typed(["P"]))
	var document := Catalog.catalog_document()
	for definition: Dictionary in document["types"]:
		if definition["id"] == "bag":
			definition["punch_distance"] = 3
	_check(Catalog.write_definition_document(document, TEMP_CATALOG) == OK, "type default changes through isolated atomic save")
	_check(Replay.revision(level) != proof["revision"] and not Replay.verify(level, proof)["valid"], "changed type default invalidates old proof")
	var rehashed := proof.duplicate(true)
	rehashed["revision"] = Replay.revision(level)
	_check(not Replay.verify(level, rehashed)["valid"], "updating only the hash cannot certify commands that no longer win")
	level["objects"][0]["params"] = {"punch_distance": 2}
	var overridden := Replay.build(level, _typed(["P"]))
	_check(overridden["valid"], "valid instance override restores actual winning behavior")
	document = Catalog.catalog_document()
	for definition: Dictionary in document["types"]:
		if definition["id"] == "bag":
			definition["punch_distance"] = 4
	_check(Catalog.write_definition_document(document, TEMP_CATALOG) == OK, "another isolated default update succeeds")
	var after_change := Replay.verify(level, overridden)
	_check(not after_change["valid"] and after_change["moves"] == 1 and after_change["punches"] == 1, "proof binds referenced type defaults even when an override preserves the successful replay")
	var visual_only := Catalog.catalog_document()
	for definition: Dictionary in visual_only["types"]:
		definition["label"] = str(definition["label"]) + " visual"
		definition["color"] = "#ffffff"
	var before_visual := Replay.revision(level)
	_check(Catalog.write_definition_document(visual_only, TEMP_CATALOG) == OK and Replay.revision(level) == before_visual, "label and color changes do not invalidate gameplay proofs")
