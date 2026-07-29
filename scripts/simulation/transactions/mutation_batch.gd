extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")
const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const IntentScript = preload("res://scripts/simulation/transactions/outbox_intent.gd")

const SCHEMA: String = "planet_simulator.mutation_batch.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "batch_id", "operation_id", "authority_owner_id", "authority_epoch",
	"server_tick", "preconditions", "operations", "outbox_intents", "checksum",
]


static func create(batch_id: String, operation_id: String, authority_owner_id: String, authority_epoch: int, server_tick: int, preconditions: Array, operations: Array, outbox_intents: Array = []) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"batch_id": batch_id,
		"operation_id": operation_id,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"server_tick": server_tick,
		"preconditions": preconditions.duplicate(true),
		"operations": operations.duplicate(true),
		"outbox_intents": outbox_intents.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not UtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return TxUtilsScript.failure("UNSUPPORTED_MUTATION_BATCH_SCHEMA")
	if not TxUtilsScript.is_identifier(String(value.get("batch_id", "")), "batch/") or not TxUtilsScript.is_identifier(String(value.get("operation_id", "")), "operation/") or not TxUtilsScript.is_identifier(String(value.get("authority_owner_id", ""))):
		return TxUtilsScript.failure("INVALID_MUTATION_BATCH_IDENTITY")
	if not UtilsScript.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1 or not UtilsScript.is_json_integer(value.get("server_tick")) or int(value["server_tick"]) < 0:
		return TxUtilsScript.failure("INVALID_MUTATION_BATCH_AUTHORITY")
	for field in ["preconditions", "operations", "outbox_intents"]:
		if typeof(value.get(field)) != TYPE_ARRAY:
			return TxUtilsScript.failure("INVALID_MUTATION_BATCH_COLLECTION", {"field": field})
	if value["operations"].is_empty() or value["preconditions"].size() != value["operations"].size():
		return TxUtilsScript.failure("MUTATION_BATCH_OPERATION_PRECONDITION_MISMATCH")
	var precondition_ids: Array[String] = []
	for raw in value["preconditions"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return TxUtilsScript.failure("INVALID_MUTATION_BATCH_PRECONDITION")
		var validation := PreconditionScript.validate(raw)
		if not bool(validation.get("success", false)):
			return validation
		precondition_ids.append(String(raw["aggregate_id"]))
	var operation_ids: Array[String] = []
	for raw in value["operations"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return TxUtilsScript.failure("INVALID_MUTATION_BATCH_OPERATION")
		var validation := OperationScript.validate(raw)
		if not bool(validation.get("success", false)):
			return validation
		operation_ids.append(String(raw["aggregate_id"]))
	var sorted_preconditions := precondition_ids.duplicate(); sorted_preconditions.sort()
	var sorted_operations := operation_ids.duplicate(); sorted_operations.sort()
	if precondition_ids != sorted_preconditions or operation_ids != sorted_operations:
		return TxUtilsScript.failure("MUTATION_BATCH_AGGREGATES_NOT_SORTED")
	if _has_duplicates(precondition_ids) or _has_duplicates(operation_ids) or precondition_ids != operation_ids:
		return TxUtilsScript.failure("MUTATION_BATCH_AGGREGATE_SET_CONFLICT")
	var preconditions_by_id: Dictionary = {}
	for precondition in value["preconditions"]: preconditions_by_id[String(precondition["aggregate_id"])] = precondition
	for operation in value["operations"]:
		var precondition: Dictionary = preconditions_by_id[String(operation["aggregate_id"])]
		if String(precondition["aggregate_kind"]) != String(operation["aggregate_kind"]) or String(precondition["state_schema"]) != String(operation["state_schema"]):
			return TxUtilsScript.failure("MUTATION_BATCH_PRECONDITION_IDENTITY_MISMATCH")
		var expects_exists: bool = String(operation["operation_kind"]) != OperationScript.OP_CREATE
		if bool(precondition["expected_exists"]) != expects_exists:
			return TxUtilsScript.failure("MUTATION_BATCH_PRECONDITION_EXISTENCE_MISMATCH")
	var intent_ids: Array[String] = []
	for raw in value["outbox_intents"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return TxUtilsScript.failure("INVALID_MUTATION_BATCH_OUTBOX_INTENT")
		var validation := IntentScript.validate(raw)
		if not bool(validation.get("success", false)):
			return validation
		intent_ids.append(String(raw["intent_id"]))
	var sorted_intents := intent_ids.duplicate(); sorted_intents.sort()
	if intent_ids != sorted_intents or _has_duplicates(intent_ids):
		return TxUtilsScript.failure("MUTATION_BATCH_OUTBOX_INTENTS_NOT_CANONICAL")
	if not TxUtilsScript.is_lower_hex_64(String(value.get("checksum", ""))) or String(value["checksum"]) != compute_checksum(value):
		return TxUtilsScript.failure("MUTATION_BATCH_CHECKSUM_MISMATCH")
	return TxUtilsScript.success()


static func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value): return true
		seen[value] = true
	return false
