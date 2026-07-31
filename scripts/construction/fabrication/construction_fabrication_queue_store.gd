extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const JobScript = preload("res://scripts/construction/fabrication/construction_fabrication_job.gd")
const SCHEMA := "planet_simulator.construction_fabrication_queue_store.v1"
const FIELDS: Array[String] = ["schema", "generation", "jobs", "progress_operations", "checksum"]
var _jobs: Dictionary = {}; var _operations: Dictionary = {}; var _generation := 0
func setup() -> Dictionary: _jobs.clear(); _operations.clear(); _generation = 0; return _success()
func enqueue(job: Dictionary) -> Dictionary:
	var checked := JobScript.validate(job); if not bool(checked.get("success", false)): return checked
	var id := String(job["job_id"])
	if _jobs.has(id):
		if String(_jobs[id]["checksum"]) == String(job["checksum"]): return _success({"replay": true, "job": get_job(id), "generation": _generation})
		return _failure("CONSTRUCTION_FABRICATION_JOB_ID_CONFLICT")
	_jobs[id] = _canonical(job); _generation += 1; return _success({"replay": false, "job": get_job(id), "generation": _generation})
func replace_job(expected_checksum: String, job: Dictionary) -> Dictionary:
	var checked := JobScript.validate(job); if not bool(checked.get("success", false)): return checked
	var id := String(job["job_id"]); if not _jobs.has(id): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_FOUND")
	if String(_jobs[id]["checksum"]) != expected_checksum: return _failure("CONSTRUCTION_FABRICATION_JOB_PRECONDITION_MISMATCH")
	if String(_jobs[id]["checksum"]) == String(job["checksum"]): return _success({"replay": true, "job": get_job(id), "generation": _generation})
	_jobs[id] = _canonical(job); _generation += 1; return _success({"replay": false, "job": get_job(id), "generation": _generation})
func advance(job_id: String, work_units: int, operation_id: String) -> Dictionary:
	if not operation_id.begins_with("operation/") or work_units < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_PROGRESS_OPERATION")
	var payload := UtilsScript.payload_hash({"job_id": job_id, "work_units": work_units})
	if _operations.has(operation_id):
		var record: Dictionary = _operations[operation_id]
		if String(record["payload_hash"]) != payload: return _failure("CONSTRUCTION_FABRICATION_PROGRESS_OPERATION_CONFLICT")
		return _success({"replay": true, "job": get_job(job_id), "generation": _generation})
	if not _jobs.has(job_id): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_FOUND")
	var before: Dictionary = _jobs[job_id]
	if not ["RESERVED", "PROCESSING", "BLOCKED"].has(String(before["status"])): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_PROCESSABLE")
	var completed := mini(int(before["work_required"]), int(before["work_completed"]) + work_units)
	var next := JobScript.with_updates(before, {"status": "PROCESSING", "work_completed": completed, "last_error_code": ""})
	_jobs[job_id] = _canonical(next); _operations[operation_id] = {"payload_hash": payload, "job_checksum": String(next["checksum"])}; _generation += 1
	return _success({"replay": false, "job": get_job(job_id), "generation": _generation})
func mark_blocked(job_id: String, error_code: String) -> Dictionary:
	if not _jobs.has(job_id): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_FOUND")
	var before: Dictionary = _jobs[job_id]; var next := JobScript.with_updates(before, {"status": "BLOCKED", "last_error_code": error_code})
	return replace_job(String(before["checksum"]), next)
func get_job(job_id: String) -> Dictionary: return Dictionary(_jobs.get(job_id, {})).duplicate(true)
func list_jobs() -> Array:
	var values: Array = _jobs.values(); values.sort_custom(func(a,b):
		if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) > int(b["priority"])
		return String(a["job_id"]) < String(b["job_id"])); return values.duplicate(true)
func get_generation() -> int: return _generation
func to_dict() -> Dictionary:
	var operation_ids := _operations.keys(); operation_ids.sort(); var rows: Array = []; for id in operation_ids: rows.append({"operation_id": String(id), "payload_hash": String(_operations[id]["payload_hash"]), "job_checksum": String(_operations[id]["job_checksum"])})
	var jobs := _jobs.values(); jobs.sort_custom(func(a,b): return String(a["job_id"]) < String(b["job_id"]))
	var value := {"schema": SCHEMA, "generation": _generation, "jobs": jobs.duplicate(true), "progress_operations": rows, "checksum": ""}; value["checksum"] = compute_checksum(value); return value
func load_dict(value: Dictionary) -> Dictionary:
	var checked := validate_state(value); if not bool(checked.get("success", false)): return checked
	var next_jobs: Dictionary = {}
	for job in value["jobs"]:
		next_jobs[String(job["job_id"])] = _canonical(job)
	var next_ops: Dictionary = {}
	for row in value["progress_operations"]:
		next_ops[String(row["operation_id"])] = {"payload_hash": String(row["payload_hash"]), "job_checksum": String(row["job_checksum"])}
	_jobs = next_jobs; _operations = next_ops; _generation = int(value["generation"]); return _success({"job_count": _jobs.size(), "generation": _generation})
static func validate_state(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_QUEUE_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("generation")) or int(value["generation"]) < 0: return _failure("INVALID_CONSTRUCTION_FABRICATION_QUEUE_GENERATION")
	if typeof(value.get("jobs")) != TYPE_ARRAY or typeof(value.get("progress_operations")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_FABRICATION_QUEUE_COLLECTIONS")
	var previous := ""
	var seen := {}
	for job in value["jobs"]:
		if typeof(job) != TYPE_DICTIONARY: return _failure("INVALID_PERSISTED_CONSTRUCTION_FABRICATION_JOB")
		var checked := JobScript.validate(job); if not bool(checked.get("success", false)): return checked
		var id := String(job["job_id"]); if seen.has(id) or (not previous.is_empty() and id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_FABRICATION_JOBS"); seen[id] = true; previous = id
	previous = ""
	seen.clear()
	for row in value["progress_operations"]:
		if typeof(row) != TYPE_DICTIONARY or row.keys().size() != 3: return _failure("INVALID_PERSISTED_CONSTRUCTION_FABRICATION_PROGRESS_OPERATION")
		var id := String(row.get("operation_id", "")); if not id.begins_with("operation/") or seen.has(id) or (not previous.is_empty() and id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_FABRICATION_PROGRESS_OPERATIONS")
		if String(row.get("payload_hash", "")).length() != 64 or String(row.get("job_checksum", "")).length() != 64: return _failure("INVALID_PERSISTED_CONSTRUCTION_FABRICATION_PROGRESS_OPERATION")
		seen[id] = true; previous = id
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_QUEUE_STORE_CHECKSUM_MISMATCH")
	return _success()
static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _canonical(value: Dictionary) -> Dictionary: var result := UtilsScript.canonicalize(value); return Dictionary(result.get("value", {})).duplicate(true) if bool(result.get("success", false)) else {}
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
