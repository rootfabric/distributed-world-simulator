extends RefCounted

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")
const HandshakeScript = preload("res://scripts/network/contracts/network_handshake_envelope.gd")

const CHECKPOINT: String = "v16.5.2-foundation-network-n1"
const BUILD_ID: String = "n1-reconnect-replay-bounded-cache"
const CONTRACT_VERSIONS: Dictionary = {
	"entity_delta": 1,
	"entity_snapshot": 1,
	"item_move_to_container": 1,
	"network_command": 1,
	"network_command_result": 1,
	"network_handshake": 1,
	"network_resume_ticket": 1,
	"network_session_resume": 1,
	"network_session_resume_result": 1,
	"network_wire_frame": 1,
	"snapshot_ack": 1,
}
const CAPABILITIES: Array[String] = [
	"command.item_move_to_container",
	"delta.receive",
	"handshake.v1",
	"session.resume",
	"snapshot.receive",
]


static func parse_options(arguments, mode: String) -> Dictionary:
	var options: Dictionary = {
		"host": "127.0.0.1",
		"port": 0,
		"result_file": "",
		"timeout_ms": 20000,
		"node_id": "sim-n1" if mode == "server" else "bot-n1",
	}
	var errors: Array[String] = []
	for raw_argument in arguments:
		var argument: String = String(raw_argument).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			errors.append("Invalid process argument: %s" % argument)
			continue
		var separator: int = argument.find("=")
		var key: String = argument.substr(2, separator - 2)
		var value: String = argument.substr(separator + 1)
		match key:
			"host": options["host"] = value
			"port": options["port"] = _parse_positive_int(value, key, errors)
			"result-file": options["result_file"] = value
			"timeout-ms": options["timeout_ms"] = _parse_positive_int(value, key, errors)
			"node-id": options["node_id"] = value
			_: errors.append("Unknown process option: --%s" % key)
	if String(options["host"]).strip_edges().is_empty(): errors.append("host cannot be empty")
	if int(options["port"]) <= 0 or int(options["port"]) > 65535: errors.append("port must be in range 1..65535")
	if String(options["result_file"]).strip_edges().is_empty(): errors.append("result-file cannot be empty")
	if String(options["node_id"]).strip_edges().is_empty(): errors.append("node-id cannot be empty")
	return {"success": errors.is_empty(), "options": options, "errors": errors}


static func create_endpoint(options: Dictionary) -> Dictionary:
	return EndpointScript.create("ENET", String(options["host"]), int(options["port"]), "simulation", false)


static func create_service_config(server_node_id: String) -> Dictionary:
	return {
		"server_node_id": server_node_id,
		"checkpoint": CHECKPOINT,
		"build_id": BUILD_ID,
		"authority_owner_id": "sim-n1",
		"authority_epoch": 5,
		"server_tick": 500,
		"required_capabilities": CAPABILITIES.duplicate(),
		"contract_versions": CONTRACT_VERSIONS.duplicate(true),
	}


static func create_handshake(client_node_id: String) -> Dictionary:
	return HandshakeScript.create(
		"handshake/n1/reconnect/initial",
		client_node_id,
		CHECKPOINT,
		BUILD_ID,
		"persistent",
		"moon",
		CAPABILITIES.duplicate(),
		CONTRACT_VERSIONS.duplicate(true)
	)


static func write_json(path: String, value: Dictionary) -> bool:
	return bool(AtomicJsonScript.write_dictionary(path, value).get("success", false))


static func _parse_positive_int(value: String, key: String, errors: Array[String]) -> int:
	if not value.is_valid_int():
		errors.append("--%s must be an integer" % key)
		return 0
	var parsed: int = value.to_int()
	if parsed <= 0:
		errors.append("--%s must be positive" % key)
		return 0
	return parsed
