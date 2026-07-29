extends RefCounted

const CommandEnvelope = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultEnvelope = preload("res://scripts/network/contracts/network_command_result_envelope.gd")

const SCHEMA: String = "planet_simulator.playable_authority_gateway_adapter.v1"

var _authority
var _configured: bool = false
var _command_count: int = 0
var _rejection_count: int = 0


func setup(authority_reference) -> Dictionary:
	if _configured:
		return _failure("PLAYABLE_AUTHORITY_ADAPTER_ALREADY_CONFIGURED")
	if authority_reference == null or not authority_reference.has_method("handle_command"):
		return _failure("PLAYABLE_AUTHORITY_HANDLER_REQUIRED")
	if not authority_reference.has_method("get_report"):
		return _failure("PLAYABLE_AUTHORITY_REPORT_REQUIRED")
	_authority = authority_reference
	_configured = true
	return _success()


func handle(command: Dictionary) -> Dictionary:
	if not _configured:
		return ResultEnvelope.create(
			String(command.get("message_id", "message/h1/unconfigured")),
			String(command.get("operation_id", "operation/h1/unconfigured")),
			"RETRYABLE",
			"PLAYABLE_AUTHORITY_ADAPTER_NOT_CONFIGURED",
			-1,
			1,
			{}
		)
	var validation: Dictionary = CommandEnvelope.validate(command)
	if not bool(validation.get("success", false)):
		_rejection_count += 1
		return ResultEnvelope.create(
			String(command.get("message_id", "message/h1/invalid")),
			String(command.get("operation_id", "operation/h1/invalid")),
			"REJECTED",
			String(validation.get("error_code", "INVALID_COMMAND")),
			-1,
			maxi(1, int(_authority.get_report().get("authority_epoch", 1))),
			{}
		)
	_command_count += 1
	var result_value = _authority.handle_command(command.duplicate(true))
	if not result_value is Dictionary:
		_rejection_count += 1
		return ResultEnvelope.create(
			String(command["message_id"]),
			String(command["operation_id"]),
			"RETRYABLE",
			"INVALID_PLAYABLE_AUTHORITY_RESULT",
			-1,
			maxi(1, int(_authority.get_report().get("authority_epoch", 1))),
			{}
		)
	var result: Dictionary = Dictionary(result_value).duplicate(true)
	var result_validation: Dictionary = ResultEnvelope.validate(result)
	if not bool(result_validation.get("success", false)):
		_rejection_count += 1
		return ResultEnvelope.create(
			String(command["message_id"]),
			String(command["operation_id"]),
			"RETRYABLE",
			"INVALID_PLAYABLE_AUTHORITY_RESULT",
			-1,
			maxi(1, int(_authority.get_report().get("authority_epoch", 1))),
			{"validation_error_code": String(result_validation.get("error_code", ""))}
		)
	if String(result.get("status", "")) != "SUCCEEDED":
		_rejection_count += 1
	return result


func get_authority_report() -> Dictionary:
	return _authority.get_report().duplicate(true) if _configured else {}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"command_count": _command_count,
		"rejection_count": _rejection_count,
		"direct_presentation_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
