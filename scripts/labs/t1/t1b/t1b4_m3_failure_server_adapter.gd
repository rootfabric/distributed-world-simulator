extends "res://scripts/labs/t1/t1a7/t1a7_m3_runtime_server_adapter.gd"

const T1B3RuntimeScript = preload("res://scripts/labs/t1/t1b/t1b3_recoverable_failure_runtime.gd")

const T1B4_SCHEMA: String = "planet_simulator.t1b4_m3_failure_server_adapter.v1"

var _failure_plan_updates: int = 0
var _failure_plan_rejections: int = 0
var _runtime_checkpoints: int = 0
var _runtime_checkpoint_failures: int = 0


func _create_t1_runtime():
	return T1B3RuntimeScript.new()


func apply_failure_plan(
	requirements_by_runtime_id: Dictionary,
	base_availability_by_runtime_id: Dictionary,
	edges: Array
) -> Dictionary:
	if _t1_runtime == null or not _t1_runtime.has_method("apply_failure_plan"):
		_failure_plan_rejections += 1
		return _t1b4_failure("T1B4_FAILURE_RUNTIME_NOT_READY")
	var before: Dictionary = create_construction_runtime_snapshot()
	var result: Dictionary = _t1_runtime.apply_failure_plan(
		requirements_by_runtime_id,
		base_availability_by_runtime_id,
		edges
	)
	if not bool(result.get("success", false)):
		_failure_plan_rejections += 1
		return result
	_failure_plan_updates += 1
	var after: Dictionary = create_construction_runtime_snapshot()
	if int(after.get("revision", -1)) > int(before.get("revision", -1)):
		_broadcast_runtime_snapshot("T1B4_FAILURE_PLAN")
	return _t1b4_success({
		"applied_runtime_ids": Array(result.get("applied_runtime_ids", [])).duplicate(),
		"snapshot": after,
	})


func checkpoint_runtime(operation_id: String) -> Dictionary:
	if _t1_runtime == null or not _t1_runtime.has_method("checkpoint_runtime"):
		_runtime_checkpoint_failures += 1
		return _t1b4_failure("T1B4_RECOVERABLE_RUNTIME_NOT_READY")
	var result: Dictionary = _t1_runtime.checkpoint_runtime(operation_id)
	if bool(result.get("success", false)):
		_runtime_checkpoints += 1
	else:
		_runtime_checkpoint_failures += 1
	return result


func get_t1b4_runtime_report() -> Dictionary:
	return {
		"schema": T1B4_SCHEMA,
		"failure_plan_updates": _failure_plan_updates,
		"failure_plan_rejections": _failure_plan_rejections,
		"runtime_checkpoints": _runtime_checkpoints,
		"runtime_checkpoint_failures": _runtime_checkpoint_failures,
		"recovered_from_m0": bool(_t1_runtime.get_report().get("recovered_from_m0", false)) if _t1_runtime != null else false,
		"runtime_checkpoint_revision": int(_t1_runtime.get_report().get("runtime_checkpoint_revision", -1)) if _t1_runtime != null else -1,
		"t1a7": get_t1a7_runtime_report(),
	}


static func _t1b4_success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _t1b4_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
