extends "res://scripts/construction/build/construction_build_process.gd"

const AllocatorScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_construction_material_allocator.gd")
const LivePortScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_live_m4_construction_transaction_port.gd")
const BuildPlanScriptP4 = preload("res://scripts/construction/build/construction_build_plan.gd")
const StageScriptP4 = preload("res://scripts/construction/build/construction_build_stage.gd")
const StagePlannerScriptP4 = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")

var _live_port
var _item_graph
var _ore_quantity_by_stage: Dictionary = {}


func setup_live(
	live_port,
	item_graph,
	build_plan_store,
	ore_quantity_by_stage: Dictionary
) -> Dictionary:
	if live_port == null or not live_port.has_method("apply_live_plan") or not live_port.has_method("is_bound_to_item_graph"):
		return _failure("P4_LIVE_BUILD_TRANSACTION_PORT_REQUIRED")
	if item_graph == null or not item_graph.has_method("create_snapshot"):
		return _failure("P4_LIVE_BUILD_ITEM_GRAPH_REQUIRED")
	if not live_port.is_bound_to_item_graph(item_graph):
		return _failure("P4_LIVE_BUILD_ITEM_GRAPH_IDENTITY_MISMATCH")
	var costs: Dictionary = {}
	for stage_index_value in ore_quantity_by_stage.keys():
		var stage_index := int(stage_index_value)
		var quantity := int(ore_quantity_by_stage[stage_index_value])
		if stage_index < 0 or quantity < 1:
			return _failure("P4_LIVE_BUILD_RECIPE_INVALID")
		costs[stage_index] = quantity
	_live_port = live_port
	_item_graph = item_graph
	_ore_quantity_by_stage = costs
	_authoritative_adapter = live_port
	_store = build_plan_store
	if _store == null or not _store.has_method("register_plan") or not _store.has_method("reconcile_progress"):
		return _failure("CONSTRUCTION_BUILD_PLAN_STORE_REQUIRED")
	_configured = true
	return _success({
		"single_item_graph_identity": true,
		"recipe_stage_count": costs.size(),
	})


func advance_stage(
	_build_plan_id: String,
	_expected_stage_index: int,
	_operation_id: String,
	_provided_capabilities: Array = [],
	_options: Dictionary = {}
) -> Dictionary:
	return _failure("P4_BUILD_PLAYER_CONTEXT_REQUIRED", {}, STATUS_REJECTED)


func advance_stage_for_actor(
	logical_player_id: String,
	build_plan_id: String,
	expected_stage_index: int,
	operation_id: String,
	provided_capabilities: Array = [],
	options: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILD_PROCESS_NOT_CONFIGURED", {}, STATUS_REJECTED)
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _failure("P4_BUILD_PLAYER_CONTEXT_REQUIRED", {}, STATUS_REJECTED)
	if not operation_id.begins_with("operation/") or operation_id.length() <= 10 or operation_id != operation_id.strip_edges():
		return _failure("INVALID_CONSTRUCTION_BUILD_OPERATION_ID", {}, STATUS_REJECTED)
	var plan: Dictionary = _store.get_plan(build_plan_id)
	if plan.is_empty():
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND", {}, STATUS_REJECTED)
	var plan_validation: Dictionary = BuildPlanScriptP4.validate(plan)
	if not bool(plan_validation.get("success", false)):
		return _with_status(plan_validation, STATUS_REJECTED)
	if expected_stage_index < 0 or expected_stage_index >= plan["stages"].size():
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_INDEX", {}, STATUS_REJECTED)
	if not _ore_quantity_by_stage.has(expected_stage_index):
		return _failure("P4_LIVE_BUILD_RECIPE_STAGE_MISSING", {}, STATUS_REJECTED)
	var reconciled: Dictionary = reconcile_plan(build_plan_id)
	if not bool(reconciled.get("success", false)):
		return _with_status(reconciled, STATUS_REJECTED)
	var ghost: Dictionary = _store.get_ghost(build_plan_id)
	if String(ghost["status"]) == GhostScript.STATUS_CANCELLED:
		return _failure("CONSTRUCTION_GHOST_CANCELLED", {}, STATUS_REJECTED)
	var next_stage_index: int = int(ghost["next_stage_index"])
	if expected_stage_index < next_stage_index:
		var recorded_operation := String(ghost["completed_operation_ids"][expected_stage_index])
		if recorded_operation != operation_id:
			return _failure("CONSTRUCTION_BUILD_STAGE_OPERATION_CONFLICT", {}, STATUS_REJECTED)
		var previous_result: Dictionary = _live_port.get_operation_result(operation_id)
		return _stage_success(plan, expected_stage_index, previous_result, true)
	if expected_stage_index > next_stage_index:
		return _failure("CONSTRUCTION_BUILD_STAGE_ORDER_VIOLATION", {
			"expected_stage_index": expected_stage_index,
			"next_stage_index": next_stage_index,
		}, STATUS_REJECTED)
	var capability_check: Dictionary = _validate_capabilities(
		plan["stages"][expected_stage_index]["required_capabilities"],
		provided_capabilities
	)
	if not bool(capability_check.get("success", false)):
		return _with_status(capability_check, STATUS_RETRYABLE)
	if not String(options.get("failure_point", "")).is_empty():
		return _failure("P4_LIVE_BUILD_UNSUPPORTED_FAILURE_POINT", {}, STATUS_REJECTED)

	var required_quantity := int(_ore_quantity_by_stage[expected_stage_index])
	var allocation: Dictionary = AllocatorScript.allocate_r1(_item_graph, player_id, required_quantity)
	if not bool(allocation.get("success", false)):
		var allocation_failure: Dictionary = allocation.duplicate(true)
		allocation_failure["status"] = STATUS_RETRYABLE
		return allocation_failure
	var derived_result: Dictionary = _build_live_stage_plan(plan, expected_stage_index, allocation)
	if not bool(derived_result.get("success", false)):
		return _with_status(derived_result, STATUS_REJECTED)
	var derived_plan: Dictionary = Dictionary(derived_result.get("plan", {}))
	var planned: Dictionary = StagePlannerScriptP4.build_stage_transaction_plan(
		derived_plan,
		expected_stage_index,
		operation_id
	)
	if not bool(planned.get("success", false)):
		return _with_status(planned, STATUS_REJECTED)
	var transaction_plan: Dictionary = planned["transaction_plan"]
	var authoritative_failure_mode := String(options.get("authoritative_failure_mode", ""))
	var authoritative_result: Dictionary = _live_port.apply_live_plan(
		transaction_plan,
		allocation,
		player_id,
		{"construction_failure_mode": authoritative_failure_mode}
	)
	if not bool(authoritative_result.get("success", false)):
		return authoritative_result
	var recorded: Dictionary = _store.record_stage_success(
		build_plan_id,
		expected_stage_index,
		operation_id,
		String(transaction_plan["checksum"])
	)
	if not bool(recorded.get("success", false)):
		return _with_status(recorded, STATUS_RETRYABLE)
	var success: Dictionary = _stage_success(plan, expected_stage_index, authoritative_result, false)
	success["logical_player_id"] = player_id
	success["required_ore_quantity"] = required_quantity
	success["allocation_checksum"] = String(allocation.get("details", {}).get("allocation_checksum", ""))
	success["single_item_graph_identity"] = true
	return success


func _build_live_stage_plan(
	base_plan: Dictionary,
	stage_index: int,
	allocation: Dictionary
) -> Dictionary:
	var sources: Array = Array(base_plan.get("source_item_projections", [])).duplicate(true)
	var material_allocations: Array = []
	for allocation_value in Dictionary(allocation.get("details", {})).get("allocations", []):
		if not allocation_value is Dictionary:
			return _failure("P4_LIVE_BUILD_ALLOCATION_INVALID")
		var row: Dictionary = allocation_value
		var item_id := String(row.get("item_id", ""))
		var projection: Dictionary = _live_port.get_item_projection(item_id)
		if projection.is_empty():
			return _failure("P4_LIVE_BUILD_M4_PROJECTION_MISSING", {"item_id": item_id})
		sources.append(projection)
		material_allocations.append({
			"item_instance_id": item_id,
			"definition_id": LivePortScript.R1_CONSTRUCTION_DEFINITION_ID,
			"quantity": int(row.get("quantity", 0)),
		})
	var stages: Array = []
	for index in range(base_plan["stages"].size()):
		var source_stage: Dictionary = base_plan["stages"][index]
		stages.append(StageScriptP4.create(
			String(source_stage["stage_id"]),
			int(source_stage["sequence_index"]),
			String(source_stage["display_name"]),
			String(source_stage["semantic_state"]),
			Array(source_stage["included_part_ids"]),
			Array(source_stage["included_bond_ids"]),
			material_allocations if index == stage_index else [],
			Array(source_stage["required_capabilities"])
		))
	var derived: Dictionary = BuildPlanScriptP4.create(
		String(base_plan["build_plan_id"]),
		String(base_plan["display_name"]),
		Dictionary(base_plan["ghost_relation"]),
		Dictionary(base_plan["target_snapshot"]),
		sources,
		stages
	)
	var validation: Dictionary = BuildPlanScriptP4.validate(derived)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"plan": derived})
