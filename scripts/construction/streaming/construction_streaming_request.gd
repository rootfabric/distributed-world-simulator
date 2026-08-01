extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const RuntimeRequest = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const StructuralSummary = preload("res://scripts/construction/structural/construction_structural_summary.gd")
const UtilitySummary = preload("res://scripts/construction/utilities/construction_utility_summary.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")

const SCHEMA := "planet_simulator.construction_streaming_request.v1"
const OWNER := "OWNER"
const READ_ONLY := "READ_ONLY"
const AUTHORITY_MODES: Array[String] = [OWNER, READ_ONLY]
const COST_FIELDS: Array[String] = ["summary_bytes", "simulation_units", "presentation_bytes"]
const FIELDS: Array[String] = ["schema", "construct_id", "authority_epoch", "owner_server_id", "local_server_id", "authority_mode", "construct_snapshot", "runtime_projection_request", "structural_summary", "utility_summaries", "capability_kinds", "pending_job_ids", "pending_operation_ids", "bounds_m", "mass_kg", "estimated_costs", "minimum_level", "checksum"]

static func create(snapshot: Dictionary, authority_epoch: int, owner_server_id: String, local_server_id: String, authority_mode: String, runtime_projection_request: Dictionary = {}, structural_summary: Dictionary = {}, utility_summaries: Array = [], capability_kinds: Array = [], pending_job_ids: Array = [], pending_operation_ids: Array = [], bounds_m: Array = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0], mass_kg: float = 0.0, estimated_costs: Dictionary = {}, minimum_level: String = Level.DORMANT) -> Dictionary:
	var costs := {"summary_bytes": int(estimated_costs.get("summary_bytes", 1024)), "simulation_units": int(estimated_costs.get("simulation_units", 1)), "presentation_bytes": int(estimated_costs.get("presentation_bytes", 4096))}
	var value := {"schema": SCHEMA, "construct_id": String(snapshot.get("construct_id", "")), "authority_epoch": authority_epoch, "owner_server_id": owner_server_id, "local_server_id": local_server_id, "authority_mode": authority_mode, "construct_snapshot": snapshot.duplicate(true), "runtime_projection_request": runtime_projection_request.duplicate(true), "structural_summary": structural_summary.duplicate(true), "utility_summaries": _sort_dicts(utility_summaries, "network_id"), "capability_kinds": _sort_strings(capability_kinds), "pending_job_ids": _sort_strings(pending_job_ids), "pending_operation_ids": _sort_strings(pending_operation_ids), "bounds_m": bounds_m.duplicate(true), "mass_kg": mass_kg, "estimated_costs": costs, "minimum_level": minimum_level, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STREAMING_REQUEST_SCHEMA")
	if not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_STREAMING_CONSTRUCT_ID")
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1: return _failure("INVALID_CONSTRUCTION_STREAMING_AUTHORITY_EPOCH")
	for field in ["owner_server_id", "local_server_id"]:
		if not String(value.get(field, "")).begins_with("server/"): return _failure("INVALID_CONSTRUCTION_STREAMING_SERVER_ID")
	if not AUTHORITY_MODES.has(String(value.get("authority_mode", ""))): return _failure("INVALID_CONSTRUCTION_STREAMING_AUTHORITY_MODE")
	if String(value["authority_mode"]) == OWNER and String(value["owner_server_id"]) != String(value["local_server_id"]): return _failure("CONSTRUCTION_STREAMING_OWNER_MODE_SERVER_MISMATCH")
	if typeof(value.get("construct_snapshot")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_SNAPSHOT")
	var checked := Snapshot.validate(value["construct_snapshot"]); if not bool(checked.get("success", false)): return checked
	if String(value["construct_snapshot"]["construct_id"]) != String(value["construct_id"]): return _failure("CONSTRUCTION_STREAMING_SNAPSHOT_ID_MISMATCH")
	if typeof(value.get("runtime_projection_request")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_RUNTIME_REQUEST")
	if not Dictionary(value["runtime_projection_request"]).is_empty():
		checked = RuntimeRequest.validate(value["runtime_projection_request"]); if not bool(checked.get("success", false)): return checked
		if String(value["runtime_projection_request"]["construct_snapshot"]["checksum"]) != String(value["construct_snapshot"]["checksum"]): return _failure("CONSTRUCTION_STREAMING_RUNTIME_SNAPSHOT_MISMATCH")
	if typeof(value.get("structural_summary")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_STRUCTURAL_SUMMARY")
	if not Dictionary(value["structural_summary"]).is_empty():
		checked = StructuralSummary.validate(value["structural_summary"]); if not bool(checked.get("success", false)): return checked
		if String(value["structural_summary"]["construct_id"]) != String(value["construct_id"]): return _failure("CONSTRUCTION_STREAMING_STRUCTURAL_SUMMARY_MISMATCH")
	if typeof(value.get("utility_summaries")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STREAMING_UTILITY_SUMMARIES")
	var previous := ""; var seen := {}
	for raw in value["utility_summaries"]:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_UTILITY_SUMMARY")
		checked = UtilitySummary.validate(raw); if not bool(checked.get("success", false)): return checked
		var network_id := String(raw["network_id"])
		if seen.has(network_id) or (not previous.is_empty() and network_id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STREAMING_UTILITY_SUMMARIES")
		seen[network_id] = true; previous = network_id
	for field in ["capability_kinds", "pending_job_ids", "pending_operation_ids"]:
		checked = _validate_sorted_strings(value.get(field)); if not bool(checked.get("success", false)): return checked
	if not _finite_vector(value.get("bounds_m"), 6): return _failure("INVALID_CONSTRUCTION_STREAMING_BOUNDS")
	var bounds: Array = value["bounds_m"]
	if float(bounds[3]) < float(bounds[0]) or float(bounds[4]) < float(bounds[1]) or float(bounds[5]) < float(bounds[2]): return _failure("INVALID_CONSTRUCTION_STREAMING_BOUNDS_ORDER")
	if typeof(value.get("mass_kg")) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(value["mass_kg"])) or is_inf(float(value["mass_kg"])) or float(value["mass_kg"]) < 0.0: return _failure("INVALID_CONSTRUCTION_STREAMING_MASS")
	if typeof(value.get("estimated_costs")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_COSTS")
	checked = Utils.validate_exact_fields(value["estimated_costs"], COST_FIELDS); if not bool(checked.get("success", false)): return checked
	for field in COST_FIELDS:
		if not Utils.is_json_integer(value["estimated_costs"].get(field)) or int(value["estimated_costs"][field]) < 0: return _failure("INVALID_CONSTRUCTION_STREAMING_COST")
	if not Level.is_valid(value.get("minimum_level")): return _failure("INVALID_CONSTRUCTION_STREAMING_MINIMUM_LEVEL")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STREAMING_REQUEST_CHECKSUM_MISMATCH")
	if not bool(Utils.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_STREAMING_REQUEST_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _validate_sorted_strings(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STREAMING_STRING_LIST")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING or String(raw).is_empty(): return _failure("INVALID_CONSTRUCTION_STREAMING_STRING_LIST")
		var text := String(raw)
		if seen.has(text) or (not previous.is_empty() and text < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STREAMING_STRING_LIST")
		seen[text] = true; previous = text
	return _success()
static func _finite_vector(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != size: return false
	for raw in value:
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(raw)) or is_inf(float(raw)): return false
	return true
static func _sort_strings(values: Array) -> Array: var result := values.duplicate(true); result.sort(); return result
static func _sort_dicts(values: Array, key: String) -> Array: var result := values.duplicate(true); result.sort_custom(func(a,b): return String(a.get(key,"")) < String(b.get(key,""))); return result
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
