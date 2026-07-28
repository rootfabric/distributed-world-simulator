extends RefCounted

const SCHEMA := "planet_simulator.network_transport_port.v1"


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "BASE",
		"supports_server": false,
		"supports_client": false,
		"synchronous_delivery": false,
	}


func start_server(_endpoint: Dictionary) -> Dictionary:
	return _failure("SERVER_NOT_SUPPORTED")


func connect_client(_endpoint: Dictionary) -> Dictionary:
	return _failure("CLIENT_NOT_SUPPORTED")


func disconnect_peer() -> Dictionary:
	return _success()


func send_message(_message_type: String, _payload: Dictionary) -> Dictionary:
	return _failure("SEND_NOT_SUPPORTED")


func poll_events(_max_events: int) -> Array[Dictionary]:
	return []


func drain() -> Dictionary:
	return _success()


func stop() -> Dictionary:
	return _success()


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
