extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA := "planet_simulator.matter_cross_region_operation_result.v1"
const OUTCOME_COMMITTED := "COMMITTED"
const OUTCOME_ABORTED := "ABORTED"
const OUTCOMES: Array[String] = [OUTCOME_COMMITTED, OUTCOME_ABORTED]
const FIELDS: Array[String] = [
	"schema", "operation_id", "transaction_id", "plan_checksum", "outcome",
	"terminal_record_checksum", "global_commit_hash", "invalidation_batch_checksum",
	"completed_tick", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"operation_id": String(data.get("operation_id", "")).strip_edges().to_lower(),
		"transaction_id": String(data.get("transaction_id", "")).strip_edges().to_lower(),
		"plan_checksum": String(data.get("plan_checksum", "")).strip_edges().to_lower(),
		"outcome": String(data.get("outcome", "")).strip_edges().to_upper(),
		"terminal_record_checksum": String(data.get("terminal_record_checksum", "")).strip_edges().to_lower(),
		"global_commit_hash": String(data.get("global_commit_hash", "")).strip_edges().to_lower(),
		"invalidation_batch_checksum": String(data.get("invalidation_batch_checksum", "")).strip_edges().to_lower(),
		"completed_tick": int(data.get("completed_tick", 0)),
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_OPERATION_RESULT_SCHEMA")
	for field in ["operation_id", "transaction_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OPERATION_RESULT_ID", {"field": field})
	for field in ["plan_checksum", "terminal_record_checksum"]:
		if not MatterUtils.is_lower_hex_64(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OPERATION_RESULT_HASH", {"field": field})
	var outcome: String = String(value.get("outcome", ""))
	if not outcome in OUTCOMES:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OPERATION_OUTCOME")
	var global_hash: String = String(value.get("global_commit_hash", ""))
	var invalidation_hash: String = String(value.get("invalidation_batch_checksum", ""))
	if outcome == OUTCOME_COMMITTED:
		if not MatterUtils.is_lower_hex_64(global_hash) or not MatterUtils.is_lower_hex_64(invalidation_hash):
			return MatterUtils.failure("MATTER_CROSS_REGION_COMMITTED_RESULT_HASH_REQUIRED")
	elif not global_hash.is_empty() or not invalidation_hash.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_ABORTED_RESULT_HAS_COMMIT_HASH")
	if not MatterUtils.is_json_integer(value.get("completed_tick")) or int(value["completed_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OPERATION_RESULT_TICK")
	return MatterUtils.validate_checksum(value)
