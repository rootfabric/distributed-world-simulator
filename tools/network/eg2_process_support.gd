extends "res://tools/network/eg1_process_support.gd"

## Shared EG2 process-worker support: extends the EG1 process support with the
## EG2 wire vocabulary (AUTHENTICATE / PLACE_REQUEST / WORLD_READY), the fixed
## two-phase cross-process scenario (phase A = fresh placement, phase B =
## resume through a NEW client process) and the combined DIRECT comparison the
## sim worker uses to prove world-state continuity across the reconnect.
##
## Identity namespaces stay strictly separated: transport peers peer/enet/*,
## gateway-minted gateway-session/* ids, client-session/* ids on the surface,
## player/* + entity/* granted ONLY by the auth service.

const CLIENT_SESSION_ID := "client-session/eg2/l2-alpha"
const WORLD_ID := "world/eg2/l2-main"
const AUTHORITY_ID := "authority/eg2-l2-sim"
const SERVER_INSTANCE_ID := "server-instance/eg2-sim-a"
const CATALOG_REVISION := 1

# Phase A: fresh placement (first client process).
const SCENARIO_A_ITEM_COMMANDS := [
	{"operation_id": "operation/eg2/l2/a-0001", "command_type": "inventory.assign_hotbar", "payload": {"item_id": "item/player/a/beacons", "slot_index": 5}, "target_id": "entity/eg2-scenario-1"},
	{"operation_id": "operation/eg2/l2/a-0002", "command_type": "inventory.select_hotbar", "payload": {"selected_hotbar_index": 2}, "target_id": "entity/eg2-scenario-2"},
]
const MOVEMENT_A_OPERATION_ID := "operation/eg2/l2/a-move-0001"
const MOVEMENT_A_INPUT_SEQ := 1

# Phase B: resume (second client process, same logical identity).
const SCENARIO_B_ITEM_COMMANDS := [
	{"operation_id": "operation/eg2/l2/b-0001", "command_type": "inventory.assign_hotbar", "payload": {"item_id": "item/player/a/battery", "slot_index": 4}, "target_id": "entity/eg2-scenario-3"},
	{"operation_id": "operation/eg2/l2/b-0002", "command_type": "inventory.select_hotbar", "payload": {"selected_hotbar_index": 1}, "target_id": "entity/eg2-scenario-4"},
]
const MOVEMENT_B_OPERATION_ID := "operation/eg2/l2/b-move-0001"
const MOVEMENT_B_INPUT_SEQ := 2


static func expected_operation_ids_all() -> Array[String]:
	var ids: Array[String] = [
		MOVEMENT_A_OPERATION_ID, MOVEMENT_B_OPERATION_ID,
	]
	for step in SCENARIO_A_ITEM_COMMANDS:
		ids.append(String(step["operation_id"]))
	for step in SCENARIO_B_ITEM_COMMANDS:
		ids.append(String(step["operation_id"]))
	ids.sort()
	return ids


static func expected_operation_ids_phase(phase: String) -> Array[String]:
	var ids: Array[String] = []
	var steps: Array = SCENARIO_A_ITEM_COMMANDS if phase == "A" else SCENARIO_B_ITEM_COMMANDS
	for step in steps:
		ids.append(String(step["operation_id"]))
	ids.append(MOVEMENT_A_OPERATION_ID if phase == "A" else MOVEMENT_B_OPERATION_ID)
	ids.sort()
	return ids


static func scenario_a_step(operation_id: String) -> Dictionary:
	for step in SCENARIO_A_ITEM_COMMANDS:
		if String(step["operation_id"]) == operation_id:
			return step
	return {}


static func scenario_b_step(operation_id: String) -> Dictionary:
	for step in SCENARIO_B_ITEM_COMMANDS:
		if String(step["operation_id"]) == operation_id:
			return step
	return {}


## ---- EG2 session-control inner frames ---------------------------------------


static func authenticate_inner(client_session_id: String, ticket_id: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg2/l2/auth/1",
			"gateway-session/eg2/probe/l2",
			"CLIENT_TO_WORLD",
			"SESSION_CONTROL",
			1,
			GatewayUtils.EG2_SESSION_AUTHENTICATE_PAYLOAD_SCHEMA,
			{
				"client_session_id": client_session_id,
				"ticket_id": ticket_id,
			})


static func place_request_inner(ticket_id: String, resume_token: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg2/l2/place/1",
			"gateway-session/eg2/probe/l2",
			"CLIENT_TO_WORLD",
			"SESSION_CONTROL",
			1,
			GatewayUtils.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA,
			{
				"client_session_id": CLIENT_SESSION_ID,
				"ticket_id": ticket_id,
				"resume_token": resume_token,
				"world_id": WORLD_ID,
			})


static func detach_inner(gateway_session_id: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg2/l2/detach/1",
			gateway_session_id,
			"CLIENT_TO_WORLD",
			"SESSION_CONTROL",
			1,
			GatewayUtils.EG1_SESSION_DETACH_PAYLOAD_SCHEMA,
			{})


## ---- domain application (SIM side only) -------------------------------------


static func apply_item_phase(service, steps: Array) -> bool:
	var ok := true
	for step in steps:
		var result: Dictionary = service.handle_canonical_item_command(
				LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1,
				String(step["operation_id"]), String(step["command_type"]),
				Dictionary(step["payload"]).duplicate(true))
		ok = ok and bool(result.get("success", false))
	return ok


static func apply_movement(service, operation_id: String, input_seq: int) -> bool:
	var moved: Dictionary = service.submit_movement_intent(
			LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1, input_seq,
			MOVEMENT_INTENT.duplicate(true), operation_id)
	return bool(moved.get("success", false))


## Fresh DIRECT application of BOTH phases in wire order (the reference the
## live gateway-fed service is compared against).
static func apply_all_phases_direct() -> Dictionary:
	var direct = ServiceScript.new()
	var setup: Dictionary = direct.setup(AUTHORITY_OWNER_ID, AUTHORITY_EPOCH, SERVER_TICK, SERVICE_CONFIG.duplicate(true))
	if not bool(setup.get("success", false)):
		return {"success": false, "error_code": "DIRECT_SETUP_FAILED"}
	var joined: Dictionary = direct.join(LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, JOIN_OPERATION_ID)
	if not bool(joined.get("success", false)):
		return {"success": false, "error_code": "DIRECT_JOIN_FAILED"}
	var ok := apply_item_phase(direct, SCENARIO_A_ITEM_COMMANDS)
	ok = apply_movement(direct, MOVEMENT_A_OPERATION_ID, MOVEMENT_A_INPUT_SEQ) and ok
	ok = apply_item_phase(direct, SCENARIO_B_ITEM_COMMANDS) and ok
	ok = apply_movement(direct, MOVEMENT_B_OPERATION_ID, MOVEMENT_B_INPUT_SEQ) and ok
	if not ok:
		return {"success": false, "error_code": "DIRECT_APPLICATION_FAILED"}
	return {"success": true, "service": direct}


static func compare_with_combined_direct(live_service) -> Dictionary:
	var baseline: Dictionary = apply_all_phases_direct()
	if not bool(baseline.get("success", false)):
		return {"success": false, "error_code": String(baseline.get("error_code", "DIRECT_FAILED"))}
	var direct = baseline["service"]
	var live_snapshot: Dictionary = live_service.create_canonical_item_graph_snapshot()
	var direct_snapshot: Dictionary = direct.create_canonical_item_graph_snapshot()
	return {
		"success": true,
		"live_checksum": String(live_snapshot.get("checksum", "")),
		"direct_checksum": String(direct_snapshot.get("checksum", "")),
		"canonical_equal": Utils.canonical_json(live_snapshot) == Utils.canonical_json(direct_snapshot),
	}


## World-state projection in the registered eg2_world_state payload shape.
static func world_state_projection(service) -> Dictionary:
	var snapshot: Dictionary = service.create_canonical_item_graph_snapshot()
	return {
		"revision": maxi(int(snapshot.get("revision", 1)), 1),
		"state_checksum": String(snapshot.get("checksum", "")),
	}
