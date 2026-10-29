extends RefCounted

# Single repository writer. Only detached value snapshots cross the thread
# boundary. No SceneTree, live gameplay service, adapter or outbox in the worker.
# Periodic callers coalesce through their dirty flag, not an unbounded queue.
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const M6Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")

var _thread: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _job: Dictionary = {}
var _completion: Dictionary = {}
var _busy := false
var _stopping := false
var _repository
var _test_command_delay_ms := 0

# Test-only slow writer (inside the worker, never on the game thread).
func configure_test_command_delay_ms(delay_ms: int) -> Dictionary:
	if OS.get_environment("DWS_NET_SMOOTH_TEST_HOOKS") != "1":
		return _failure("ASYNC_CHECKPOINT_TEST_HOOK_DISABLED")
	if delay_ms < 0 or delay_ms > 2000:
		return _failure("ASYNC_CHECKPOINT_TEST_DELAY_INVALID")
	_mutex.lock()
	if _busy:
		_mutex.unlock()
		return _failure("ASYNC_CHECKPOINT_BUSY")
	_test_command_delay_ms = delay_ms
	_mutex.unlock()
	return {"success": true, "error_code": "", "details": {"delay_ms": delay_ms}}


func setup(root_path: String) -> Dictionary:
	if _thread != null:
		return _failure("ASYNC_CHECKPOINT_ALREADY_STARTED")
	_stopping = false
	# CLI/process fault injection requires both test-only env variables;
	# ordinary production environment cannot slow the writer.
	_test_command_delay_ms = 0
	if OS.get_environment("DWS_NET_SMOOTH_TEST_HOOKS") == "1":
		var configured_delay := OS.get_environment("DWS_NET_SMOOTH_TEST_ITEM_DELAY_MS").to_int()
		if configured_delay >= 0 and configured_delay <= 2000:
			_test_command_delay_ms = configured_delay
	_repository = Repository.new()
	var configured: Dictionary = _repository.configure(root_path)
	if not bool(configured.get("success", false)):
		_repository = null
		return configured
	_thread = Thread.new()
	var error := _thread.start(_run)
	if error != OK:
		_thread = null
		_repository = null
		return _failure("ASYNC_CHECKPOINT_THREAD_START_FAILED", {"godot_error": error})
	return {"success": true, "error_code": "", "details": {}}

func is_busy() -> bool:
	_mutex.lock()
	var result := _busy
	_mutex.unlock()
	return result

func submit(authority_state: Dictionary, replay_state: Dictionary,
		checkpoint_id: String, generation: int, previous_generation: int,
		operation_id: String = "") -> Dictionary:
	# All mutable caller dictionaries need exactly one deep copy at the
	# cross-thread boundary, irrespective of which entry point submits them.
	return submit_owned(authority_state, replay_state,
		checkpoint_id, generation, previous_generation, operation_id)


# R3 Windows repair: submit_owned() is a compatibility name, NOT a guarantee
# of exclusive ownership. The caller can still mutate nested Dictionary
# values immediately after submission (proven by the M6 real-worker falsifier).
# Never hand an alias of caller-owned durable state to an async thread.
func submit_owned(authority_state: Dictionary, replay_state: Dictionary,
		checkpoint_id: String, generation: int, previous_generation: int,
		operation_id: String = "") -> Dictionary:
	if authority_state.is_empty() or replay_state.is_empty():
		return _failure("ASYNC_CHECKPOINT_FROZEN_STATE_REQUIRED")
	if _thread == null:
		return _failure("ASYNC_CHECKPOINT_NOT_STARTED")
	_mutex.lock()
	if _busy or _stopping:
		_mutex.unlock()
		return _failure("ASYNC_CHECKPOINT_BUSY")
	_busy = true
	_mutex.unlock()
	# Snapshot BOTH trees once before posting the worker semaphore.
	# A shallow duplicate or a direct alias corrupts authoritative-checkpoint
	# SHA when the submitting side edits nested replay/authority dictionaries.
	# No live Node or Resource may enter this interface.
	var job := {
		"authority": authority_state.duplicate(true),
		"replay": replay_state.duplicate(true),
		"checkpoint_id": checkpoint_id, "generation": generation,
		"previous_generation": previous_generation, "operation_id": operation_id,
	}
	_mutex.lock()
	_job = job
	_mutex.unlock()
	_wake.post()
	return {"success": true, "error_code": "", "details": {"generation": generation}}


# R3C.4 R2 periodic-only handoff. The raw durable gameplay DTO is frozen at
# the same authoritative frame as the replay outbox. A DEEP COPY of both
# structures precedes worker wakeup, exactly like submit_owned(); no Node,
# Service, Mutable outbox or live authority may enter the worker thread.
func submit_frozen_gameplay_source(
	frozen_gameplay: Dictionary, replay_state: Dictionary,
	checkpoint_id: String, generation: int, previous_generation: int,
	profile_handoff_copy: bool = false
) -> Dictionary:
	if frozen_gameplay.is_empty() or replay_state.is_empty():
		return _failure("R3C4_R2_FROZEN_SOURCE_REQUIRED")
	if _thread == null:
		return _failure("ASYNC_CHECKPOINT_NOT_STARTED")
	_mutex.lock()
	if _busy or _stopping:
		_mutex.unlock()
		return _failure("ASYNC_CHECKPOINT_BUSY")
	_busy = true
	_mutex.unlock()
	# R3.0 diagnostic only: the deep copies are still on the authoritative
	# thread. Measuring them does NOT move mutable state across the worker fence.
	var copy_started_us: int = Time.get_ticks_usec() if profile_handoff_copy else 0
	var job: Dictionary = {
		"job_kind": "R3C4_R2_PERIODIC_FROZEN_GAMEPLAY",
		"frozen_gameplay": frozen_gameplay.duplicate(true),
		"replay": replay_state.duplicate(true),
		"checkpoint_id": checkpoint_id,
		"generation": generation, "previous_generation": previous_generation,
		"operation_id": "",
	}
	var copy_ms: float = (
		float(Time.get_ticks_usec() - copy_started_us) / 1000.0
		if profile_handoff_copy else 0.0
	)
	_mutex.lock()
	_job = job
	_mutex.unlock()
	_wake.post()
	var result_details: Dictionary = {"generation": generation}
	if profile_handoff_copy:
		result_details["handoff_copy_ms"] = copy_ms
	return {"success": true, "error_code": "", "details": result_details}


func poll_completed() -> Dictionary:
	_mutex.lock()
	# P1-B: detach even the bounded worker-completion metadata. The owning
	# main thread cannot retain a mutable alias of writer-owned state.
	var result: Dictionary = _completion.duplicate(true)
	if not result.is_empty():
		_completion = {}
		_busy = false
	_mutex.unlock()
	return result

func wait_completed() -> Dictionary:
	# Explicit durability/shutdown barrier only. Never called by the normal
	# periodic poll. Existing command ACK ordering is deliberately preserved.
	while is_busy():
		var result := poll_completed()
		if not result.is_empty():
			return result
		OS.delay_msec(1)
	return {}

func stop() -> Dictionary:
	if _thread == null:
		return {}
	var result := wait_completed()
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()
	_thread = null
	_repository = null
	return result

func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var stopping := _stopping
		var job := _job
		var test_delay_ms := _test_command_delay_ms
		_job = {}
		_mutex.unlock()
		if stopping:
			return
		if job.is_empty():
			continue
		var started := Time.get_ticks_usec()
		var injected_ms := 0
		if not String(job.get("operation_id", "")).is_empty() and test_delay_ms > 0:
			OS.delay_msec(test_delay_ms)
			injected_ms = test_delay_ms
		var authority: Dictionary = Dictionary(job.get("authority", {}))
		var wrap_started: int = Time.get_ticks_usec()
		if String(job.get("job_kind", "")) == "R3C4_R2_PERIODIC_FROZEN_GAMEPLAY":
			# Only pure value-envelope work here. The writer is the ONLY disk
			# owner for periodic and command generations; ACK gates stay on main.
			authority = M6Adapter.wrap_frozen_gameplay_source(
				Dictionary(job.get("frozen_gameplay", {}))
			)
		var wrap_ms: float = float(Time.get_ticks_usec() - wrap_started) / 1000.0
		var checkpoint: Dictionary = {}
		var saved: Dictionary = {}
		if authority.is_empty():
			saved = _failure("R3C4_R2_WORKER_ENVELOPE_INVALID")
		else:
			checkpoint = Checkpoint.create(
				String(job["checkpoint_id"]), int(job["generation"]),
				int(job["previous_generation"]), authority, job["replay"],
				String(job["operation_id"]), int(authority.get("server_tick", -1)))
		var built: int = Time.get_ticks_usec()
		if not authority.is_empty():
			saved = _repository.save_atomic(checkpoint)
		var finished: int = Time.get_ticks_usec()
		# Return bounded metadata, never copy the full checkpoint into the main
		# thread again. Failure cause is retained for fail-closed recovery.
		var result := {
			"success": bool(saved.get("success", false)),
			"error_code": String(saved.get("error_code", "")),
			"details": {
				"generation": int(job["generation"]),
				"checkpoint_id": String(job["checkpoint_id"]),
				"operation_id": String(job["operation_id"]),
				"server_tick": int(authority.get("server_tick", -1)),
				"build_ms": float(built - started) / 1000.0,
				"wrap_ms": wrap_ms,
				"write_ms": float(finished - built) / 1000.0,
				"injected_ms": injected_ms,
				"worker_ms": float(finished - started) / 1000.0,
			},
		}
		if not bool(saved.get("success", false)):
			result["details"]["cause"] = saved
		_mutex.lock()
		_completion = result
		_mutex.unlock()

func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details}
