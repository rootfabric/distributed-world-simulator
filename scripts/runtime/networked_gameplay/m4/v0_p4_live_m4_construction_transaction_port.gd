extends RefCounted

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const ItemRelationsScript = preload("res://scripts/items/domain/item_relations.gd")

const R1_DEFINITION_ID := "item/ore"
const R1_CONSTRUCTION_DEFINITION_ID := "ore"
const FAILURE_AFTER_M4_COMMIT := "AFTER_M4_COMMIT"
const ALLOWED_CONSTRUCTION_FAILURE_MODES: Array[String] = ["", "BEFORE_COMMIT"]

var _item_graph
var _construction_adapter
var _configured := false


func setup(item_graph, construction_adapter) -> Dictionary:
	if item_graph == null:
		return _failure("P4_LIVE_M4_ITEM_GRAPH_REQUIRED")
	for method_name in [
		"create_snapshot",
		"validate_snapshot",
		"export_durable_state",
		"restore_durable_state",
		"export_replay_state",
		"restore_replay_state",
		"preflight_server_construction_consume",
		"apply_server_construction_consume",
	]:
		if not item_graph.has_method(method_name):
			return _failure("P4_LIVE_M4_ITEM_GRAPH_METHOD_MISSING", {"method": method_name})
	if construction_adapter == null:
		return _failure("P4_CONSTRUCTION_ADAPTER_REQUIRED")
	for method_name in [
		"apply_plan",
		"get_item_projection",
		"get_construct_snapshot",
		"get_operation_result",
		"export_state",
		"load_state",
	]:
		if not construction_adapter.has_method(method_name):
			return _failure("P4_CONSTRUCTION_ADAPTER_METHOD_MISSING", {"method": method_name})
	_item_graph = item_graph
	_construction_adapter = construction_adapter
	_configured = true
	return _success({"single_item_graph_identity": true})


func is_bound_to_item_graph(candidate) -> bool:
	return _configured and candidate != null and _item_graph == candidate


func get_item_projection(item_instance_id: String) -> Dictionary:
	if not _configured:
		return {}
	var local: Dictionary = _construction_adapter.get_item_projection(item_instance_id)
	if not local.is_empty():
		return local
	var snapshot: Dictionary = _item_graph.create_snapshot()
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		if String(item.get("item_id", "")) != item_instance_id:
			continue
		return _project_m4_item(item, int(snapshot.get("revision", 0)))
	return {}


func get_construct_snapshot(construct_id: String) -> Dictionary:
	return _construction_adapter.get_construct_snapshot(construct_id) if _configured else {}


func get_operation_result(operation_id: String) -> Dictionary:
	return _construction_adapter.get_operation_result(operation_id) if _configured else {}


func get_generation() -> int:
	if not _configured:
		return 0
	var state: Dictionary = _construction_adapter.export_state()
	return int(state.get("server_tick", 0))


func has_terminal_operation(operation_id: String) -> bool:
	return _configured and not operation_id.is_empty() and not get_operation_result(operation_id).is_empty()


func export_state() -> Dictionary:
	if not _configured:
		return {"generation": 0, "items": [], "constructs": []}
	var state: Dictionary = _construction_adapter.export_state()
	var projections: Array = []
	for item_value in Dictionary(state.get("item_registry", {})).get("items", []):
		if not item_value is Dictionary:
			continue
		var projection_result: Dictionary = ProjectionScript.from_item_instance_dict(Dictionary(item_value))
		if bool(projection_result.get("success", false)):
			projections.append(Dictionary(projection_result.get("projection", {})).duplicate(true))
	projections.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("item_instance_id", "")) < String(right.get("item_instance_id", ""))
	)
	var constructs: Array = Array(Dictionary(state.get("construct_store", {})).get("constructs", [])).duplicate(true)
	constructs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("construct_id", "")) < String(right.get("construct_id", ""))
	)
	return {
		"generation": int(state.get("server_tick", 0)),
		"items": projections,
		"constructs": constructs,
	}


func apply_live_plan(
	transaction_plan: Dictionary,
	allocation_result: Dictionary,
	logical_player_id: String,
	options: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure("P4_LIVE_M4_TRANSACTION_PORT_NOT_CONFIGURED")
	var plan_validation: Dictionary = PlanScript.validate(transaction_plan)
	if not bool(plan_validation.get("success", false)):
		return _failure("P4_CONSTRUCTION_TRANSACTION_PLAN_INVALID", {"cause": plan_validation})
	var allocation_validation := _validate_allocation_binding(transaction_plan, allocation_result, logical_player_id)
	if not bool(allocation_validation.get("success", false)):
		return allocation_validation
	var binding: Dictionary = Dictionary(allocation_validation.get("details", {}))
	var construction_failure_mode := String(options.get("construction_failure_mode", ""))
	if not ALLOWED_CONSTRUCTION_FAILURE_MODES.has(construction_failure_mode):
		return _failure("P4_UNSAFE_CONSTRUCTION_FAILURE_MODE")
	var failure_point := String(options.get("failure_point", ""))
	if not failure_point.is_empty() and failure_point != FAILURE_AFTER_M4_COMMIT:
		return _failure("P4_UNKNOWN_LIVE_TRANSACTION_FAILURE_POINT")

	var bridge_plan_result := _build_construction_bridge_plan(
		transaction_plan,
		Array(binding.get("local_item_mutations", [])),
		String(binding.get("allocation_checksum", ""))
	)
	if not bool(bridge_plan_result.get("success", false)):
		return bridge_plan_result
	var bridge_plan: Dictionary = Dictionary(bridge_plan_result.get("details", {}).get("bridge_plan", {}))
	var allocations: Array = Array(binding.get("allocations", []))
	var player_id := String(binding.get("logical_player_id", ""))
	var snapshot_revision := int(binding.get("snapshot_revision", -1))
	var snapshot_tick := int(binding.get("snapshot_tick", -1))
	var snapshot_checksum := String(binding.get("snapshot_checksum", ""))
	var source_plan_checksum := String(transaction_plan.get("checksum", ""))

	var item_preflight: Dictionary = _item_graph.preflight_server_construction_consume(
		String(transaction_plan.get("operation_id", "")),
		player_id,
		allocations,
		snapshot_revision,
		snapshot_tick,
		snapshot_checksum,
		source_plan_checksum
	)
	if not bool(item_preflight.get("success", false)):
		return _failure(String(item_preflight.get("error_code", "P4_M4_PREFLIGHT_FAILED")), {
			"cause": item_preflight,
		})

	var before_item_snapshot: Dictionary = _item_graph.create_snapshot()
	var before_item_durable: Dictionary = _item_graph.export_durable_state()
	var before_item_replay: Dictionary = _item_graph.export_replay_state()
	var before_construction_state: Dictionary = _construction_adapter.export_state()
	if before_item_durable.is_empty() or before_item_replay.is_empty() or before_construction_state.is_empty():
		return _failure("P4_ATOMIC_ROLLBACK_SNAPSHOT_UNAVAILABLE")
	var construction_preexisting: bool = not _construction_adapter.get_operation_result(
		String(transaction_plan.get("operation_id", ""))
	).is_empty()

	var item_result: Dictionary = _item_graph.apply_server_construction_consume(
		String(transaction_plan.get("operation_id", "")),
		player_id,
		allocations,
		snapshot_revision,
		snapshot_tick,
		snapshot_checksum,
		source_plan_checksum
	)
	if not bool(item_result.get("success", false)):
		return _failure(String(item_result.get("error_code", "P4_M4_COMMIT_FAILED")), {"cause": item_result})

	if failure_point == FAILURE_AFTER_M4_COMMIT:
		var injected_rollback := _rollback(
			before_item_durable,
			before_item_replay,
			before_construction_state,
			before_item_snapshot
		)
		if not bool(injected_rollback.get("success", false)):
			return injected_rollback
		return _failure("INJECTED_P4_FAILURE_AFTER_M4_COMMIT", {
			"status": "RETRYABLE",
			"rolled_back": true,
		})

	var construction_result: Dictionary = _construction_adapter.apply_plan(
		bridge_plan,
		construction_failure_mode
	)
	if not bool(construction_result.get("success", false)):
		var rolled_back := _rollback(
			before_item_durable,
			before_item_replay,
			before_construction_state,
			before_item_snapshot
		)
		if not bool(rolled_back.get("success", false)):
			return rolled_back
		return _failure(String(construction_result.get("error_code", "P4_CONSTRUCTION_COMMIT_FAILED")), {
			"cause": construction_result,
			"rolled_back": true,
		})

	var after_item_snapshot: Dictionary = _item_graph.create_snapshot()
	var item_replay := bool(item_result.get("replay", false))
	return _success({
		"operation_id": String(transaction_plan.get("operation_id", "")),
		"transaction_plan_checksum": source_plan_checksum,
		"bridge_plan_checksum": String(bridge_plan.get("checksum", "")),
		"allocation_checksum": String(binding.get("allocation_checksum", "")),
		"logical_player_id": player_id,
		"item_graph_before_revision": int(before_item_snapshot.get("revision", -1)),
		"item_graph_after_revision": int(after_item_snapshot.get("revision", -1)),
		"item_graph_before_checksum": String(before_item_snapshot.get("checksum", "")),
		"item_graph_after_checksum": String(after_item_snapshot.get("checksum", "")),
		"item_graph_result": item_result.duplicate(true),
		"construction_result": construction_result.duplicate(true),
		"external_material_item_ids": Array(binding.get("external_material_item_ids", [])).duplicate(),
		"replay": item_replay and construction_preexisting,
		"single_item_graph_identity": true,
	})


func _validate_allocation_binding(
	transaction_plan: Dictionary,
	allocation_result: Dictionary,
	logical_player_id: String
) -> Dictionary:
	if not bool(allocation_result.get("success", false)) or not allocation_result.get("details") is Dictionary:
		return _failure("P4_ALLOCATOR_RESULT_REQUIRED")
	var allocation: Dictionary = allocation_result.get("details", {})
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty() or String(allocation.get("logical_player_id", "")) != player_id:
		return _failure("P4_ALLOCATOR_PLAYER_MISMATCH")
	if String(allocation.get("definition_id", "")) != R1_DEFINITION_ID:
		return _failure("P4_ALLOCATOR_DEFINITION_MISMATCH")
	var allocations_value = allocation.get("allocations", [])
	if not allocations_value is Array or Array(allocations_value).is_empty():
		return _failure("P4_ALLOCATOR_ALLOCATIONS_REQUIRED")
	var allocations: Array = Array(allocations_value).duplicate(true)
	var identity := {
		"logical_player_id": player_id,
		"definition_id": R1_DEFINITION_ID,
		"required_quantity": int(allocation.get("required_quantity", 0)),
		"snapshot_revision": int(allocation.get("snapshot_revision", -1)),
		"snapshot_tick": int(allocation.get("snapshot_tick", -1)),
		"snapshot_checksum": String(allocation.get("snapshot_checksum", "")),
		"allocations": allocations,
	}
	var expected_allocation_checksum := NetworkUtils.payload_hash(identity)
	if String(allocation.get("allocation_checksum", "")) != expected_allocation_checksum:
		return _failure("P4_ALLOCATOR_CHECKSUM_MISMATCH")

	var allocation_by_item: Dictionary = {}
	for allocation_value in allocations:
		if not allocation_value is Dictionary:
			return _failure("P4_ALLOCATOR_ALLOCATION_INVALID")
		var row: Dictionary = allocation_value
		var item_id := String(row.get("item_id", ""))
		if item_id.is_empty() or allocation_by_item.has(item_id):
			return _failure("P4_ALLOCATOR_ALLOCATION_INVALID")
		allocation_by_item[item_id] = row

	var local_item_mutations: Array = []
	var external_item_ids: Array[String] = []
	var external_seen: Dictionary = {}
	var consumed_total := 0
	for mutation_value in transaction_plan.get("item_mutations", []):
		var mutation: Dictionary = mutation_value
		if String(mutation.get("purpose", "")) != ItemMutationScript.PURPOSE_CONSUME_MATERIAL:
			local_item_mutations.append(mutation.duplicate(true))
			continue
		var item_id := String(mutation.get("item_instance_id", ""))
		if not allocation_by_item.has(item_id) or external_seen.has(item_id):
			return _failure("P4_PLAN_ALLOCATION_ITEM_MISMATCH", {"item_id": item_id})
		var row: Dictionary = allocation_by_item[item_id]
		var before: Dictionary = mutation.get("before_projection", {})
		var after: Dictionary = mutation.get("after_projection", {})
		if (
			String(before.get("definition_id", "")) != R1_CONSTRUCTION_DEFINITION_ID
			or int(before.get("quantity", 0)) != int(row.get("available_quantity", -1))
		):
			return _failure("P4_PLAN_ALLOCATION_PRECONDITION_MISMATCH", {"item_id": item_id})
		var consumed := 0
		match String(mutation.get("operation_kind", "")):
			ItemMutationScript.OP_DELETE:
				if not after.is_empty():
					return _failure("P4_PLAN_ALLOCATION_MUTATION_INVALID", {"item_id": item_id})
				consumed = int(before.get("quantity", 0))
			ItemMutationScript.OP_UPDATE:
				consumed = int(before.get("quantity", 0)) - int(after.get("quantity", 0))
			_:
				return _failure("P4_PLAN_ALLOCATION_MUTATION_INVALID", {"item_id": item_id})
		if consumed != int(row.get("quantity", 0)) or consumed < 1:
			return _failure("P4_PLAN_ALLOCATION_QUANTITY_MISMATCH", {"item_id": item_id})
		external_seen[item_id] = true
		external_item_ids.append(item_id)
		consumed_total += consumed
	if external_seen.size() != allocation_by_item.size():
		return _failure("P4_PLAN_ALLOCATION_SET_MISMATCH")
	if consumed_total != int(allocation.get("required_quantity", 0)):
		return _failure("P4_PLAN_ALLOCATION_TOTAL_MISMATCH")
	if local_item_mutations.is_empty():
		return _failure("P4_CONSTRUCTION_LOCAL_MUTATION_REQUIRED")
	external_item_ids.sort()
	return _success({
		"logical_player_id": player_id,
		"allocations": allocations,
		"allocation_checksum": expected_allocation_checksum,
		"snapshot_revision": int(allocation.get("snapshot_revision", -1)),
		"snapshot_tick": int(allocation.get("snapshot_tick", -1)),
		"snapshot_checksum": String(allocation.get("snapshot_checksum", "")),
		"local_item_mutations": local_item_mutations,
		"external_material_item_ids": external_item_ids,
	})


func _build_construction_bridge_plan(
	source_plan: Dictionary,
	local_item_mutations: Array,
	allocation_checksum: String
) -> Dictionary:
	var authoritative_local_mutations: Array = _authoritative_local_mutations(local_item_mutations)
	var bridge_identity := NetworkUtils.payload_hash({
		"source_plan_checksum": String(source_plan.get("checksum", "")),
		"allocation_checksum": allocation_checksum,
	})
	var bridge_plan := PlanScript.create(
		"plan/p4-live-m4/%s" % bridge_identity.left(32),
		String(source_plan.get("operation_id", "")),
		String(source_plan.get("command_type", "")),
		Dictionary(source_plan.get("construct_mutation", {})),
		authoritative_local_mutations,
		Array(source_plan.get("invariants", []))
	)
	var validation: Dictionary = PlanScript.validate(bridge_plan)
	if not bool(validation.get("success", false)):
		return _failure("P4_CONSTRUCTION_BRIDGE_PLAN_INVALID", {"cause": validation})
	return _success({"bridge_plan": bridge_plan})


func _authoritative_local_mutations(local_item_mutations: Array) -> Array:
	var result: Array = []
	for mutation_value in local_item_mutations:
		var mutation: Dictionary = Dictionary(mutation_value).duplicate(true)
		if (
			String(mutation.get("operation_kind", "")) == ItemMutationScript.OP_CREATE
			and String(mutation.get("purpose", "")) == ItemMutationScript.PURPOSE_CREATE_ROOT
		):
			var after: Dictionary = Dictionary(mutation.get("after_projection", {})).duplicate(true)
			var relation: Dictionary = Dictionary(after.get("relation", {}))
			if (
				String(relation.get("kind", "")) == ProjectionScript.WORLD
				and String(relation.get("entity_id", "")).is_empty()
				and not relation.has("spatial_ref")
			):
				after["relation"] = ItemRelationsScript.world()
				mutation = ItemMutationScript.create(
					ItemMutationScript.OP_CREATE,
					ItemMutationScript.PURPOSE_CREATE_ROOT,
					String(mutation.get("item_instance_id", "")),
					{},
					after
				)
		result.append(mutation)
	return result


func _rollback(
	before_item_durable: Dictionary,
	before_item_replay: Dictionary,
	before_construction_state: Dictionary,
	before_item_snapshot: Dictionary
) -> Dictionary:
	var construction_restore: Dictionary = _construction_adapter.load_state(before_construction_state)
	if not bool(construction_restore.get("success", false)):
		return _failure("P4_CONSTRUCTION_ROLLBACK_FAILED", {"cause": construction_restore})
	var item_restore: Dictionary = _item_graph.restore_durable_state(before_item_durable)
	if not bool(item_restore.get("success", false)):
		return _failure("P4_M4_DURABLE_ROLLBACK_FAILED", {"cause": item_restore})
	var replay_restore: Dictionary = _item_graph.restore_replay_state(before_item_replay)
	if not bool(replay_restore.get("success", false)):
		return _failure("P4_M4_REPLAY_ROLLBACK_FAILED", {"cause": replay_restore})
	var restored_snapshot: Dictionary = _item_graph.create_snapshot()
	if String(restored_snapshot.get("checksum", "")) != String(before_item_snapshot.get("checksum", "")):
		return _failure("P4_M4_ROLLBACK_CHECKSUM_MISMATCH")
	if NetworkUtils.canonical_json(_construction_adapter.export_state()) != NetworkUtils.canonical_json(before_construction_state):
		return _failure("P4_CONSTRUCTION_ROLLBACK_CHECKSUM_MISMATCH")
	return _success({"rolled_back": true})


func _project_m4_item(item: Dictionary, snapshot_revision: int) -> Dictionary:
	var location_value = item.get("location", {})
	if not location_value is Dictionary:
		return {}
	var location: Dictionary = location_value
	var relation: Dictionary = {}
	match String(location.get("kind", "")):
		"INVENTORY":
			var player_id := String(location.get("player_id", "")).strip_edges().to_lower()
			var slot_index := int(location.get("slot_index", -1))
			if player_id.is_empty() or slot_index < 0:
				return {}
			relation = ProjectionScript.container_relation("inventory/%s" % player_id, slot_index)
		"CONTAINER":
			var container_id := String(location.get("container_id", ""))
			if container_id.is_empty():
				return {}
			relation = ProjectionScript.container_relation(container_id, int(location.get("slot_index", -1)))
		"WORLD":
			relation = ProjectionScript.world_relation()
		_:
			return {}
	var projection := ProjectionScript.create(
		String(item.get("item_id", "")),
		R1_CONSTRUCTION_DEFINITION_ID if String(item.get("definition_id", "")) == R1_DEFINITION_ID else String(item.get("definition_id", "")),
		String(item.get("definition_id", "")),
		int(item.get("quantity", 0)),
		relation,
		{},
		snapshot_revision
	)
	var validation: Dictionary = ProjectionScript.validate(projection)
	return projection if bool(validation.get("success", false)) else {}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
