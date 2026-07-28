extends RefCounted

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")
const HandshakeScript = preload("res://scripts/network/contracts/network_handshake_envelope.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const CHECKPOINT: String = "v16.5.0-network-n1-snapshot"
const BUILD_ID: String = "n1-enet-handshake-initial-snapshot"
const CONTRACT_VERSIONS: Dictionary = {
	"entity_snapshot": 1,
	"network_handshake": 1,
	"network_wire_frame": 1,
	"snapshot_ack": 1,
}
const CAPABILITIES: Array[String] = ["handshake.v1", "snapshot.receive"]


static func parse_options(arguments, mode: String) -> Dictionary:
	var options: Dictionary = {
		"host": "127.0.0.1",
		"port": 0,
		"result_file": "",
		"timeout_ms": 10000,
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
			"host":
				options["host"] = value
			"port":
				options["port"] = _parse_positive_int(value, key, errors)
			"result-file":
				options["result_file"] = value
			"timeout-ms":
				options["timeout_ms"] = _parse_positive_int(value, key, errors)
			"node-id":
				options["node_id"] = value
			_:
				errors.append("Unknown process option: --%s" % key)
	if String(options["host"]).strip_edges().is_empty():
		errors.append("host cannot be empty")
	if int(options["port"]) <= 0 or int(options["port"]) > 65535:
		errors.append("port must be in range 1..65535")
	if String(options["result_file"]).strip_edges().is_empty():
		errors.append("result-file cannot be empty")
	if String(options["node_id"]).strip_edges().is_empty():
		errors.append("node-id cannot be empty")
	return {"success": errors.is_empty(), "options": options, "errors": errors}


static func create_endpoint(options: Dictionary) -> Dictionary:
	return EndpointScript.create("ENET", String(options["host"]), int(options["port"]), "simulation", false)


static func create_snapshot() -> Dictionary:
	var spatial: Dictionary = SpatialRefScript.create(
		"body/moon/fixed",
		Vector3(1000.0, 20.0, -30.0),
		Basis.IDENTITY,
		Vector3(0.0, 0.0, 1.0),
		Vector3.ZERO,
		500.0,
		"main",
		"moon",
		"persistent"
	)
	return SnapshotScript.create(
		"snapshot/n1/initial/1",
		"entity/item/n1-beacon",
		"world_item",
		12,
		"sim-n1",
		5,
		500,
		spatial,
		{"region_id": "region/moon/a", "partition_key": "moon/a/0001"},
		{"sleeping": false, "mass_kg": 5.0},
		{"item": {"definition_id": "survey_beacon", "quantity": 1}}
	)


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
		"handshake/n1/1",
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
