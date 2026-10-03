extends RefCounted

const SOFT_STALL_MS := 2000
const HARD_STALL_MS := 5000
const POLL_INTERVAL_MS := 250
const MAX_STAGE_TEXT := 96
const MAX_CONTEXT_TEXT := 160

var _thread := Thread.new()
var _mutex := Mutex.new()
var _stop_requested := false
var _process_id := 0
var _next_token := 0
var _stack: Array[Dictionary] = []
var _soft_reports := 0
var _hard_reports := 0
var _max_elapsed_ms := 0
var _max_stage := ""
var _unbalanced_scope_repairs := 0
var _started := false


func start(process_id: int = 0) -> Dictionary:
	if _started:
		return _success({"already_started": true})
	_process_id = process_id if process_id > 0 else OS.get_process_id()
	_stop_requested = false
	_stack.clear()
	_soft_reports = 0
	_hard_reports = 0
	_max_elapsed_ms = 0
	_max_stage = ""
	_unbalanced_scope_repairs = 0
	var error := _thread.start(Callable(self, "_worker"))
	if error != OK:
		return _failure("STALL_WATCHDOG_THREAD_START_FAILED", {"error": error})
	_started = true
	return _success()


func enter(stage: String, context: Dictionary = {}) -> int:
	if not _started:
		return 0
	var normalized := stage.strip_edges().left(MAX_STAGE_TEXT)
	if normalized.is_empty():
		normalized = "UNKNOWN"
	_mutex.lock()
	_next_token += 1
	var token := _next_token
	_stack.append({
		"token": token,
		"stage": normalized,
		"started_ms": Time.get_ticks_msec(),
		"context": _bounded_context(context),
		"soft_reported": false,
		"hard_reported": false,
	})
	_mutex.unlock()
	return token


func exit(token: int) -> Dictionary:
	if not _started or token < 1:
		return _success({"elapsed_ms": 0})
	var now_ms := Time.get_ticks_msec()
	var elapsed := 0
	var stage := ""
	var repaired_children := 0
	_mutex.lock()
	var index := -1
	for offset in range(_stack.size()):
		var candidate := _stack.size() - 1 - offset
		if int(_stack[candidate].get("token", 0)) == token:
			index = candidate
			break
	if index >= 0:
		var entry: Dictionary = Dictionary(_stack[index])
		elapsed = maxi(now_ms - int(entry.get("started_ms", now_ms)), 0)
		stage = String(entry.get("stage", ""))
		# If a parent scope returns, every nested scope above it must also have
		# returned. Remove leaked child scopes defensively so diagnostics cannot
		# manufacture a permanent false stall after normal control flow resumes.
		repaired_children = maxi(_stack.size() - index - 1, 0)
		if repaired_children > 0:
			_unbalanced_scope_repairs += repaired_children
		for remove_index in range(_stack.size() - 1, index - 1, -1):
			_stack.remove_at(remove_index)
		if elapsed > _max_elapsed_ms:
			_max_elapsed_ms = elapsed
			_max_stage = stage
	_mutex.unlock()
	return _success({
		"elapsed_ms": elapsed,
		"stage": stage,
		"repaired_children": repaired_children,
	})


func stop() -> Dictionary:
	if not _started:
		return _success({"already_stopped": true})
	_mutex.lock()
	_stop_requested = true
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()
	_started = false
	_stack.clear()
	return _success()


func get_report() -> Dictionary:
	_mutex.lock()
	var current := Dictionary(_stack.back()).duplicate(true) if not _stack.is_empty() else {}
	var report := {
		"schema": "distributed_world_simulator.live2_server_stall_watchdog.v1",
		"started": _started,
		"process_id": _process_id,
		"soft_threshold_ms": SOFT_STALL_MS,
		"hard_threshold_ms": HARD_STALL_MS,
		"poll_interval_ms": POLL_INTERVAL_MS,
		"active_depth": _stack.size(),
		"current": current,
		"soft_reports": _soft_reports,
		"hard_reports": _hard_reports,
		"max_elapsed_ms": _max_elapsed_ms,
		"max_stage": _max_stage,
		"unbalanced_scope_repairs": _unbalanced_scope_repairs,
	}
	_mutex.unlock()
	return report


func _worker() -> void:
	while true:
		OS.delay_msec(POLL_INTERVAL_MS)
		var now_ms := Time.get_ticks_msec()
		var event: Dictionary = {}
		var stop_now := false
		_mutex.lock()
		stop_now = _stop_requested
		if not stop_now and not _stack.is_empty():
			var index := _stack.size() - 1
			var entry: Dictionary = Dictionary(_stack[index])
			var elapsed := maxi(now_ms - int(entry.get("started_ms", now_ms)), 0)
			if elapsed > _max_elapsed_ms:
				_max_elapsed_ms = elapsed
				_max_stage = String(entry.get("stage", ""))
			var severity := ""
			if elapsed >= HARD_STALL_MS and not bool(entry.get("hard_reported", false)):
				severity = "HARD"
				entry["hard_reported"] = true
				entry["soft_reported"] = true
				_hard_reports += 1
			elif elapsed >= SOFT_STALL_MS and not bool(entry.get("soft_reported", false)):
				severity = "SOFT"
				entry["soft_reported"] = true
				_soft_reports += 1
			if not severity.is_empty():
				_stack[index] = entry
				event = {
					"event": "SERVER_PUMP_HARD_STALL" if severity == "HARD" else "SERVER_PUMP_STALL",
					"severity": severity,
					"process_id": _process_id,
					"time_msec": now_ms,
					"elapsed_ms": elapsed,
					"stage": String(entry.get("stage", "")),
					"token": int(entry.get("token", 0)),
					"active_depth": _stack.size(),
					"context": Dictionary(entry.get("context", {})).duplicate(true),
				}
		_mutex.unlock()
		if stop_now:
			break
		if not event.is_empty():
			print("[live2_stall_watchdog] %s" % JSON.stringify(event, "", true, true))


func _bounded_context(context: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value in context.keys():
		if result.size() >= 16:
			break
		var key := String(key_value).left(64)
		var value = context[key_value]
		match typeof(value):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
				result[key] = value
			TYPE_STRING, TYPE_STRING_NAME:
				result[key] = String(value).replace("\n", " ").replace("\r", " ").replace("\t", " ").left(MAX_CONTEXT_TEXT)
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
