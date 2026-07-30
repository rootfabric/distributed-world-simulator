extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const SCHEMA := "planet_simulator.networked_gameplay_command_result.v1"
const FIELDS: Array[String] = ["schema", "message_id", "operation_id", "status", "error_code", "authority_epoch", "result_revision", "payload"]
const STATUSES := ["SUCCEEDED", "REJECTED", "RETRYABLE"]

static func create(message_id: String, operation_id: String, status: String, error_code: String, authority_epoch: int, result_revision: int, payload: Dictionary) -> Dictionary:
	return Wire.create(SCHEMA, {"message_id": message_id, "operation_id": operation_id, "status": status, "error_code": error_code, "authority_epoch": authority_epoch, "result_revision": result_revision, "payload": payload.duplicate(true)})

static func validate(value: Dictionary) -> Dictionary:
	if not bool(Wire.validate(value, SCHEMA, FIELDS).get("success", false)): return Wire.failure("INVALID_GAMEPLAY_COMMAND_RESULT")
	for pair in [["message_id", "message"], ["operation_id", "operation"]]:
		if not bool(Wire.require_id(value, pair[0], pair[1]).get("success", false)): return Wire.failure("INVALID_GAMEPLAY_COMMAND_RESULT")
	if String(value.get("status", "")) not in STATUSES or typeof(value.get("error_code")) != TYPE_STRING or not value.get("payload") is Dictionary: return Wire.failure("INVALID_GAMEPLAY_COMMAND_RESULT")
	if not bool(Wire.require_positive_integer(value, "authority_epoch").get("success", false)) or not bool(Wire.require_positive_integer(value, "result_revision", true).get("success", false)): return Wire.failure("INVALID_GAMEPLAY_COMMAND_RESULT")
	if String(value.get("status", "")) == "SUCCEEDED" and not String(value.get("error_code", "")).is_empty(): return Wire.failure("INVALID_GAMEPLAY_COMMAND_RESULT")
	return Wire.success()
