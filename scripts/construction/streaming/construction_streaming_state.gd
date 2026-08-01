extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Record = preload("res://scripts/construction/streaming/construction_activity_record.gd")
const Summary = preload("res://scripts/construction/streaming/construction_construct_summary.gd")
const SCHEMA := "planet_simulator.construction_streaming_state.v1"
const OP_FIELDS: Array[String] = ["tick", "input_checksum", "report"]
const FIELDS: Array[String] = ["schema", "tick", "generation", "policy_checksum", "records", "summaries", "reconcile_operations", "checksum"]

static func create(tick: int, generation: int, policy_checksum: String, records: Array, summaries: Array, operations: Array) -> Dictionary:
	var value := {"schema": SCHEMA, "tick": tick, "generation": generation, "policy_checksum": policy_checksum, "records": _sorted(records, "construct_id"), "summaries": _sorted(summaries, "construct_id"), "reconcile_operations": _sorted(operations, "tick"), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STREAMING_STATE_SCHEMA")
	for field in ["tick", "generation"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_INTEGER")
	if String(value.get("policy_checksum", "")).length() != 64: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_POLICY")
	if typeof(value.get("records")) != TYPE_ARRAY or typeof(value.get("summaries")) != TYPE_ARRAY or typeof(value.get("reconcile_operations")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_COLLECTIONS")
	var seen := {}; var previous := ""
	for row in value["records"]:
		if typeof(row) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_RECORD")
		var checked := Record.validate(row); if not bool(checked.get("success", false)): return checked
		var id := String(row["construct_id"]); if seen.has(id) or (not previous.is_empty() and id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STREAMING_STATE_RECORDS")
		seen[id] = true; previous = id
	seen.clear(); previous = ""
	for row in value["summaries"]:
		if typeof(row) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_SUMMARY")
		var checked := Summary.validate(row); if not bool(checked.get("success", false)): return checked
		var id := String(row["construct_id"]); if seen.has(id) or (not previous.is_empty() and id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STREAMING_STATE_SUMMARIES")
		if not _record_has(value["records"], id): return _failure("CONSTRUCTION_STREAMING_SUMMARY_WITHOUT_RECORD")
		seen[id] = true; previous = id
	var previous_tick := -1
	for row in value["reconcile_operations"]:
		if typeof(row) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_OPERATION")
		exact = Utils.validate_exact_fields(row, OP_FIELDS); if not bool(exact.get("success", false)): return exact
		if not Utils.is_json_integer(row.get("tick")) or int(row["tick"]) < 0 or int(row["tick"]) <= previous_tick: return _failure("NON_CANONICAL_CONSTRUCTION_STREAMING_STATE_OPERATIONS")
		if String(row.get("input_checksum", "")).length() != 64 or typeof(row.get("report")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_STATE_OPERATION")
		previous_tick = int(row["tick"])
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STREAMING_STATE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _record_has(records: Array, id: String) -> bool:
	for row in records:
		if String(row.get("construct_id", "")) == id: return true
	return false
static func _sorted(values: Array, key: String) -> Array:
	var result := values.duplicate(true); result.sort_custom(func(a,b):
		if key == "tick": return int(a.get(key,0)) < int(b.get(key,0))
		return String(a.get(key,"")) < String(b.get(key,"")))
	return result
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
