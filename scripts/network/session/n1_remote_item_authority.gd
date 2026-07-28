extends RefCounted

const FactoryScript = preload("res://scripts/items/services/item_domain_factory.gd")
const DefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ContainerStateScript = preload("res://scripts/containers/container_state.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const PartitionAddressScript = preload("res://scripts/simulation/partition/partition_address.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const GatewayScript = preload("res://scripts/network/loopback/network_command_gateway.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")
const MoveResultScript = preload("res://scripts/network/contracts/item_move_to_container_result.gd")

const COMMAND_TYPE: String = "item.move_to_container"
const SNAPSHOT_ID: String = "snapshot/n1/remote-item/1"
const ENTITY_ID: String = "entity/item/n1-storage-terminal"
const SOURCE_CONTAINER_ID: String = "container/n1/source"
const DESTINATION_CONTAINER_ID: String = "container/n1/destination"
const INITIAL_REVISION: int = 12
const INITIAL_SERVER_TICK: int = 500

var domain: Dictionary = {}
var aggregate
var gateway
var authority_owner_id: String = ""
var authority_epoch: int = 0
var server_tick: int = INITIAL_SERVER_TICK
var session_id: String = ""
var command_item_id: String = ""
var terminal_item_id: String = ""
var mutation_count: int = 0
var handler_invocation_count: int = 0
var deltas_by_operation: Dictionary = {}
var final_snapshots_by_operation: Dictionary = {}


func setup(owner_id: String = "sim-n1", epoch: int = 5, tick: int = INITIAL_SERVER_TICK) -> Dictionary:
	if not domain.is_empty():
		return _failure("AUTHORITY_ALREADY_CONFIGURED")
	if owner_id.strip_edges().is_empty() or epoch < 1 or tick < 0:
		return _failure("INVALID_AUTHORITY_CONFIGURATION")
	authority_owner_id = owner_id
	authority_epoch = epoch
	server_tick = tick
	domain = FactoryScript.create()
	domain.world_entities.setup({
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
	})
	_register_definitions()
	var terminal = domain.items.create_item(
		"n1_storage_terminal",
		1,
		{"container": {"container_id": DESTINATION_CONTAINER_ID}},
		RelationsScript.world_from_spatial_ref(_create_spatial_ref()),
		"N1 Storage Terminal"
	)
	if terminal == null:
		return _failure("TERMINAL_ITEM_CREATE_FAILED")
	terminal_item_id = String(terminal.instance_id)
	var source = ContainerStateScript.new({
		"container_id": SOURCE_CONTAINER_ID,
		"owner_kind": "SYSTEM",
		"owner_id": "n1-command-source",
		"storage_mode": ContainerStateScript.STORAGE_BULK,
		"slot_count": 8,
		"maximum_mass_kg": 100.0,
		"maximum_volume_l": 100.0,
	})
	var destination = ContainerStateScript.new({
		"container_id": DESTINATION_CONTAINER_ID,
		"owner_kind": "ITEM_INSTANCE",
		"owner_id": terminal_item_id,
		"storage_mode": ContainerStateScript.STORAGE_BULK,
		"slot_count": 8,
		"maximum_mass_kg": 100.0,
		"maximum_volume_l": 100.0,
	})
	if not domain.containers.add_container(source) or not domain.containers.add_container(destination):
		return _failure("CONTAINER_CREATE_FAILED")
	var cargo = domain.items.create_item(
		"n1_command_cargo",
		3,
		{"network_fixture": {"stage": "initial"}},
		RelationsScript.container(SOURCE_CONTAINER_ID),
		"N1 Command Cargo"
	)
	if cargo == null:
		return _failure("COMMAND_ITEM_CREATE_FAILED")
	command_item_id = String(cargo.instance_id)
	source.assign_item(command_item_id)
	if not source.item_ids.has(command_item_id):
		return _failure("SOURCE_MEMBERSHIP_FAILED")
	aggregate = domain.world_entities.create_for_item(terminal_item_id, _create_spatial_ref(), {
		"entity_id": ENTITY_ID,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"state_revision": INITIAL_REVISION,
		"last_simulation_tick": server_tick,
		"partition_address": PartitionAddressScript.create_cube_sphere(
			0, 1, 1, 0, 1, "main", "moon", "cube_sphere", "persistent", 1
		),
		"physics_state": {"sleeping": true, "mass_kg": 12.0},
		"domain_components": {
			"inventory": _build_inventory_projection(),
		},
	})
	if aggregate == null:
		return _failure("AGGREGATE_CREATE_FAILED")
	terminal.set_relation(RelationsScript.world_entity(aggregate.entity_id))
	var graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		return _failure("INITIAL_ITEM_GRAPH_INVALID", {"cause": graph_validation})
	var binding_validation: Dictionary = domain.world_entities.validate_item_bindings(domain.items)
	if not bool(binding_validation.get("success", false)):
		return _failure("INITIAL_WORLD_BINDING_INVALID", {"cause": binding_validation})
	gateway = GatewayScript.new()
	gateway.setup(authority_epoch, _resolve_authority_epoch)
	if not gateway.register_handler(COMMAND_TYPE, _handle_move_to_container):
		return _failure("COMMAND_HANDLER_REGISTRATION_FAILED")
	return _success({
		"entity_id": String(aggregate.entity_id),
		"item_id": command_item_id,
		"snapshot": create_snapshot(),
	})


func bind_session(value: String) -> Dictionary:
	if value.strip_edges().is_empty():
		return _failure("SESSION_ID_REQUIRED")
	if not session_id.is_empty() and session_id != value:
		return _failure("SESSION_ALREADY_BOUND")
	session_id = value
	return _success({"session_id": session_id})


func create_snapshot() -> Dictionary:
	if aggregate == null:
		return {}
	return SnapshotScript.create(
		SNAPSHOT_ID,
		String(aggregate.entity_id),
		String(aggregate.entity_type),
		int(aggregate.state_revision),
		String(aggregate.authority_owner_id),
		int(aggregate.authority_epoch),
		int(aggregate.last_simulation_tick),
		aggregate.spatial_ref,
		aggregate.partition_address,
		aggregate.physics_state,
		aggregate.domain_components
	)


func handle_command(envelope: Dictionary) -> Dictionary:
	if gateway == null:
		return _failure("AUTHORITY_NOT_CONFIGURED")
	return gateway.handle(envelope)


func get_delta(operation_id: String) -> Dictionary:
	return Dictionary(deltas_by_operation.get(operation_id, {})).duplicate(true)


func get_final_snapshot(operation_id: String) -> Dictionary:
	return Dictionary(final_snapshots_by_operation.get(operation_id, {})).duplicate(true)


func get_report() -> Dictionary:
	var item = domain.items.get_item(command_item_id) if not domain.is_empty() else null
	var source = domain.containers.get_container(SOURCE_CONTAINER_ID) if not domain.is_empty() else null
	var destination = domain.containers.get_container(DESTINATION_CONTAINER_ID) if not domain.is_empty() else null
	var snapshot: Dictionary = create_snapshot()
	return {
		"schema": "planet_simulator.n1_remote_item_authority_report.v1",
		"entity_id": ENTITY_ID,
		"command_item_id": command_item_id,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"server_tick": server_tick,
		"aggregate_revision": int(aggregate.state_revision) if aggregate != null else -1,
		"snapshot_checksum": String(snapshot.get("checksum", "")),
		"item_revision": int(item.revision) if item != null else -1,
		"item_relation": item.relation.duplicate(true) if item != null else {},
		"source_contains_item": source != null and source.item_ids.has(command_item_id),
		"destination_contains_item": destination != null and destination.item_ids.has(command_item_id),
		"mutation_count": mutation_count,
		"handler_invocation_count": handler_invocation_count,
		"completed_gateway_operations": gateway.completed_operations.size() if gateway != null else 0,
		"operation_ledger_count": domain.operations.records.size() if not domain.is_empty() else 0,
	}


func _handle_move_to_container(payload: Dictionary, envelope: Dictionary) -> Dictionary:
	handler_invocation_count += 1
	var payload_validation: Dictionary = MovePayloadScript.validate(payload)
	if not bool(payload_validation.get("success", false)):
		return _handler_failure(String(payload_validation.get("error_code", "INVALID_COMMAND_PAYLOAD")))
	if session_id.is_empty() or String(payload["session_id"]) != session_id:
		return _handler_failure("SESSION_ID_MISMATCH")
	if String(payload["authority_owner_id"]) != authority_owner_id:
		return _handler_failure("AUTHORITY_OWNER_MISMATCH")
	if String(envelope["entity_id"]) != String(aggregate.entity_id):
		return _handler_failure("ENTITY_ID_MISMATCH")
	if int(envelope["expected_revision"]) != int(aggregate.state_revision):
		return _handler_failure("REVISION_CONFLICT", {
			"expected_revision": int(envelope["expected_revision"]),
			"actual_revision": int(aggregate.state_revision),
			"requires_snapshot": true,
		})
	if String(payload["source_container_id"]) != SOURCE_CONTAINER_ID:
		return _handler_failure("SOURCE_CONTAINER_MISMATCH")
	if String(payload["destination_container_id"]) != DESTINATION_CONTAINER_ID:
		return _handler_failure("DESTINATION_CONTAINER_MISMATCH")
	if String(payload["item_id"]) != command_item_id:
		return _handler_failure("ITEM_NOT_FOUND")
	var item = domain.items.get_item(command_item_id)
	if item == null:
		return _handler_failure("ITEM_NOT_FOUND")
	if int(payload["expected_item_revision"]) != int(item.revision):
		return _handler_failure("ITEM_REVISION_CONFLICT", {
			"expected_item_revision": int(payload["expected_item_revision"]),
			"actual_item_revision": int(item.revision),
		})
	var source = domain.containers.get_container(SOURCE_CONTAINER_ID)
	if source == null or not source.item_ids.has(command_item_id):
		return _handler_failure("SOURCE_MEMBERSHIP_MISMATCH")
	var base_snapshot: Dictionary = create_snapshot()
	var staged_state: Dictionary = _capture_domain_state()
	var transfer_result: Dictionary = domain.transfer.move_item(
		command_item_id,
		RelationsScript.container(DESTINATION_CONTAINER_ID),
		String(envelope["operation_id"]),
		int(payload["expected_item_revision"])
	)
	if not bool(transfer_result.get("success", false)):
		return _handler_failure(
			String(transfer_result.get("error_code", "ITEM_TRANSFER_REJECTED")),
			{"item_result": transfer_result.duplicate(true)}
		)
	var graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		_restore_domain_state(staged_state)
		return _handler_failure("ITEM_GRAPH_INVALID_AFTER_COMMAND", {"cause": graph_validation})
	var next_tick: int = server_tick + 1
	var component_result: Dictionary = aggregate.apply_domain_components(
		{"inventory": _build_inventory_projection(mutation_count + 1)},
		int(base_snapshot["state_revision"]),
		authority_epoch,
		next_tick
	)
	if not bool(component_result.get("success", false)):
		_restore_domain_state(staged_state)
		return _handler_failure("AGGREGATE_UPDATE_FAILED", {"cause": component_result})
	var binding_validation: Dictionary = domain.world_entities.validate_item_bindings(domain.items)
	if not bool(binding_validation.get("success", false)):
		_restore_domain_state(staged_state)
		return _handler_failure("WORLD_BINDING_INVALID_AFTER_COMMAND", {"cause": binding_validation})
	server_tick = next_tick
	var result_snapshot: Dictionary = create_snapshot()
	var delta_id: String = "delta/n1/%s" % String(envelope["operation_id"]).replace("/", "-")
	var delta: Dictionary = DeltaScript.create(
		delta_id,
		String(aggregate.entity_id),
		String(aggregate.entity_type),
		int(base_snapshot["state_revision"]),
		int(result_snapshot["state_revision"]),
		authority_owner_id,
		authority_epoch,
		server_tick,
		{"domain_components.inventory": aggregate.domain_components["inventory"]},
		[]
	)
	var delta_validation: Dictionary = DeltaScript.validate(delta)
	if not bool(delta_validation.get("success", false)):
		_restore_domain_state(staged_state)
		return _handler_failure("DELTA_BUILD_FAILED", {"cause": delta_validation})
	var applied: Dictionary = DeltaScript.apply_to_snapshot(base_snapshot, delta)
	if (
		not bool(applied.get("success", false))
		or String(applied.get("snapshot", {}).get("checksum", "")) != String(result_snapshot["checksum"])
	):
		_restore_domain_state(staged_state)
		return _handler_failure("DELTA_SNAPSHOT_MISMATCH", {"cause": applied})
	var operation_id: String = String(envelope["operation_id"])
	deltas_by_operation[operation_id] = delta.duplicate(true)
	final_snapshots_by_operation[operation_id] = result_snapshot.duplicate(true)
	mutation_count += 1
	var moved_item = domain.items.get_item(command_item_id)
	return {
		"success": true,
		"retryable": false,
		"error_code": "",
		"result_revision": int(aggregate.state_revision),
		"payload": MoveResultScript.create(
			String(aggregate.entity_id),
			command_item_id,
			SOURCE_CONTAINER_ID,
			DESTINATION_CONTAINER_ID,
			int(moved_item.revision),
			delta_id,
			String(result_snapshot["checksum"]),
			server_tick
		),
	}


func _handler_failure(error_code: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"retryable": false,
		"error_code": error_code,
		"result_revision": int(aggregate.state_revision) if aggregate != null else -1,
		"payload": payload.duplicate(true),
	}


func _resolve_authority_epoch(entity_id: String) -> int:
	return authority_epoch if aggregate != null and entity_id == String(aggregate.entity_id) else authority_epoch


func _register_definitions() -> void:
	domain.items.register_definition(DefinitionScript.new({
		"id": "n1_storage_terminal",
		"display_name": "N1 Storage Terminal",
		"max_stack": 1,
		"unit_mass_kg": 12.0,
		"external_volume_l": 30.0,
		"tags": ["container", "network_fixture"],
	}))
	domain.items.register_definition(DefinitionScript.new({
		"id": "n1_command_cargo",
		"display_name": "N1 Command Cargo",
		"max_stack": 10,
		"unit_mass_kg": 1.0,
		"external_volume_l": 0.5,
		"tags": ["cargo", "network_fixture"],
	}))


func _create_spatial_ref() -> Dictionary:
	return SpatialRefScript.create(
		"body/moon/fixed",
		Vector3(1010.0, 20.0, -30.0),
		Basis.IDENTITY,
		Vector3.ZERO,
		Vector3.ZERO,
		float(server_tick),
		"main",
		"moon",
		"persistent"
	)


func _build_inventory_projection(committed_count: int = -1) -> Dictionary:
	var source = domain.containers.get_container(SOURCE_CONTAINER_ID)
	var destination = domain.containers.get_container(DESTINATION_CONTAINER_ID)
	var item = domain.items.get_item(command_item_id)
	var source_ids: Array[String] = []
	var destination_ids: Array[String] = []
	if source != null:
		source_ids.assign(source.item_ids)
		source_ids.sort()
	if destination != null:
		destination_ids.assign(destination.item_ids)
		destination_ids.sort()
	return {
		"schema": "planet_simulator.n1_inventory_projection.v1",
		"command_type": COMMAND_TYPE,
		"command_item_id": command_item_id,
		"source_container_id": SOURCE_CONTAINER_ID,
		"destination_container_id": DESTINATION_CONTAINER_ID,
		"source_item_ids": source_ids,
		"destination_item_ids": destination_ids,
		"source_revision": int(source.revision) if source != null else -1,
		"destination_revision": int(destination.revision) if destination != null else -1,
		"item_definition_id": String(item.definition_id) if item != null else "",
		"item_quantity": int(item.quantity) if item != null else 0,
		"item_revision": int(item.revision) if item != null else -1,
		"item_relation": item.relation.duplicate(true) if item != null else {},
		"committed_operation_count": mutation_count if committed_count < 0 else committed_count,
	}


func _capture_domain_state() -> Dictionary:
	return {
		"items": domain.items.to_dict(),
		"containers": domain.containers.to_dict(),
		"operations": domain.operations.to_dict(),
		"world_entities": domain.world_entities.to_dict(),
		"server_tick": server_tick,
		"mutation_count": mutation_count,
	}


func _restore_domain_state(state: Dictionary) -> bool:
	var restored_domain: Dictionary = FactoryScript.create()
	var item_result: Dictionary = restored_domain.items.load_dict(state["items"])
	var container_result: Dictionary = restored_domain.containers.load_dict(state["containers"])
	var operation_result: Dictionary = restored_domain.operations.load_dict(state["operations"])
	var entity_result: Dictionary = restored_domain.world_entities.load_dict(state["world_entities"])
	if not (
		bool(item_result.get("success", false))
		and bool(container_result.get("success", false))
		and bool(operation_result.get("success", false))
		and bool(entity_result.get("success", false))
	):
		return false
	var restored_graph: Dictionary = restored_domain.validator.validate_graph()
	var restored_bindings: Dictionary = restored_domain.world_entities.validate_item_bindings(restored_domain.items)
	if not (
		bool(restored_graph.get("success", false))
		and bool(restored_bindings.get("success", false))
	):
		return false
	var restored_aggregate = restored_domain.world_entities.get_entity(ENTITY_ID)
	if restored_aggregate == null:
		return false
	domain = restored_domain
	aggregate = restored_aggregate
	server_tick = int(state["server_tick"])
	mutation_count = int(state["mutation_count"])
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
