extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")

const ISLAND_ID := "island/ship/01"
const ISLAND_ENTITY_ID := "ship/01"
const ISLAND_AUTHORITY_ID := "authority/island/ship/01"
const LOGICAL_PLAYER_ID := "a"
const PLAYER_ENTITY_ID := "player/a"

const ANCHOR_SCHEMA := "distributed_world_simulator.sm0_p8_moving_island_anchor.v1"
const ROUTE_SCHEMA := "distributed_world_simulator.sm0_p8_moving_island_transfer.v1"
const VIEW_SCHEMA := "distributed_world_simulator.sm0_p8_moving_island_view.v1"

const PHASE_PREPARE := "PREPARE"
const PHASE_PREPARED := "PREPARED"
const PHASE_COMMIT := "COMMIT"
const PHASE_COMMITTED := "COMMITTED"
const PHASES: Array[String] = [PHASE_PREPARE, PHASE_PREPARED, PHASE_COMMIT, PHASE_COMMITTED]

const ANCHOR_FIELDS: Array[String] = [
	"schema", "island_id", "island_entity_id", "inner_authority_id",
	"outer_owner_authority_id", "outer_authority_epoch", "simulation_tick",
	"world_position", "world_yaw", "linear_velocity", "angular_velocity_yaw", "checksum",
]
const ROUTE_FIELDS: Array[String] = [
	"schema", "transfer_id", "phase", "source_authority_id", "destination_authority_id",
	"handoff_source_authority_id", "handoff_target_authority_id", "route_path", "hop_index",
	"source_outer_epoch", "target_outer_epoch", "reservation_tick", "anchor", "retirement_proof", "checksum",
]
const VIEW_FIELDS: Array[String] = [
	"schema", "view_sequence", "anchor", "inner_authority_id", "inner_authority_epoch",
	"player", "player_world_position", "checksum",
]

static func create_anchor(
	outer_owner_authority_id: String,
	outer_authority_epoch: int,
	simulation_tick: int,
	world_position: Dictionary,
	world_yaw: float,
	linear_velocity: Dictionary,
	angular_velocity_yaw: float
) -> Dictionary:
	return _finalize({
		"schema": ANCHOR_SCHEMA,
		"island_id": ISLAND_ID,
		"island_entity_id": ISLAND_ENTITY_ID,
		"inner_authority_id": ISLAND_AUTHORITY_ID,
		"outer_owner_authority_id": outer_owner_authority_id,
		"outer_authority_epoch": outer_authority_epoch,
		"simulation_tick": simulation_tick,
		"world_position": _vec3(world_position),
		"world_yaw": world_yaw,
		"linear_velocity": _vec3(linear_velocity),
		"angular_velocity_yaw": angular_velocity_yaw,
		"checksum": "",
	})

static func validate_anchor(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, ANCHOR_FIELDS)
	if not bool(fields.get("success", false)): return _failure("SM0_P8_ANCHOR_FIELDS_INVALID", {"cause": fields})
	if String(value.get("schema", "")) != ANCHOR_SCHEMA: return _failure("SM0_P8_ANCHOR_SCHEMA_INVALID")
	if String(value.get("island_id", "")) != ISLAND_ID or String(value.get("island_entity_id", "")) != ISLAND_ENTITY_ID:
		return _failure("SM0_P8_ANCHOR_IDENTITY_INVALID")
	if String(value.get("inner_authority_id", "")) != ISLAND_AUTHORITY_ID: return _failure("SM0_P8_INNER_AUTHORITY_INVALID")
	var owner := String(value.get("outer_owner_authority_id", ""))
	if owner not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]: return _failure("SM0_P8_OUTER_OWNER_INVALID")
	if not Utils.is_json_integer(value.get("outer_authority_epoch")) or int(value.get("outer_authority_epoch", 0)) < 1:
		return _failure("SM0_P8_OUTER_EPOCH_INVALID")
	if not Utils.is_json_integer(value.get("simulation_tick")) or int(value.get("simulation_tick", -1)) < 0:
		return _failure("SM0_P8_SIMULATION_TICK_INVALID")
	for field in ["world_position", "linear_velocity"]:
		if not _valid_vec3(value.get(field)): return _failure("SM0_P8_VECTOR_INVALID", {"field": field})
	for field in ["world_yaw", "angular_velocity_yaw"]:
		if typeof(value.get(field)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.get(field))):
			return _failure("SM0_P8_ANGLE_INVALID", {"field": field})
	if not _checksum_valid(value): return _failure("SM0_P8_ANCHOR_CHECKSUM_MISMATCH")
	return _success()

static func create_transfer(
	transfer_id: String,
	phase: String,
	message_source: String,
	message_destination: String,
	handoff_source: String,
	handoff_target: String,
	source_outer_epoch: int,
	target_outer_epoch: int,
	reservation_tick: int,
	anchor: Dictionary = {},
	retirement_proof: String = ""
) -> Dictionary:
	var route := Topology.plan_route(message_source, message_destination)
	return _finalize({
		"schema": ROUTE_SCHEMA,
		"transfer_id": transfer_id,
		"phase": phase,
		"source_authority_id": message_source,
		"destination_authority_id": message_destination,
		"handoff_source_authority_id": handoff_source,
		"handoff_target_authority_id": handoff_target,
		"route_path": route,
		"hop_index": 0,
		"source_outer_epoch": source_outer_epoch,
		"target_outer_epoch": target_outer_epoch,
		"reservation_tick": reservation_tick,
		"anchor": anchor.duplicate(true),
		"retirement_proof": retirement_proof,
		"checksum": "",
	})

static func advance(value: Dictionary) -> Dictionary:
	var next := value.duplicate(true)
	next["hop_index"] = int(value.get("hop_index", -1)) + 1
	return _finalize(next)

static func validate_transfer(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, ROUTE_FIELDS)
	if not bool(fields.get("success", false)): return _failure("SM0_P8_TRANSFER_FIELDS_INVALID", {"cause": fields})
	if String(value.get("schema", "")) != ROUTE_SCHEMA: return _failure("SM0_P8_TRANSFER_SCHEMA_INVALID")
	if String(value.get("transfer_id", "")).strip_edges().is_empty(): return _failure("SM0_P8_TRANSFER_ID_REQUIRED")
	var phase := String(value.get("phase", ""))
	if phase not in PHASES: return _failure("SM0_P8_TRANSFER_PHASE_INVALID")
	var source := String(value.get("source_authority_id", ""))
	var destination := String(value.get("destination_authority_id", ""))
	var handoff_source := String(value.get("handoff_source_authority_id", ""))
	var handoff_target := String(value.get("handoff_target_authority_id", ""))
	if handoff_source not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] or handoff_target not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] or handoff_source == handoff_target:
		return _failure("SM0_P8_HANDOFF_ENDPOINT_INVALID")
	if phase in [PHASE_PREPARE, PHASE_COMMIT]:
		if source != handoff_source or destination != handoff_target: return _failure("SM0_P8_PHASE_DIRECTION_INVALID")
	else:
		if source != handoff_target or destination != handoff_source: return _failure("SM0_P8_PHASE_DIRECTION_INVALID")
	var route: Array = Array(value.get("route_path", []))
	var route_check := Topology.validate_route(route, source, destination)
	if not bool(route_check.get("success", false)): return _failure("SM0_P8_ROUTE_INVALID", {"cause": route_check})
	if not Utils.is_json_integer(value.get("hop_index")):
		return _failure("SM0_P8_HOP_INDEX_INVALID")
	var hop_index := int(value.get("hop_index", -1))
	if hop_index < 0 or hop_index >= route.size(): return _failure("SM0_P8_HOP_INDEX_INVALID")
	if not Utils.is_json_integer(value.get("source_outer_epoch")) or not Utils.is_json_integer(value.get("target_outer_epoch")):
		return _failure("SM0_P8_TRANSFER_EPOCH_INVALID")
	if int(value.get("source_outer_epoch", 0)) < 1 or int(value.get("target_outer_epoch", 0)) != int(value.get("source_outer_epoch", 0)) + 1:
		return _failure("SM0_P8_TRANSFER_EPOCH_INVALID")
	if not Utils.is_json_integer(value.get("reservation_tick")) or int(value.get("reservation_tick", -1)) < 0:
		return _failure("SM0_P8_RESERVATION_TICK_INVALID")
	var anchor: Dictionary = Dictionary(value.get("anchor", {}))
	var proof := String(value.get("retirement_proof", ""))
	if phase == PHASE_COMMIT:
		var anchor_check := validate_anchor(anchor)
		if not bool(anchor_check.get("success", false)): return _failure("SM0_P8_COMMIT_ANCHOR_INVALID", {"cause": anchor_check})
		if String(anchor.get("outer_owner_authority_id", "")) != handoff_target or int(anchor.get("outer_authority_epoch", 0)) != int(value.get("target_outer_epoch", 0)):
			return _failure("SM0_P8_COMMIT_ANCHOR_OWNER_INVALID")
		if int(anchor.get("simulation_tick", -1)) < int(value.get("reservation_tick", 0)):
			return _failure("SM0_P8_COMMIT_TICK_BEFORE_RESERVATION")
		if proof.is_empty() or proof != retirement_proof_for(value, anchor): return _failure("SM0_P8_RETIREMENT_PROOF_INVALID")
	else:
		if not anchor.is_empty() or not proof.is_empty(): return _failure("SM0_P8_PHASE_PAYLOAD_FORBIDDEN")
	if not _checksum_valid(value): return _failure("SM0_P8_TRANSFER_CHECKSUM_MISMATCH")
	return _success()

static func current_authority(value: Dictionary) -> String:
	var route: Array = Array(value.get("route_path", [])); var index := int(value.get("hop_index", -1))
	return String(route[index]) if index >= 0 and index < route.size() else ""

static func previous_authority(value: Dictionary) -> String:
	var route: Array = Array(value.get("route_path", [])); var index := int(value.get("hop_index", -1))
	return String(route[index - 1]) if index > 0 and index < route.size() else ""

static func next_authority(value: Dictionary) -> String:
	var route: Array = Array(value.get("route_path", [])); var index := int(value.get("hop_index", -1))
	return String(route[index + 1]) if index >= 0 and index + 1 < route.size() else ""

static func retirement_proof_for(transfer: Dictionary, anchor: Dictionary) -> String:
	return Utils.payload_hash({
		"transfer_id": String(transfer.get("transfer_id", "")),
		"island_id": ISLAND_ID,
		"island_entity_id": ISLAND_ENTITY_ID,
		"inner_authority_id": ISLAND_AUTHORITY_ID,
		"handoff_source_authority_id": String(transfer.get("handoff_source_authority_id", "")),
		"handoff_target_authority_id": String(transfer.get("handoff_target_authority_id", "")),
		"source_outer_epoch": int(transfer.get("source_outer_epoch", 0)),
		"target_outer_epoch": int(transfer.get("target_outer_epoch", 0)),
		"reservation_tick": int(transfer.get("reservation_tick", 0)),
		"commit_tick": int(anchor.get("simulation_tick", 0)),
		"anchor_checksum": String(anchor.get("checksum", "")),
		"source_retired": true,
	})

static func create_view(view_sequence: int, anchor: Dictionary, inner_epoch: int, player: Dictionary) -> Dictionary:
	var local_position: Dictionary = Dictionary(player.get("position", {}))
	return _finalize({
		"schema": VIEW_SCHEMA,
		"view_sequence": view_sequence,
		"anchor": anchor.duplicate(true),
		"inner_authority_id": ISLAND_AUTHORITY_ID,
		"inner_authority_epoch": inner_epoch,
		"player": _canonical_player(player),
		"player_world_position": compose_world_position(anchor, local_position),
		"checksum": "",
	})

static func validate_view(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, VIEW_FIELDS)
	if not bool(fields.get("success", false)): return _failure("SM0_P8_VIEW_FIELDS_INVALID", {"cause": fields})
	if String(value.get("schema", "")) != VIEW_SCHEMA: return _failure("SM0_P8_VIEW_SCHEMA_INVALID")
	if not Utils.is_json_integer(value.get("view_sequence")) or int(value.get("view_sequence", 0)) < 1: return _failure("SM0_P8_VIEW_SEQUENCE_INVALID")
	var anchor := Dictionary(value.get("anchor", {})); var anchor_check := validate_anchor(anchor)
	if not bool(anchor_check.get("success", false)): return _failure("SM0_P8_VIEW_ANCHOR_INVALID", {"cause": anchor_check})
	if String(value.get("inner_authority_id", "")) != ISLAND_AUTHORITY_ID or int(value.get("inner_authority_epoch", 0)) != 1:
		return _failure("SM0_P8_VIEW_INNER_AUTHORITY_INVALID")
	var player := Dictionary(value.get("player", {}))
	if String(player.get("logical_player_id", "")) != LOGICAL_PLAYER_ID or String(player.get("player_entity_id", "")) != PLAYER_ENTITY_ID:
		return _failure("SM0_P8_VIEW_PLAYER_IDENTITY_INVALID")
	if not _valid_vec3(player.get("position")): return _failure("SM0_P8_VIEW_PLAYER_POSITION_INVALID")
	if not _valid_vec3(value.get("player_world_position")): return _failure("SM0_P8_VIEW_WORLD_POSITION_INVALID")
	var expected_world := compose_world_position(anchor, Dictionary(player.get("position", {})))
	if not _vec_close(Dictionary(value.get("player_world_position", {})), expected_world, 0.000001): return _failure("SM0_P8_VIEW_COMPOSITION_MISMATCH")
	if not _checksum_valid(value): return _failure("SM0_P8_VIEW_CHECKSUM_MISMATCH")
	return _success()

static func compose_world_position(anchor: Dictionary, local_position: Dictionary) -> Dictionary:
	var wp := Dictionary(anchor.get("world_position", {})); var yaw := float(anchor.get("world_yaw", 0.0))
	var lx := float(local_position.get("x", 0.0)); var lz := float(local_position.get("z", 0.0))
	var c := cos(yaw); var s := sin(yaw)
	return {
		"x": float(wp.get("x", 0.0)) + c * lx - s * lz,
		"y": float(wp.get("y", 0.0)) + float(local_position.get("y", 0.0)),
		"z": float(wp.get("z", 0.0)) + s * lx + c * lz,
	}

static func immutable_transfer_fingerprint(value: Dictionary) -> String:
	return Utils.payload_hash({
		"transfer_id": String(value.get("transfer_id", "")), "phase": String(value.get("phase", "")),
		"source_authority_id": String(value.get("source_authority_id", "")), "destination_authority_id": String(value.get("destination_authority_id", "")),
		"handoff_source_authority_id": String(value.get("handoff_source_authority_id", "")), "handoff_target_authority_id": String(value.get("handoff_target_authority_id", "")),
		"source_outer_epoch": int(value.get("source_outer_epoch", 0)), "target_outer_epoch": int(value.get("target_outer_epoch", 0)),
		"reservation_tick": int(value.get("reservation_tick", 0)), "anchor": Dictionary(value.get("anchor", {})), "retirement_proof": String(value.get("retirement_proof", "")),
	})

static func _canonical_player(player: Dictionary) -> Dictionary:
	return {
		"logical_player_id": String(player.get("logical_player_id", "")),
		"player_entity_id": String(player.get("player_entity_id", "")),
		"position": _vec3(Dictionary(player.get("position", {}))),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"state_revision": int(player.get("state_revision", 0)),
	}

static func _vec3(value: Dictionary) -> Dictionary:
	return {"x": float(value.get("x", 0.0)), "y": float(value.get("y", 0.0)), "z": float(value.get("z", 0.0))}
static func _valid_vec3(value) -> bool:
	if not value is Dictionary: return false
	var d := Dictionary(value)
	for axis in ["x","y","z"]:
		if typeof(d.get(axis)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(d.get(axis))): return false
	return true
static func _vec_close(a: Dictionary, b: Dictionary, epsilon: float) -> bool:
	return absf(float(a.get("x",0.0))-float(b.get("x",0.0))) <= epsilon and absf(float(a.get("y",0.0))-float(b.get("y",0.0))) <= epsilon and absf(float(a.get("z",0.0))-float(b.get("z",0.0))) <= epsilon
static func _checksum_valid(value: Dictionary) -> bool:
	var expected := String(value.get("checksum", "")); if expected.is_empty(): return false
	var payload := value.duplicate(true); payload.erase("checksum")
	return expected == Utils.payload_hash(payload)
static func _finalize(value: Dictionary) -> Dictionary:
	return Utils.finalize_json_checksum(value)
static func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}