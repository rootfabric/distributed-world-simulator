extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const ResultScript = preload("res://scripts/simulation/transactions/mutation_batch_result.gd")
const OutboxScript = preload("res://scripts/simulation/transactions/outbox_record.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const SCHEMA: String = "planet_simulator.aggregate_transaction_state.v1"
const FIELDS: Array[String] = ["schema", "generation", "previous_generation", "aggregates_by_id", "operation_records_by_id", "outbox_by_id", "checksum"]


static func create(generation: int, previous_generation: int, aggregates: Dictionary, operation_records: Dictionary, outbox: Dictionary) -> Dictionary:
	var value := {"schema": SCHEMA, "generation": generation, "previous_generation": previous_generation, "aggregates_by_id": aggregates.duplicate(true), "operation_records_by_id": operation_records.duplicate(true), "outbox_by_id": outbox.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value


static func empty() -> Dictionary:
	return create(0, -1, {}, {}, {})


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return TxUtilsScript.failure("UNSUPPORTED_AGGREGATE_TRANSACTION_STATE_SCHEMA")
	for field in ["generation", "previous_generation"]:
		if not UtilsScript.is_json_integer(value.get(field)): return TxUtilsScript.failure("INVALID_TRANSACTION_STATE_GENERATION")
	if int(value["generation"]) < 0 or int(value["previous_generation"]) != int(value["generation"]) - 1: return TxUtilsScript.failure("INVALID_TRANSACTION_STATE_GENERATION_CHAIN")
	for field in ["aggregates_by_id", "operation_records_by_id", "outbox_by_id"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY: return TxUtilsScript.failure("INVALID_TRANSACTION_STATE_COLLECTION")
	for aggregate_id in value["aggregates_by_id"]:
		var snapshot = value["aggregates_by_id"][aggregate_id]
		if typeof(aggregate_id) != TYPE_STRING or typeof(snapshot) != TYPE_DICTIONARY or String(aggregate_id) != SnapshotScript.aggregate_id(snapshot) or not bool(SnapshotScript.validate(snapshot).get("success", false)):
			return TxUtilsScript.failure("INVALID_TRANSACTION_STATE_AGGREGATE")
	var referenced_outbox_by_id: Dictionary = {}
	for operation_id in value["operation_records_by_id"]:
		var record = value["operation_records_by_id"][operation_id]
		if typeof(record) != TYPE_DICTIONARY or record.keys().size() != 2 or not record.has("batch_checksum") or not record.has("result") or not TxUtilsScript.is_lower_hex_64(String(record["batch_checksum"])) or not bool(ResultScript.validate(record["result"]).get("success", false)) or String(record["result"].get("operation_id", "")) != String(operation_id):
			return TxUtilsScript.failure("INVALID_TRANSACTION_OPERATION_RECORD")
		var result: Dictionary = record["result"]
		if int(result["commit_generation"]) > int(value["generation"]):
			return TxUtilsScript.failure("TRANSACTION_RESULT_GENERATION_AHEAD_OF_STATE")
		for outbox_id in result["outbox_record_ids"]:
			if referenced_outbox_by_id.has(outbox_id):
				return TxUtilsScript.failure("TRANSACTION_OUTBOX_RECORD_REFERENCED_TWICE")
			referenced_outbox_by_id[outbox_id] = {
				"batch_id": String(result["batch_id"]),
				"operation_id": String(operation_id),
				"commit_generation": int(result["commit_generation"]),
				"committed_at_tick": int(result["committed_at_tick"]),
			}
	for record_id in value["outbox_by_id"]:
		var record = value["outbox_by_id"][record_id]
		if typeof(record) != TYPE_DICTIONARY or String(record_id) != String(record.get("record_id", "")) or not bool(OutboxScript.validate(record).get("success", false)):
			return TxUtilsScript.failure("INVALID_TRANSACTION_OUTBOX_RECORD")
		if not referenced_outbox_by_id.has(record_id):
			return TxUtilsScript.failure("ORPHAN_TRANSACTION_OUTBOX_RECORD")
		var reference: Dictionary = referenced_outbox_by_id[record_id]
		if String(record["batch_id"]) != String(reference["batch_id"]) or String(record["operation_id"]) != String(reference["operation_id"]) or int(record["commit_generation"]) != int(reference["commit_generation"]) or int(record["created_at_tick"]) != int(reference["committed_at_tick"]):
			return TxUtilsScript.failure("TRANSACTION_OUTBOX_RESULT_MISMATCH")
	for referenced_id in referenced_outbox_by_id:
		if not value["outbox_by_id"].has(referenced_id):
			return TxUtilsScript.failure("TRANSACTION_RESULT_OUTBOX_RECORD_MISSING")
	if not TxUtilsScript.is_lower_hex_64(String(value.get("checksum", ""))) or String(value["checksum"]) != compute_checksum(value): return TxUtilsScript.failure("TRANSACTION_STATE_CHECKSUM_MISMATCH")
	return TxUtilsScript.success()
