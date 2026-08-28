extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const NetworkConditionSimulatorPort = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const NetworkConditionProfileStore = preload("res://scripts/network/conditions/network_condition_profile_store.gd")
const NetworkConditionProfile = preload("res://scripts/network/conditions/network_condition_profile.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const MESSAGE_SCHEMA := "planet_simulator.sm1_graphical_process_message.v1"
const PRODUCT_SESSION_ID := "session/sm1/graphical-acceptance"
const LOGICAL_PLAYER_ID := "player/sm1-graphical-a"
const PLAYER_ENTITY_ID := "entity/sm1-graphical-a"
const GATEWAY_ENDPOINT_ID := "gateway/sm1/graphical-primary"
const AUTHORITY_A := "authority/a"
const AUTHORITY_B := "authority/b"

static func parse_options(arguments, spec: Dictionary) -> Dictionary:
	var options: Dictionary = {}
	var errors: Array[String] = []
	for key_value in spec.keys():
		var key := String(key_value)
		options[key] = Dictionary(spec[key_value]).get("default", "")
	for raw in arguments:
		var argument := String(raw).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			errors.append("invalid argument: %s" % argument)
			continue
		var split := argument.find("=")
		var key := argument.substr(2, split - 2)
		var text := argument.substr(split + 1)
		if not spec.has(key):
			errors.append("unknown option: --%s" % key)
			continue
		var kind := String(Dictionary(spec[key]).get("kind", "string"))
		if kind == "int":
			if not text.is_valid_int():
				errors.append("--%s must be integer" % key)
			else:
				options[key] = int(text)
		elif kind == "bool":
			options[key] = text.to_lower() in ["1", "true", "yes", "on"]
		else:
			options[key] = text
	for key_value in spec.keys():
		var key := String(key_value)
		if not bool(Dictionary(spec[key_value]).get("required", false)):
			continue
		var value = options[key]
		if (value is String and String(value).is_empty()) or (value is int and int(value) <= 0):
			errors.append("missing required option: --%s" % key)
	return {"success": errors.is_empty(), "options": options, "errors": errors}


static func endpoint(host: String, port: int) -> Dictionary:
	return {"transport": "ENET", "host": host, "port": port, "channel": "CONTROL", "secure": false}


static func make_boundary(network_profile_id: String = "", seed_offset: int = 0) -> Object:
	var bundle: Dictionary = make_boundary_bundle(network_profile_id, seed_offset)
	return bundle.get("boundary")


static func make_boundary_bundle(network_profile_id: String = "", seed_offset: int = 0) -> Dictionary:
	var port = EnetPortScript.new()
	var simulator = null
	var profile: Dictionary = {}
	var normalized_profile := network_profile_id.strip_edges().to_upper()
	if not normalized_profile.is_empty():
		var loaded: Dictionary = NetworkConditionProfileStore.load_profile(normalized_profile)
		if not bool(loaded.get("success", false)):
			return {}
		profile = Dictionary(loaded.get("details", {}).get("profile", {})).duplicate(true)
		if seed_offset != 0:
			var values := profile.duplicate(true)
			values.erase("schema")
			values.erase("profile_id")
			values.erase("checksum")
			values["random_seed"] = maxi(1, int(profile.get("random_seed", 1)) + seed_offset)
			profile = NetworkConditionProfile.create(normalized_profile, values)
		simulator = NetworkConditionSimulatorPort.new()
		var setup: Dictionary = simulator.setup(port, profile)
		if not bool(setup.get("success", false)):
			return {}
		port = simulator
	var boundary = BoundaryScript.new()
	var configured: Dictionary = boundary.configure(port, 1048576, 256, 4194304)
	if not bool(configured.get("success", false)):
		return {}
	return {"boundary": boundary, "simulator": simulator, "profile": profile}


static func mark_ready(boundary, peer_id: String) -> bool:
	if boundary == null or peer_id.is_empty():
		return false
	var snapshot: Dictionary = boundary.get_peer_snapshot(peer_id)
	var state := String(snapshot.get("state", ""))
	if state == "READY":
		return true
	if state == "TRANSPORT_CONNECTED":
		if not bool(boundary.mark_peer_handshaking(peer_id).get("success", false)):
			return false
		state = "HANDSHAKING"
	if state == "HANDSHAKING":
		if not bool(boundary.mark_peer_synchronizing(peer_id).get("success", false)):
			return false
		state = "SYNCHRONIZING"
	if state == "SYNCHRONIZING":
		if not bool(boundary.mark_peer_ready(peer_id).get("success", false)):
			return false
	return String(boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"


static func send(boundary, peer_id: String, payload: Dictionary) -> Dictionary:
	if boundary == null:
		return {"success": false, "error_code": "SM1_PROCESS_BOUNDARY_MISSING"}
	var built: Dictionary = boundary.create_frame_for_peer(
		peer_id,
		"CONTROL",
		MESSAGE_SCHEMA,
		payload,
		"RELIABLE_ORDERED"
	)
	if not bool(built.get("success", false)):
		return built
	var frame: Dictionary = Dictionary(built.get("details", {}).get("frame", {}))
	return boundary.send_to_peer(peer_id, frame)


static func payload_from_event(event: Dictionary) -> Dictionary:
	if String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
		return {}
	var frame: Dictionary = Dictionary(event.get("frame", {}))
	if String(frame.get("payload_schema", "")) != MESSAGE_SCHEMA:
		return {}
	var payload = frame.get("payload", {})
	return Dictionary(payload).duplicate(true) if payload is Dictionary else {}


static func write_state(path: String, state: String, extra: Dictionary = {}) -> bool:
	var value := {
		"schema": "planet_simulator.sm1_graphical_process_state.v1",
		"state": state,
		"passed": false,
		"process_id": OS.get_process_id(),
	}
	for key in extra.keys():
		value[String(key)] = extra[key]
	return write_json(path, value)


static func write_json(path: String, value: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))


static func checksum(value: Dictionary) -> String:
	return Utils.payload_hash(value)


static func canonical_state() -> Dictionary:
	return {
		"schema": "planet_simulator.sm1_graphical_shared_state.v1",
		"product_session_id": PRODUCT_SESSION_ID,
		"logical_player_id": LOGICAL_PLAYER_ID,
		"player_entity_id": PLAYER_ENTITY_ID,
		"spawn_generation": 1,
		"last_input_sequence": 0,
		"last_operation_id": "",
		"position_x": 0.0,
		"action_count": 0,
		"world_revision": 0,
		"operation_ids": [],
	}
