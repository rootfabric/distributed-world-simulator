extends RefCounted

const SCHEMA: String = "planet_simulator.enet_command_transport_adapter.v1"

var _runtime
var _configured: bool = false
var _commands_sent: int = 0
var _failures: int = 0


func setup(runtime_reference) -> Dictionary:
	if _configured:
		return _failure("ENET_COMMAND_TRANSPORT_ALREADY_CONFIGURED")
	if runtime_reference == null or not runtime_reference.has_method("send_command_blocking"):
		return _failure("ENET_COMMAND_RUNTIME_REQUIRED")
	_runtime = runtime_reference
	_configured = true
	return _success()


func send(command: Dictionary) -> Dictionary:
	if not _configured or _runtime == null:
		return _failure("ENET_COMMAND_TRANSPORT_NOT_CONFIGURED")
	_commands_sent += 1
	var result_value = _runtime.call("send_command_blocking", command.duplicate(true))
	if not result_value is Dictionary:
		_failures += 1
		return _failure("INVALID_ENET_COMMAND_RESULT")
	var result: Dictionary = Dictionary(result_value).duplicate(true)
	if not bool(result.get("success", false)):
		_failures += 1
	return result


func invalidate() -> void:
	_runtime = null
	_configured = false


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"commands_sent": _commands_sent,
		"failures": _failures,
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
