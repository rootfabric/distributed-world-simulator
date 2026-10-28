extends RefCounted
## ECO ARCH2 A14.6 R3.2 — OPTIONAL single-worker, host-owned LAB A4.
##
## CPU-only accepted Runtime/A5/R2 paths execute in Godot WorkerThreadPool.
## Never call Node, SceneTree, rendering, network or Region/Matter APIs from
## the worker. The main thread ONLY polls an already complete task, performs
## a canonical source-frontier check, and adopts ONE finished Runtime tick.
## The entire task is atomic from the caller's perspective. No worker result
## may be committed after a cancellation/PAUSE/restore or changed source.
##
## The source is a shallow outer copy of a *trusted*, controller-private
## immutable canonical frontier; the worker does NOT write any source member.
## Host MUST disallow concurrent mutable aliases, just like A14.5 staging.
## True cancellation is cooperative BETWEEN indivisible Runtime steps.
## A canceled task is drained before a new task is enqueued.
## No hard deadline, guaranteed throughput, or WORLD_COMPAT activation.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")

const SCHEMA := "dws.ecology.a14-6-r3-2-off-main-session.v1"
const MAX_WORKER_RESUMES := 4096
const MAX_CURSOR_BYTES := 16777216
const MAX_ALLOCATOR_ITEMS := 4096

var _task_id := -1
var _mutex: Mutex = Mutex.new()
var _cancel_requested := false
var _abandoned := false
var _worker_result: Dictionary = {}
var _source_hash := ""
var _options_hash := ""
var _source_tick := -1
var _job_started_us := 0
var _jobs_started := 0
var _jobs_committed := 0
var _jobs_abandoned := 0
var _jobs_failed := 0
var _drained := 0
var _max_poll_us := 0
var _last_worker_wall_us := 0
var _last_error := ""

func has_pending() -> bool:
	return _task_id >= 0 and not _abandoned

func is_draining() -> bool:
	return _task_id >= 0 and _abandoned

## Reap an abandoned completed pool task WITHOUT blocking the main thread.
## Call while paused/reconfigured as well, otherwise Godot retains task IDs.
func reap_discarded() -> bool:
	if not is_draining() or not WorkerThreadPool.is_task_completed(_task_id):
		return false
	var joined: Error = WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_drained += 1
	_abandoned = false
	_mutex.lock()
	_worker_result = {}
	_cancel_requested = false
	_mutex.unlock()
	if joined != OK:
		_jobs_failed += 1
		_last_error = "R3_ASYNC_ABANDONED_TASK_JOIN"
	return true

func cancel() -> bool:
	reap_discarded()
	var was_pending := has_pending()
	if was_pending:
		_mutex.lock()
		_cancel_requested = true
		_mutex.unlock()
		_abandoned = true
		_jobs_abandoned += 1
	# The task can still be in its current indivisible operation;
	# its result is never returned or committed after abandonment.
	return was_pending

func status() -> Dictionary:
	reap_discarded()
	return {
		"schema": SCHEMA,
		"pending": has_pending(),
		"abandoned_draining": is_draining(),
		"jobs_started": _jobs_started,
		"jobs_committed": _jobs_committed,
		"jobs_abandoned": _jobs_abandoned,
		"jobs_failed": _jobs_failed,
		"tasks_joined": _drained,
		"peak_poll_wall_us": _max_poll_us,
		"last_worker_wall_us": _last_worker_wall_us,
		"last_error": _last_error,
	}

func advance(state: Dictionary, options: Dictionary,
		max_members: int = 8, allocator_items: int = 64,
		cursor_cap_bytes: int = 8388608) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	reap_discarded()
	if not C.integer(max_members, 1, Spatial.MAX_MEMBERS) \
			or not C.integer(allocator_items, 1, MAX_ALLOCATOR_ITEMS) \
			or not C.integer(cursor_cap_bytes, 1024, MAX_CURSOR_BYTES):
		return _failed("R3_ASYNC_PARAMETERS", t0)
	if _task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return _pending(t0, "DRAINING" if _abandoned else "BACKGROUND")
		# Non-blocking by contract: the task is already completed. Always
		# wait exactly once so Godot releases the task's pool resources.
		var joined: Error = WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_drained += 1
		if joined != OK:
			_worker_result = {}
			return _failed("R3_ASYNC_TASK_JOIN", t0)
		_mutex.lock()
		var payload: Dictionary = _worker_result
		_worker_result = {}
		_mutex.unlock()
		if _abandoned:
			_abandoned = false
			# The caller may re-run from a trusted new frontier on its next
			# frame, but no result from the cancelled generation is returned.
			return _pending(t0, "DRAINED")
		if String(state.get("integrity_hash", "")) != _source_hash \
				or int(state.get("tick", -1)) != _source_tick \
				or C.digest(options) != _options_hash:
			return _failed("R3_ASYNC_SOURCE_CHANGED", t0)
		if not bool(payload.get("success", false)):
			_jobs_failed += 1
			return _failed("R3_ASYNC_WORKER:" + String(payload.get("error", "?")), t0)
		if not payload.has("state") or not payload.state is Dictionary \
				or int(payload.state.tick) != _source_tick + 1:
			_jobs_failed += 1
			return _failed("R3_ASYNC_FINAL_STATE", t0)
		# Main-thread final source admission runs ONCE, not on each
		# pending frame. Error => no canonical result adoption.
		var canonical_error: String = Runtime.validate(state)
		if not canonical_error.is_empty():
			_jobs_failed += 1
			return _failed("R3_ASYNC_SOURCE_INVALID:" + canonical_error, t0)
		_jobs_committed += 1
		_last_worker_wall_us = int(payload.get("worker_wall_us", 0))
		var result: Dictionary = payload.state
		_source_hash = ""
		_options_hash = ""
		_source_tick = -1
		return {
			"success": true, "complete": true, "pending": false,
			"phase": "COMPLETE", "state": result,
			"canonical_tick": int(result.tick),
			"replayed_ticks": 1, "resume_calls": int(payload.get("resumes", 0)),
			"cursor_bytes": 0,
			"wall_us": maxi(0, Time.get_ticks_usec() - t0),
			"overrun_us": 0,
			"worker_wall_us": _last_worker_wall_us,
		}
	# Exactly one job can run per host session. Starting with
	# shallow read-only input avoids a full main-thread deep copy.
	# Heavy Runtime.validate runs in the CPU worker's begin and once on
	# final source admission, never in the GUI dispatch frame.
	if not state.has("integrity_hash") or not state.has("tick") 			or not state.integrity_hash is String or not state.tick is int:
		return _failed("R3_ASYNC_INVALID_SOURCE_HEADER", t0)
	var options_hash: String = C.digest(options)
	if options_hash.is_empty():
		return _failed("R3_ASYNC_INVALID_OPTIONS", t0)
	var anchor: String = String(state.integrity_hash)
	_mutex.lock()
	_cancel_requested = false
	_worker_result = {}
	_mutex.unlock()
	_abandoned = false
	_source_hash = anchor
	_options_hash = options_hash
	_source_tick = int(state.tick)
	_job_started_us = Time.get_ticks_usec()
	# The worker is the only writer to this isolated outer dictionary; all
	# nested authoritative state remains read-only until Runtime duplicates it.
	var frozen_state: Dictionary = state.duplicate(false)
	var frozen_options: Dictionary = options.duplicate(true)
	_task_id = WorkerThreadPool.add_task(
		Callable(self, "_compute").bind(
			frozen_state, frozen_options, max_members,
			allocator_items, cursor_cap_bytes),
		false, "eco-a146-r3-2-global-a4")
	if _task_id < 0:
		return _failed("R3_ASYNC_SPAWN_FAILED", t0)
	_jobs_started += 1
	return _pending(t0, "BACKGROUND")

func _compute(frozen: Dictionary, options: Dictionary, members: int,
		items: int, cursor_cap: int) -> void:
	var started_us: int = Time.get_ticks_usec()
	var payload: Dictionary = {}
	var started: Dictionary = Runtime.begin_staged_global_tick(
		frozen, options, 4, members, true)
	if not bool(started.get("success", false)) or not started.has("cursor"):
		payload = {"success": false,
			"error": "BEGIN:" + String(started.get("error", "?"))}
	else:
		var cursor: Dictionary = started.cursor
		for i in MAX_WORKER_RESUMES:
			if _is_cancel_requested():
				payload = {"success": false, "error": "CANCELLED"}
				break
			var encoded: String = C.encode(cursor)
			if encoded.is_empty() or encoded.to_utf8_buffer().size() > cursor_cap:
				payload = {"success": false, "error": "CURSOR_CAP"}
				break
			var step: Dictionary = Runtime.resume_staged_global_tick(
				frozen, options, cursor, 1, items, cursor_cap)
			if not bool(step.get("success", false)):
				payload = {"success": false,
					"error": "RESUME:" + String(step.get("error", "?"))}
				break
			if bool(step.get("complete", false)):
				if not step.has("state") or not step.state is Dictionary:
					payload = {"success": false, "error": "FINAL_STATE"}
				else:
					payload = {"success": true, "state": step.state,
						"resumes": i + 1}
				break
			if step.has("state") or not step.has("cursor"):
				payload = {"success": false, "error": "PARTIAL_COMMIT"}
				break
			cursor = step.cursor
		if payload.is_empty():
			payload = {"success": false, "error": "WORKER_RESUME_LIMIT"}
	payload["worker_wall_us"] = maxi(0, Time.get_ticks_usec() - started_us)
	_mutex.lock()
	_worker_result = payload
	_mutex.unlock()

func _is_cancel_requested() -> bool:
	_mutex.lock()
	var cancelled: bool = _cancel_requested
	_mutex.unlock()
	return cancelled

func _pending(started_us: int, phase: String) -> Dictionary:
	var wall: int = maxi(0, Time.get_ticks_usec() - started_us)
	_max_poll_us = maxi(_max_poll_us, wall)
	return {
		"success": true, "complete": false, "pending": true,
		"phase": phase, "replayed_ticks": 0, "resume_calls": 0,
		"cursor_bytes": 0, "wall_us": wall, "overrun_us": 0,
	}

func _failed(reason: String, started_us: int) -> Dictionary:
	_last_error = reason
	return {"success": false, "complete": false,
		"error": reason, "wall_us": maxi(0, Time.get_ticks_usec() - started_us)}
