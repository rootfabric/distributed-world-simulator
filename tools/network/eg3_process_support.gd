extends "res://tools/network/eg2_process_support.gd"

## Shared EG3 process-worker support: extends EG2 with the shared-multiplexed
## backend tunnel scenario — THREE logical client sessions over ONE physical
## gateway->sim link, per-tag operation tables, paced input floods, two-wave
## clients (wave 2 fires on a trigger file so the orchestrator can drop the
## flooder in between), and resume phase support.
##
## Identity namespaces stay strictly separated: peer/enet/* transport peers,
## gateway-minted gateway-session/* ids, client-session/eg3/* surface ids,
## player/eg3-* + entity/* granted ONLY by the auth service.

const CLIENT_SESSION_A := "client-session/eg3/alpha"
const CLIENT_SESSION_B := "client-session/eg3/beta"
const CLIENT_SESSION_C := "client-session/eg3/gamma"
const WORLD_ID_EG3 := "world/eg3/l2-main"
const AUTHORITY_ID_EG3 := "authority/eg3-l2-sim"

const FLOOD_INPUT_COUNT := 60
## Gentle pacing: every flood input shares ONE unreliable stream key with the
## survivors' movements, and same-pump batches coalesce the earlier frame.
## A slow drip keeps the pressure window long while giving survivor movement
## retries a high per-attempt success probability.
const FLOOD_INPUT_INTERVAL_MS := 250
const FLOOD_INPUT_SEQ_BASE := 1000

## Movement receipts ride the RELIABLE ITEM stream; the movement itself rides
## the shared unreliable INPUT stream and may be coalesced away under
## concurrency, so clients retry until the receipt arrives.
const MOVEMENT_RECEIPT_RETRY_MS := 700
const MOVEMENT_RECEIPT_MAX_ATTEMPTS := 8

const OPS_PER_WAVE := 2


## Distinct, per-session operation id table: tag x wave x index.
static func operation_id(tag: String, wave: int, index: int) -> String:
	return "operation/eg3/l2/%s-w%d-%04d" % [tag, wave, index]


static func tag_operations(tag: String, wave: int) -> Array[String]:
	var ids: Array[String] = []
	for index in range(OPS_PER_WAVE):
		ids.append(operation_id(tag, wave, index))
	return ids


## ---- EG3 session-control / scenario inner frames -----------------------------

## The domain replay ledger is GLOBALLY keyed by operation_id, so every
## player's join must carry its own id or the second/third join collides with
## the first player's fingerprint (OPERATION_REPLAY_CONFLICT).
static func join_operation_id_for(logical_player_id: String) -> String:
	return "operation/eg3/l2/join/%s" % logical_player_id.replace("/", "-")


static func authenticate_inner_eg3(client_session_id: String, ticket_id: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg3/l2/auth/1",
			"gateway-session/eg3/probe/l2",
			"CLIENT_TO_WORLD", "SESSION_CONTROL", 1,
			GatewayUtils.EG2_SESSION_AUTHENTICATE_PAYLOAD_SCHEMA,
			{"client_session_id": client_session_id, "ticket_id": ticket_id})


static func place_request_inner_eg3(client_session_id: String, ticket_id: String, resume_token: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg3/l2/place/1",
			"gateway-session/eg3/probe/l2",
			"CLIENT_TO_WORLD", "SESSION_CONTROL", 1,
			GatewayUtils.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA,
			{
				"client_session_id": client_session_id,
				"ticket_id": ticket_id,
				"resume_token": resume_token,
				"world_id": WORLD_ID_EG3,
			})


static func detach_inner_eg3(gateway_session_id: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg3/l2/detach/1", gateway_session_id,
			"CLIENT_TO_WORLD", "SESSION_CONTROL", 1,
			GatewayUtils.EG1_SESSION_DETACH_PAYLOAD_SCHEMA, {})


static func select_hotbar_inner(gateway_session_id: String, operation_id_value: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg3/l2/op/%s" % operation_id_value.replace("/", "-"),
			gateway_session_id,
			"CLIENT_TO_WORLD", "WORLD_OPERATION", 1,
			"planet_simulator.test_world_operation.v1",
			{
				"operation_id": operation_id_value,
				"command": "inventory.select_hotbar",
				"target_id": "entity/eg3-l2-scenario",
			})


static func movement_inner(gateway_session_id: String, input_seq: int) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg3/l2/move/%s/%d" % [gateway_session_id.replace("/", "-"), input_seq],
			gateway_session_id,
			"CLIENT_TO_WORLD", "INPUT_MOVEMENT", input_seq,
			"planet_simulator.test_input.v1",
			{"input_seq": input_seq, "axis_x": 0.0})


## ---- expected totals ---------------------------------------------------------

## Operations APPLIED at the sim: everything except the probe session's op
## (the backend link is already dead when the probe sends it).
static func expected_operation_ids_applied() -> Array[String]:
	var ids: Array[String] = []
	for wave in [1, 2]:
		for tag in ["alpha", "beta", "gamma"]:
			if tag == "alpha" and wave == 2:
				continue
			for id_value in tag_operations(tag, wave):
				ids.append(id_value)
	for id_value in tag_operations("beta", 3):
		ids.append(id_value)
	ids.sort()
	return ids


## Non-flood movements ANSWERED with a reliable receipt: alpha-w1, beta-w1/w2,
## gamma-w1/w2, beta-resume. Flood inputs are counted but never answered and
## may legally be coalesced away on the shared unreliable stream.
static func expected_movement_total() -> int:
	return 5
