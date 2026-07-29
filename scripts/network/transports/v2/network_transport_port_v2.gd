extends RefCounted

const TransportUtilsScript = preload("res://scripts/network/transports/v2/transport_contract_utils.gd")
const SCHEMA: String = "planet_simulator.network_transport_port.v2"


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "BASE",
		"supports_server": false,
		"supports_client": false,
		"synchronous_delivery": false,
		"multi_peer": true,
		"max_peers": 0,
	}


func start_server(_endpoint: Dictionary) -> Dictionary:
	return TransportUtilsScript.failure("SERVER_NOT_SUPPORTED")


func connect_client(_endpoint: Dictionary, _peer_id: String, _session_id: String, _route_id: String, _route_generation: int) -> Dictionary:
	return TransportUtilsScript.failure("CLIENT_NOT_SUPPORTED")


func disconnect_peer(_peer_id: String, _session_id: String) -> Dictionary:
	return TransportUtilsScript.failure("DISCONNECT_NOT_SUPPORTED")


func send_to_peer(_peer_id: String, _frame: Dictionary) -> Dictionary:
	return TransportUtilsScript.failure("SEND_NOT_SUPPORTED")


func poll_events(_max_events: int) -> Array[Dictionary]:
	return []


func drain() -> Dictionary:
	return TransportUtilsScript.success()


func stop() -> Dictionary:
	return TransportUtilsScript.success()
