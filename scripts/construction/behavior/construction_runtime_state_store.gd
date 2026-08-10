extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_state_store.v1"
const FIELDS: Array[String] = ["schema", "generation", "subjects", "checksum"]

var _subjects_by_runtime_id: Dictionary = {}
var _generation: int = 0


func setup() -> Dictionary:
	_subjects_by_runtime_id.clear()
	_generation = 0
	return _success()


func register_subject(subject: Dictionary) -> Dictionary:
	var validation: Dictionary = SubjectScript.validate(subject)
	if not bool(validation.get("success", false)):
		return validation
	var runtime_id: String = String(subject["runtime_id"])
	if _subjects_by_runtime_id.has(runtime_id):
		var existing: Dictionary = _subjects_by_runtime_id[runtime_id]
		if String(existing.get("checksum", "")) == String(subject.get("checksum", "")):
			return _success({"replay": true, "subject": existing.duplicate(true), "generation": _generation})
		return _failure("CONSTRUCTION_RUNTIME_SUBJECT_CONFLICT", {"runtime_id": runtime_id})
	_subjects_by_runtime_id[runtime_id] = _canonical_dictionary(subject)
	_generation += 1
	return _success({"replay": false, "subject": get_subject(runtime_id), "generation": _generation})


func get_subject(runtime_id: String) -> Dictionary:
	return Dictionary(_subjects_by_runtime_id.get(runtime_id, {})).duplicate(true)


func has_subject(runtime_id: String) -> bool:
	return _subjects_by_runtime_id.has(runtime_id)


func list_subjects() -> Array:
	return _sorted_subjects()


func get_generation() -> int:
	return _generation


func update_subject(runtime_id: String, expected_revision: int, next_state: Dictionary) -> Dictionary:
	if not _subjects_by_runtime_id.has(runtime_id):
		return _failure("CONSTRUCTION_RUNTIME_SUBJECT_NOT_FOUND", {"runtime_id": runtime_id})
	var before: Dictionary = _subjects_by_runtime_id[runtime_id]
	if int(before.get("revision", -1)) != expected_revision:
		return _failure("CONSTRUCTION_RUNTIME_REVISION_MISMATCH", {
			"runtime_id": runtime_id,
			"expected_revision": expected_revision,
			"current_revision": int(before.get("revision", -1)),
		})
	var canonical_state: Dictionary = UtilsScript.canonicalize(next_state)
	if not bool(canonical_state.get("success", false)) or not canonical_state.get("value") is Dictionary:
		return _failure("CONSTRUCTION_RUNTIME_STATE_NOT_JSON_SAFE")
	var after: Dictionary = SubjectScript.create(
		runtime_id,
		String(before["construct_id"]),
		String(before["item_instance_id"]),
		String(before["capability_id"]),
		expected_revision + 1,
		Dictionary(canonical_state["value"])
	)
	var validation: Dictionary = SubjectScript.validate(after)
	if not bool(validation.get("success", false)):
		return validation
	_subjects_by_runtime_id[runtime_id] = _canonical_dictionary(after)
	_generation += 1
	return _success({
		"before": before.duplicate(true),
		"after": get_subject(runtime_id),
		"generation": _generation,
	})


func to_dict() -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"generation": _generation,
		"subjects": _sorted_subjects(),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


func load_dict(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var canonical: Dictionary = _canonical_dictionary(value)
	var next_subjects: Dictionary = {}
	for subject_value in canonical.get("subjects", []):
		var subject: Dictionary = Dictionary(subject_value)
		next_subjects[String(subject["runtime_id"])] = subject.duplicate(true)
	_subjects_by_runtime_id = next_subjects
	_generation = int(canonical.get("generation", 0))
	return _success({"subject_count": _subjects_by_runtime_id.size(), "generation": _generation})


static func validate_state(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_STATE_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("generation")) or int(value["generation"]) < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_STATE_STORE_GENERATION")
	if typeof(value.get("subjects")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_STATE_STORE_SUBJECTS")
	var seen: Dictionary = {}
	var previous: String = ""
	for raw in value["subjects"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_STATE_STORE_SUBJECT")
		var subject: Dictionary = raw
		var validation: Dictionary = SubjectScript.validate(subject)
		if not bool(validation.get("success", false)):
			return validation
		var runtime_id: String = String(subject["runtime_id"])
		if seen.has(runtime_id):
			return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_SUBJECT")
		if not previous.is_empty() and runtime_id < previous:
			return _failure("CONSTRUCTION_RUNTIME_SUBJECTS_NOT_SORTED")
		seen[runtime_id] = true
		previous = runtime_id
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_RUNTIME_STATE_STORE_CHECKSUM_MISMATCH")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


func _sorted_subjects() -> Array:
	var ids: Array = _subjects_by_runtime_id.keys()
	ids.sort()
	var rows: Array = []
	for runtime_id in ids:
		rows.append(Dictionary(_subjects_by_runtime_id[runtime_id]).duplicate(true))
	return rows


static func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var canonical: Dictionary = UtilsScript.canonicalize(value)
	return Dictionary(canonical.get("value", {})).duplicate(true) if bool(canonical.get("success", false)) else {}


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
