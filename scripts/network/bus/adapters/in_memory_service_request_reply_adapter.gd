extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const RequestScript = preload("res://scripts/network/bus/service_request_envelope.gd")
const ResponseScript = preload("res://scripts/network/bus/service_response_envelope.gd")

var _adapter_id: String
var _handlers: Dictionary = {}
var _latency_by_service: Dictionary = {}
var _request_records: Dictionary = {}


func _init(adapter_id: String = "adapter/in-memory-service-direct") -> void:
	_adapter_id = adapter_id


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("SERVICE_REQUEST_REPLY", _adapter_id, ["canonical_round_trip", "deterministic_timeout", "idempotent_request_id", "strict_response"])


func register_handler(service_id: String, handler, simulated_latency_ms: int = 0) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(service_id, "service") or handler == null or not handler.has_method("handle_service_request"):
		return ResultScript.failure("REJECTED", "INVALID_HANDLER", false)
	if simulated_latency_ms < 0 or simulated_latency_ms > 3600000:
		return ResultScript.failure("REJECTED", "INVALID_LATENCY", false)
	if _handlers.has(service_id):
		return ResultScript.failure("REJECTED", "HANDLER_ALREADY_REGISTERED", false)
	_handlers[service_id] = handler
	_latency_by_service[service_id] = simulated_latency_ms
	return ResultScript.success("COMPLETED")


func request(request_value: Dictionary) -> Dictionary:
	var request_check: Dictionary = RequestScript.validate(request_value)
	if not bool(request_check.get("success", false)):
		return ResultScript.failure("REJECTED", String(request_check.get("error_code", "INVALID_REQUEST")), false)
	var copied: Dictionary = BusUtilsScript.deep_copy_json(request_value)
	if not bool(copied.get("success", false)):
		return ResultScript.failure("REJECTED", "NON_CANONICAL_REQUEST", false)
	var request_copy: Dictionary = copied.get("value", {})
	var replay: Dictionary = _check_request_replay(request_copy)
	if not replay.is_empty():
		return replay
	var service_id: String = String(request_copy["service_id"])
	if not _handlers.has(service_id):
		return ResultScript.failure("NOT_FOUND", "SERVICE_NOT_FOUND", false, {"service_id": service_id})
	var latency_ms: int = int(_latency_by_service.get(service_id, 0))
	if latency_ms >= int(request_copy["timeout_ms"]):
		return ResultScript.failure("TIMEOUT", "REQUEST_TIMEOUT", true, {"service_id": service_id, "elapsed_ms": latency_ms})
	return _invoke_handler(_handlers[service_id], request_copy)


func _invoke_handler(handler, request_copy: Dictionary) -> Dictionary:
	var response = handler.handle_service_request(request_copy.duplicate(true))
	if typeof(response) != TYPE_DICTIONARY:
		return ResultScript.failure("FAILED", "INVALID_HANDLER_RESPONSE", false)
	var response_check: Dictionary = ResponseScript.validate(response)
	if not bool(response_check.get("success", false)):
		return ResultScript.failure("FAILED", String(response_check.get("error_code", "INVALID_HANDLER_RESPONSE")), false)
	if String(response.get("request_id", "")) != String(request_copy.get("request_id", "")):
		return ResultScript.failure("FAILED", "RESPONSE_REQUEST_MISMATCH", false)
	var copied: Dictionary = BusUtilsScript.deep_copy_json(response)
	if not bool(copied.get("success", false)):
		return ResultScript.failure("FAILED", "NON_CANONICAL_RESPONSE", false)
	var result: Dictionary = ResultScript.success("DELIVERED", {"response": copied.get("value"), "duplicate": false})
	_store_request_result(request_copy, result)
	return result


func _check_request_replay(request_value: Dictionary) -> Dictionary:
	var request_id: String = String(request_value.get("request_id", ""))
	if not _request_records.has(request_id):
		return {}
	var record: Dictionary = _request_records[request_id]
	if String(record.get("fingerprint", "")) != NetworkUtilsScript.payload_hash(request_value):
		return ResultScript.failure("REJECTED", "REQUEST_ID_CONFLICT", false)
	var replayed: Dictionary = record.get("result", {}).duplicate(true)
	replayed["details"]["duplicate"] = true
	return replayed


func _store_request_result(request_value: Dictionary, result: Dictionary) -> void:
	_request_records[String(request_value["request_id"])] = {
		"fingerprint": NetworkUtilsScript.payload_hash(request_value),
		"result": result.duplicate(true),
	}
