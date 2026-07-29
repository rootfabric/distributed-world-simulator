extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")

const SCHEMA: String = "planet_simulator.affected_aggregate_result.v1"
const FIELDS: Array[String] = ["schema", "aggregate_id", "operation_kind", "previous_revision", "result_revision", "result_checksum"]


static func create(aggregate_id: String, operation_kind: String, previous_revision: int, result_revision: int, result_checksum: String) -> Dictionary:
	return {"schema": SCHEMA, "aggregate_id": aggregate_id, "operation_kind": operation_kind, "previous_revision": previous_revision, "result_revision": result_revision, "result_checksum": result_checksum}


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not TxUtilsScript.is_identifier(String(value.get("aggregate_id", "")), "aggregate/") or not OperationScript.OPERATION_KINDS.has(String(value.get("operation_kind", ""))):
		return TxUtilsScript.failure("INVALID_AFFECTED_AGGREGATE_RESULT")
	if not UtilsScript.is_json_integer(value.get("previous_revision")) or not UtilsScript.is_json_integer(value.get("result_revision")):
		return TxUtilsScript.failure("INVALID_AFFECTED_AGGREGATE_REVISION")
	var kind: String = String(value["operation_kind"])
	if kind == OperationScript.OP_CREATE and (int(value["previous_revision"]) != -1 or int(value["result_revision"]) != 0): return TxUtilsScript.failure("INVALID_CREATE_RESULT_REVISION")
	if kind == OperationScript.OP_UPDATE and int(value["result_revision"]) != int(value["previous_revision"]) + 1: return TxUtilsScript.failure("INVALID_UPDATE_RESULT_REVISION")
	if kind == OperationScript.OP_DELETE and int(value["result_revision"]) != -1: return TxUtilsScript.failure("INVALID_DELETE_RESULT_REVISION")
	var checksum: String = String(value.get("result_checksum", ""))
	if kind == OperationScript.OP_DELETE:
		if checksum != "": return TxUtilsScript.failure("DELETE_RESULT_CHECKSUM_MUST_BE_EMPTY")
	elif not TxUtilsScript.is_lower_hex_64(checksum): return TxUtilsScript.failure("INVALID_AFFECTED_AGGREGATE_CHECKSUM")
	return TxUtilsScript.success()
