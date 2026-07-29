extends Node

const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const CommandResult = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const EntityDelta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")
const ItemGameplayController = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const StateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const SCHEMA: String = "planet_simulator.playable_listen_host_authority.v1"
const PLAYER_ENTITY_ID: String = "player/local-astronaut"
const ITEM_GRAPH_ENTITY_ID: String = "item-graph/player/local-astronaut"
const PLAYER_ENTITY_TYPE: String = "player"
const ITEM_GRAPH_ENTITY_TYPE: String = "item_graph"
const MAX_MOVEMENT_DELTA_SECONDS: float = 0.25
const MAX_PLAYER_SPEED_MPS: float = 250.0
const MOVEMENT_DISTANCE_ALLOWANCE_M: float = 2.0
const ITEM_INTERACTION_DISTANCE_M: float = 8.0
const ITEM_PLACEMENT_DISTANCE_M: float = 12.0
const MAX_LEDGER_ENTRIES: int = 4096

const ITEM_MUTATION_COMMANDS: Array[String] = [
	"inventory.select_hotbar",
	"item.move_to_container",
	"item.pickup",
	"item.drop",
	"item.mount",
	"item.detach",
	"item.place",
	"item.grant_debug",
	"item.reload",
]

var _configured: bool = false
var _authority_owner_id: String = ""
var _authority_epoch: int = 1
var _server_tick: int = 0
var _session_id: String = ""
var _universe_id: String = "main"
var _instance_id: String = "persistent"
var _space_id: String = "moon"
var _frame_id: String = "body/moon/fixed"
var _player_revision: int = 0
var _item_revision: int = 0
var _player_state: Dictionary = {}
var _player_snapshot: Dictionary = {}
var _item_snapshot: Dictionary = {}
var _item_controller
var _open_external_container_id: String = ""
var _command_ledger: Dictionary = {}
var _command_order: Array[String] = []
var _handler_invocation_count: int = 0
var _mutation_count: int = 0
var _replay_count: int = 0
var _rejection_count: int = 0


func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("PLAYABLE_AUTHORITY_ALREADY_CONFIGURED")
	_authority_owner_id = String(config.get("authority_owner_id", "local-listen-host"))
	_authority_epoch = int(config.get("authority_epoch", 1))
	_server_tick = int(config.get("server_tick", 0))
	_session_id = String(config.get("session_id", "session/h1/listen-host/1"))
	_universe_id = String(config.get("universe_id", "main")).strip_edges().to_lower()
	_instance_id = String(config.get("instance_id", "persistent")).strip_edges().to_lower()
	_space_id = String(config.get("space_id", "moon")).strip_edges().to_lower()
	_frame_id = String(config.get("frame_id", "body/moon/fixed")).strip_edges()
	if (
		_authority_owner_id.strip_edges().is_empty()
		or _authority_epoch < 1
		or _server_tick < 0
		or _session_id.strip_edges().is_empty()
		or _frame_id.is_empty()
	):
		return _failure("INVALID_PLAYABLE_AUTHORITY_CONFIGURATION")
	var player_state_value = config.get("player_state", {})
	if not player_state_value is Dictionary:
		return _failure("PLAYER_STATE_REQUIRED")
	var player_validation: Dictionary = StateCodec.validate_player_state(
		Dictionary(player_state_value)
	)
	if not bool(player_validation.get("success", false)):
		return _failure(
			String(player_validation.get("error_code", "INVALID_PLAYER_STATE")),
			player_validation.get("details", {})
		)
	_player_state = StateCodec.normalize_player_state(Dictionary(player_state_value))

	_item_controller = ItemGameplayController.new()
	_item_controller.name = "H1AuthoritativeItemGameplay"
	add_child(_item_controller)
	var item_setup: Dictionary = _item_controller.setup_runtime(
		null,
		null,
		null,
		null,
		_frame_id,
		String(config.get("gravity_reference_body_id", "moon-local")),
		String(config.get("item_state_key", "moon-player-r2")),
		String(config.get("item_profile_id", "moon")),
		false,
		{
			"mode": ItemGameplayController.RUNTIME_MODE_AUTHORITY,
			"authority_owner_id": _authority_owner_id,
			"authority_epoch": _authority_epoch,
			"persistence_enabled": bool(config.get("item_persistence_enabled", true)),
			"persistence_root": String(
				config.get("item_persistence_root", "user://planet_simulator/item_graphs")
			),
			"presentation_enabled": false,
			"include_demo_world": bool(config.get("include_demo_world", false)),
		}
	)
	if not bool(item_setup.get("success", false)):
		_item_controller.queue_free()
		_item_controller = null
		return _failure(
			String(item_setup.get("error_code", "ITEM_AUTHORITY_SETUP_FAILED")),
			item_setup
		)
	_player_snapshot = _create_player_snapshot("snapshot/h1/player/initial")
	_item_snapshot = _create_item_snapshot("snapshot/h1/items/initial")
	if not bool(EntitySnapshot.validate(_player_snapshot).get("success", false)):
		return _failure("INVALID_INITIAL_PLAYER_SNAPSHOT")
	if not bool(EntitySnapshot.validate(_item_snapshot).get("success", false)):
		return _failure("INVALID_INITIAL_ITEM_SNAPSHOT")
	_configured = true
	return _success({
		"player_entity_id": PLAYER_ENTITY_ID,
		"item_graph_entity_id": ITEM_GRAPH_ENTITY_ID,
		"player_revision": _player_revision,
		"item_revision": _item_revision,
	})


func handle_command(command_value: Dictionary) -> Dictionary:
	if not _configured:
		return _raw_result(command_value, "RETRYABLE", "PLAYABLE_AUTHORITY_NOT_READY", -1, {})
	var validation: Dictionary = NetworkCommand.validate(command_value)
	if not bool(validation.get("success", false)):
		return _raw_result(
			command_value,
			"REJECTED",
			String(validation.get("error_code", "INVALID_COMMAND")),
			_current_revision_for_entity(String(command_value.get("entity_id", ""))),
			{}
		)
	var command: Dictionary = NetworkCommand.normalize(command_value)
	var operation_id: String = String(command["operation_id"])
	var fingerprint: String = NetworkCommand.command_fingerprint(command)
	if _command_ledger.has(operation_id):
		var recorded: Dictionary = _command_ledger[operation_id]
		if String(recorded.get("fingerprint", "")) != fingerprint:
			_rejection_count += 1
			return _raw_result(
				command,
				"REJECTED",
				"OPERATION_REPLAY_CONFLICT",
				_current_revision_for_entity(String(command["entity_id"])),
				{"operation_result": _failure("OPERATION_REPLAY_CONFLICT")}
			)
		_replay_count += 1
		var replay_result: Dictionary = Dictionary(recorded.get("result", {})).duplicate(true)
		replay_result["message_id"] = String(command["message_id"])
		return replay_result

	_handler_invocation_count += 1
	var result: Dictionary = _execute_command(command)
	_record_operation(operation_id, fingerprint, result)
	return result


func create_initial_snapshots() -> Array[Dictionary]:
	return [_player_snapshot.duplicate(true), _item_snapshot.duplicate(true)]


func create_snapshot(entity_id: String) -> Dictionary:
	match entity_id:
		PLAYER_ENTITY_ID:
			return _player_snapshot.duplicate(true)
		ITEM_GRAPH_ENTITY_ID:
			return _item_snapshot.duplicate(true)
	return {}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"server_tick": _server_tick,
		"session_id": _session_id,
		"player_entity_id": PLAYER_ENTITY_ID,
		"item_graph_entity_id": ITEM_GRAPH_ENTITY_ID,
		"player_revision": _player_revision,
		"item_revision": _item_revision,
		"player_checksum": String(_player_snapshot.get("checksum", "")),
		"item_checksum": String(_item_snapshot.get("checksum", "")),
		"open_external_container_id": _open_external_container_id,
		"handler_invocation_count": _handler_invocation_count,
		"mutation_count": _mutation_count,
		"replay_count": _replay_count,
		"rejection_count": _rejection_count,
		"operation_ledger_count": _command_ledger.size(),
		"item_graph_valid": (
			bool(_item_controller.domain.validator.validate_graph().get("success", false))
			if _item_controller != null
			else false
		),
		"presentation_objects": 0,
	}


func get_world_entity_store_for_kernel():
	if _item_controller == null or _item_controller.domain.is_empty():
		return null
	return _item_controller.domain.world_entities


func get_item_controller_for_authority_tests():
	# Test-only access is intentionally explicit and never handed to ClientRuntime,
	# UI, or the graphical world runtime.
	return _item_controller


func shutdown() -> Dictionary:
	if _item_controller != null:
		_item_controller.save_graph()
		remove_child(_item_controller)
		_item_controller.free()
		_item_controller = null
	_configured = false
	return _success()


func _execute_command(command: Dictionary) -> Dictionary:
	var payload: Dictionary = Dictionary(command["payload"])
	if String(payload.get("session_id", "")) != _session_id:
		return _reject(command, "SESSION_NOT_BOUND")
	if int(command["authority_epoch"]) != _authority_epoch:
		return _reject(command, "STALE_AUTHORITY_EPOCH")
	var entity_id: String = String(command["entity_id"])
	var command_type: String = String(command["command_type"])
	if entity_id == PLAYER_ENTITY_ID:
		if command_type != "player.move":
			return _reject(command, "UNSUPPORTED_PLAYER_COMMAND")
		return _handle_player_move(command, payload)
	if entity_id == ITEM_GRAPH_ENTITY_ID:
		return _handle_item_command(command, command_type, payload)
	return _reject(command, "UNKNOWN_PLAYABLE_ENTITY")


func _handle_player_move(command: Dictionary, payload: Dictionary) -> Dictionary:
	var fields: Dictionary = NetworkUtils.validate_exact_fields(
		payload,
		["session_id", "player_state", "delta_seconds"]
	)
	if not bool(fields.get("success", false)):
		return _reject(command, String(fields.get("error_code", "INVALID_PLAYER_MOVE_PAYLOAD")))
	if int(command["expected_revision"]) != _player_revision:
		return _reject(command, "REVISION_CONFLICT")
	var delta_seconds_value = payload.get("delta_seconds")
	if (
		typeof(delta_seconds_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(delta_seconds_value))
		or float(delta_seconds_value) <= 0.0
		or float(delta_seconds_value) > MAX_MOVEMENT_DELTA_SECONDS
	):
		return _reject(command, "INVALID_MOVEMENT_DELTA")
	var candidate_value = payload.get("player_state", {})
	if not candidate_value is Dictionary:
		return _reject(command, "INVALID_PLAYER_STATE")
	var candidate_validation: Dictionary = StateCodec.validate_player_state(
		Dictionary(candidate_value)
	)
	if not bool(candidate_validation.get("success", false)):
		return _reject(command, String(candidate_validation.get("error_code", "INVALID_PLAYER_STATE")))
	var candidate: Dictionary = StateCodec.normalize_player_state(Dictionary(candidate_value))
	var input_sequence: int = int(candidate["last_input_sequence"])
	var previous_sequence: int = int(_player_state.get("last_input_sequence", 0))
	if input_sequence <= previous_sequence:
		return _reject(command, "DUPLICATE_INPUT_SEQUENCE")
	var velocity: Vector3 = StateCodec.player_velocity(candidate)
	if velocity.length() > MAX_PLAYER_SPEED_MPS:
		return _reject(command, "PLAYER_SPEED_LIMIT_EXCEEDED")
	var delta_seconds: float = float(delta_seconds_value)
	var world_displacement: float = StateCodec.player_position(candidate).distance_to(
		StateCodec.player_position(_player_state)
	)
	var interaction_displacement: float = StateCodec.player_interaction_position(candidate).distance_to(
		StateCodec.player_interaction_position(_player_state)
	)
	var maximum_displacement: float = (
		MAX_MOVEMENT_DELTA_SECONDS * 0.0
		+ MAX_PLAYER_SPEED_MPS * delta_seconds
		+ MOVEMENT_DISTANCE_ALLOWANCE_M
	)
	if world_displacement > maximum_displacement or interaction_displacement > maximum_displacement:
		return _reject(command, "PLAYER_MOVEMENT_LIMIT_EXCEEDED")
	var base_revision: int = _player_revision
	_player_state = candidate
	_player_revision += 1
	_server_tick += 1
	var delta: Dictionary = EntityDelta.create(
		"delta/h1/player/%s" % String(command["operation_id"]),
		PLAYER_ENTITY_ID,
		PLAYER_ENTITY_TYPE,
		base_revision,
		_player_revision,
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		{
			"spatial_ref": Dictionary(_player_state["spatial_ref"]).duplicate(true),
			"physics_state": {
				"linear_velocity_mps": Array(
					_player_state["spatial_ref"]["linear_velocity_mps"]
				).duplicate(),
			},
			"domain_components": {"player_state": _player_state.duplicate(true)},
		}
	)
	_player_snapshot = _apply_delta_or_rebuild(
		_player_snapshot,
		delta,
		_create_player_snapshot("snapshot/h1/player/%d" % _player_revision)
	)
	_mutation_count += 1
	return _succeed(command, _player_revision, {
		"operation_result": {
			"success": true,
			"input_sequence": input_sequence,
			"player_revision": _player_revision,
		},
		"replication_delta": delta,
	})


func _handle_item_command(
	command: Dictionary,
	command_type: String,
	payload: Dictionary
) -> Dictionary:
	if int(command["expected_revision"]) != _item_revision:
		return _reject(command, "REVISION_CONFLICT")
	var payload_validation: Dictionary = _validate_item_payload(command_type, payload)
	if not bool(payload_validation.get("success", false)):
		return _reject(
			command,
			String(payload_validation.get("error_code", "INVALID_ITEM_COMMAND_PAYLOAD"))
		)
	var operation_result: Dictionary = _execute_item_operation(command_type, payload)
	if not bool(operation_result.get("success", false)):
		return _reject(
			command,
			String(operation_result.get("error_code", "ITEM_COMMAND_REJECTED")),
			operation_result
		)
	if not ITEM_MUTATION_COMMANDS.has(command_type):
		return _succeed(command, _item_revision, {
			"operation_result": _canonical_dictionary(operation_result),
		})
	var base_revision: int = _item_revision
	_item_revision += 1
	_server_tick += 1
	var graph_snapshot: Dictionary = _item_controller.create_network_graph_snapshot()
	if graph_snapshot.is_empty():
		return _reject(command, "ITEM_GRAPH_SNAPSHOT_FAILED", operation_result)
	var components: Dictionary = _item_domain_components(graph_snapshot)
	var delta: Dictionary = EntityDelta.create(
		"delta/h1/items/%s" % String(command["operation_id"]),
		ITEM_GRAPH_ENTITY_ID,
		ITEM_GRAPH_ENTITY_TYPE,
		base_revision,
		_item_revision,
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		{"domain_components": components}
	)
	_item_snapshot = _apply_delta_or_rebuild(
		_item_snapshot,
		delta,
		_create_item_snapshot("snapshot/h1/items/%d" % _item_revision)
	)
	_mutation_count += 1
	return _succeed(command, _item_revision, {
		"operation_result": _canonical_dictionary(operation_result),
		"replication_delta": delta,
	})


func _validate_item_payload(command_type: String, payload: Dictionary) -> Dictionary:
	var expected: Array[String] = ["session_id"]
	match command_type:
		"inventory.select_hotbar":
			expected.append("selected_hotbar_index")
		"item.move_to_container":
			expected.append_array([
				"item_id", "quantity", "target_container_id",
				"target_slot_index", "target_item_id",
			])
		"item.pickup":
			expected.append("item_id")
		"item.drop":
			expected.append_array(["item_id", "quantity", "transform"])
		"item.mount", "item.detach":
			expected.append_array(["assembly_id", "socket_id"])
		"item.place":
			expected.append("transform")
		"container.open", "container.close":
			expected.append("container_id")
		"item.grant_debug":
			expected.append_array(["definition_id", "quantity"])
		"item.save", "item.reload":
			pass
		_:
			return _failure("UNSUPPORTED_ITEM_COMMAND")
	var fields: Dictionary = NetworkUtils.validate_exact_fields(payload, expected)
	if not bool(fields.get("success", false)):
		return fields
	for string_field in [
		"item_id", "target_container_id", "target_item_id", "assembly_id",
		"socket_id", "container_id", "definition_id",
	]:
		if payload.has(string_field) and typeof(payload[string_field]) != TYPE_STRING:
			return _failure("INVALID_ITEM_COMMAND_FIELD", {"field": string_field})
	for integer_field in ["quantity", "target_slot_index", "selected_hotbar_index"]:
		if payload.has(integer_field) and not NetworkUtils.is_json_integer(payload[integer_field]):
			return _failure("INVALID_ITEM_COMMAND_FIELD", {"field": integer_field})
	if payload.has("transform"):
		if not payload["transform"] is Dictionary:
			return _failure("INVALID_TRANSFORM_PAYLOAD")
		var transform_validation: Dictionary = StateCodec.validate_transform_dto(
			Dictionary(payload["transform"])
		)
		if not bool(transform_validation.get("success", false)):
			return transform_validation
	return _success()


func _execute_item_operation(command_type: String, payload: Dictionary) -> Dictionary:
	match command_type:
		"inventory.select_hotbar":
			return _item_controller.select_hotbar(int(payload["selected_hotbar_index"]))
		"item.move_to_container":
			var move_quantity: int = int(payload["quantity"])
			var move_item = _item_controller.get_item(String(payload["item_id"]))
			if move_item == null:
				return _failure("ITEM_NOT_FOUND")
			if move_quantity == 0 or move_quantity < -1 or move_quantity > int(move_item.quantity):
				return _failure("INVALID_SPLIT_QUANTITY", {
					"requested_quantity": move_quantity,
					"available_quantity": int(move_item.quantity),
				})
			var access: Dictionary = _validate_transfer_access(
				String(payload["item_id"]),
				String(payload["target_container_id"])
			)
			if not bool(access.get("success", false)):
				return access
			return _item_controller.move_item_quantity_to_container(
				String(payload["item_id"]),
				int(payload["quantity"]),
				String(payload["target_container_id"]),
				int(payload["target_slot_index"]),
				String(payload["target_item_id"])
			)
		"item.pickup":
			var pickup_access: Dictionary = _validate_world_item_access(
				String(payload["item_id"]), ITEM_INTERACTION_DISTANCE_M
			)
			if not bool(pickup_access.get("success", false)):
				return pickup_access
			return _item_controller.pickup_world_item(String(payload["item_id"]))
		"item.drop":
			var drop_transform: Transform3D = StateCodec.transform_from_dto(
				Dictionary(payload["transform"])
			)
			if drop_transform.origin.distance_to(
				StateCodec.player_interaction_position(_player_state)
			) > ITEM_PLACEMENT_DISTANCE_M:
				return _failure("DROP_OUT_OF_RANGE")
			return _item_controller.drop_item_quantity(
				String(payload["item_id"]),
				int(payload["quantity"]),
				drop_transform
			)
		"item.mount":
			var mount_access: Dictionary = _validate_socket_access(
				String(payload["assembly_id"]), String(payload["socket_id"])
			)
			if not bool(mount_access.get("success", false)):
				return mount_access
			return _item_controller.mount_selected_item(
				String(payload["assembly_id"]),
				String(payload["socket_id"])
			)
		"item.detach":
			var detach_access: Dictionary = _validate_socket_access(
				String(payload["assembly_id"]), String(payload["socket_id"])
			)
			if not bool(detach_access.get("success", false)):
				return detach_access
			return _item_controller.detach_socket_to_inventory(
				String(payload["assembly_id"]),
				String(payload["socket_id"])
			)
		"item.place":
			var placement_transform: Transform3D = StateCodec.transform_from_dto(
				Dictionary(payload["transform"])
			)
			if placement_transform.origin.distance_to(
				StateCodec.player_interaction_position(_player_state)
			) > ITEM_PLACEMENT_DISTANCE_M:
				return _failure("PLACEMENT_OUT_OF_RANGE")
			return _item_controller.place_selected_item_at_transform(placement_transform)
		"container.open":
			return _open_external_container(String(payload["container_id"]))
		"container.close":
			return _close_external_container(String(payload["container_id"]))
		"item.grant_debug":
			return _item_controller.grant_debug_item(
				String(payload["definition_id"]),
				int(payload["quantity"])
			)
		"item.save":
			return _item_controller.save_graph()
		"item.reload":
			return _item_controller.reload_graph()
	return _failure("UNSUPPORTED_ITEM_COMMAND")


func _validate_transfer_access(item_id: String, target_container_id: String) -> Dictionary:
	var item = _item_controller.get_item(item_id)
	if item == null:
		return _failure("ITEM_NOT_FOUND")
	var source_container_id: String = ""
	if ItemRelations.kind_of(item.relation) == ItemRelations.CONTAINER:
		source_container_id = String(item.relation.get("container_id", ""))
	if not source_container_id.is_empty() and not _container_is_accessible(source_container_id):
		return _failure("SOURCE_CONTAINER_ACCESS_DENIED")
	if not _container_is_accessible(target_container_id):
		return _failure("TARGET_CONTAINER_ACCESS_DENIED")
	return _success()


func _container_is_accessible(container_id: String) -> bool:
	return container_id in [
		_item_controller.player_inventory_id,
		_item_controller.player_hotbar_id,
		_open_external_container_id,
	]


func _open_external_container(container_id: String) -> Dictionary:
	var container = _item_controller.get_container(container_id)
	if container == null:
		return _failure("CONTAINER_NOT_FOUND")
	if container_id in [
		_item_controller.player_inventory_id,
		_item_controller.player_hotbar_id,
	]:
		return _failure("EXTERNAL_CONTAINER_REQUIRED")
	if String(container.owner_kind) != "ITEM_INSTANCE":
		return _failure("EXTERNAL_CONTAINER_OWNER_REQUIRED")
	var owner_item_id: String = String(container.owner_id)
	var access: Dictionary = _validate_world_item_access(
		owner_item_id,
		ITEM_INTERACTION_DISTANCE_M
	)
	if not bool(access.get("success", false)):
		return access
	_open_external_container_id = container_id
	return {
		"success": true,
		"container_id": container_id,
		"message": "Контейнер открыт",
	}


func _close_external_container(container_id: String) -> Dictionary:
	if container_id.is_empty() or container_id != _open_external_container_id:
		return _failure("EXTERNAL_CONTAINER_NOT_OPEN")
	_open_external_container_id = ""
	return {
		"success": true,
		"container_id": container_id,
		"message": "Контейнер закрыт",
	}


func _validate_socket_access(assembly_id: String, socket_id: String) -> Dictionary:
	var socket: Dictionary = _item_controller.get_socket_state(assembly_id, socket_id)
	if socket.is_empty():
		return _failure("SOCKET_NOT_FOUND")
	var parent_item_id: String = String(socket.get("parent_item_id", ""))
	if parent_item_id.is_empty():
		return _failure("SOCKET_PARENT_REQUIRED")
	return _validate_world_item_access(parent_item_id, ITEM_INTERACTION_DISTANCE_M)


func _validate_world_item_access(item_id: String, maximum_distance: float) -> Dictionary:
	var item = _item_controller.get_item(item_id)
	if item == null:
		return _failure("ITEM_NOT_FOUND")
	if ItemRelations.kind_of(item.relation) != ItemRelations.WORLD:
		return _failure("ITEM_NOT_IN_WORLD")
	var item_transform: Transform3D = _item_controller.get_world_item_transform(item_id)
	var distance: float = item_transform.origin.distance_to(
		StateCodec.player_interaction_position(_player_state)
	)
	if distance > maximum_distance:
		return _failure("ITEM_OUT_OF_RANGE", {"distance_m": distance})
	return _success({"distance_m": distance})


func _create_player_snapshot(snapshot_id: String) -> Dictionary:
	return EntitySnapshot.create(
		snapshot_id,
		PLAYER_ENTITY_ID,
		PLAYER_ENTITY_TYPE,
		_player_revision,
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		Dictionary(_player_state["spatial_ref"]).duplicate(true),
		{},
		{
			"linear_velocity_mps": Array(
				_player_state["spatial_ref"]["linear_velocity_mps"]
			).duplicate(),
		},
		{"player_state": _player_state.duplicate(true)}
	)


func _create_item_snapshot(snapshot_id: String) -> Dictionary:
	var graph_snapshot: Dictionary = _item_controller.create_network_graph_snapshot()
	return EntitySnapshot.create(
		snapshot_id,
		ITEM_GRAPH_ENTITY_ID,
		ITEM_GRAPH_ENTITY_TYPE,
		_item_revision,
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		SpatialRef.create(
			_frame_id,
			Vector3.ZERO,
			Basis.IDENTITY,
			Vector3.ZERO,
			Vector3.ZERO,
			0.0,
			_universe_id,
			_space_id,
			_instance_id
		),
		{},
		{},
		_item_domain_components(graph_snapshot)
	)


func _item_domain_components(graph_snapshot: Dictionary) -> Dictionary:
	return {
		"item_graph": graph_snapshot.duplicate(true),
		"player_inventory_id": _item_controller.player_inventory_id,
		"player_hotbar_id": _item_controller.player_hotbar_id,
		"selected_hotbar_index": _item_controller.selected_hotbar_index,
	}


func _apply_delta_or_rebuild(
	base_snapshot: Dictionary,
	delta: Dictionary,
	fallback_snapshot: Dictionary
) -> Dictionary:
	var applied: Dictionary = EntityDelta.apply_to_snapshot(base_snapshot, delta)
	if bool(applied.get("success", false)):
		return Dictionary(applied.get("snapshot", {})).duplicate(true)
	return fallback_snapshot.duplicate(true)


func _current_revision_for_entity(entity_id: String) -> int:
	if entity_id == PLAYER_ENTITY_ID:
		return _player_revision
	if entity_id == ITEM_GRAPH_ENTITY_ID:
		return _item_revision
	return -1


func _succeed(command: Dictionary, revision: int, payload: Dictionary) -> Dictionary:
	return CommandResult.create(
		String(command.get("message_id", "message/h1/unknown")),
		String(command.get("operation_id", "operation/h1/unknown")),
		"SUCCEEDED",
		"",
		revision,
		_authority_epoch,
		payload
	)


func _reject(
	command: Dictionary,
	error_code: String,
	operation_result: Dictionary = {}
) -> Dictionary:
	_rejection_count += 1
	var entity_id: String = String(command.get("entity_id", ""))
	var details: Dictionary = (
		operation_result.duplicate(true)
		if not operation_result.is_empty()
		else _failure(error_code)
	)
	details["success"] = false
	if String(details.get("error_code", "")).is_empty():
		details["error_code"] = error_code
	return _raw_result(
		command,
		"REJECTED",
		error_code,
		_current_revision_for_entity(entity_id),
		{"operation_result": _canonical_dictionary(details)}
	)


func _raw_result(
	command: Dictionary,
	status: String,
	error_code: String,
	revision: int,
	payload: Dictionary
) -> Dictionary:
	return CommandResult.create(
		String(command.get("message_id", "message/h1/invalid")),
		String(command.get("operation_id", "operation/h1/invalid")),
		status,
		error_code,
		revision,
		_authority_epoch,
		payload
	)


func _record_operation(
	operation_id: String,
	fingerprint: String,
	result: Dictionary
) -> void:
	_command_ledger[operation_id] = {
		"fingerprint": fingerprint,
		"result": result.duplicate(true),
	}
	_command_order.append(operation_id)
	while _command_order.size() > MAX_LEDGER_ENTRIES:
		var expired: String = _command_order.pop_front()
		_command_ledger.erase(expired)


func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var round_trip: Dictionary = NetworkUtils.json_round_trip(value)
	return (
		Dictionary(round_trip.get("value", {})).duplicate(true)
		if bool(round_trip.get("success", false))
		else {"success": false, "error_code": "NON_CANONICAL_OPERATION_RESULT"}
	)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
