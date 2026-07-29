extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const RequestScript = preload("res://scripts/network/bus/service_request_envelope.gd")
const ResponseScript = preload("res://scripts/network/bus/service_response_envelope.gd")

var _adapter_id: String
var _routes: Dictionary = {}
var _handlers: Dictionary = {}
var _latency_by_backend: Dictionary = {}
var _request_records: Dictionary = {}


func _init(adapter_id: String = "adapter/in-memory-service-router") -> void:
	_adapter_id = adapter_id


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("SERVICE_REQUEST_REPLY", _adapter_id, ["canonical_round_trip", "deterministic_timeout", "idempotent_request_id", "service_route_table"])


func add_route(public_service_id: String, backend_service_id: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(public_service_id, "service") or not BusUtilsScript.is_canonical_id(backend_service_id, "service"):
		return ResultScript.failure("REJECTED", "INVALID_SERVICE_ROUTE", false)
	if _routes.has(public_service_id):
		return ResultScript.failure("REJECTED", "ROUTE_ALREADY_REGISTERED", false)
	_routes[public_service_id] = backend_service_id
	return ResultScript.success()


func register_handler(service_id: String, handler, simulated_latency_ms: int = 0) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(service_id, "service") or handler == null or not handler.has_method("handle_service_request"):
		return ResultScript.failure("REJECTED", "INVALID_HANDLER", false)
	if simulated_latency_ms < 0 or simulated_latency_ms > 3600000:
		return ResultScript.failure("REJECTED", "INVALID_LATENCY", false)
	if _handlers.has(service_id):
		return ResultScript.failure("REJECTED", "HANDLER_ALREADY_REGISTERED", false)
	_handlers[service_id] = handler
	_latency_by_backend[service_id] = simulated_latency_ms
	return ResultScript.success()


func request(request_value: Dictionary) -> Dictionary:
	var request_check: Dictionary = RequestScript.validate(request_value)
	if not bool(request_check.get("success", false)):
		return ResultScript.failure("REJECTED", String(request_check.get("error_code", "INVALID_REQUEST")), false)
	var copied: Dictionary = BusUtilsScript.deep_copy_json(request_value)
	if not bool(copied.get("success", false)):
		return ResultScript.failure("REJECTED", "NON_CANONICAL_REQUEST", false)
	var public_request: Dictionary = copied.get("value", {})
	var replay: Dictionary = _check_request_replay(public_request)
	if not replay.is_empty():
		return replay
	var public_service_id: String = String(public_request["service_id"])
	var backend_service_id: String = String(_routes.get(public_service_id, public_service_id))
	if not _handlers.has(backend_service_id):
		return ResultScript.failure("NOT_FOUND", "SERVICE_NOT_FOUND", false, {"service_id": public_service_id})
	var latency_ms: int = int(_latency_by_backend.get(backend_service_id, 0))
	if latency_ms >= int(public_request["timeout_ms"]):
		return ResultScript.failure("TIMEOUT", "REQUEST_TIMEOUT", true, {"service_id": public_service_id, "elapsed_ms": latency_ms})
	var backend_request: Dictionary = public_request.duplicate(true)
	backend_request["service_id"] = backend_service_id
	var response = _handlers[backend_service_id].handle_service_request(backend_request)
	if typeof(response) != TYPE_DICTIONARY:
		return ResultScript.failure("FAILED", "INVALID_HANDLER_RESPONSE", false)
	var response_check: Dictionary = ResponseScript.validate(response)
	if not bool(response_check.get("success", false)):
		return ResultScript.failure("FAILED", String(response_check.get("error_code", "INVALID_HANDLER_RESPONSE")), false)
	if String(response.get("request_id", "")) != String(public_request["request_id"]):
		return ResultScript.failure("FAILED", "RESPONSE_REQUEST_MISMATCH", false)
	var response_copy: Dictionary = BusUtilsScript.deep_copy_json(response)
	if not bool(response_copy.get("success", false)):
		return ResultScript.failure("FAILED", "NON_CANONICAL_RESPONSE", false)
	var result: Dictionary = ResultScript.success("DELIVERED", {"response": response_copy.get("value"), "duplicate": false})
	_store_request_result(public_request, result)
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
