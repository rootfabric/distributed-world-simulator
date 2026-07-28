extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const PortScript = preload("res://scripts/network/transports/network_transport_port.gd")

const SCHEMA := "planet_simulator.network_transport_boundary.v1"
const STATE_STOPPED := "STOPPED"
const STATE_STARTING := "STARTING"
const STATE_LISTENING := "LISTENING"
const STATE_CONNECTING := "CONNECTING"
const STATE_READY := "READY"
const STATE_DRAINING := "DRAINING"
const STATE_FAILED := "FAILED"
const ALLOWED_MESSAGE_TYPES := {
	"COMMAND": true,
	"COMMAND_RESULT": true,
	"SNAPSHOT": true,
	"DELTA": true,
	"HANDSHAKE": true,
	"HANDSHAKE_RESULT": true,
	"SNAPSHOT_ACK": true,
}

var _port
var _state: String = STATE_STOPPED
var _max_payload_bytes: int = 65536
var _max_pending_messages: int = 128
var _pending_messages: int = 0
var _failure_code: String = ""
var _mode: String = ""


func configure(port_reference, max_payload_bytes: int = 65536, max_pending_messages: int = 128) -> Dictionary:
	if _state != STATE_STOPPED:
		return _failure("BOUNDARY_NOT_STOPPED")
	if not _is_transport_port(port_reference):
		return _failure("INVALID_TRANSPORT_PORT")
	if max_payload_bytes <= 0:
		return _failure("INVALID_PAYLOAD_LIMIT")
	if max_pending_messages <= 0:
		return _failure("INVALID_QUEUE_LIMIT")
	var descriptor_result: Dictionary = _validate_port_descriptor(port_reference.get_descriptor())
	if not bool(descriptor_result.get("success", false)):
		return descriptor_result
	_port = port_reference
	_max_payload_bytes = max_payload_bytes
	_max_pending_messages = max_pending_messages
	_pending_messages = 0
	_failure_code = ""
	_mode = ""
	return _success()


func start_server(endpoint: Dictionary) -> Dictionary:
	if _port == null:
		return _failure("NOT_CONFIGURED")
	if _state != STATE_STOPPED:
		return _failure("INVALID_STATE")
	if not bool(_port.get_descriptor().get("supports_server", false)):
		return _failure("SERVER_NOT_SUPPORTED")
	_mode = "SERVER"
	_state = STATE_STARTING
	var result: Dictionary = _normalize_result(_port.start_server(endpoint))
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "START_SERVER_FAILED")))
	_state = STATE_LISTENING
	return _success({"state": _state})


func connect_client(endpoint: Dictionary) -> Dictionary:
	if _port == null:
		return _failure("NOT_CONFIGURED")
	if _state != STATE_STOPPED:
		return _failure("INVALID_STATE")
	if not bool(_port.get_descriptor().get("supports_client", false)):
		return _failure("CLIENT_NOT_SUPPORTED")
	_mode = "CLIENT"
	_state = STATE_CONNECTING
	var result: Dictionary = _normalize_result(_port.connect_client(endpoint))
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "CONNECT_FAILED")))
	if bool(_port.get_descriptor().get("synchronous_delivery", false)):
		_state = STATE_READY
	return _success({"state": _state})


func mark_ready() -> Dictionary:
	if _state != STATE_LISTENING and _state != STATE_CONNECTING:
		return _failure("INVALID_STATE")
	_state = STATE_READY
	return _success({"state": _state})


func send(message_type: String, payload: Dictionary) -> Dictionary:
	if _state != STATE_READY:
		return _failure("TRANSPORT_NOT_READY")
	if not ALLOWED_MESSAGE_TYPES.has(message_type):
		return _failure("UNKNOWN_MESSAGE_TYPE")
	if _pending_messages >= _max_pending_messages:
		return _failure("OUTBOUND_QUEUE_FULL")
	var encoded: String = UtilsScript.canonical_json(payload)
	if encoded.is_empty():
		return _failure("SERIALIZATION_FAILED")
	var byte_count: int = encoded.to_utf8_buffer().size()
	if byte_count > _max_payload_bytes:
		return _failure("PAYLOAD_TOO_LARGE", {
			"payload_bytes": byte_count,
			"max_payload_bytes": _max_payload_bytes,
		})
	_pending_messages += 1
	var result: Dictionary = _normalize_result(_port.send_message(message_type, payload.duplicate(true)))
	_pending_messages -= 1
	if not bool(result.get("success", false)):
		return _failure(String(result.get("error_code", "SEND_FAILED")), result.get("details", {}))
	return _success({
		"message_type": message_type,
		"payload_bytes": byte_count,
		"transport_result": result.get("details", {}).duplicate(true),
	})


func poll_events(max_events: int = 64) -> Dictionary:
	if _port == null:
		return _failure("NOT_CONFIGURED")
	if max_events <= 0:
		return _failure("INVALID_EVENT_LIMIT")
	if _state == STATE_STOPPED or _state == STATE_FAILED:
		return _failure("INVALID_STATE")
	var events = _port.poll_events(max_events)
	if not events is Array:
		return _enter_failed("INVALID_EVENT_BATCH")
	if events.size() > max_events:
		return _enter_failed("EVENT_BATCH_OVERFLOW")
	for event in events:
		if not event is Dictionary:
			return _enter_failed("INVALID_EVENT")
	return _success({"events": events.duplicate(true)})


func disconnect_peer() -> Dictionary:
	if _port == null:
		return _failure("NOT_CONFIGURED")
	if _state != STATE_READY and _state != STATE_LISTENING:
		return _failure("INVALID_STATE")
	var result: Dictionary = _normalize_result(_port.disconnect_peer())
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "DISCONNECT_FAILED")))
	_state = STATE_LISTENING if _mode == "SERVER" else STATE_STOPPED
	if _state == STATE_STOPPED:
		_mode = ""
	return _success({"state": _state})


func drain() -> Dictionary:
	if _port == null:
		return _failure("NOT_CONFIGURED")
	if _state == STATE_STOPPED:
		return _success({"state": _state, "replay": true})
	if _state == STATE_DRAINING:
		return _success({"state": _state, "replay": true})
	if _state == STATE_FAILED:
		return _failure("TRANSPORT_FAILED", {"failure_code": _failure_code})
	_state = STATE_DRAINING
	var result: Dictionary = _normalize_result(_port.drain())
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "DRAIN_FAILED")))
	return _success({"state": _state, "replay": false})


func stop() -> Dictionary:
	if _port == null:
		_state = STATE_STOPPED
		_pending_messages = 0
		_failure_code = ""
		_mode = ""
		return _success({"state": _state, "replay": true})
	if _state == STATE_STOPPED:
		return _success({"state": _state, "replay": true})
	var result: Dictionary = _normalize_result(_port.stop())
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "STOP_FAILED")))
	_state = STATE_STOPPED
	_pending_messages = 0
	_failure_code = ""
	_mode = ""
	return _success({"state": _state, "replay": false})


func get_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"state": _state,
		"configured": _port != null,
		"max_payload_bytes": _max_payload_bytes,
		"max_pending_messages": _max_pending_messages,
		"pending_messages": _pending_messages,
		"failure_code": _failure_code,
		"mode": _mode,
		"port_descriptor": _port.get_descriptor().duplicate(true) if _port != null else {},
	}


func _is_transport_port(value) -> bool:
	if value == null or not value is RefCounted:
		return false
	var script = value.get_script()
	while script != null:
		if script == PortScript:
			return true
		script = script.get_base_script()
	return false


func _validate_port_descriptor(descriptor) -> Dictionary:
	if not descriptor is Dictionary:
		return _failure("INVALID_PORT_DESCRIPTOR")
	var expected_fields: Array[String] = [
		"schema", "transport_kind", "supports_server", "supports_client", "synchronous_delivery"
	]
	if descriptor.size() != expected_fields.size():
		return _failure("INVALID_PORT_DESCRIPTOR")
	for field in expected_fields:
		if not descriptor.has(field):
			return _failure("INVALID_PORT_DESCRIPTOR")
	if typeof(descriptor["schema"]) != TYPE_STRING or String(descriptor["schema"]) != PortScript.SCHEMA:
		return _failure("INVALID_PORT_SCHEMA")
	if typeof(descriptor["transport_kind"]) != TYPE_STRING or String(descriptor["transport_kind"]).strip_edges().is_empty():
		return _failure("INVALID_TRANSPORT_KIND")
	for field in ["supports_server", "supports_client", "synchronous_delivery"]:
		if typeof(descriptor[field]) != TYPE_BOOL:
			return _failure("INVALID_PORT_DESCRIPTOR")
	if not bool(descriptor["supports_server"]) and not bool(descriptor["supports_client"]):
		return _failure("PORT_HAS_NO_ROLE")
	return _success()


func _normalize_result(value) -> Dictionary:
	if not value is Dictionary:
		return _failure("INVALID_PORT_RESULT")
	if typeof(value.get("success")) != TYPE_BOOL:
		return _failure("INVALID_PORT_RESULT")
	if typeof(value.get("error_code")) != TYPE_STRING:
		return _failure("INVALID_PORT_RESULT")
	if value.has("details") and not value["details"] is Dictionary:
		return _failure("INVALID_PORT_RESULT")
	return {
		"success": bool(value["success"]),
		"error_code": String(value["error_code"]),
		"details": value.get("details", {}).duplicate(true),
	}


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "TRANSPORT_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
