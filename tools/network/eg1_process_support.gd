extends RefCounted

## Shared EG1 process-worker support: option parsing, atomic report writing,
## the fixed cross-process scenario table and wire-frame builders.
##
## Identity namespaces are strictly separated here: transport peers use
## peer/enet/*, the gateway mints gateway-session/* ids, clients declare
## client-session/* ids and the sim resolves player/* identities internally.

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const ServiceScript = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.eg1_process_support.v1"

# Deterministic domain authority configuration (identical for DIRECT and
# GATEWAY applications so canonical snapshots are comparable byte-for-byte).
const AUTHORITY_OWNER_ID := "simulation/eg1/process-equivalence"
const AUTHORITY_EPOCH := 7
const SERVER_TICK := 300
const SERVICE_CONFIG := {
	"profile": "MULTIPLAYER_CORE",
	"region_id": "region/eg1/process-equivalence",
	"topology_adapter": "LOOPBACK",
	"playable_sandbox": true,
}
const LOGICAL_PLAYER_ID := "a"
const PLAYER_TRANSPORT_SESSION := "transport-session/eg1/player-a"
const JOIN_OPERATION_ID := "operation/eg1/p2p/join"

const SCENARIO_ITEM_COMMANDS := [
	{"operation_id": "operation/eg1/p2p/0001", "command_type": "item.split", "payload": {"item_id": "item/player/a/beacons", "quantity": 1}, "target_id": "entity/eg1-scenario-1"},
	{"operation_id": "operation/eg1/p2p/0002", "command_type": "inventory.assign_hotbar", "payload": {"item_id": "item/player/a/battery", "slot_index": 5}, "target_id": "entity/eg1-scenario-2"},
	{"operation_id": "operation/eg1/p2p/0003", "command_type": "inventory.select_hotbar", "payload": {"selected_hotbar_index": 2}, "target_id": "entity/eg1-scenario-3"},
]
const MOVEMENT_OPERATION_ID := "operation/eg1/p2p/move/0001"
const MOVEMENT_INPUT_SEQ := 1
const MOVEMENT_INTENT := {
	"move_x": 0.0, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0,
	"jump_pressed": false, "sprint": false, "delta_seconds": 0.05,
}
const EXPECTED_OPERATION_IDS := [
	"operation/eg1/p2p/0001",
	"operation/eg1/p2p/0002",
	"operation/eg1/p2p/0003",
	"operation/eg1/p2p/move/0001",
]


static func parse_options(arguments, spec: Dictionary) -> Dictionary:
	var options: Dictionary = {}
	var errors: Array[String] = []
	for key_value in spec.keys():
		var defaults: Dictionary = spec[key_value]
		options[String(key_value)] = defaults.get("default", "")
	for raw_argument in arguments:
		var argument := String(raw_argument).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			errors.append("Invalid process argument: %s" % argument)
			continue
		var separator := argument.find("=")
		var key := argument.substr(2, separator - 2)
		var value := argument.substr(separator + 1)
		if not options.has(key):
			errors.append("Unknown process option: --%s" % key)
			continue
		if String(spec[key].get("kind", "string")) == "int":
			if not value.is_valid_int():
				errors.append("--%s must be an integer" % key)
			else:
				options[key] = int(value)
		else:
			options[key] = value
	for key_value in spec.keys():
		var required := bool(spec[key_value].get("required", false))
		if not required:
			continue
		var current = options[key_value]
		var empty := (current is int and int(current) <= 0) or (current is String and String(current).is_empty())
		if empty:
			errors.append("Missing required option: --%s" % String(key_value))
	return {"success": errors.is_empty(), "options": options, "errors": errors}


static func write_state(path: String, state: String, extra: Dictionary = {}) -> bool:
	var report: Dictionary = {
		"schema": "planet_simulator.eg1_process_state.v1",
		"state": state,
		"passed": false,
		"process_id": OS.get_process_id(),
	}
	for key in extra.keys():
		report[String(key)] = extra[key]
	return write_json(path, report)


static func write_json(path: String, value: Dictionary) -> bool:
	return bool(AtomicJsonScript.write_dictionary(path, value).get("success", false))


static func enet_endpoint(host: String, port: int) -> Dictionary:
	return {"transport": "ENET", "host": host, "port": port, "channel": "CONTROL", "secure": false}


## Build the inner ClientWorldFrame for one scenario step (surface encoding:
## only registered EG0 semantic schemas travel on the client surface).
static func scenario_inner_frame(gateway_session_id: String, step: Dictionary, sequence: int) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg1/p2p/op/%s" % String(step["operation_id"]).get_slice("/", 3),
			gateway_session_id,
			"CLIENT_TO_WORLD",
			"WORLD_OPERATION",
			sequence,
			"planet_simulator.test_world_operation.v1",
			{
				"operation_id": String(step["operation_id"]),
				"command": String(step["command_type"]),
				"target_id": String(step["target_id"]),
			})


static func movement_inner_frame(gateway_session_id: String, input_seq: int) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg1/p2p/move/%d" % input_seq,
			gateway_session_id,
			"CLIENT_TO_WORLD",
			"INPUT_MOVEMENT",
			input_seq,
			"planet_simulator.test_input.v1",
			{"input_seq": input_seq, "axis_x": 0.0})


## Materialize a protocol-frame wire envelope for an inner ClientWorldFrame.
static func wire_frame_for_inner(inner: Dictionary, wire_session: String, frame_id: String, sequence: int) -> Dictionary:
	var physical := GatewayUtils.eg1_physical_channel_for(String(inner["channel"]))
	return FrameScript.create(
			frame_id,
			wire_session,
			maxi(sequence, 1),
			physical,
			GatewayUtils.eg1_delivery_mode_for(String(inner["channel"])),
			String(inner["payload_schema"]),
			Dictionary(inner))


static func scenario_step(operation_id: String) -> Dictionary:
	for step in SCENARIO_ITEM_COMMANDS:
		if String(step["operation_id"]) == operation_id:
			return step
	return {}


## Apply the whole fixed scenario directly through one service instance.
## Returns {service, ok} where ok reports every step succeeded.
static func apply_direct_scenario(service) -> Dictionary:
	var ok := true
	var join_result: Dictionary = service.join(LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, JOIN_OPERATION_ID)
	ok = ok and bool(join_result.get("success", false))
	for step in SCENARIO_ITEM_COMMANDS:
		var result: Dictionary = service.handle_canonical_item_command(
				LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1,
				String(step["operation_id"]), String(step["command_type"]),
				Dictionary(step["payload"]).duplicate(true))
		ok = ok and bool(result.get("success", false))
	var moved: Dictionary = service.submit_movement_intent(
			LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1, MOVEMENT_INPUT_SEQ,
			MOVEMENT_INTENT.duplicate(true), MOVEMENT_OPERATION_ID)
	ok = ok and bool(moved.get("success", false))
	return {"ok": ok}


## Compare a live (gateway-fed) service against a fresh DIRECT application of
## the same fixed scenario: canonical JSON equality plus checksum equality.
static func compare_with_direct(live_service) -> Dictionary:
	var direct = ServiceScript.new()
	var setup: Dictionary = direct.setup(AUTHORITY_OWNER_ID, AUTHORITY_EPOCH, SERVER_TICK, SERVICE_CONFIG.duplicate(true))
	if not bool(setup.get("success", false)):
		return {"success": false, "error_code": "DIRECT_SETUP_FAILED"}
	var applied: Dictionary = apply_direct_scenario(direct)
	if not bool(applied.get("ok", false)):
		return {"success": false, "error_code": "DIRECT_APPLICATION_FAILED"}
	var live_snapshot: Dictionary = live_service.create_canonical_item_graph_snapshot()
	var direct_snapshot: Dictionary = direct.create_canonical_item_graph_snapshot()
	return {
		"success": true,
		"live_checksum": String(live_snapshot.get("checksum", "")),
		"direct_checksum": String(direct_snapshot.get("checksum", "")),
		"canonical_equal": Utils.canonical_json(live_snapshot) == Utils.canonical_json(direct_snapshot),
	}
