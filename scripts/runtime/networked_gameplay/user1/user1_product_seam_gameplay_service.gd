extends "res://scripts/runtime/networked_gameplay/user1/user1_product_seam_authority_service.gd"

# USER1-SEM1: ordinary Product Shell / M3 protocol with a real SM1 movement
# authority seam underneath it.
#
# Primary authority owns the existing global gameplay domains:
#   M4 Item Graph + ResourceMining + Construction + durable persistence.
# A secondary authority may temporarily own only a player's movement/ownership
# row. The accepted SM1 freeze -> warm -> commit -> retire -> activate sequence
# moves that row. After returning to primary, all temporary gates are released
# and the service is again an ordinary single-owner durable product service.

const SecondaryAuthorityService = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_movement_authority_service.gd"
)
const SM1Coordinator = preload(
	"res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd"
)
const Carry = preload(
	"res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd"
)
const SeamUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProductSeamState = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_state.gd"
)

const PRIMARY_REGION := "region/user1/a"
const SECONDARY_REGION := "region/user1/b"
const SEAM_ENTER_X_M := 10.0
const SEAM_RETURN_X_M := 0.0

var _secondary
var _primary_authority_id := ""
var _secondary_authority_id := ""
var _primary_port
var _secondary_port
var _seam_coordinators: Dictionary = {}
var _seam_sessions: Dictionary = {}
var _seam_last_operation: Dictionary = {}
var _seam_state: Dictionary = {}
var _transfer_serial := 0
var _transfer_failures := 0
var _transfer_log: Array[Dictionary] = []


func setup(
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int = 0,
	config: Dictionary = {}
) -> Dictionary:
	_primary_authority_id = authority_owner_id.strip_edges()
	_secondary_authority_id = "%s/user1-seam-b" % _primary_authority_id
	var primary_config := config.duplicate(true)
	primary_config["region_id"] = String(
		config.get("region_id", "region/m3/single-server")
	)
	var primary_setup: Dictionary = super.setup(
		authority_owner_id,
		authority_epoch,
		server_tick,
		primary_config
	)
	if not bool(primary_setup.get("success", false)):
		return primary_setup

	_secondary = SecondaryAuthorityService.new()
	var secondary_setup: Dictionary = _secondary.setup(
		_secondary_authority_id,
		authority_epoch,
		server_tick,
		{
			"profile": PROFILE_MULTIPLAYER_CORE,
			"topology_adapter": "USER1_PRODUCT_SEAM_INTERNAL",
			"region_id": SECONDARY_REGION,
			"playable_sandbox": false,
			"fixed_tick_authority": true,
		}
	)
	if not bool(secondary_setup.get("success", false)):
		super.shutdown()
		_secondary = null
		return _failure(
			"USER1_SECONDARY_AUTHORITY_SETUP_FAILED",
			{"cause": secondary_setup}
		)

	_primary_port = get_live_player_transfer_port()
	_secondary_port = _secondary.get_live_player_transfer_port()
	if _primary_port == null or _secondary_port == null:
		shutdown()
		return _failure("USER1_PRODUCT_SEAM_TRANSFER_PORT_REQUIRED")
	var primary_peer: Dictionary = _primary_port.register_peer(
		_secondary_authority_id,
		_secondary_port
	)
	if not bool(primary_peer.get("success", false)):
		shutdown()
		return primary_peer
	var secondary_peer: Dictionary = _secondary_port.register_peer(
		_primary_authority_id,
		_primary_port
	)
	if not bool(secondary_peer.get("success", false)):
		shutdown()
		return secondary_peer

	var details: Dictionary = Dictionary(
		primary_setup.get("details", {})
	).duplicate(true)
	details["product_seam"] = {
		"enabled": true,
		"primary_authority": _primary_authority_id,
		"secondary_authority": _secondary_authority_id,
		"enter_x_m": SEAM_ENTER_X_M,
		"return_x_m": SEAM_RETURN_X_M,
		"item_graph_owner": "PRIMARY_PRODUCT_M4",
		"resource_owner": "PRIMARY_PRODUCT_RESOURCE_MINING",
		"construction_owner": "PRIMARY_PRODUCT_CONSTRUCTION",
	}
	primary_setup["details"] = details
	return primary_setup


func join(
	logical_player_id: String,
	transport_session_id: String,
	operation_id: String
) -> Dictionary:
	if not _seam_coordinators.is_empty():
		return _failure("USER1_SEAM_JOIN_FROZEN_WHILE_PLAYER_REMOTE")
	var result: Dictionary = super.join(
		logical_player_id,
		transport_session_id,
		operation_id
	)
	if bool(result.get("success", false)):
		var player_id := logical_player_id.strip_edges().to_lower()
		_seam_sessions[player_id] = transport_session_id
		_seam_last_operation[player_id] = operation_id
		if not _seam_state.has(player_id):
			_seam_state[player_id] = _initial_seam_state(player_id)
		else:
			var state: Dictionary = Dictionary(_seam_state[player_id]).duplicate(true)
			state["active_authority_id"] = _primary_authority_id
			state["region_id"] = PRIMARY_REGION
			state["transport_session_id"] = transport_session_id
			_seam_state[player_id] = state
	return result


func leave(
	logical_player_id: String,
	transport_session_id: String,
	operation_id: String
) -> Dictionary:
	var returned := _force_all_primary()
	if not bool(returned.get("success", false)):
		return returned
	var result: Dictionary = super.leave(
		logical_player_id,
		transport_session_id,
		operation_id
	)
	if bool(result.get("success", false)):
		_seam_sessions.erase(logical_player_id)
		_seam_last_operation[logical_player_id] = operation_id
	return result


func leave_transport_session(
	transport_session_id: String,
	operation_id: String
) -> Dictionary:
	var returned := _force_all_primary()
	if not bool(returned.get("success", false)):
		return returned
	var logical_id := ""
	for player_id_value in _seam_sessions:
		if String(_seam_sessions[player_id_value]) == transport_session_id:
			logical_id = String(player_id_value)
			break
	var result: Dictionary = super.leave_transport_session(
		transport_session_id,
		operation_id
	)
	if bool(result.get("success", false)) and not logical_id.is_empty():
		_seam_sessions.erase(logical_id)
		_seam_last_operation[logical_id] = operation_id
	return result


func advance_fixed_server_tick(server_tick: int) -> Dictionary:
	var primary: Dictionary = super.advance_fixed_server_tick(server_tick)
	if not bool(primary.get("success", false)):
		return primary
	if _secondary == null:
		return _failure("USER1_SECONDARY_AUTHORITY_MISSING")
	var secondary: Dictionary = _secondary.advance_fixed_server_tick(server_tick)
	if not bool(secondary.get("success", false)):
		return _failure(
			"USER1_SECONDARY_FIXED_TICK_FAILED",
			{"cause": secondary}
		)
	return primary


func simulate_fixed_movement_tick(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	input_sequence: int,
	intent: Dictionary,
	fixed_delta_seconds: float
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	var active_authority := _active_authority(player_id)
	var authorization := _authorize_active(player_id, active_authority)
	if not bool(authorization.get("success", false)):
		return authorization

	var result: Dictionary
	if active_authority == _secondary_authority_id:
		result = _secondary.simulate_fixed_movement_tick(
			player_id,
			transport_session_id,
			ownership_epoch,
			input_sequence,
			intent,
			fixed_delta_seconds
		)
		if (
			bool(result.get("success", false))
			and bool(result.get("details", {}).get("changed", false))
		):
			note_product_seam_projection_change()
	else:
		result = super.simulate_fixed_movement_tick(
			player_id,
			transport_session_id,
			ownership_epoch,
			input_sequence,
			intent,
			fixed_delta_seconds
		)
	if not bool(result.get("success", false)):
		return result

	var crossed := _maybe_cross(player_id)
	if not bool(crossed.get("success", false)):
		_transfer_failures += 1
		return crossed
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["product_seam"] = get_product_seam_state(player_id)
	result["details"] = details
	return result


func get_player(logical_player_id: String) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if _active_authority(player_id) == _secondary_authority_id:
		return _secondary.get_player(player_id) if _secondary != null else {}
	return super.get_player(player_id)


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.create_snapshot()
	if _secondary == null or _seam_coordinators.is_empty():
		return snapshot
	var by_id: Dictionary = {}
	for player_value in snapshot.get("players", []):
		if player_value is Dictionary:
			var player: Dictionary = player_value
			by_id[String(player.get("logical_player_id", ""))] = player.duplicate(true)
	for player_id_value in _seam_coordinators:
		var player_id := String(player_id_value)
		var active := _active_authority(player_id)
		var player: Dictionary = (
			_secondary.get_player(player_id)
			if active == _secondary_authority_id
			else super.get_player(player_id)
		)
		if player.is_empty():
			by_id.erase(player_id)
		else:
			by_id[player_id] = player.duplicate(true)
	var ids := by_id.keys()
	ids.sort()
	var players: Array = []
	for player_id_value in ids:
		players.append(Dictionary(by_id[player_id_value]).duplicate(true))
	snapshot["players"] = players
	snapshot.erase("checksum")
	snapshot["checksum"] = SeamUtils.payload_hash(snapshot)
	return snapshot


func requires_immediate_join_persistence() -> bool:
	# A transport JOIN is intentionally transient. Durable player exports clear
	# connected/session fields, so blocking JOIN_ACK on a full-world fsync buys
	# no recoverable transport state. Canonical mutations remain sync-durable.
	return false


func _seam_transfers_quiescent() -> bool:
	for player_id_value in _seam_coordinators:
		var player_id := String(player_id_value)
		var decision: Dictionary = _seam_coordinators[player_id].snapshot()
		if String(decision.get("state", "")) != "ACTIVE":
			return false
	return true


func _active_ownership_record(player_id: String) -> Dictionary:
	if _active_authority(player_id) == _secondary_authority_id:
		return (
			_secondary.get_movement_ownership_record(player_id)
			if _secondary != null
			else {}
		)
	return _ownership.get_player(player_id) if _ownership != null else {}


func _validate_product_actor(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if not product_mutation_allowed(player_id):
		return _failure("USER1_SEAM_GAMEPLAY_MUTATION_FROZEN")
	var active_authority := _active_authority(player_id)
	var authorized := _authorize_active(player_id, active_authority)
	if not bool(authorized.get("success", false)):
		return authorized
	var player: Dictionary = get_player(player_id)
	var ownership: Dictionary = _active_ownership_record(player_id)
	if player.is_empty() or ownership.is_empty():
		return _failure("PLAYER_NOT_FOUND")
	if (
		not bool(player.get("connected", false))
		or not bool(ownership.get("connected", false))
	):
		return _failure("PLAYER_NOT_CONNECTED")
	if (
		String(player.get("transport_session_id", "")) != transport_session_id
		or String(ownership.get("transport_session_id", "")) != transport_session_id
	):
		return _failure("STALE_PLAYER_SESSION")
	if (
		int(player.get("ownership_epoch", 0)) != ownership_epoch
		or int(ownership.get("ownership_epoch", 0)) != ownership_epoch
	):
		return _failure("STALE_PLAYER_OWNERSHIP_EPOCH")
	return _success({
		"player": player.duplicate(true),
		"ownership": ownership.duplicate(true),
		"active_authority_id": active_authority,
	})


func _product_actor_context(player: Dictionary) -> Dictionary:
	var position_value: Dictionary = Dictionary(player.get("position", {}))
	var position := Vector3(
		float(position_value.get("x", 0.0)),
		float(position_value.get("y", 0.0)),
		float(position_value.get("z", 0.0))
	)
	var yaw := float(player.get("orientation_yaw", 0.0))
	var view_direction := (-Basis(Vector3.UP, yaw).z).normalized()
	var interaction_origin := position + Vector3(0.0, 0.9, 0.0)
	return {
		"player_position": {"x": position.x, "y": position.y, "z": position.z},
		"interaction_origin": {
			"x": interaction_origin.x,
			"y": interaction_origin.y,
			"z": interaction_origin.z,
		},
		"view_direction": {
			"x": view_direction.x,
			"y": view_direction.y,
			"z": view_direction.z,
		},
		"orientation_yaw": yaw,
		"server_tick": _tick,
	}


func _build_remote_player_durable_state() -> Dictionary:
	var rows: Array = []
	for player_value in create_snapshot().get("players", []):
		if not player_value is Dictionary:
			continue
		var row: Dictionary = Dictionary(player_value).duplicate(true)
		row["connected"] = false
		row["transport_session_id"] = ""
		rows.append(row)
	var state := SeamUtils.finalize_json_checksum({
		"schema": "planet_simulator.player_registry_state.v1",
		"players": rows,
		"checksum": "",
	})
	var checked: Dictionary = _players.validate_durable_state(state)
	return state if bool(checked.get("success", false)) else {}


func _build_remote_ownership_durable_state() -> Dictionary:
	var rows: Array = []
	for player_value in create_snapshot().get("players", []):
		if not player_value is Dictionary:
			continue
		var player_id := String(player_value.get("logical_player_id", ""))
		var row: Dictionary = _active_ownership_record(player_id).duplicate(true)
		if row.is_empty():
			return {}
		row["connected"] = false
		row["transport_session_id"] = ""
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("logical_player_id", "")) < String(b.get("logical_player_id", ""))
	)
	var ownership_report: Dictionary = _ownership.get_report()
	var state := SeamUtils.finalize_json_checksum({
		"schema": "planet_simulator.player_ownership_state.v1",
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": int(ownership_report.get("revision", 0)),
		"server_tick": _tick,
		"players": rows,
		"checksum": "",
	})
	var checked: Dictionary = _ownership.validate_durable_state(state)
	return state if bool(checked.get("success", false)) else {}


func export_durable_state() -> Dictionary:
	if _seam_coordinators.is_empty():
		return super.export_durable_state()
	if not _seam_transfers_quiescent():
		return {}
	var players_state := _build_remote_player_durable_state()
	var ownership_state := _build_remote_ownership_durable_state()
	if (
		players_state.is_empty()
		or ownership_state.is_empty()
		or _shared_items == null
		or _canonical_multiplayer_items == null
		or _resource_mining == null
	):
		return {}
	var state: Dictionary = {
		"schema": DURABLE_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"server_tick": _tick,
		"region_id": _region_id,
		"topology_adapter": _topology_adapter,
		"profile": _profile,
		"players": players_state,
		"ownership": ownership_state,
		"shared_item": _shared_items.export_durable_state(),
		"canonical_item_graph": _canonical_multiplayer_items.export_durable_state(),
		"resource_mining": _resource_mining.export_durable_state(),
		"checksum": "",
	}
	state = SeamUtils.finalize_json_checksum(state)
	var validated := validate_durable_state(state)
	return state if bool(validated.get("success", false)) else {}


func set_player_presentation(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	orientation_yaw: float,
	flashlight_enabled: bool,
	operation_id: String
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if not product_mutation_allowed(player_id):
		return _failure("USER1_SEAM_GAMEPLAY_MUTATION_FROZEN")
	if _active_authority(player_id) == _primary_authority_id:
		return super.set_player_presentation(
			player_id,
			transport_session_id,
			ownership_epoch,
			orientation_yaw,
			flashlight_enabled,
			operation_id
		)
	var fingerprint := SeamUtils.payload_hash({
		"kind": "PLAYER_PRESENTATION",
		"logical_player_id": player_id,
		"transport_session_id": transport_session_id,
		"ownership_epoch": ownership_epoch,
		"orientation_yaw": orientation_yaw,
		"flashlight_enabled": flashlight_enabled,
	})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var actor := _validate_product_actor(
		player_id, transport_session_id, ownership_epoch
	)
	if not bool(actor.get("success", false)):
		return _record_failure(
			operation_id,
			fingerprint,
			String(actor.get("error_code", "PLAYER_OWNERSHIP_REJECTED"))
		)
	var before_revision := _revision
	var updated: Dictionary = _secondary.update_movement_presentation(
		player_id,
		transport_session_id,
		ownership_epoch,
		orientation_yaw,
		flashlight_enabled
	)
	if not bool(updated.get("success", false)):
		return _record_failure(
			operation_id,
			fingerprint,
			String(updated.get("error_code", "PLAYER_PRESENTATION_REJECTED"))
		)
	note_product_seam_projection_change()
	var player: Dictionary = Dictionary(updated.get("details", {}).get("player", {}))
	var delta := _create_delta(
		before_revision, "PLAYER_PRESENTATION_UPDATED", player, {}
	)
	var result := _success({
		"replay": false,
		"player": player.duplicate(true),
		"delta": delta,
		"snapshot": create_snapshot(),
	})
	_record(operation_id, fingerprint, result)
	return result


func handle_canonical_item_command(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	operation_id: String,
	command_type: String,
	payload: Dictionary
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if not product_mutation_allowed(player_id):
		return _failure("USER1_SEAM_GAMEPLAY_MUTATION_FROZEN")
	if _active_authority(player_id) == _primary_authority_id:
		return super.handle_canonical_item_command(
			player_id,
			transport_session_id,
			ownership_epoch,
			operation_id,
			command_type,
			payload
		)
	if _canonical_multiplayer_items == null:
		return _failure("CANONICAL_ITEM_GRAPH_NOT_READY")
	var replay_lookup: Dictionary = _canonical_multiplayer_items.lookup_replay(
		player_id, ownership_epoch, operation_id, command_type, payload
	)
	if bool(replay_lookup.get("found", false)):
		return Dictionary(replay_lookup.get("result", {})).duplicate(true)
	var actor := _validate_product_actor(
		player_id, transport_session_id, ownership_epoch
	)
	if not bool(actor.get("success", false)):
		return _failure(
			String(actor.get("error_code", "PLAYER_OWNERSHIP_REJECTED"))
		)
	var result: Dictionary = _canonical_multiplayer_items.execute(
		player_id,
		ownership_epoch,
		operation_id,
		command_type,
		payload,
		_product_actor_context(
			Dictionary(actor.get("details", {}).get("player", {}))
		)
	)
	if bool(result.get("success", false)) and not bool(result.get("replay", false)):
		_advance()
	return result


func handle_resource_mine(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	operation_id: String,
	payload: Dictionary
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if not product_mutation_allowed(player_id):
		return _failure("USER1_SEAM_GAMEPLAY_MUTATION_FROZEN")
	if _active_authority(player_id) == _primary_authority_id:
		return super.handle_resource_mine(
			player_id,
			transport_session_id,
			ownership_epoch,
			operation_id,
			payload
		)
	if _resource_mining == null:
		return _failure("RESOURCE_MINING_NOT_READY")
	var actor := _validate_product_actor(
		player_id, transport_session_id, ownership_epoch
	)
	if not bool(actor.get("success", false)):
		return actor
	var player: Dictionary = Dictionary(
		actor.get("details", {}).get("player", {})
	)
	var position_value = player.get("position", {})
	if not position_value is Dictionary:
		return _failure("RESOURCE_OUT_OF_RANGE")
	var result: Dictionary = _resource_mining.mine(
		player_id,
		operation_id,
		payload,
		Dictionary(position_value)
	)
	if bool(result.get("success", false)) and not bool(result.get("replay", false)):
		_advance()
	return result


func preflight_canonical_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	if not product_mutation_allowed(logical_player_id):
		return _failure("USER1_SEAM_GAMEPLAY_MUTATION_FROZEN")
	return super.preflight_canonical_server_output(
		operation_id,
		logical_player_id,
		definition_id,
		quantity,
		source_id
	)


func apply_canonical_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	if not product_mutation_allowed(logical_player_id):
		return _failure("USER1_SEAM_GAMEPLAY_MUTATION_FROZEN")
	return super.apply_canonical_server_output(
		operation_id,
		logical_player_id,
		definition_id,
		quantity,
		source_id
	)


func product_mutation_allowed(logical_player_id: String = "") -> bool:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _seam_transfers_quiescent()
	if not _seam_coordinators.has(player_id):
		return true
	return String(
		_seam_coordinators[player_id].snapshot().get("state", "")
	) == "ACTIVE"


func can_persist_product_state() -> bool:
	return _seam_transfers_quiescent()


func prepare_product_persistence() -> Dictionary:
	if not _seam_transfers_quiescent():
		return _failure("USER1_SEAM_PERSISTENCE_TRANSFER_IN_FLIGHT")
	var durable := export_durable_state()
	if durable.is_empty():
		return _failure("USER1_SEAM_DURABLE_PROJECTION_FAILED")
	return _success({
		"quiescent": true,
		"primary_authority_id": _primary_authority_id,
		"remote_binding_count": _seam_coordinators.size(),
		"durable_state_checksum": String(durable.get("checksum", "")),
	})


func get_product_seam_state(logical_player_id: String) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	var state: Dictionary = Dictionary(
		_seam_state.get(player_id, _initial_seam_state(player_id))
	).duplicate(true)
	if _seam_coordinators.has(player_id):
		var decision: Dictionary = _seam_coordinators[player_id].snapshot()
		var authority := String(
			decision.get("active_authority_id", _primary_authority_id)
		)
		state["active_authority_id"] = authority
		state["authority_epoch"] = int(
			decision.get("authority_epoch", state.get("authority_epoch", 1))
		)
		state["region_id"] = (
			SECONDARY_REGION
			if authority == _secondary_authority_id
			else PRIMARY_REGION
		)
		state["transfer_state"] = String(decision.get("state", "ACTIVE"))
	else:
		state["active_authority_id"] = _primary_authority_id
		state["region_id"] = PRIMARY_REGION
		state["transfer_state"] = "ACTIVE"
	state["canonical_state_owned"] = false
	state["decision_owner"] = "SM1_AUTHORITY_TRANSFER_COORDINATOR"
	state["item_graph_owner"] = "PRIMARY_PRODUCT_M4"
	return ProductSeamState.create(state)


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var seam_states: Dictionary = {}
	for player_id_value in _seam_state:
		var player_id := String(player_id_value)
		seam_states[player_id] = get_product_seam_state(player_id)
	report["user1_product_seam"] = {
		"enabled": true,
		"primary_authority": _primary_authority_id,
		"secondary_authority": _secondary_authority_id,
		"enter_x_m": SEAM_ENTER_X_M,
		"return_x_m": SEAM_RETURN_X_M,
		"active_binding_count": _seam_coordinators.size(),
		"persistence_quiescent": can_persist_product_state(),
		"product_mutation_allowed": product_mutation_allowed(),
		"transfer_serial": _transfer_serial,
		"transfer_failures": _transfer_failures,
		"transfers": _transfer_log.duplicate(true),
		"players": seam_states,
		"secondary": (
			_secondary.product_seam_authority_report()
			if _secondary != null
			else {}
		),
		"canonical_state_owned": false,
	}
	return report


func shutdown() -> Dictionary:
	_seam_coordinators.clear()
	_seam_sessions.clear()
	_seam_last_operation.clear()
	if _secondary != null:
		_secondary.shutdown()
		_secondary = null
	_secondary_port = null
	_primary_port = null
	return super.shutdown()


func _maybe_cross(player_id: String) -> Dictionary:
	var authority := _active_authority(player_id)
	var player := get_player(player_id)
	if player.is_empty():
		return _failure("USER1_SEAM_PLAYER_NOT_FOUND")
	var x := float(Dictionary(player.get("position", {})).get("x", 0.0))
	if authority == _primary_authority_id and x >= SEAM_ENTER_X_M:
		var prepared := _ensure_seam_binding(player_id)
		if not bool(prepared.get("success", false)):
			return prepared
		return _perform_transfer(player_id, _secondary_authority_id, false)
	if authority == _secondary_authority_id and x < SEAM_RETURN_X_M:
		return _perform_transfer(player_id, _primary_authority_id, true)
	return _success({"crossed": false})


func _ensure_seam_binding(player_id: String) -> Dictionary:
	if _seam_coordinators.has(player_id):
		return _success({"reused": true})
	var player := super.get_player(player_id)
	if player.is_empty():
		return _failure("USER1_SEAM_PRIMARY_PLAYER_REQUIRED")
	var session_id := String(player.get("transport_session_id", ""))
	var ownership_epoch := int(player.get("ownership_epoch", 0))
	var last_operation_id := String(_seam_last_operation.get(player_id, ""))
	if (
		session_id.is_empty()
		or ownership_epoch < 1
		or last_operation_id.is_empty()
	):
		return _failure("USER1_SEAM_PLAYER_BINDING_INCOMPLETE")

	var state: Dictionary = Dictionary(
		_seam_state.get(player_id, _initial_seam_state(player_id))
	)
	var coordinator = SM1Coordinator.new()
	var configured: Dictionary = coordinator.configure(
		_primary_authority_id,
		int(state.get("authority_epoch", 1)),
		{
			"logical_player_id": player_id,
			"player_entity_id": String(player.get("player_entity_id", "")),
			"last_input_sequence": int(player.get("last_input_sequence", 0)),
			"last_operation_id": last_operation_id,
		}
	)
	if not bool(configured.get("success", false)):
		return configured

	var primary_bound: Dictionary = _primary_port.bind_player(
		player_id,
		session_id,
		ownership_epoch,
		coordinator
	)
	if not bool(primary_bound.get("success", false)):
		return primary_bound
	var secondary_bound: Dictionary = _secondary_port.bind_player(
		player_id,
		session_id,
		ownership_epoch,
		coordinator
	)
	if not bool(secondary_bound.get("success", false)):
		var primary_release: Dictionary = _primary_port.release_binding(player_id)
		if not bool(primary_release.get("success", false)):
			return _failure(
				"USER1_SEAM_BIND_ROLLBACK_FAILED",
				{
					"secondary_cause": secondary_bound,
					"primary_release_cause": primary_release,
				}
			)
		return secondary_bound
	_seam_coordinators[player_id] = coordinator
	return _success({"bound": true})


func _perform_transfer(
	player_id: String,
	target_authority: String,
	release_after: bool
) -> Dictionary:
	if not _seam_coordinators.has(player_id):
		return _failure("USER1_SEAM_COORDINATOR_REQUIRED")
	var coordinator = _seam_coordinators[player_id]
	var decision: Dictionary = coordinator.snapshot()
	var source_authority := String(decision.get("active_authority_id", ""))
	var source_epoch := int(decision.get("authority_epoch", 0))
	if (
		source_authority not in [_primary_authority_id, _secondary_authority_id]
		or target_authority not in [_primary_authority_id, _secondary_authority_id]
		or source_authority == target_authority
	):
		return _failure("USER1_SEAM_TRANSFER_TUPLE_INVALID")

	var source_port = (
		_primary_port
		if source_authority == _primary_authority_id
		else _secondary_port
	)
	var target_port = (
		_primary_port
		if target_authority == _primary_authority_id
		else _secondary_port
	)
	var source_service = (
		self
		if source_authority == _primary_authority_id
		else _secondary
	)
	var before: Dictionary = source_service.get_player(player_id)
	if before.is_empty():
		return _failure("USER1_SEAM_SOURCE_PLAYER_REQUIRED")

	_transfer_serial += 1
	var transfer_id := "transfer/user1/%s/%06d" % [
		player_id.sha256_text().left(12),
		_transfer_serial,
	]
	var begun: Dictionary = coordinator.begin_transfer(
		transfer_id,
		source_authority,
		target_authority,
		source_epoch
	)
	if not bool(begun.get("success", false)):
		return begun

	var manifest := _build_carry_manifest(
		player_id,
		transfer_id,
		source_authority,
		target_authority,
		source_epoch,
		source_epoch + 1,
		before
	)
	var exported: Dictionary = source_port.prepare_export(
		player_id,
		transfer_id,
		manifest
	)
	if not bool(exported.get("success", false)):
		_abort_transfer_before_commit(player_id, source_authority, transfer_id)
		return exported
	var packet: Dictionary = Dictionary(
		exported.get("details", {}).get("packet", {})
	)
	var staged: Dictionary = target_port.stage_export(player_id, packet)
	if not bool(staged.get("success", false)):
		_abort_transfer_before_commit(player_id, source_authority, transfer_id)
		return staged

	var shadow: Dictionary = Dictionary(
		staged.get("details", {}).get("shadow_report", {})
	)
	var warm_report := _build_warm_report(
		transfer_id,
		shadow,
		String(manifest.get("manifest_checksum", ""))
	)
	var warm: Dictionary = coordinator.validate_warm_target(
		transfer_id,
		target_authority,
		warm_report
	)
	if not bool(warm.get("success", false)):
		_abort_transfer_before_commit(player_id, source_authority, transfer_id)
		return warm

	var committed: Dictionary = coordinator.commit_ownership(
		transfer_id,
		source_authority,
		target_authority,
		source_epoch,
		source_epoch + 1
	)
	if not bool(committed.get("success", false)):
		_abort_transfer_before_commit(player_id, source_authority, transfer_id)
		return committed
	var token := String(committed.get("details", {}).get("commit_token", ""))
	var source_retired: Dictionary = source_port.retire_source(
		player_id,
		transfer_id,
		token
	)
	if not bool(source_retired.get("success", false)):
		return source_retired
	var coordinator_retired: Dictionary = coordinator.retire_source(
		transfer_id,
		source_authority,
		token
	)
	if not bool(coordinator_retired.get("success", false)):
		return coordinator_retired
	var coordinator_activated: Dictionary = coordinator.activate_target(
		transfer_id,
		target_authority,
		source_epoch + 1,
		token
	)
	if not bool(coordinator_activated.get("success", false)):
		return coordinator_activated
	var target_activated: Dictionary = target_port.activate_target(
		player_id,
		transfer_id,
		token
	)
	if not bool(target_activated.get("success", false)):
		return target_activated

	var after: Dictionary = (
		super.get_player(player_id)
		if target_authority == _primary_authority_id
		else _secondary.get_player(player_id)
	)
	if (
		after.is_empty()
		or String(after.get("player_entity_id", ""))
			!= String(before.get("player_entity_id", ""))
		or String(after.get("transport_session_id", ""))
			!= String(before.get("transport_session_id", ""))
		or int(after.get("ownership_epoch", 0))
			!= int(before.get("ownership_epoch", -1))
		or int(after.get("last_input_sequence", -1))
			!= int(before.get("last_input_sequence", -2))
	):
		return _failure("USER1_SEAM_IDENTITY_CONTINUITY_FAILED")

	var state: Dictionary = Dictionary(
		_seam_state.get(player_id, _initial_seam_state(player_id))
	).duplicate(true)
	state["active_authority_id"] = target_authority
	state["authority_epoch"] = source_epoch + 1
	state["region_id"] = (
		PRIMARY_REGION
		if target_authority == _primary_authority_id
		else SECONDARY_REGION
	)
	state["crossings"] = int(state.get("crossings", 0)) + 1
	if target_authority == _secondary_authority_id:
		state["secondary_entries"] = int(state.get("secondary_entries", 0)) + 1
	if target_authority == _primary_authority_id:
		state["roundtrips"] = int(state.get("roundtrips", 0)) + 1
	state["last_transfer_id"] = transfer_id
	_seam_state[player_id] = state

	_transfer_log.append({
		"transfer_id": transfer_id,
		"logical_player_id": player_id,
		"source_authority_id": source_authority,
		"target_authority_id": target_authority,
		"source_epoch": source_epoch,
		"target_epoch": source_epoch + 1,
		"player_entity_id": String(after.get("player_entity_id", "")),
		"last_input_sequence": int(after.get("last_input_sequence", 0)),
		"item_graph_transferred": false,
	})
	if _transfer_log.size() > 64:
		_transfer_log.pop_front()

	# The primary service owns the external product snapshot revision. Handoff
	# itself is an observable state transition even before the next movement.
	note_product_seam_projection_change()

	if release_after:
		var released := _release_roundtrip_binding(player_id)
		if not bool(released.get("success", false)):
			return released
	return _success({
		"crossed": true,
		"transfer_id": transfer_id,
		"state": get_product_seam_state(player_id),
	})


func _abort_transfer_before_commit(
	player_id: String,
	source_authority: String,
	transfer_id: String
) -> Dictionary:
	if not _seam_coordinators.has(player_id):
		return _success({"replay": true})
	var coordinator = _seam_coordinators[player_id]
	var aborted: Dictionary = coordinator.abort_before_commit(
		transfer_id,
		source_authority
	)
	if not bool(aborted.get("success", false)):
		return aborted
	var source_port = (
		_primary_port
		if source_authority == _primary_authority_id
		else _secondary_port
	)
	var target_port = (
		_secondary_port
		if source_authority == _primary_authority_id
		else _primary_port
	)
	# discard_aborted_stage requires the coordinator to be ACTIVE on the source,
	# therefore cleanup intentionally happens after SM1 abort.
	target_port.discard_aborted_stage(player_id, transfer_id)
	source_port.discard_aborted_stage(player_id, transfer_id)
	if source_authority == _primary_authority_id:
		var primary_release: Dictionary = _primary_port.release_binding(player_id)
		if not bool(primary_release.get("success", false)):
			return primary_release
		var secondary_release: Dictionary = _secondary_port.release_binding(player_id)
		if not bool(secondary_release.get("success", false)):
			return secondary_release
		_seam_coordinators.erase(player_id)
	return _success({
		"aborted": true,
		"source_authority_id": source_authority,
		"persistence_quiescent": _seam_coordinators.is_empty(),
	})


func _force_all_primary() -> Dictionary:
	var players := _seam_coordinators.keys().duplicate()
	for player_id_value in players:
		var player_id := String(player_id_value)
		if _active_authority(player_id) == _secondary_authority_id:
			var returned := _perform_transfer(
				player_id,
				_primary_authority_id,
				true
			)
			if not bool(returned.get("success", false)):
				return returned
		elif _seam_coordinators.has(player_id):
			var released := _release_roundtrip_binding(player_id)
			if not bool(released.get("success", false)):
				return released
	return _success({"quiescent": true})


func _release_roundtrip_binding(player_id: String) -> Dictionary:
	if not _seam_coordinators.has(player_id):
		return _success({"replay": true})
	if _active_authority(player_id) != _primary_authority_id:
		return _failure("USER1_SEAM_RELEASE_REQUIRES_PRIMARY")
	var primary_release: Dictionary = _primary_port.release_binding(player_id)
	if not bool(primary_release.get("success", false)):
		return primary_release
	var secondary_release: Dictionary = _secondary_port.release_binding(player_id)
	if not bool(secondary_release.get("success", false)):
		return secondary_release
	_seam_coordinators.erase(player_id)
	return _success({"released": true, "persistence_quiescent": true})


func _authorize_active(player_id: String, authority_id: String) -> Dictionary:
	if not _seam_coordinators.has(player_id):
		return (
			_success()
			if authority_id == _primary_authority_id
			else _failure("USER1_SEAM_PRIMARY_EXPECTED")
		)
	var decision: Dictionary = _seam_coordinators[player_id].snapshot()
	return _seam_coordinators[player_id].authorize_write(
		authority_id,
		int(decision.get("authority_epoch", 0))
	)


func _active_authority(player_id: String) -> String:
	if not _seam_coordinators.has(player_id):
		return _primary_authority_id
	return String(
		_seam_coordinators[player_id].snapshot().get(
			"active_authority_id",
			_primary_authority_id
		)
	)


func _build_carry_manifest(
	player_id: String,
	transfer_id: String,
	source_authority: String,
	target_authority: String,
	source_epoch: int,
	target_epoch: int,
	player: Dictionary
) -> Dictionary:
	var last_operation_id := String(_seam_last_operation.get(player_id, ""))
	var manifest := {
		"schema": "distributed_world_simulator.user1_product_carry_manifest.v1",
		"logical_player_id": player_id,
		"player_entity_id": String(player.get("player_entity_id", "")),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"last_operation_id": last_operation_id,
		"closure_view": {
			"carried_operations": [last_operation_id],
			"canonical_item_graph_owner": "PRIMARY_PRODUCT_M4",
			"item_graph_transferred": false,
		},
		"transfer_id": transfer_id,
		"source_authority_id": source_authority,
		"target_authority_id": target_authority,
		"source_epoch": source_epoch,
		"target_epoch": target_epoch,
		"captured_after_source_freeze": true,
	}
	manifest["manifest_checksum"] = _manifest_checksum(manifest)
	return manifest


func _build_warm_report(
	transfer_id: String,
	shadow_report: Dictionary,
	manifest_checksum: String
) -> Dictionary:
	var shadow_checksum := String(shadow_report.get("checksum", ""))
	var payload := {
		"schema": Carry.WARM_SCHEMA,
		"transfer_id": transfer_id,
		"p6_shadow_checksum": shadow_checksum,
		"carrying_manifest_checksum": manifest_checksum,
	}
	var result := shadow_report.duplicate(true)
	result["schema"] = Carry.WARM_SCHEMA
	result["checksum"] = SeamUtils.payload_hash(payload)
	result["previous_warm_checksum"] = shadow_checksum
	result["p6_shadow_checksum"] = shadow_checksum
	result["carrying_manifest_checksum"] = manifest_checksum
	result["transfer_id"] = transfer_id
	result["derived_only"] = true
	return result


func _manifest_checksum(manifest: Dictionary) -> String:
	var payload := manifest.duplicate(true)
	payload.erase("manifest_checksum")
	return SeamUtils.payload_hash(payload)


func _initial_seam_state(player_id: String) -> Dictionary:
	return {
		"logical_player_id": player_id,
		"transport_session_id": String(_seam_sessions.get(player_id, "")),
		"active_authority_id": _primary_authority_id,
		"authority_epoch": 1,
		"region_id": PRIMARY_REGION,
		"transfer_state": "ACTIVE",
		"crossings": 0,
		"secondary_entries": 0,
		"roundtrips": 0,
		"last_transfer_id": "",
	}
