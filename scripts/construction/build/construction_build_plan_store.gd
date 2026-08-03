extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const GhostScript = preload("res://scripts/construction/build/construction_ghost_state.gd")

const SCHEMA: String = "planet_simulator.construction_build_plan_store.v1"
const FIELDS: Array[String] = ["schema", "generation", "plans", "ghosts", "checksum"]

var _plans: Dictionary = {}
var _ghosts: Dictionary = {}
var _generation: int = 0


func setup() -> Dictionary:
	_plans.clear()
	_ghosts.clear()
	_generation = 0
	return _success()


func register_plan(plan: Dictionary) -> Dictionary:
	var validation: Dictionary = BuildPlanScript.validate(plan)
	if not bool(validation.get("success", false)):
		return validation
	var plan_id: String = String(plan["build_plan_id"])
	if _plans.has(plan_id):
		if String(_plans[plan_id]["checksum"]) == String(plan["checksum"]):
			return _success({"replay": true, "ghost": get_ghost(plan_id)})
		return _failure("CONSTRUCTION_BUILD_PLAN_ID_CONFLICT")
	for existing_plan in _plans.values():
		if String(existing_plan["construct_id"]) == String(plan["construct_id"]):
			return _failure("CONSTRUCTION_BUILD_PLAN_CONSTRUCT_CONFLICT")
	var ghost: Dictionary = GhostScript.create(plan)
	var ghost_validation: Dictionary = GhostScript.validate(ghost)
	if not bool(ghost_validation.get("success", false)):
		return ghost_validation
	_plans[plan_id] = _canonical_dictionary(plan)
	_ghosts[plan_id] = _canonical_dictionary(ghost)
	_generation += 1
	return _success({"replay": false, "ghost": get_ghost(plan_id)})


func get_plan(build_plan_id: String) -> Dictionary:
	return Dictionary(_plans.get(build_plan_id, {})).duplicate(true)


func get_ghost(build_plan_id: String) -> Dictionary:
	return Dictionary(_ghosts.get(build_plan_id, {})).duplicate(true)


func get_generation() -> int:
	return _generation


func record_stage_success(
	build_plan_id: String,
	stage_index: int,
	operation_id: String,
	transaction_checksum: String
) -> Dictionary:
	if not _plans.has(build_plan_id) or not _ghosts.has(build_plan_id):
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
	var plan: Dictionary = _plans[build_plan_id]
	var ghost: Dictionary = _ghosts[build_plan_id]
	if stage_index < 0 or stage_index >= plan["stages"].size():
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_INDEX")
	var next_index: int = int(ghost["next_stage_index"])
	if stage_index < next_index:
		if (
			String(ghost["completed_operation_ids"][stage_index]) == operation_id
			and String(ghost["completed_transaction_checksums"][stage_index]) == transaction_checksum
		):
			return _success({"replay": true, "ghost": ghost.duplicate(true)})
		return _failure("CONSTRUCTION_BUILD_STAGE_ALREADY_COMPLETED")
	if stage_index > next_index:
		return _failure("CONSTRUCTION_BUILD_STAGE_ORDER_VIOLATION")
	var completed_stages: Array = ghost["completed_stage_ids"].duplicate(true)
	var completed_operations: Array = ghost["completed_operation_ids"].duplicate(true)
	var completed_checksums: Array = ghost["completed_transaction_checksums"].duplicate(true)
	completed_stages.append(String(plan["stages"][stage_index]["stage_id"]))
	completed_operations.append(operation_id)
	completed_checksums.append(transaction_checksum)
	var updated: Dictionary = GhostScript.with_progress(
		ghost,
		completed_stages,
		completed_operations,
		completed_checksums,
		plan["stages"].size()
	)
	var validation: Dictionary = _validate_ghost_against_plan(updated, plan)
	if not bool(validation.get("success", false)):
		return validation
	_ghosts[build_plan_id] = _canonical_dictionary(updated)
	_generation += 1
	return _success({"replay": false, "ghost": get_ghost(build_plan_id)})


func reconcile_progress(build_plan_id: String, completed_count: int) -> Dictionary:
	if not _plans.has(build_plan_id) or not _ghosts.has(build_plan_id):
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
	var plan: Dictionary = _plans[build_plan_id]
	var ghost: Dictionary = _ghosts[build_plan_id]
	if completed_count < 0 or completed_count > plan["stages"].size():
		return _failure("INVALID_CONSTRUCTION_BUILD_RECONCILIATION_COUNT")
	var current_count: int = int(ghost["next_stage_index"])
	if completed_count < current_count:
		return _failure("CONSTRUCTION_GHOST_AHEAD_OF_AUTHORITY")
	if completed_count == current_count:
		return _success({"replay": true, "ghost": ghost.duplicate(true)})
	var completed_stages: Array = ghost["completed_stage_ids"].duplicate(true)
	var completed_operations: Array = ghost["completed_operation_ids"].duplicate(true)
	var completed_checksums: Array = ghost["completed_transaction_checksums"].duplicate(true)
	for index in range(current_count, completed_count):
		completed_stages.append(String(plan["stages"][index]["stage_id"]))
		completed_operations.append("")
		completed_checksums.append("")
	var updated: Dictionary = GhostScript.with_progress(
		ghost,
		completed_stages,
		completed_operations,
		completed_checksums,
		plan["stages"].size()
	)
	var validation: Dictionary = _validate_ghost_against_plan(updated, plan)
	if not bool(validation.get("success", false)):
		return validation
	_ghosts[build_plan_id] = _canonical_dictionary(updated)
	_generation += 1
	return _success({"replay": false, "ghost": get_ghost(build_plan_id)})


func bind_stage_operation(
	build_plan_id: String,
	stage_index: int,
	operation_id: String,
	transaction_checksum: String
) -> Dictionary:
	if not _plans.has(build_plan_id) or not _ghosts.has(build_plan_id):
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
	var plan: Dictionary = _plans[build_plan_id]
	var ghost: Dictionary = _ghosts[build_plan_id]
	if stage_index < 0 or stage_index >= int(ghost["next_stage_index"]):
		return _failure("CONSTRUCTION_BUILD_STAGE_NOT_COMPLETED")
	var existing_operation: String = String(ghost["completed_operation_ids"][stage_index])
	var existing_checksum: String = String(ghost["completed_transaction_checksums"][stage_index])
	if not existing_operation.is_empty():
		if existing_operation == operation_id and existing_checksum == transaction_checksum:
			return _success({"replay": true, "ghost": ghost.duplicate(true)})
		return _failure("CONSTRUCTION_BUILD_STAGE_OPERATION_CONFLICT")
	var operations: Array = ghost["completed_operation_ids"].duplicate(true)
	var checksums: Array = ghost["completed_transaction_checksums"].duplicate(true)
	operations[stage_index] = operation_id
	checksums[stage_index] = transaction_checksum
	var updated: Dictionary = ghost.duplicate(true)
	updated["completed_operation_ids"] = operations
	updated["completed_transaction_checksums"] = checksums
	updated["state_revision"] = int(updated["state_revision"]) + 1
	updated["checksum"] = ""
	updated["checksum"] = GhostScript.compute_checksum(updated)
	var validation: Dictionary = _validate_ghost_against_plan(updated, plan)
	if not bool(validation.get("success", false)):
		return validation
	_ghosts[build_plan_id] = _canonical_dictionary(updated)
	_generation += 1
	return _success({"replay": false, "ghost": get_ghost(build_plan_id)})


func cancel_ghost(build_plan_id: String) -> Dictionary:
	if not _plans.has(build_plan_id) or not _ghosts.has(build_plan_id):
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
	var ghost: Dictionary = _ghosts[build_plan_id]
	if int(ghost["next_stage_index"]) != 0:
		return _failure("STARTED_CONSTRUCTION_GHOST_CANNOT_CANCEL")
	if String(ghost["status"]) == GhostScript.STATUS_CANCELLED:
		return _success({"replay": true, "ghost": ghost.duplicate(true)})
	var updated: Dictionary = GhostScript.cancelled(ghost)
	_ghosts[build_plan_id] = _canonical_dictionary(updated)
	_generation += 1
	return _success({"replay": false, "ghost": get_ghost(build_plan_id)})


func to_dict() -> Dictionary:
	var state: Dictionary = {
		"schema": SCHEMA,
		"generation": _generation,
		"plans": _sorted_values(_plans, "build_plan_id"),
		"ghosts": _sorted_values(_ghosts, "build_plan_id"),
		"checksum": "",
	}
	state["checksum"] = compute_checksum(state)
	return state


func load_dict(state: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_state(state)
	if not bool(validation.get("success", false)):
		return validation
	var canonical: Dictionary = _canonical_dictionary(state)
	var next_plans: Dictionary = {}
	var next_ghosts: Dictionary = {}
	for plan in canonical["plans"]:
		next_plans[String(plan["build_plan_id"])] = plan.duplicate(true)
	for ghost in canonical["ghosts"]:
		next_ghosts[String(ghost["build_plan_id"])] = ghost.duplicate(true)
	_plans = next_plans
	_ghosts = next_ghosts
	_generation = int(canonical["generation"])
	return _success({"plan_count": _plans.size(), "ghost_count": _ghosts.size()})


static func validate_state(state: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(state, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if state.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_BUILD_PLAN_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0:
		return _failure("INVALID_CONSTRUCTION_BUILD_PLAN_STORE_GENERATION")
	if typeof(state.get("plans")) != TYPE_ARRAY or typeof(state.get("ghosts")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_BUILD_PLAN_STORE_COLLECTIONS")
	var plans: Dictionary = {}
	var previous_plan_id: String = ""
	for plan_value in state["plans"]:
		if typeof(plan_value) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_BUILD_PLAN")
		var plan: Dictionary = plan_value
		var validation: Dictionary = BuildPlanScript.validate(plan)
		if not bool(validation.get("success", false)):
			return validation
		var plan_id: String = String(plan["build_plan_id"])
		if plans.has(plan_id) or (not previous_plan_id.is_empty() and plan_id < previous_plan_id):
			return _failure("NON_CANONICAL_PERSISTED_CONSTRUCTION_BUILD_PLANS")
		plans[plan_id] = plan.duplicate(true)
		previous_plan_id = plan_id
	var ghosts: Dictionary = {}
	var previous_ghost_plan_id: String = ""
	for ghost_value in state["ghosts"]:
		if typeof(ghost_value) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_GHOST")
		var ghost: Dictionary = ghost_value
		var validation: Dictionary = GhostScript.validate(ghost)
		if not bool(validation.get("success", false)):
			return validation
		var plan_id: String = String(ghost["build_plan_id"])
		if ghosts.has(plan_id) or (not previous_ghost_plan_id.is_empty() and plan_id < previous_ghost_plan_id):
			return _failure("NON_CANONICAL_PERSISTED_CONSTRUCTION_GHOSTS")
		if not plans.has(plan_id):
			return _failure("PERSISTED_CONSTRUCTION_GHOST_PLAN_MISSING")
		var binding: Dictionary = _validate_ghost_against_plan(ghost, plans[plan_id])
		if not bool(binding.get("success", false)):
			return binding
		ghosts[plan_id] = ghost.duplicate(true)
		previous_ghost_plan_id = plan_id
	if plans.size() != ghosts.size():
		return _failure("CONSTRUCTION_BUILD_PLAN_STORE_PLAN_GHOST_SET_MISMATCH")
	if typeof(state.get("checksum")) != TYPE_STRING or String(state["checksum"]) != compute_checksum(state):
		return _failure("CONSTRUCTION_BUILD_PLAN_STORE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(state).get("success", false)):
		return _failure("CONSTRUCTION_BUILD_PLAN_STORE_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(state: Dictionary) -> String:
	var payload: Dictionary = state.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _validate_ghost_against_plan(ghost: Dictionary, plan: Dictionary) -> Dictionary:
	var ghost_validation: Dictionary = GhostScript.validate(ghost)
	if not bool(ghost_validation.get("success", false)):
		return ghost_validation
	if (
		String(ghost["build_plan_id"]) != String(plan["build_plan_id"])
		or String(ghost["build_plan_checksum"]) != String(plan["checksum"])
		or String(ghost["construct_id"]) != String(plan["construct_id"])
		or String(ghost["root_item_instance_id"]) != String(plan["root_item_instance_id"])
		or ghost["relation"] != plan["ghost_relation"]
	):
		return _failure("CONSTRUCTION_GHOST_PLAN_BINDING_MISMATCH")
	if int(ghost["next_stage_index"]) > plan["stages"].size():
		return _failure("CONSTRUCTION_GHOST_PROGRESS_EXCEEDS_PLAN")
	for index in range(ghost["completed_stage_ids"].size()):
		if String(ghost["completed_stage_ids"][index]) != String(plan["stages"][index]["stage_id"]):
			return _failure("CONSTRUCTION_GHOST_STAGE_SEQUENCE_MISMATCH")
	var should_complete: bool = int(ghost["next_stage_index"]) == plan["stages"].size()
	if should_complete != (String(ghost["status"]) == GhostScript.STATUS_COMPLETE):
		if String(ghost["status"]) != GhostScript.STATUS_CANCELLED:
			return _failure("CONSTRUCTION_GHOST_COMPLETION_STATUS_MISMATCH")
	return _success()


static func _sorted_values(source: Dictionary, id_field: String) -> Array:
	var ids: Array = source.keys()
	ids.sort()
	var result: Array = []
	for key in ids:
		var value: Dictionary = source[key]
		if String(value.get(id_field, "")) != String(key):
			return []
		result.append(value.duplicate(true))
	return result


static func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = UtilsScript.canonicalize(value)
	if bool(result.get("success", false)) and result.get("value") is Dictionary:
		return Dictionary(result["value"])
	return value.duplicate(true)


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
