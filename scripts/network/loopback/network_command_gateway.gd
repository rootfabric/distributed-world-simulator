extends RefCounted

const CommandEnvelopeScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultEnvelopeScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const INVALID_MESSAGE_ID: String = "message/invalid"
const INVALID_OPERATION_ID: String = "operation/invalid"

const HANDLER_RESULT_FIELDS: Array[String] = [
	"success",
	"retryable",
	"error_code",
	"result_revision",
	"payload",
]

var handlers: Dictionary = {}
var completed_operations: Dictionary = {}
var default_authority_epoch: int = 1
var authority_epoch_resolver: Callable


func setup(authority_epoch: int = 1, resolver: Callable = Callable()) -> void:
	handlers.clear()
	completed_operations.clear()
	default_authority_epoch = maxi(1, authority_epoch)
	authority_epoch_resolver = resolver


func register_handler(command_type: String, callback: Callable) -> bool:
	var normalized: String = command_type.strip_edges()
	if normalized.is_empty() or not callback.is_valid() or handlers.has(normalized):
		return false
	handlers[normalized] = callback
	return true


func handle(envelope_value: Dictionary) -> Dictionary:
	var validation: Dictionary = CommandEnvelopeScript.validate(envelope_value)
	if not bool(validation.get("success", false)):
		return _result(
			envelope_value,
			"REJECTED",
			String(validation.get("error_code", "INVALID_ENVELOPE")),
			-1,
			default_authority_epoch,
			{"message": String(validation.get("message", ""))}
		)
	var envelope: Dictionary = CommandEnvelopeScript.normalize(envelope_value)
	var operation_id: String = String(envelope["operation_id"])
	var fingerprint: String = CommandEnvelopeScript.command_fingerprint(envelope)
	if completed_operations.has(operation_id):
		var completed: Dictionary = completed_operations[operation_id]
		if String(completed.get("fingerprint", "")) == fingerprint:
			var replay_result: Dictionary = completed.get("result", {}).duplicate(true)
			replay_result["message_id"] = String(envelope["message_id"])
			return replay_result
		return _result(
			envelope,
			"REJECTED",
			"OPERATION_ID_CONFLICT",
			int(completed.get("result_revision", -1)),
			_resolve_authority_epoch(String(envelope["entity_id"])),
			{}
		)
	var entity_id: String = String(envelope["entity_id"])
	var actual_epoch: int = _resolve_authority_epoch(entity_id)
	if int(envelope["authority_epoch"]) != actual_epoch:
		var stale_result: Dictionary = _result(
			envelope,
			"REJECTED",
			"STALE_AUTHORITY_EPOCH",
			-1,
			actual_epoch,
			{"received_authority_epoch": int(envelope["authority_epoch"])}
		)
		_store_validated(operation_id, fingerprint, stale_result)
		return stale_result
	var command_type: String = String(envelope["command_type"])
	if not handlers.has(command_type):
		var unknown_result: Dictionary = _result(
			envelope,
			"REJECTED",
			"UNKNOWN_COMMAND_TYPE",
			-1,
			actual_epoch,
			{}
		)
		_store_validated(operation_id, fingerprint, unknown_result)
		return unknown_result
	var callback: Callable = handlers[command_type]
	var raw_result = callback.call(
		envelope["payload"].duplicate(true),
		envelope.duplicate(true)
	)
	var handler_validation: Dictionary = _validate_handler_result(raw_result)
	if not bool(handler_validation.get("success", false)):
		var invalid_result: Dictionary = _invalid_handler_result(
			envelope,
			actual_epoch,
			raw_result,
			String(handler_validation.get("error_code", "INVALID_HANDLER_RESULT")),
			String(handler_validation.get("message", "Handler returned an invalid result"))
		)
		_store_validated(operation_id, fingerprint, invalid_result)
		return invalid_result
	var handler_result: Dictionary = raw_result
	var succeeded: bool = bool(handler_result["success"])
	var retryable: bool = bool(handler_result.get("retryable", false))
	var status: String = "SUCCEEDED" if succeeded else ("RETRYABLE" if retryable else "REJECTED")
	var result: Dictionary = _result(
		envelope,
		status,
		String(handler_result.get("error_code", "")),
		int(handler_result["result_revision"]),
		actual_epoch,
		handler_result.get("payload", {}).duplicate(true)
	)
	var result_validation: Dictionary = ResultEnvelopeScript.validate(result)
	if not bool(result_validation.get("success", false)):
		var invalid_envelope_result: Dictionary = _invalid_handler_result(
			envelope,
			actual_epoch,
			handler_result,
			String(result_validation.get("error_code", "INVALID_HANDLER_RESULT")),
			String(result_validation.get("message", "Result envelope is invalid"))
		)
		_store_validated(operation_id, fingerprint, invalid_envelope_result)
		return invalid_envelope_result
	if status in ["SUCCEEDED", "REJECTED"]:
		_store_validated(operation_id, fingerprint, result)
	return result


func _resolve_authority_epoch(entity_id: String) -> int:
	if authority_epoch_resolver.is_valid():
		return maxi(1, int(authority_epoch_resolver.call(entity_id)))
	return default_authority_epoch


func _validate_handler_result(raw_result) -> Dictionary:
	if not raw_result is Dictionary:
		return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", "Handler result must be a Dictionary")
	var result: Dictionary = raw_result
	for key in ["success", "result_revision"]:
		if not result.has(key):
			return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", "Handler result is missing: %s" % key)
	for raw_key in result.keys():
		if typeof(raw_key) != TYPE_STRING or not HANDLER_RESULT_FIELDS.has(String(raw_key)):
			return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", "Unexpected handler result field: %s" % String(raw_key))
	var check: Dictionary = UtilsScript.require_boolean(result, "success")
	if not bool(check.get("success", false)):
		return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", String(check.get("message", "success must be Boolean")))
	if result.has("retryable"):
		check = UtilsScript.require_boolean(result, "retryable")
		if not bool(check.get("success", false)):
			return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", String(check.get("message", "retryable must be Boolean")))
	if bool(result["success"]) and bool(result.get("retryable", false)):
		return UtilsScript.validation_failure(
			"INVALID_HANDLER_RESULT",
			"Handler result cannot be both successful and retryable"
		)
	if result.has("error_code"):
		check = UtilsScript.require_string(result, "error_code", true)
		if not bool(check.get("success", false)):
			return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", String(check.get("message", "error_code must be String")))
	check = UtilsScript.require_json_integer(result, "result_revision")
	if not bool(check.get("success", false)) or int(result["result_revision"]) < -1:
		return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", "result_revision must be an integer-valued number >= -1")
	if result.has("payload"):
		check = UtilsScript.require_dictionary(result, "payload")
		if not bool(check.get("success", false)):
			return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", String(check.get("message", "payload must be Dictionary")))
		var safe: Dictionary = UtilsScript.canonicalize(result["payload"], "$.handler_result.payload")
		if not bool(safe.get("success", false)):
			return UtilsScript.validation_failure("INVALID_HANDLER_RESULT", String(safe.get("error", "Handler payload is not JSON-safe")))
	return UtilsScript.validation_success()


func _invalid_handler_result(
	envelope: Dictionary,
	authority_epoch: int,
	raw_result,
	validation_error_code: String,
	validation_message: String
) -> Dictionary:
	var reported_revision: int = -1
	if raw_result is Dictionary:
		var candidate = raw_result.get("result_revision")
		if UtilsScript.is_json_integer(candidate) and int(candidate) >= -1:
			reported_revision = int(candidate)
	return _result(
		envelope,
		"REJECTED",
		"INVALID_HANDLER_RESULT",
		reported_revision,
		authority_epoch,
		{
			"handler_validation_error": validation_error_code,
			"message": validation_message,
			"requires_snapshot": true,
		}
	)


func _store_validated(operation_id: String, fingerprint: String, result: Dictionary) -> bool:
	var validation: Dictionary = ResultEnvelopeScript.validate(result)
	if not bool(validation.get("success", false)):
		return false
	completed_operations[operation_id] = {
		"fingerprint": fingerprint,
		"result_revision": int(result["result_revision"]),
		"result": result.duplicate(true),
	}
	return true


func _result(
	envelope: Dictionary,
	status: String,
	error_code: String,
	result_revision: int,
	authority_epoch: int,
	payload: Dictionary
) -> Dictionary:
	return ResultEnvelopeScript.create(
		_safe_correlation_id(envelope, "message_id", INVALID_MESSAGE_ID),
		_safe_correlation_id(envelope, "operation_id", INVALID_OPERATION_ID),
		status,
		error_code,
		result_revision,
		authority_epoch,
		payload
	)


func _safe_correlation_id(envelope: Dictionary, field: String, fallback: String) -> String:
	var candidate = envelope.get(field)
	if typeof(candidate) == TYPE_STRING and not String(candidate).strip_edges().is_empty():
		return String(candidate)
	return fallback
