extends RefCounted

const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const AGGREGATE_KIND: String = "TEST_TRANSACTION_AGGREGATE"
const STATE_SCHEMA: String = "planet_simulator.test_transaction_aggregate_state.v1"
const ROLES: Array[String] = ["CONTAINER", "ITEM", "FIELD"]


func get_aggregate_kind() -> String:
	return AGGREGATE_KIND


func supports_aggregate(_value) -> bool:
	return false


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var envelope := SnapshotScript.validate(snapshot)
	if not bool(envelope.get("success", false)):
		return envelope
	var identity: Dictionary = snapshot["descriptor"]["identity"]
	if String(identity["aggregate_kind"]) != AGGREGATE_KIND or String(identity["state_schema"]) != STATE_SCHEMA:
		return _failure("TEST_TRANSACTION_IDENTITY_MISMATCH")
	var state: Dictionary = snapshot["state"]
	var exact := UtilsScript.validate_exact_fields(state, ["role", "container_id", "members_by_id", "quantity", "metadata"])
	if not bool(exact.get("success", false)):
		return _failure("INVALID_TEST_TRANSACTION_STATE")
	if typeof(state["role"]) != TYPE_STRING or not ROLES.has(String(state["role"])):
		return _failure("INVALID_TEST_TRANSACTION_ROLE")
	if typeof(state["container_id"]) != TYPE_STRING or typeof(state["members_by_id"]) != TYPE_DICTIONARY or typeof(state["metadata"]) != TYPE_DICTIONARY:
		return _failure("INVALID_TEST_TRANSACTION_STATE_TYPE")
	if not UtilsScript.is_json_integer(state["quantity"]) or int(state["quantity"]) < 0:
		return _failure("INVALID_TEST_TRANSACTION_QUANTITY")
	for member_id in state["members_by_id"]:
		if typeof(member_id) != TYPE_STRING or not String(member_id).begins_with("aggregate/") or typeof(state["members_by_id"][member_id]) != TYPE_BOOL or not bool(state["members_by_id"][member_id]):
			return _failure("INVALID_TEST_TRANSACTION_MEMBER")
	if String(state["role"]) == "ITEM" and (not state["members_by_id"].is_empty() or int(state["quantity"]) < 1):
		return _failure("INVALID_TEST_TRANSACTION_ITEM")
	if String(state["role"]) != "ITEM" and not String(state["container_id"]).is_empty():
		return _failure("NON_ITEM_CONTAINER_REFERENCE")
	return _success()


func validate_delta(delta: Dictionary) -> Dictionary:
	var validation := DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return validation
	if String(delta["aggregate_kind"]) != AGGREGATE_KIND or String(delta["state_schema"]) != STATE_SCHEMA:
		return _failure("TEST_TRANSACTION_DELTA_IDENTITY_MISMATCH")
	return _success()


func export_snapshot(_aggregate, _snapshot_id: String) -> Dictionary:
	return {}


func export_delta(_base_snapshot: Dictionary, _aggregate, _delta_id: String) -> Dictionary:
	return {}


func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
