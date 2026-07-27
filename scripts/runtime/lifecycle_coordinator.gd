extends RefCounted

const CREATED: String = "CREATED"
const STARTING: String = "STARTING"
const RUNNING: String = "RUNNING"
const DRAINING: String = "DRAINING"
const STOPPING: String = "STOPPING"
const STOPPED: String = "STOPPED"
const FAILED: String = "FAILED"

const SCHEMA: String = "planet_simulator.lifecycle_coordinator.v1"

var state: String = CREATED
var node_id: String = "local-offline"
var shutdown_reason: String = ""
var requested_exit_code: int = 0
var last_error: String = ""
var transitions: Array[Dictionary] = []
var started_msec: int = 0
var stopped_msec: int = 0


func setup(context: Dictionary = {}) -> void:
	node_id = String(context.get("node_id", node_id))
	started_msec = Time.get_ticks_msec()
	_transition(STARTING, "setup")


func mark_running(reason: String = "runtime_ready") -> Dictionary:
	if state != STARTING:
		return _failure("INVALID_LIFECYCLE_TRANSITION", "%s -> RUNNING" % state)
	_transition(RUNNING, reason)
	return _success()


func begin_shutdown(reason: String, exit_code: int = 0) -> Dictionary:
	if state == STOPPED:
		return _success()
	if state == FAILED:
		return _failure("LIFECYCLE_FAILED", last_error)
	if state not in [STARTING, RUNNING, DRAINING, STOPPING]:
		return _failure("INVALID_LIFECYCLE_TRANSITION", "%s -> DRAINING" % state)
	shutdown_reason = reason.strip_edges() if not reason.strip_edges().is_empty() else "shutdown"
	requested_exit_code = exit_code
	if state in [STARTING, RUNNING]:
		_transition(DRAINING, shutdown_reason)
	return _success()


func drain_runtime(runtime: Node, reason: String, timeout_ms: int = 30000) -> Dictionary:
	if runtime == null or not is_instance_valid(runtime):
		return {"success": true, "drained": true, "details": {}}
	var request_result: Dictionary = {"success": true}
	if runtime.has_method("request_runtime_stop"):
		var request_value = runtime.call("request_runtime_stop", reason)
		if request_value is Dictionary:
			request_result = request_value
	if not bool(request_result.get("success", true)):
		return request_result
	var drain_result: Dictionary = {"success": true, "drained": true}
	if runtime.has_method("drain_runtime_stop"):
		var drain_value = runtime.call("drain_runtime_stop", timeout_ms)
		if drain_value is Dictionary:
			drain_result = drain_value
	else:
		runtime.call("prepare_for_unload")
	if not bool(drain_result.get("success", true)):
		return drain_result
	return {
		"success": true,
		"drained": bool(drain_result.get("drained", true)),
		"request": request_result,
		"details": drain_result,
	}


func mark_stopping(reason: String = "runtime_drained") -> Dictionary:
	if state == STOPPING:
		return _success()
	if state != DRAINING:
		return _failure("INVALID_LIFECYCLE_TRANSITION", "%s -> STOPPING" % state)
	_transition(STOPPING, reason)
	return _success()


func mark_stopped(reason: String = "process_stopped") -> Dictionary:
	if state == STOPPED:
		return _success()
	if state not in [DRAINING, STOPPING]:
		return _failure("INVALID_LIFECYCLE_TRANSITION", "%s -> STOPPED" % state)
	stopped_msec = Time.get_ticks_msec()
	_transition(STOPPED, reason)
	return _success()


func mark_failed(message: String) -> Dictionary:
	last_error = message
	_transition(FAILED, message)
	return _failure("LIFECYCLE_FAILED", message)


func accepts_commands() -> bool:
	return state == RUNNING


func is_stopping() -> bool:
	return state in [DRAINING, STOPPING, STOPPED, FAILED]


func create_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"node_id": node_id,
		"state": state,
		"accepts_commands": accepts_commands(),
		"shutdown_reason": shutdown_reason,
		"requested_exit_code": requested_exit_code,
		"last_error": last_error,
		"started_msec": started_msec,
		"stopped_msec": stopped_msec,
		"transitions": transitions.duplicate(true),
	}


func _transition(next_state: String, reason: String) -> void:
	var previous: String = state
	state = next_state
	transitions.append({
		"from": previous,
		"to": next_state,
		"reason": reason,
		"ticks_msec": Time.get_ticks_msec(),
	})


func _success() -> Dictionary:
	return {"success": true, "error_code": "", "state": state}


func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message, "state": state}
