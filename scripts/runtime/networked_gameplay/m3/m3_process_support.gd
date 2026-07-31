extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")

const CHECKPOINT := "v16.10.2-runtime-m3-dedicated-graphical-multiplayer"
const BUILD_ID := "m3-dedicated-two-graphical-clients"
const MESSAGE_SCHEMA := "planet_simulator.m3.graphical_multiplayer_message.v1"

static func endpoint(host: String, port: int, server_mode: bool = false) -> Dictionary:
	return Endpoint.create("ENET", "*" if server_mode else host, port, "simulation", false)

static func transport_bound_operation_id(logical_player_id: String, operation_name: String, transport_session_id: String) -> String:
	var player_id := logical_player_id.strip_edges().to_lower()
	var operation := operation_name.strip_edges().to_lower()
	var session_id := transport_session_id.strip_edges()
	if player_id.is_empty() or operation.is_empty() or session_id.is_empty():
		return ""
	return "operation/m3/%s/%s/%s" % [player_id, operation, session_id.sha256_text().left(16)]

static func write(path: String, value: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))
