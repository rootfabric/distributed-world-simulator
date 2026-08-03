extends RefCounted

const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const GhostScript = preload("res://scripts/construction/build/construction_ghost_state.gd")
const StoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")
const StagePlannerScript = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")

const STATUS_SUCCEEDED: String = "SUCCEEDED"
const STATUS_REJECTED: String = "REJECTED"
const STATUS_RETRYABLE: String = "RETRYABLE"
const FAILURE_AFTER_AUTHORITATIVE_COMMIT: String = "AFTER_AUTHORITATIVE_COMMIT"

var _authoritative_adapter
var _store
var _configured: bool = false


func setup(authoritative_adapter, build_plan_store = null) -> Dictionary:
	if (
		authoritative_adapter == null
		or not authoritative_adapter.has_method("apply_plan")
		or not authoritative_adapter.has_method("get_item_projection")
		or not authoritative_adapter.has_method("get_construct_snapshot")
		or not authoritative_adapter.has_method("get_operation_result")
	):
		return _failure("AUTHORITATIVE_CONSTRUCTION_ADAPTER_REQUIRED")
	_authoritative_adapter = authoritative_adapter
	_store = build_plan_store if build_plan_store != null else StoreScript.new()
	if not _store.has_method("register_plan") or not _store.has_method("reconcile_progress"):
		return _failure("CONSTRUCTION_BUILD_PLAN_STORE_REQUIRED")
	_configured = true
	return _success()


func register_plan(build_plan: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILD_PROCESS_NOT_CONFIGURED")
	var registered: Dictionary = _store.register_plan(build_plan)
	if not bool(registered.get("success", false)):
		return registered
	var reconciled: Dictionary = reconcile_plan(String(build_plan.get("build_plan_id", "")))
	if not bool(reconciled.get("success", false)):
		return reconciled
	return _success({
		"replay": bool(registered.get("replay", false)),
		"ghost": _store.get_ghost(String(build_plan["build_plan_id"])),
	})


func reconcile_plan(build_plan_id: String) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILD_PROCESS_NOT_CONFIGURED")
	var plan: Dictionary = _store.get_plan(build_plan_id)
	if plan.is_empty():
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
	var current_snapshot: Dictionary = _authoritative_adapter.get_construct_snapshot(String(plan["construct_id"]))
	var resolved: Dictionary = SnapshotBuilderScript.completed_stage_count(plan, current_snapshot)
	if not bool(resolved.get("success", false)):
		return resolved
	var reconciled: Dictionary = _store.reconcile_progress(build_plan_id, int(resolved["completed_stage_count"]))
	if not bool(reconciled.get("success", false)):
		return reconciled
	return _success({
		"completed_stage_count": int(resolved["completed_stage_count"]),
		"ghost": _store.get_ghost(build_plan_id),
		"replay": bool(reconciled.get("replay", false)),
	})


func reconcile_all() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILD_PROCESS_NOT_CONFIGURED")
	var state: Dictionary = _store.to_dict()
	var plan_ids: Array[String] = []
	for plan in state.get("plans", []):
		plan_ids.append(String(plan.get("build_plan_id", "")))
	plan_ids.sort()
	var reports: Array = []
	for plan_id in plan_ids:
		var reconciled: Dictionary = reconcile_plan(plan_id)
		if not bool(reconciled.get("success", false)):
			return reconciled
		reports.append(reconciled)
	return _success({"plan_count": plan_ids.size(), "reports": reports})


func advance_stage(
	build_plan_id: String,
	expected_stage_index: int,
	operation_id: String,
	provided_capabilities: Array = [],
	options: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILD_PROCESS_NOT_CONFIGURED", {}, STATUS_REJECTED)
	if not operation_id.begins_with("operation/") or operation_id.length() <= 10 or operation_id != operation_id.strip_edges():
		return _failure("INVALID_CONSTRUCTION_BUILD_OPERATION_ID", {}, STATUS_REJECTED)
	var plan: Dictionary = _store.get_plan(build_plan_id)
	if plan.is_empty():
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND", {}, STATUS_REJECTED)
	var plan_validation: Dictionary = BuildPlanScript.validate(plan)
	if not bool(plan_validation.get("success", false)):
		return _with_status(plan_validation, STATUS_REJECTED)
	if expected_stage_index < 0 or expected_stage_index >= plan["stages"].size():
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_INDEX", {}, STATUS_REJECTED)
	var reconciled: Dictionary = reconcile_plan(build_plan_id)
	if not bool(reconciled.get("success", false)):
		return _with_status(reconciled, STATUS_REJECTED)
	var ghost: Dictionary = _store.get_ghost(build_plan_id)
	if String(ghost["status"]) == GhostScript.STATUS_CANCELLED:
		return _failure("CONSTRUCTION_GHOST_CANCELLED", {}, STATUS_REJECTED)
	var planned: Dictionary = StagePlannerScript.build_stage_transaction_plan(plan, expected_stage_index, operation_id)
	if not bool(planned.get("success", false)):
		return _with_status(planned, STATUS_REJECTED)
	var transaction_plan: Dictionary = planned["transaction_plan"]
	var next_stage_index: int = int(ghost["next_stage_index"])
	if expected_stage_index < next_stage_index:
		var recorded_operation: String = String(ghost["completed_operation_ids"][expected_stage_index])
		var recorded_checksum: String = String(ghost["completed_transaction_checksums"][expected_stage_index])
		if recorded_operation.is_empty():
			var recovered_result: Dictionary = _authoritative_adapter.get_operation_result(operation_id)
			if recovered_result.is_empty():
				return _failure("CONSTRUCTION_BUILD_STAGE_ALREADY_COMPLETED", {}, STATUS_REJECTED)
			var authoritative_replay: Dictionary = _authoritative_adapter.apply_plan(transaction_plan)
			if not bool(authoritative_replay.get("success", false)):
				return authoritative_replay
			var bound: Dictionary = _store.bind_stage_operation(
				build_plan_id,
				expected_stage_index,
				operation_id,
				String(transaction_plan["checksum"])
			)
			if not bool(bound.get("success", false)):
				return _with_status(bound, STATUS_REJECTED)
			return _stage_success(plan, expected_stage_index, authoritative_replay, true)
		if recorded_operation != operation_id or recorded_checksum != String(transaction_plan["checksum"]):
			return _failure("CONSTRUCTION_BUILD_STAGE_OPERATION_CONFLICT", {}, STATUS_REJECTED)
		var replay: Dictionary = _authoritative_adapter.apply_plan(transaction_plan)
		if not bool(replay.get("success", false)):
			return replay
		return _stage_success(plan, expected_stage_index, replay, true)
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
	var authoritative_failure_mode: String = String(options.get("authoritative_failure_mode", ""))
	var authoritative_result: Dictionary = _authoritative_adapter.apply_plan(transaction_plan, authoritative_failure_mode)
	if not bool(authoritative_result.get("success", false)):
		return authoritative_result
	if String(options.get("failure_point", "")) == FAILURE_AFTER_AUTHORITATIVE_COMMIT:
		return _failure("INJECTED_FAILURE_AFTER_AUTHORITATIVE_STAGE_COMMIT", {
			"operation_id": operation_id,
			"transaction_plan_checksum": String(transaction_plan["checksum"]),
		}, STATUS_RETRYABLE)
	if not String(options.get("failure_point", "")).is_empty():
		return _failure("UNKNOWN_CONSTRUCTION_BUILD_FAILURE_POINT", {}, STATUS_REJECTED)
	var recorded: Dictionary = _store.record_stage_success(
		build_plan_id,
		expected_stage_index,
		operation_id,
		String(transaction_plan["checksum"])
	)
	if not bool(recorded.get("success", false)):
		return _with_status(recorded, STATUS_RETRYABLE)
	return _stage_success(plan, expected_stage_index, authoritative_result, false)


func get_ghost_projection(build_plan_id: String) -> Dictionary:
	if not _configured:
		return {}
	var plan: Dictionary = _store.get_plan(build_plan_id)
	var ghost: Dictionary = _store.get_ghost(build_plan_id)
	if plan.is_empty() or ghost.is_empty():
		return {}
	var completed_count: int = int(ghost["next_stage_index"])
	var materialized_part_ids: Array = []
	if completed_count > 0:
		materialized_part_ids = plan["stages"][completed_count - 1]["included_part_ids"].duplicate(true)
	var target_part_ids: Array = []
	for part in plan["target_snapshot"]["parts"]:
		target_part_ids.append(String(part["part_id"]))
	target_part_ids.sort()
	return {
		"schema": "planet_simulator.construction_ghost_projection.v1",
		"ghost_id": String(ghost["ghost_id"]),
		"build_plan_id": build_plan_id,
		"construct_id": String(plan["construct_id"]),
		"relation": Dictionary(plan["ghost_relation"]).duplicate(true),
		"status": String(ghost["status"]),
		"completed_stage_count": completed_count,
		"stage_count": plan["stages"].size(),
		"target_part_ids": target_part_ids,
		"materialized_part_ids": materialized_part_ids,
		"physical": completed_count > 0,
		"capabilities": [],
		"mass_kg": 0.0,
	}


func get_stage_requirements(build_plan_id: String, stage_index: int) -> Dictionary:
	if not _configured:
		return {}
	var plan: Dictionary = _store.get_plan(build_plan_id)
	if plan.is_empty() or stage_index < 0 or stage_index >= plan["stages"].size():
		return {}
	var stage: Dictionary = plan["stages"][stage_index]
	var previous_parts: Dictionary = {}
	if stage_index > 0:
		for part_id in plan["stages"][stage_index - 1]["included_part_ids"]:
			previous_parts[String(part_id)] = true
	var added_parts: Array = []
	for part_id in stage["included_part_ids"]:
		if not previous_parts.has(String(part_id)):
			added_parts.append(String(part_id))
	return {
		"stage_id": String(stage["stage_id"]),
		"stage_index": stage_index,
		"semantic_state": String(stage["semantic_state"]),
		"part_ids": added_parts,
		"material_allocations": stage["material_allocations"].duplicate(true),
		"required_capabilities": stage["required_capabilities"].duplicate(true),
	}


func get_store():
	return _store


func _validate_capabilities(required: Array, provided: Array) -> Dictionary:
	var available: Dictionary = {}
	for raw in provided:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_PROVIDED_CONSTRUCTION_CAPABILITY")
		available[String(raw)] = true
	var missing: Array[String] = []
	for raw in required:
		var capability: String = String(raw)
		if not available.has(capability):
			missing.append(capability)
	if not missing.is_empty():
		return _failure("CONSTRUCTION_BUILD_STAGE_CAPABILITY_MISSING", {"missing_capabilities": missing})
	return _success()


func _stage_success(plan: Dictionary, stage_index: int, authoritative_result: Dictionary, replay: bool) -> Dictionary:
	var ghost: Dictionary = _store.get_ghost(String(plan["build_plan_id"]))
	return _success({
		"status": STATUS_SUCCEEDED,
		"replay": replay,
		"build_plan_id": String(plan["build_plan_id"]),
		"stage_id": String(plan["stages"][stage_index]["stage_id"]),
		"stage_index": stage_index,
		"authoritative_result": authoritative_result.duplicate(true),
		"ghost": ghost,
		"completed_stage_count": int(ghost["next_stage_index"]),
		"stage_count": plan["stages"].size(),
	})


func _with_status(result: Dictionary, status: String) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	output["status"] = status
	return output


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String, details: Dictionary = {}, status: String = "") -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	if not status.is_empty():
		result["status"] = status
	return result
