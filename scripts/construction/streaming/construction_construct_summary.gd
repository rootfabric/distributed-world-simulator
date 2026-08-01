extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Request = preload("res://scripts/construction/streaming/construction_streaming_request.gd")
const SCHEMA := "planet_simulator.construction_construct_summary.v1"
const UTILITY_FIELDS: Array[String] = ["network_id", "utility_kind", "status", "profile_checksum"]
const FIELDS: Array[String] = ["schema", "construct_id", "authority_epoch", "construct_revision", "construct_checksum", "bounds_m", "mass_kg", "capability_kinds", "structural_state", "structural_maximum_utilization", "utility_statuses", "pending_job_count", "pending_operation_count", "checksum"]

static func compile(request: Dictionary) -> Dictionary:
	var checked := Request.validate(request); if not bool(checked.get("success", false)): return checked
	var structural_state := "UNKNOWN"; var structural_utilization := 0.0
	if not request["structural_summary"].is_empty():
		structural_state = String(request["structural_summary"]["structural_state"]); structural_utilization = float(request["structural_summary"]["maximum_utilization"])
	var utilities: Array = []
	for summary in request["utility_summaries"]:
		utilities.append({"network_id": String(summary["network_id"]), "utility_kind": String(summary["utility_kind"]), "status": String(summary["status"]), "profile_checksum": String(summary["profile_checksum"])})
	var snapshot: Dictionary = request["construct_snapshot"]
	var value := {"schema": SCHEMA, "construct_id": String(request["construct_id"]), "authority_epoch": int(request["authority_epoch"]), "construct_revision": int(snapshot["state_revision"]), "construct_checksum": String(snapshot["checksum"]), "bounds_m": request["bounds_m"].duplicate(true), "mass_kg": float(request["mass_kg"]), "capability_kinds": request["capability_kinds"].duplicate(true), "structural_state": structural_state, "structural_maximum_utilization": structural_utilization, "utility_statuses": utilities, "pending_job_count": request["pending_job_ids"].size(), "pending_operation_count": request["pending_operation_ids"].size(), "checksum": ""}
	value["checksum"] = compute_checksum(value); return {"success": true, "error_code": "", "message": "", "summary": value}

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_CONSTRUCT_SUMMARY_SCHEMA")
	if not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_ID")
	for field in ["authority_epoch", "construct_revision", "pending_job_count", "pending_operation_count"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_INTEGER")
	if int(value["authority_epoch"]) < 1 or String(value.get("construct_checksum", "")).length() != 64: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_SOURCE")
	if typeof(value.get("bounds_m")) != TYPE_ARRAY or Array(value["bounds_m"]).size() != 6: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_BOUNDS")
	if typeof(value.get("mass_kg")) not in [TYPE_INT, TYPE_FLOAT] or float(value["mass_kg"]) < 0.0: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_MASS")
	if typeof(value.get("capability_kinds")) != TYPE_ARRAY or typeof(value.get("utility_statuses")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_COLLECTION")
	var sorted_caps := Array(value["capability_kinds"]).duplicate(); sorted_caps.sort(); if sorted_caps != value["capability_kinds"]: return _failure("NON_CANONICAL_CONSTRUCTION_CONSTRUCT_SUMMARY_CAPABILITIES")
	var previous := ""
	for utility in value["utility_statuses"]:
		if typeof(utility) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_UTILITY")
		exact = Utils.validate_exact_fields(utility, UTILITY_FIELDS); if not bool(exact.get("success", false)): return exact
		var network_id := String(utility.get("network_id", ""))
		if network_id.is_empty() or (not previous.is_empty() and network_id < previous) or String(utility.get("profile_checksum", "")).length() != 64: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_UTILITY")
		previous = network_id
	if typeof(value.get("structural_state")) != TYPE_STRING or typeof(value.get("structural_maximum_utilization")) not in [TYPE_INT, TYPE_FLOAT] or float(value["structural_maximum_utilization"]) < 0.0: return _failure("INVALID_CONSTRUCTION_CONSTRUCT_SUMMARY_STRUCTURAL")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_CONSTRUCT_SUMMARY_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
