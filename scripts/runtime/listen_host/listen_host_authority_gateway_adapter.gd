extends RefCounted

const SCHEMA: String = "planet_simulator.listen_host_authority_gateway_adapter.v1"

var _authority


func setup(authority_reference) -> Dictionary:
	if authority_reference == null or not authority_reference is RefCounted:
		return _failure("INVALID_AUTHORITY_REFERENCE")
	for method_name in ["handle_command", "get_delta", "create_snapshot", "get_report"]:
		if not authority_reference.has_method(method_name):
			return _failure("AUTHORITY_METHOD_MISSING", {"method": method_name})
	_authority = authority_reference
	return _success()


func handle(envelope: Dictionary) -> Dictionary:
	if _authority == null:
		return _failure("AUTHORITY_ADAPTER_NOT_CONFIGURED")
	var result = _authority.call("handle_command", envelope.duplicate(true))
	if not result is Dictionary:
		return _failure("INVALID_AUTHORITY_RESULT")
	return Dictionary(result).duplicate(true)


func get_delta(operation_id: String) -> Dictionary:
	if _authority == null:
		return {}
	var value = _authority.call("get_delta", operation_id)
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func create_snapshot() -> Dictionary:
	if _authority == null:
		return {}
	var value = _authority.call("create_snapshot")
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func get_authority_report() -> Dictionary:
	if _authority == null:
		return {}
	var value = _authority.call("get_report")
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _authority != null,
		"exposes_domain_objects": false,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
