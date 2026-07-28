extends "res://scripts/network/transports/network_transport_port.gd"

var _started: bool = false
var _connected: bool = false
var _messages: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _message_handler: Callable = Callable()


func setup(message_handler: Callable = Callable()) -> void:
	_message_handler = message_handler


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "LOOPBACK",
		"supports_server": true,
		"supports_client": true,
		"synchronous_delivery": true,
	}


func start_server(endpoint: Dictionary) -> Dictionary:
	if _started:
		return _failure("ALREADY_STARTED")
	if endpoint.is_empty():
		return _failure("INVALID_ENDPOINT")
	_started = true
	_events.append({"type": "LISTENING", "endpoint": endpoint.duplicate(true)})
	return _success()


func connect_client(endpoint: Dictionary) -> Dictionary:
	if _connected:
		return _failure("ALREADY_CONNECTED")
	if endpoint.is_empty():
		return _failure("INVALID_ENDPOINT")
	_connected = true
	_events.append({"type": "CONNECTED", "endpoint": endpoint.duplicate(true)})
	return _success()


func disconnect_peer() -> Dictionary:
	_connected = false
	_events.append({"type": "DISCONNECTED"})
	return _success()


func send_message(message_type: String, payload: Dictionary) -> Dictionary:
	var message := {
		"message_type": message_type,
		"payload": payload.duplicate(true),
	}
	_messages.append(message)
	if _message_handler.is_valid():
		var handled = _message_handler.call(message_type, payload.duplicate(true))
		if not handled is Dictionary:
			return _failure("INVALID_HANDLER_RESULT")
		if not bool(handled.get("success", false)):
			return _failure(String(handled.get("error_code", "HANDLER_REJECTED")), handled.get("details", {}))
		return _success(handled.get("details", {}))
	return _success({"delivered": true})


func poll_events(max_events: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = mini(max_events, _events.size())
	for _index in range(count):
		result.append(_events.pop_front())
	return result


func drain() -> Dictionary:
	_events.append({"type": "DRAINED"})
	return _success()


func stop() -> Dictionary:
	_started = false
	_connected = false
	_events.clear()
	return _success()


func get_messages() -> Array[Dictionary]:
	return _messages.duplicate(true)
