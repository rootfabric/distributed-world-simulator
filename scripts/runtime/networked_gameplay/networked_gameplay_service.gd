extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const JoinCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_join_command.gd")
const LeaveCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_leave_command.gd")
const InputCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const PresentationCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_presentation_command.gd")
const ItemCommand = preload("res://scripts/runtime/networked_gameplay/contracts/item_command.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const PlayerDelta = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")
const ItemGraphSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_snapshot.gd")
const OwnershipService = preload("res://scripts/runtime/networked_gameplay/services/player_ownership_service.gd")
const PlayerRegistry = preload("res://scripts/runtime/networked_gameplay/services/player_registry.gd")
const MovementService = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const SharedItemService = preload("res://scripts/runtime/networked_gameplay/services/shared_item_fixture_service.gd")
const ResultRouter = preload("res://scripts/runtime/networked_gameplay/services/command_result_router.gd")
const ReplicationPublisher = preload("res://scripts/runtime/networked_gameplay/services/replication_publisher.gd")
const ItemGraphService = preload("res://scripts/runtime/networked_gameplay/services/item_graph_service.gd")
const ContainerInteractionService = preload("res://scripts/runtime/networked_gameplay/services/container_interaction_service.gd")
const MountInteractionService = preload("res://scripts/runtime/networked_gameplay/services/mount_interaction_service.gd")
const CanonicalPlayableBackend = preload("res://scripts/runtime/networked_gameplay/backends/canonical_playable_backend.gd")
const CanonicalMultiplayerItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const SCHEMA := "planet_simulator.networked_gameplay_service.v1"
const SNAPSHOT_SCHEMA := PlayerSnapshot.SCHEMA
const DELTA_SCHEMA := PlayerDelta.SCHEMA
const SHARED_ITEM_ID := SharedItemService.SHARED_ITEM_ID
const PROFILE_MULTIPLAYER_CORE := "MULTIPLAYER_CORE"
const PROFILE_CANONICAL_PLAYABLE := "CANONICAL_PLAYABLE"
const DURABLE_SCHEMA := "planet_simulator.networked_gameplay_durable_state.v1"
const REPLAY_SCHEMA := "planet_simulator.networked_gameplay_replay_state.v1"

var _configured := false
var _authority_owner_id := ""
var _authority_epoch := 0
var _revision := 0
var _tick := 0
var _region_id := "region/m1/default"
var _topology_adapter := "UNSPECIFIED"
var _profile := PROFILE_MULTIPLAYER_CORE
var _ownership
var _players
var _movement
var _shared_items
var _result_router
var _replication
var _item_graph_service
var _container_interactions
var _mount_interactions
var _playable_backend
var _operation_ledger: Dictionary = {}
var _canonical_multiplayer_items
var _playable_sandbox := false


func setup(authority_owner_id: String, authority_epoch: int, server_tick: int = 0, config: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_ALREADY_CONFIGURED")
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1 or server_tick < 0:
		return _failure("INVALID_MULTIPLAYER_AUTHORITY_CONFIGURATION")
	_authority_owner_id = authority_owner_id.strip_edges()
	_authority_epoch = authority_epoch
	_tick = server_tick
	_revision = 0
	_region_id = String(config.get("region_id", "region/m1/default")).strip_edges()
	_topology_adapter = String(config.get("topology_adapter", "UNSPECIFIED")).strip_edges().to_upper()
	_profile = String(config.get("profile", PROFILE_MULTIPLAYER_CORE)).strip_edges().to_upper()
	_playable_sandbox = bool(config.get("playable_sandbox", false))
	if _region_id.is_empty() or _topology_adapter.is_empty() or _profile not in [PROFILE_MULTIPLAYER_CORE, PROFILE_CANONICAL_PLAYABLE]:
		return _failure("INVALID_NETWORKED_GAMEPLAY_CONFIGURATION")
	_operation_ledger.clear()
	_ownership = OwnershipService.new()
	var ownership_setup: Dictionary = _ownership.setup(_authority_owner_id, _authority_epoch, server_tick)
	if not bool(ownership_setup.get("success", false)):
		return ownership_setup
	_players = PlayerRegistry.new()
	_players.clear()
	_movement = MovementService.new()
	_shared_items = SharedItemService.new()
	_shared_items.setup()
	_canonical_multiplayer_items = CanonicalMultiplayerItemGraph.new()
	var multiplayer_items_setup: Dictionary = _canonical_multiplayer_items.setup(_authority_owner_id, _authority_epoch, {"playable_sandbox": _playable_sandbox})
	if not bool(multiplayer_items_setup.get("success", false)):
		return multiplayer_items_setup
	_result_router = ResultRouter.new()
	_replication = ReplicationPublisher.new()
	_configured = true
	return _success({"snapshot": create_snapshot(), "profile": _profile, "topology_adapter": _topology_adapter})


func setup_playable(config: Dictionary) -> Dictionary:
	var core_setup := setup(
		String(config.get("authority_owner_id", "local-listen-host")),
		int(config.get("authority_epoch", 1)),
		int(config.get("server_tick", 0)),
		{"profile": PROFILE_CANONICAL_PLAYABLE, "topology_adapter": String(config.get("topology_adapter", "LOOPBACK")), "region_id": String(config.get("region_id", "region/m1/playable"))}
	)
	if not bool(core_setup.get("success", false)):
		return core_setup
	_playable_backend = CanonicalPlayableBackend.new()
	_playable_backend.name = "CanonicalPlayableBackend"
	var backend_setup: Dictionary = _playable_backend.setup(config)
	if not bool(backend_setup.get("success", false)):
		_playable_backend.free()
		_playable_backend = null
		_configured = false
		return backend_setup
	_item_graph_service = ItemGraphService.new()
	var item_graph_setup: Dictionary = _item_graph_service.setup(_playable_backend)
	if not bool(item_graph_setup.get("success", false)):
		shutdown()
		return item_graph_setup
	_container_interactions = ContainerInteractionService.new()
	var container_setup: Dictionary = _container_interactions.setup(_item_graph_service)
	if not bool(container_setup.get("success", false)):
		shutdown()
		return container_setup
	_mount_interactions = MountInteractionService.new()
	var mount_setup: Dictionary = _mount_interactions.setup(_item_graph_service)
	if not bool(mount_setup.get("success", false)):
		shutdown()
		return mount_setup
	return backend_setup


func handle_join_command(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	var validation := JoinCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_JOIN_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var operation_id := String(command.get("operation_id", ""))
	var fingerprint := Utils.payload_hash(command)
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var ownership_result: Dictionary = _ownership.handle_join_command(command)
	if not bool(ownership_result.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(ownership_result.get("error_code", "OWNERSHIP_JOIN_FAILED")))
	var ownership_record: Dictionary = ownership_result.get("details", {}).get("player", {})
	var logical_player_id := String(ownership_record.get("logical_player_id", ""))
	var before_revision := _revision
	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		record = {
			"logical_player_id": logical_player_id,
			"player_entity_id": String(ownership_record.get("player_entity_id", "player/%s" % logical_player_id)),
			"transport_session_id": String(ownership_record.get("transport_session_id", "")),
			"ownership_epoch": int(ownership_record.get("ownership_epoch", 1)),
			"connected": true,
			"position": _spawn_position(logical_player_id),
			"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
			"inventory": [],
			"last_input_sequence": 0,
			"state_revision": 1,
			"orientation_yaw": 0.0,
			"flashlight_enabled": false,
		}
	else:
		record["transport_session_id"] = String(ownership_record.get("transport_session_id", ""))
		record["ownership_epoch"] = int(ownership_record.get("ownership_epoch", int(record.get("ownership_epoch", 0)) + 1))
		record["connected"] = true
		record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players.upsert(record)
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_JOINED", record, {})
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func handle_leave_command(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	var validation := LeaveCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_LEAVE_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var operation_id := String(command.get("operation_id", ""))
	var fingerprint := Utils.payload_hash(command)
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var logical_player_id := String(command.get("logical_player_id", ""))
	var ownership_result: Dictionary = _ownership.handle_leave_command(command)
	if not bool(ownership_result.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(ownership_result.get("error_code", "OWNERSHIP_LEAVE_FAILED")))
	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		return _record_failure(operation_id, fingerprint, "PLAYER_STATE_NOT_FOUND")
	var before_revision := _revision
	record["connected"] = false
	record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players.upsert(record)
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_LEFT", record, {})
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func handle_player_input(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	var validation := InputCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_INPUT_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var operation_id := String(command.get("operation_id", ""))
	var fingerprint := Utils.payload_hash(command)
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var logical_player_id := String(command.get("logical_player_id", ""))
	var owner_check := _validate_owner(logical_player_id, String(command.get("transport_session_id", "")), int(command.get("ownership_epoch", 0)))
	if not bool(owner_check.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	var record: Dictionary = _players.get_player(logical_player_id)
	var movement_result: Dictionary
	var input_kind := String(command.get("input_kind", ""))
	if input_kind == "MOVEMENT_DELTA":
		movement_result = _movement.apply_delta(
			record,
			int(command.get("input_sequence", 0)),
			float(command.get("payload", {}).get("delta_x", 0.0)),
			float(command.get("payload", {}).get("delta_z", 0.0))
		)
	elif input_kind == "MOVEMENT_INTENT":
		if not _playable_sandbox:
			return _record_failure(operation_id, fingerprint, "MOVEMENT_INTENT_REQUIRES_PLAYABLE_SANDBOX")
		movement_result = _movement.apply_movement_intent(
			record,
			int(command.get("input_sequence", 0)),
			Dictionary(command.get("payload", {}))
		)
	else:
		return _record_failure(operation_id, fingerprint, "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")
	if not bool(movement_result.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(movement_result.get("error_code", "PLAYER_MOVE_REJECTED")))
	var before_revision := _revision
	record = movement_result.get("details", {}).get("player", {}).duplicate(true)
	_players.upsert(record)
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_MOVED", record, {})
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func handle_player_presentation(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	var validation := PresentationCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_PRESENTATION_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var operation_id := String(command.get("operation_id", ""))
	var fingerprint := Utils.payload_hash(command)
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var logical_player_id := String(command.get("logical_player_id", ""))
	var owner_check := _validate_owner(logical_player_id, String(command.get("transport_session_id", "")), int(command.get("ownership_epoch", 0)))
	if not bool(owner_check.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		return _record_failure(operation_id, fingerprint, "PLAYER_STATE_NOT_FOUND")
	var before_revision := _revision
	record["orientation_yaw"] = float(command.get("orientation_yaw", 0.0))
	record["flashlight_enabled"] = bool(command.get("flashlight_enabled", false))
	record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players.upsert(record)
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_PRESENTATION_UPDATED", record, {})
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func handle_item_command(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	var validation := ItemCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_ITEM_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var operation_id := String(command.get("operation_id", ""))
	var fingerprint := Utils.payload_hash(command)
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var logical_player_id := String(command.get("logical_player_id", ""))
	var owner_check := _validate_owner(logical_player_id, String(command.get("transport_session_id", "")), int(command.get("ownership_epoch", 0)))
	if not bool(owner_check.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	var command_type := String(command.get("command_type", ""))
	if command_type == "item.pickup_shared_fixture":
		var item_id := String(command.get("payload", {}).get("item_id", ""))
		var record: Dictionary = _players.get_player(logical_player_id)
		var claimed: Dictionary = _shared_items.claim(item_id, String(record.get("player_entity_id", "")))
		if not bool(claimed.get("success", false)):
			return _record_failure(operation_id, fingerprint, String(claimed.get("error_code", "ITEM_COMMAND_REJECTED")), claimed.get("details", {}))
		var before_revision := _revision
		var inventory: Array = Array(record.get("inventory", [])).duplicate(true)
		if item_id not in inventory:
			inventory.append(item_id)
		record["inventory"] = inventory
		record["state_revision"] = int(record.get("state_revision", 0)) + 1
		_players.upsert(record)
		_advance()
		var shared_item: Dictionary = _shared_items.get_item()
		var delta := _create_delta(before_revision, "ITEM_PICKED_UP", record, shared_item)
		var result := _success({"replay": false, "player": record.duplicate(true), "shared_item": shared_item, "delta": delta, "snapshot": create_snapshot()})
		_record(operation_id, fingerprint, result)
		return result
	if command_type == "inventory.permission_probe":
		var target_player_id := String(command.get("payload", {}).get("target_player_id", "")).strip_edges().to_lower()
		if target_player_id != logical_player_id:
			return _record_failure(operation_id, fingerprint, "PLAYER_PERMISSION_DENIED")
		var permission_result := _success({"replay": false, "player": _players.get_player(logical_player_id)})
		_record(operation_id, fingerprint, permission_result)
		return permission_result
	return _record_failure(operation_id, fingerprint, "UNSUPPORTED_ITEM_COMMAND")


func join(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	return handle_join_command(JoinCommand.create("message/m1/join/%s" % operation_id.sha256_text().left(12), operation_id, logical_player_id, transport_session_id, _authority_epoch))


func leave(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	var player: Dictionary = _players.get_player(logical_player_id)
	return handle_leave_command(LeaveCommand.create("message/m1/leave/%s" % operation_id.sha256_text().left(12), operation_id, logical_player_id, transport_session_id, _authority_epoch, int(player.get("ownership_epoch", 1))))


func leave_transport_session(transport_session_id: String, operation_id: String) -> Dictionary:
	var player: Dictionary = _ownership.get_player_for_session(transport_session_id)
	if player.is_empty():
		return _success({"replay": true, "snapshot": create_snapshot()})
	return leave(String(player.get("logical_player_id", "")), transport_session_id, operation_id)


func move_player(logical_player_id: String, transport_session_id: String, ownership_epoch: int, input_sequence: int, delta_x: float, delta_z: float, operation_id: String) -> Dictionary:
	return handle_player_input(InputCommand.create("message/m1/move/%s" % operation_id.sha256_text().left(12), operation_id, logical_player_id, transport_session_id, _authority_epoch, ownership_epoch, input_sequence, "MOVEMENT_DELTA", {"delta_x": delta_x, "delta_z": delta_z}))



func submit_movement_intent(logical_player_id: String, transport_session_id: String, ownership_epoch: int, input_sequence: int, intent: Dictionary, operation_id: String) -> Dictionary:
	return handle_player_input(InputCommand.create(
		"message/m7/input/%s" % operation_id.sha256_text().left(12),
		operation_id,
		logical_player_id,
		transport_session_id,
		_authority_epoch,
		ownership_epoch,
		input_sequence,
		"MOVEMENT_INTENT",
		intent.duplicate(true)
	))

func submit_player_state(logical_player_id: String, transport_session_id: String, ownership_epoch: int, input_sequence: int, player_state: Dictionary, delta_seconds: float, operation_id: String) -> Dictionary:
	return handle_player_input(InputCommand.create(
		"message/m7/rejected-state/%s" % operation_id.sha256_text().left(12),
		operation_id,
		logical_player_id,
		transport_session_id,
		_authority_epoch,
		ownership_epoch,
		input_sequence,
		"AUTHORITATIVE_STATE",
		{"player_state": player_state.duplicate(true), "delta_seconds": delta_seconds}
	))

func set_player_presentation(logical_player_id: String, transport_session_id: String, ownership_epoch: int, orientation_yaw: float, flashlight_enabled: bool, operation_id: String) -> Dictionary:
	return handle_player_presentation(PresentationCommand.create("message/m3/presentation/%s" % operation_id.sha256_text().left(12), operation_id, logical_player_id, transport_session_id, _authority_epoch, ownership_epoch, orientation_yaw, flashlight_enabled))


func pickup_shared_item(logical_player_id: String, transport_session_id: String, ownership_epoch: int, item_id: String, operation_id: String) -> Dictionary:
	return handle_item_command(ItemCommand.create("message/m1/item/%s" % operation_id.sha256_text().left(12), operation_id, logical_player_id, transport_session_id, _authority_epoch, ownership_epoch, 0, "item.pickup_shared_fixture", {"item_id": item_id}))


func request_inventory_write(requester_player_id: String, target_player_id: String, transport_session_id: String, ownership_epoch: int, operation_id: String) -> Dictionary:
	return handle_item_command(ItemCommand.create("message/m1/inventory/%s" % operation_id.sha256_text().left(12), operation_id, requester_player_id, transport_session_id, _authority_epoch, ownership_epoch, 0, "inventory.permission_probe", {"target_player_id": target_player_id}))



func handle_canonical_item_command(logical_player_id: String, transport_session_id: String, ownership_epoch: int, operation_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	if not _configured or _canonical_multiplayer_items == null:
		return _failure("CANONICAL_ITEM_GRAPH_NOT_READY")
	var replay_lookup: Dictionary = _canonical_multiplayer_items.lookup_replay(
		logical_player_id, ownership_epoch, operation_id, command_type, payload
	)
	if bool(replay_lookup.get("found", false)):
		return Dictionary(replay_lookup.get("result", {})).duplicate(true)
	var owner_check := _validate_owner(logical_player_id, transport_session_id, ownership_epoch)
	if not bool(owner_check.get("success", false)):
		return _failure(String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	var result: Dictionary = _canonical_multiplayer_items.execute(
		logical_player_id,
		ownership_epoch,
		operation_id,
		command_type,
		payload,
		_create_item_authority_context(logical_player_id)
	)
	if bool(result.get("success", false)) and not bool(result.get("replay", false)):
		_advance()
	return result


func create_canonical_item_graph_snapshot() -> Dictionary:
	return _canonical_multiplayer_items.create_snapshot() if _canonical_multiplayer_items != null else {}


func validate_canonical_item_graph_snapshot(snapshot: Dictionary) -> Dictionary:
	return _canonical_multiplayer_items.validate_snapshot(snapshot) if _canonical_multiplayer_items != null else _failure("CANONICAL_ITEM_GRAPH_NOT_READY")

func export_durable_state() -> Dictionary:
	if not _configured:
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
		"players": _players.export_durable_state(),
		"ownership": _ownership.export_durable_state(),
		"shared_item": _shared_items.export_durable_state(),
		"canonical_item_graph": _canonical_multiplayer_items.export_durable_state(),
		"checksum": "",
	}
	state["checksum"] = _state_checksum(state)
	return state


func restore_durable_state(value: Dictionary) -> Dictionary:
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	if _configured:
		if String(value.get("authority_owner_id", "")) != _authority_owner_id:
			return _failure("GAMEPLAY_RECOVERY_OWNER_MISMATCH")
		if int(value.get("authority_epoch", 0)) != _authority_epoch:
			return _failure("GAMEPLAY_RECOVERY_EPOCH_MISMATCH")
	var staged_players = PlayerRegistry.new()
	var players_result: Dictionary = staged_players.restore_durable_state(Dictionary(value.get("players", {})))
	if not bool(players_result.get("success", false)):
		return _failure("GAMEPLAY_PLAYER_RECOVERY_FAILED", {"cause": players_result})
	var staged_ownership = OwnershipService.new()
	var ownership_setup: Dictionary = staged_ownership.setup(
		String(value.get("authority_owner_id", "")),
		int(value.get("authority_epoch", 0)),
		0
	)
	if not bool(ownership_setup.get("success", false)):
		return _failure("GAMEPLAY_OWNERSHIP_RECOVERY_SETUP_FAILED", {"cause": ownership_setup})
	var ownership_result: Dictionary = staged_ownership.restore_durable_state(Dictionary(value.get("ownership", {})))
	if not bool(ownership_result.get("success", false)):
		return _failure("GAMEPLAY_OWNERSHIP_RECOVERY_FAILED", {"cause": ownership_result})
	var staged_shared = SharedItemService.new()
	staged_shared.setup()
	var shared_result: Dictionary = staged_shared.restore_durable_state(Dictionary(value.get("shared_item", {})))
	if not bool(shared_result.get("success", false)):
		return _failure("GAMEPLAY_SHARED_ITEM_RECOVERY_FAILED", {"cause": shared_result})
	var staged_items = CanonicalMultiplayerItemGraph.new()
	var durable_item_state: Dictionary = Dictionary(value.get("canonical_item_graph", {}))
	var durable_item_snapshot: Dictionary = Dictionary(durable_item_state.get("snapshot", {}))
	var item_setup: Dictionary = staged_items.setup(
		String(value.get("authority_owner_id", "")),
		int(value.get("authority_epoch", 0)),
		{"playable_sandbox": bool(durable_item_snapshot.get("playable_sandbox", _playable_sandbox))}
	)
	if not bool(item_setup.get("success", false)):
		return _failure("GAMEPLAY_ITEM_RECOVERY_SETUP_FAILED", {"cause": item_setup})
	var item_result: Dictionary = staged_items.restore_durable_state(durable_item_state)
	if not bool(item_result.get("success", false)):
		return _failure("GAMEPLAY_ITEM_RECOVERY_FAILED", {"cause": item_result})
	var consistency := _validate_recovered_player_consistency(staged_players, staged_ownership)
	if not bool(consistency.get("success", false)):
		return consistency
	_authority_owner_id = String(value.get("authority_owner_id", ""))
	_authority_epoch = int(value.get("authority_epoch", 0))
	_revision = int(value.get("revision", 0))
	_tick = int(value.get("server_tick", 0))
	_region_id = String(value.get("region_id", ""))
	_topology_adapter = String(value.get("topology_adapter", ""))
	_profile = String(value.get("profile", PROFILE_MULTIPLAYER_CORE))
	_playable_sandbox = bool(durable_item_snapshot.get("playable_sandbox", false))
	_players = staged_players
	_ownership = staged_ownership
	_shared_items = staged_shared
	_canonical_multiplayer_items = staged_items
	_movement = MovementService.new()
	_result_router = ResultRouter.new()
	_replication = ReplicationPublisher.new()
	_operation_ledger.clear()
	_configured = true
	return _success({
		"revision": _revision,
		"server_tick": _tick,
		"player_count": _players.get_players().size(),
		"item_graph_checksum": String(create_canonical_item_graph_snapshot().get("checksum", "")),
	})


func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA:
		return _failure("INVALID_GAMEPLAY_DURABLE_SCHEMA")
	var required := [
		"authority_owner_id", "authority_epoch", "revision", "server_tick", "region_id",
		"topology_adapter", "profile", "players", "ownership", "shared_item",
		"canonical_item_graph", "checksum",
	]
	for field in required:
		if not value.has(field):
			return _failure("GAMEPLAY_DURABLE_FIELD_MISSING", {"field": field})
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty():
		return _failure("INVALID_GAMEPLAY_DURABLE_OWNER")
	if int(value.get("authority_epoch", 0)) < 1 or int(value.get("revision", -1)) < 0 or int(value.get("server_tick", -1)) < 0:
		return _failure("INVALID_GAMEPLAY_DURABLE_REVISION")
	if String(value.get("region_id", "")).strip_edges().is_empty() or String(value.get("topology_adapter", "")).strip_edges().is_empty():
		return _failure("INVALID_GAMEPLAY_DURABLE_TOPOLOGY")
	if String(value.get("profile", "")) not in [PROFILE_MULTIPLAYER_CORE, PROFILE_CANONICAL_PLAYABLE]:
		return _failure("INVALID_GAMEPLAY_DURABLE_PROFILE")
	if String(value.get("profile", "")) != PROFILE_MULTIPLAYER_CORE:
		return _failure("M6_RECOVERY_REQUIRES_MULTIPLAYER_CORE_PROFILE")
	for section in ["players", "ownership", "shared_item", "canonical_item_graph"]:
		if typeof(value.get(section)) != TYPE_DICTIONARY:
			return _failure("INVALID_GAMEPLAY_DURABLE_SECTION", {"section": section})
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("GAMEPLAY_DURABLE_CHECKSUM_MISMATCH")
	var players_validator = PlayerRegistry.new()
	var players_result: Dictionary = players_validator.validate_durable_state(Dictionary(value.get("players", {})))
	if not bool(players_result.get("success", false)):
		return _failure("INVALID_GAMEPLAY_PLAYER_STATE", {"cause": players_result})
	var ownership_validator = OwnershipService.new()
	var ownership_result: Dictionary = ownership_validator.validate_durable_state(Dictionary(value.get("ownership", {})))
	if not bool(ownership_result.get("success", false)):
		return _failure("INVALID_GAMEPLAY_OWNERSHIP_STATE", {"cause": ownership_result})
	var shared_validator = SharedItemService.new()
	var shared_result: Dictionary = shared_validator.validate_durable_state(Dictionary(value.get("shared_item", {})))
	if not bool(shared_result.get("success", false)):
		return _failure("INVALID_GAMEPLAY_SHARED_ITEM_STATE", {"cause": shared_result})
	var item_validator = CanonicalMultiplayerItemGraph.new()
	var durable_item_state: Dictionary = Dictionary(value.get("canonical_item_graph", {}))
	var durable_item_snapshot: Dictionary = Dictionary(durable_item_state.get("snapshot", {}))
	var validator_setup: Dictionary = item_validator.setup(
		String(value.get("authority_owner_id", "")),
		int(value.get("authority_epoch", 0)),
		{"playable_sandbox": bool(durable_item_snapshot.get("playable_sandbox", false))}
	)
	if not bool(validator_setup.get("success", false)):
		return _failure("INVALID_GAMEPLAY_ITEM_GRAPH_VALIDATOR_SETUP", {"cause": validator_setup})
	var item_result: Dictionary = item_validator.validate_durable_state(durable_item_state)
	if not bool(item_result.get("success", false)):
		return _failure("INVALID_GAMEPLAY_ITEM_GRAPH_STATE", {"cause": item_result})
	var ownership_state: Dictionary = value.get("ownership", {})
	var item_state: Dictionary = value.get("canonical_item_graph", {})
	var item_snapshot: Dictionary = item_state.get("snapshot", {})
	if (
		String(ownership_state.get("authority_owner_id", "")) != String(value.get("authority_owner_id", ""))
		or int(ownership_state.get("authority_epoch", 0)) != int(value.get("authority_epoch", 0))
		or String(item_snapshot.get("authority_owner_id", "")) != String(value.get("authority_owner_id", ""))
		or int(item_snapshot.get("authority_epoch", 0)) != int(value.get("authority_epoch", 0))
	):
		return _failure("GAMEPLAY_DURABLE_AUTHORITY_MISMATCH")
	var player_ids: Dictionary = {}
	for player_value in Dictionary(value.get("players", {})).get("players", []):
		player_ids[String(Dictionary(player_value).get("logical_player_id", ""))] = true
	for inventory_player_id_value in Dictionary(item_snapshot.get("inventories", {})).keys():
		if not player_ids.has(String(inventory_player_id_value)):
			return _failure("ITEM_GRAPH_INVENTORY_PLAYER_MISSING", {"logical_player_id": String(inventory_player_id_value)})
	var safe := Utils.canonicalize(value, "$.networked_gameplay_durable_state")
	if not bool(safe.get("success", false)):
		return _failure("GAMEPLAY_DURABLE_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success()


func export_replay_state() -> Dictionary:
	if not _configured:
		return {}
	var ledger: Dictionary = {}
	var operation_ids := _operation_ledger.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		ledger[String(operation_id_value)] = Dictionary(_operation_ledger[operation_id_value]).duplicate(true)
	var state: Dictionary = {
		"schema": REPLAY_SCHEMA,
		"service_operation_ledger": ledger,
		"ownership_replay": _ownership.export_replay_state(),
		"item_graph_replay": _canonical_multiplayer_items.export_replay_state(),
		"checksum": "",
	}
	state["checksum"] = _state_checksum(state)
	return state


func restore_replay_state(value: Dictionary) -> Dictionary:
	var validation := validate_replay_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var ownership_result: Dictionary = _ownership.restore_replay_state(Dictionary(value.get("ownership_replay", {})))
	if not bool(ownership_result.get("success", false)):
		return _failure("GAMEPLAY_OWNERSHIP_REPLAY_RECOVERY_FAILED", {"cause": ownership_result})
	var item_result: Dictionary = _canonical_multiplayer_items.restore_replay_state(Dictionary(value.get("item_graph_replay", {})))
	if not bool(item_result.get("success", false)):
		return _failure("GAMEPLAY_ITEM_REPLAY_RECOVERY_FAILED", {"cause": item_result})
	_operation_ledger = Dictionary(value.get("service_operation_ledger", {})).duplicate(true)
	return _success({
		"service_operation_count": _operation_ledger.size(),
		"ownership_operation_count": int(ownership_result.get("details", {}).get("operation_count", 0)),
		"item_operation_count": int(item_result.get("details", {}).get("operation_count", 0)),
	})


func validate_replay_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != REPLAY_SCHEMA:
		return _failure("INVALID_GAMEPLAY_REPLAY_SCHEMA")
	if typeof(value.get("service_operation_ledger")) != TYPE_DICTIONARY:
		return _failure("INVALID_GAMEPLAY_REPLAY_LEDGER")
	if typeof(value.get("ownership_replay")) != TYPE_DICTIONARY or typeof(value.get("item_graph_replay")) != TYPE_DICTIONARY:
		return _failure("INVALID_GAMEPLAY_REPLAY_SECTION")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("GAMEPLAY_REPLAY_CHECKSUM_MISMATCH")
	for operation_id_value in value.get("service_operation_ledger", {}).keys():
		var entry_value = value["service_operation_ledger"][operation_id_value]
		if String(operation_id_value).strip_edges().is_empty() or not entry_value is Dictionary:
			return _failure("INVALID_GAMEPLAY_REPLAY_RECORD")
		var entry: Dictionary = entry_value
		if String(entry.get("fingerprint", "")).length() != 64 or typeof(entry.get("result")) != TYPE_DICTIONARY:
			return _failure("INVALID_GAMEPLAY_REPLAY_RECORD")
	var ownership_validator = OwnershipService.new()
	var ownership_result := ownership_validator.validate_replay_state(Dictionary(value.get("ownership_replay", {})))
	if not bool(ownership_result.get("success", false)):
		return _failure("INVALID_GAMEPLAY_OWNERSHIP_REPLAY", {"cause": ownership_result})
	var item_validator = CanonicalMultiplayerItemGraph.new()
	var item_result := item_validator.validate_replay_state(Dictionary(value.get("item_graph_replay", {})))
	if not bool(item_result.get("success", false)):
		return _failure("INVALID_GAMEPLAY_ITEM_REPLAY", {"cause": item_result})
	var safe := Utils.canonicalize(value, "$.networked_gameplay_replay_state")
	if not bool(safe.get("success", false)):
		return _failure("GAMEPLAY_REPLAY_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success()


func has_durable_replay_operation(operation_id: String) -> bool:
	if operation_id.is_empty():
		return false
	if _operation_ledger.has(operation_id):
		return true
	return (
		_canonical_multiplayer_items != null
		and _canonical_multiplayer_items.has_replay_operation(operation_id)
	)


func get_recovery_report() -> Dictionary:
	return {
		"durable_state_checksum": String(export_durable_state().get("checksum", "")),
		"replay_state_checksum": String(export_replay_state().get("checksum", "")),
		"service_operation_count": _operation_ledger.size(),
		"ownership_operation_count": int(_ownership.get_report().get("operation_count", 0)) if _ownership != null else 0,
		"item_operation_count": _canonical_multiplayer_items.get_replay_operation_count() if _canonical_multiplayer_items != null else 0,
	}


func _validate_recovered_player_consistency(players_service, ownership_service) -> Dictionary:
	var player_records: Array = players_service.get_players()
	var ownership_records: Array = ownership_service.get_players()
	if player_records.size() != ownership_records.size():
		return _failure("RECOVERED_PLAYER_OWNERSHIP_COUNT_MISMATCH", {
			"player_count": player_records.size(),
			"ownership_count": ownership_records.size(),
		})
	var player_ids: Dictionary = {}
	for record_value in player_records:
		var record: Dictionary = record_value
		var logical_id := String(record.get("logical_player_id", ""))
		player_ids[logical_id] = true
		var ownership_record: Dictionary = ownership_service.get_player(logical_id)
		if ownership_record.is_empty():
			return _failure("RECOVERED_PLAYER_OWNERSHIP_MISSING", {"logical_player_id": logical_id})
		if String(ownership_record.get("player_entity_id", "")) != String(record.get("player_entity_id", "")):
			return _failure("RECOVERED_PLAYER_ENTITY_MISMATCH", {"logical_player_id": logical_id})
		if int(ownership_record.get("ownership_epoch", 0)) != int(record.get("ownership_epoch", 0)):
			return _failure("RECOVERED_PLAYER_EPOCH_MISMATCH", {"logical_player_id": logical_id})
		if bool(record.get("connected", true)) or bool(ownership_record.get("connected", true)):
			return _failure("RECOVERED_PLAYER_SESSION_NOT_CLEARED", {"logical_player_id": logical_id})
		if not String(record.get("transport_session_id", "")).is_empty() or not String(ownership_record.get("transport_session_id", "")).is_empty():
			return _failure("RECOVERED_PLAYER_TRANSPORT_NOT_CLEARED", {"logical_player_id": logical_id})
	for ownership_value in ownership_records:
		var logical_id := String(Dictionary(ownership_value).get("logical_player_id", ""))
		if not player_ids.has(logical_id):
			return _failure("RECOVERED_OWNERSHIP_PLAYER_MISSING", {"logical_player_id": logical_id})
	return _success({"player_count": player_records.size()})


func _state_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


func create_snapshot() -> Dictionary:
	if not _configured:
		return {}
	return _replication.create_snapshot(_authority_owner_id, _authority_epoch, _revision, _tick, _region_id, _players.get_players(), _shared_items.get_item())


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	return PlayerSnapshot.validate_legacy(snapshot)


func validate_delta(delta: Dictionary) -> Dictionary:
	return PlayerDelta.validate_legacy(delta)


func get_player(logical_player_id: String) -> Dictionary:
	return _players.get_player(logical_player_id) if _players != null else {}


func create_targeted_command_result(message_id: String, operation_id: String, result: Dictionary) -> Dictionary:
	return _result_router.route(message_id, operation_id, _authority_epoch, _revision, result)


func handle_network_command(command: Dictionary) -> Dictionary:
	if _playable_backend == null or _item_graph_service == null:
		return {}
	var validation := NetworkCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _item_graph_service.handle_command(command)
	var command_type := String(command.get("command_type", ""))
	if command_type.begins_with("item.") or command_type.begins_with("inventory.") or command_type.begins_with("container."):
		var item_validation := ItemCommand.validate_network_envelope(command)
		if not bool(item_validation.get("success", false)):
			return _item_graph_service.handle_command(command)
	if _container_interactions.supports(command_type):
		return _container_interactions.handle_command(command)
	if _mount_interactions.supports(command_type):
		return _mount_interactions.handle_command(command)
	return _item_graph_service.handle_command(command)


func create_initial_entity_snapshots() -> Array[Dictionary]:
	return _item_graph_service.create_initial_snapshots() if _item_graph_service != null else []


func create_entity_snapshot(entity_id: String) -> Dictionary:
	return _item_graph_service.create_snapshot(entity_id) if _item_graph_service != null else {}


func get_world_entity_store_for_kernel():
	return _playable_backend.get_world_entity_store_for_kernel() if _playable_backend != null else null


func get_item_controller_for_authority_tests():
	return _playable_backend.get_item_controller_for_authority_tests() if _playable_backend != null else null


func shutdown() -> Dictionary:
	if _playable_backend != null:
		_playable_backend.shutdown()
		_playable_backend.free()
		_playable_backend = null
	_item_graph_service = null
	_container_interactions = null
	_mount_interactions = null
	_configured = false
	return _success()


func get_report() -> Dictionary:
	var connected := 0
	if _players != null:
		for record in _players.get_players():
			if bool(record.get("connected", false)):
				connected += 1
	var report: Dictionary = {
		"schema": SCHEMA,
		"configured": _configured,
		"profile": _profile,
		"topology_adapter": _topology_adapter,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"server_tick": _tick,
		"player_count": _players.get_players().size() if _players != null else 0,
		"connected_count": connected,
		"operation_count": _operation_ledger.size(),
		"shared_item_available": bool(_shared_items.get_item().get("available", false)) if _shared_items != null else false,
		"shared_item_owner": String(_shared_items.get_item().get("owner_player_entity_id", "")) if _shared_items != null else "",
		"ownership_service": _ownership.get_report() if _ownership != null else {},
		"player_registry": _players.get_report() if _players != null else {},
		"movement_service": _movement.get_report() if _movement != null else {},
		"command_result_router": _result_router.get_report() if _result_router != null else {},
		"replication_publisher": _replication.get_report() if _replication != null else {},
		"item_graph_service": _item_graph_service.get_report() if _item_graph_service != null else {},
		"container_interaction_service": _container_interactions.get_report() if _container_interactions != null else {},
		"mount_interaction_service": _mount_interactions.get_report() if _mount_interactions != null else {},
		"canonical_multiplayer_item_graph": _canonical_multiplayer_items.create_snapshot() if _canonical_multiplayer_items != null else {},
		"direct_client_authority_references": 0,
		"recovery": get_recovery_report() if _configured else {},
	}
	if _playable_backend != null:
		report["playable_backend"] = _playable_backend.get_report()
		for field in ["player_entity_id", "item_graph_entity_id", "player_revision", "item_revision", "player_checksum", "item_checksum", "open_external_container_id", "handler_invocation_count", "mutation_count", "replay_count", "rejection_count", "operation_ledger_count", "item_graph_valid", "presentation_objects"]:
			report[field] = report["playable_backend"].get(field)
	return report


func _create_delta(base_revision: int, event_type: String, player: Dictionary, shared_item: Dictionary) -> Dictionary:
	var target_snapshot: Dictionary = create_snapshot()
	return _replication.create_delta(_authority_owner_id, _authority_epoch, base_revision, _revision, _tick, event_type, player, shared_item, target_snapshot)


func _validate_owner(logical_player_id: String, transport_session_id: String, ownership_epoch: int) -> Dictionary:
	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty(): return _failure("PLAYER_NOT_FOUND")
	if not bool(record.get("connected", false)): return _failure("PLAYER_NOT_CONNECTED")
	if String(record.get("transport_session_id", "")) != transport_session_id: return _failure("STALE_PLAYER_SESSION")
	if int(record.get("ownership_epoch", 0)) != ownership_epoch: return _failure("STALE_PLAYER_OWNERSHIP_EPOCH")
	return _success()


func _record_to_playable_state(record: Dictionary) -> Dictionary:
	var position: Dictionary = Dictionary(record.get("position", {}))
	var velocity: Dictionary = Dictionary(record.get("velocity", {}))
	var yaw := float(record.get("orientation_yaw", 0.0))
	var basis := Basis(Vector3.UP, yaw)
	var world_position := Vector3(float(position.get("x", 0.0)), float(position.get("y", 0.0)), float(position.get("z", 0.0)))
	return PlayableStateCodec.create_player_state(
		world_position,
		basis,
		Vector3(float(velocity.get("x", 0.0)), float(velocity.get("y", 0.0)), float(velocity.get("z", 0.0))),
		world_position,
		"flat_humanoid",
		"first_person",
		bool(record.get("flashlight_enabled", false)),
		int(record.get("last_input_sequence", 0)),
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground"
	)

func _apply_playable_state_to_record(record: Dictionary, player_state: Dictionary) -> Dictionary:
	var next := record.duplicate(true)
	var position := PlayableStateCodec.player_position(player_state)
	var velocity := PlayableStateCodec.player_velocity(player_state)
	var forward := -PlayableStateCodec.player_basis(player_state).z
	next["position"] = {"x": position.x, "y": position.y, "z": position.z}
	next["velocity"] = {"x": velocity.x, "y": velocity.y, "z": velocity.z}
	if forward.slide(Vector3.UP).length_squared() > 0.000001:
		next["orientation_yaw"] = atan2(forward.x, forward.z)
	next["flashlight_enabled"] = bool(player_state.get("flashlight_enabled", false))
	next["last_input_sequence"] = int(player_state.get("last_input_sequence", 0))
	next["state_revision"] = int(next.get("state_revision", 0)) + 1
	return next

func _create_item_authority_context(logical_player_id: String) -> Dictionary:
	var record: Dictionary = _players.get_player(logical_player_id)
	if record.is_empty():
		return {}
	var position_value: Dictionary = Dictionary(record.get("position", {}))
	var position := Vector3(
		float(position_value.get("x", 0.0)),
		float(position_value.get("y", 0.0)),
		float(position_value.get("z", 0.0))
	)
	var yaw := float(record.get("orientation_yaw", 0.0))
	var view_direction := (-Basis(Vector3.UP, yaw).z).normalized()
	var interaction_origin := position + Vector3(0.0, 0.9, 0.0)
	return {
		"player_position": {"x": position.x, "y": position.y, "z": position.z},
		"interaction_origin": {"x": interaction_origin.x, "y": interaction_origin.y, "z": interaction_origin.z},
		"view_direction": {"x": view_direction.x, "y": view_direction.y, "z": view_direction.z},
		"orientation_yaw": yaw,
		"server_tick": _tick,
	}


func _spawn_position(logical_player_id: String) -> Dictionary:
	return {"x": -2.0 if logical_player_id == "a" else 2.0, "y": 0.0, "z": 0.0}


func _advance() -> void:
	_revision += 1
	_tick += 1


func _replay(operation_id: String, fingerprint: String) -> Dictionary:
	if operation_id.strip_edges().is_empty(): return _failure("OPERATION_ID_REQUIRED")
	if not _operation_ledger.has(operation_id): return {}
	var entry: Dictionary = _operation_ledger[operation_id]
	if String(entry.get("fingerprint", "")) != fingerprint: return _failure("OPERATION_REPLAY_CONFLICT")
	var result: Dictionary = Dictionary(entry.get("result", {})).duplicate(true)
	result["replay"] = true
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["replay"] = true
	result["details"] = details
	return result


func _record(operation_id: String, fingerprint: String, result: Dictionary) -> void:
	_operation_ledger[operation_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}


func _record_failure(operation_id: String, fingerprint: String, error_code: String, details: Dictionary = {}) -> Dictionary:
	var result := _failure(error_code, details)
	_record(operation_id, fingerprint, result)
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
