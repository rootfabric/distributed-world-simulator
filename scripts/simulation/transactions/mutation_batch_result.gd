extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")
const AffectedScript = preload("res://scripts/simulation/transactions/affected_aggregate_result.gd")

const SCHEMA: String = "planet_simulator.mutation_batch_result.v1"
const FIELDS: Array[String] = ["schema", "batch_id", "operation_id", "commit_generation", "committed_at_tick", "affected_aggregates", "created_aggregate_ids", "updated_aggregate_ids", "deleted_aggregate_ids", "outbox_record_ids", "checksum"]


static func create(batch_id: String, operation_id: String, generation: int, tick: int, affected: Array, created: Array[String], updated: Array[String], deleted: Array[String], outbox_ids: Array[String]) -> Dictionary:
	var value := {"schema": SCHEMA, "batch_id": batch_id, "operation_id": operation_id, "commit_generation": generation, "committed_at_tick": tick, "affected_aggregates": affected.duplicate(true), "created_aggregate_ids": created.duplicate(), "updated_aggregate_ids": updated.duplicate(), "deleted_aggregate_ids": deleted.duplicate(), "outbox_record_ids": outbox_ids.duplicate(), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not TxUtilsScript.is_identifier(String(value.get("batch_id", "")), "batch/") or not TxUtilsScript.is_identifier(String(value.get("operation_id", "")), "operation/"):
		return TxUtilsScript.failure("INVALID_MUTATION_BATCH_RESULT_IDENTITY")
	for field in ["commit_generation", "committed_at_tick"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return TxUtilsScript.failure("INVALID_MUTATION_BATCH_RESULT_INTEGER")
	if int(value["commit_generation"]) < 1: return TxUtilsScript.failure("INVALID_MUTATION_BATCH_RESULT_GENERATION")
	for field in ["affected_aggregates", "created_aggregate_ids", "updated_aggregate_ids", "deleted_aggregate_ids", "outbox_record_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return TxUtilsScript.failure("INVALID_MUTATION_BATCH_RESULT_COLLECTION")
	var affected_ids: Array[String] = []
	var expected_created: Array[String] = []
	var expected_updated: Array[String] = []
	var expected_deleted: Array[String] = []
	for affected in value["affected_aggregates"]:
		if typeof(affected) != TYPE_DICTIONARY or not bool(AffectedScript.validate(affected).get("success", false)): return TxUtilsScript.failure("INVALID_AFFECTED_AGGREGATE_RESULT")
		var aggregate_id: String = String(affected["aggregate_id"])
		affected_ids.append(aggregate_id)
		match String(affected["operation_kind"]):
			"CREATE": expected_created.append(aggregate_id)
			"UPDATE": expected_updated.append(aggregate_id)
			"DELETE": expected_deleted.append(aggregate_id)
	var sorted_affected := affected_ids.duplicate(); sorted_affected.sort()
	if affected_ids != sorted_affected or _has_duplicates(affected_ids): return TxUtilsScript.failure("NON_CANONICAL_AFFECTED_AGGREGATE_RESULTS")
	for field in ["created_aggregate_ids", "updated_aggregate_ids", "deleted_aggregate_ids", "outbox_record_ids"]:
		var strings: Array[String] = []
		for raw in value[field]:
			if typeof(raw) != TYPE_STRING or not TxUtilsScript.is_identifier(String(raw)): return TxUtilsScript.failure("INVALID_MUTATION_BATCH_RESULT_ID")
			strings.append(String(raw))
		var sorted := strings.duplicate(); sorted.sort()
		if strings != sorted or _has_duplicates(strings): return TxUtilsScript.failure("NON_CANONICAL_MUTATION_BATCH_RESULT_IDS")
	if value["created_aggregate_ids"] != expected_created or value["updated_aggregate_ids"] != expected_updated or value["deleted_aggregate_ids"] != expected_deleted:
		return TxUtilsScript.failure("MUTATION_BATCH_RESULT_EFFECT_SET_MISMATCH")
	if not TxUtilsScript.is_lower_hex_64(String(value.get("checksum", ""))) or String(value["checksum"]) != compute_checksum(value): return TxUtilsScript.failure("MUTATION_BATCH_RESULT_CHECKSUM_MISMATCH")
	return TxUtilsScript.success()


static func _has_duplicates(values: Array[String]) -> bool:
	var seen := {}
	for value in values:
		if seen.has(value): return true
		seen[value] = true
	return false
