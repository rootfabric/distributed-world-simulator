extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const SCHEMA: String = "planet_simulator.aggregate_mutation_operation.v1"
const OP_CREATE: String = "CREATE"
const OP_UPDATE: String = "UPDATE"
const OP_DELETE: String = "DELETE"
const OPERATION_KINDS: Array[String] = [OP_CREATE, OP_UPDATE, OP_DELETE]
const FIELDS: Array[String] = ["schema", "operation_kind", "aggregate_id", "aggregate_kind", "state_schema", "result_snapshot"]


static func create(operation_kind: String, aggregate_id: String, aggregate_kind: String, state_schema: String, result_snapshot: Dictionary = {}) -> Dictionary:
	return {
		"schema": SCHEMA,
		"operation_kind": operation_kind,
		"aggregate_id": aggregate_id,
		"aggregate_kind": aggregate_kind,
		"state_schema": state_schema,
		"result_snapshot": result_snapshot.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return TxUtilsScript.failure("UNSUPPORTED_AGGREGATE_MUTATION_OPERATION_SCHEMA")
	var kind: String = String(value.get("operation_kind", ""))
	if not OPERATION_KINDS.has(kind):
		return TxUtilsScript.failure("INVALID_AGGREGATE_OPERATION_KIND")
	var aggregate_id: String = String(value.get("aggregate_id", ""))
	var aggregate_kind: String = String(value.get("aggregate_kind", ""))
	var state_schema: String = String(value.get("state_schema", ""))
	if not TxUtilsScript.is_identifier(aggregate_id, "aggregate/") or not TxUtilsScript.is_upper_kind(aggregate_kind) or not TxUtilsScript.is_versioned_schema(state_schema):
		return TxUtilsScript.failure("INVALID_AGGREGATE_OPERATION_IDENTITY")
	if typeof(value.get("result_snapshot")) != TYPE_DICTIONARY:
		return TxUtilsScript.failure("INVALID_AGGREGATE_OPERATION_SNAPSHOT")
	var snapshot: Dictionary = value["result_snapshot"]
	if kind == OP_DELETE:
		if not snapshot.is_empty():
			return TxUtilsScript.failure("DELETE_OPERATION_MUST_NOT_HAVE_RESULT_SNAPSHOT")
		return TxUtilsScript.success()
	var snapshot_validation := SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return TxUtilsScript.failure("INVALID_AGGREGATE_OPERATION_RESULT_SNAPSHOT", {"cause": snapshot_validation})
	var identity: Dictionary = snapshot["descriptor"]["identity"]
	if String(identity["aggregate_id"]) != aggregate_id or String(identity["aggregate_kind"]) != aggregate_kind or String(identity["state_schema"]) != state_schema:
		return TxUtilsScript.failure("AGGREGATE_OPERATION_RESULT_IDENTITY_MISMATCH")
	return TxUtilsScript.success()
