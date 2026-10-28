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
## Direct OffMain clients are UNTRUSTED: full final Runtime.validate stays
## on main. Only the real LAB Controller can issue an exclusive generation
## lease for its private canonical frontier (no public mutable aliases).
## The worker always fully validates both source and candidate at finish.
## A hash/tick alone cannot prove a mutable Dictionary has not changed.
## Bypassing the Controller to mutate _runtime directly voids its lease.
## True cancellation is cooperative BETWEEN indivisible Runtime steps.
## A canceled task is drained before a new task is enqueued.
## No hard deadline, guaranteed throughput, or WORLD_COMPAT activation.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const SnapshotProjector = preload("res://scripts/ecology/workbench/ecology_r323_snapshot_projector_v1.gd")

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
# R3.2.2 transient, controller-only authority to skip the duplicate main
# validate after the worker fully validated BOTH frontier and next state.
var _trusted_owner: Object = null
var _trusted_token: RefCounted = null
var _trusted_generation := -1
var _last_admission_mode := "FULL_SOURCE_VALIDATE"
var _last_worker_source_validate_us := 0
var _last_worker_candidate_validate_us := 0
var _last_projection_wall_us := 0
# A14.7 R2 Stage A: CPU-only wall-clock attribution. Never part of the
# canonical Runtime/checkpoint or thread scheduling. Per-job totals are
# published only after the existing full source/candidate validation.
var _last_worker_phase_profile: Dictionary = {}
# R2 Stage B opt-in single-worker batch: only the number of consecutive
# canonical A5 worksets processed per Runtime.resume call changes. No
# concurrent mutation, reordering, allocator duplication or unchecked state.
var _worker_worksets_per_resume := 1
var _last_worker_worksets_per_resume := 1
# R2C bounded nested A13 workset threads in worker-only CPU execution.
# Frozen for the full candidate generation; DEFAULT ONE = old serial path.
var _r2c_parallel_workset_workers := 1
var _last_r2c_parallel_workset_workers := 1
# R2E opt-in HOST-ONLY instrumentation, frozen per job generation.
# Does not skip Runtime/A5/A4 validation or change canonical state.
var _worker_r2e_profile := false
var _last_worker_r2e_profile := false
var _job_started_us := 0
var _jobs_started := 0
var _jobs_committed := 0
var _jobs_abandoned := 0
var _jobs_failed := 0
var _drained := 0
var _max_poll_us := 0
# R3.2.1 host-only phase attribution. No canonical state/checkpoint changes.
var _peak_background_poll_us := 0
var _peak_complete_poll_us := 0
var _last_join_us := 0
var _last_source_admission_us := 0
var _peak_source_admission_us := 0
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
	_clear_trusted_lease()
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
		"peak_background_poll_us": _peak_background_poll_us,
		"peak_complete_poll_us": _peak_complete_poll_us,
		"last_join_wall_us": _last_join_us,
		"last_source_admission_wall_us": _last_source_admission_us,
		"peak_source_admission_wall_us": _peak_source_admission_us,
		"last_admission_mode": _last_admission_mode,
		"last_worker_source_validate_wall_us": _last_worker_source_validate_us,
		"last_worker_candidate_validate_wall_us": _last_worker_candidate_validate_us,
		"last_projection_wall_us": _last_projection_wall_us,
		"last_worker_phase_profile": _last_worker_phase_profile.duplicate(true),
		"last_worker_worksets_per_resume": _last_worker_worksets_per_resume,
		"last_r2c_parallel_workset_workers": _last_r2c_parallel_workset_workers,
		"last_worker_r2e_profile_enabled": _last_worker_r2e_profile,
		"last_worker_wall_us": _last_worker_wall_us,
		"last_error": _last_error,
	}

func advance(state: Dictionary, options: Dictionary,
		max_members: int = 8, allocator_items: int = 64,
		cursor_cap_bytes: int = 8388608,
		lease_owner: Object = null, lease_token: RefCounted = null,
		lease_generation: int = -1,
		projection_manifest: Dictionary = {},
		worksets_per_resume: int = 1,
		r2c_parallel_workset_workers: int = 1,
		r2e_profile: bool = false) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	reap_discarded()
	if not C.integer(max_members, 1, Spatial.MAX_MEMBERS) \
			or not C.integer(allocator_items, 1, MAX_ALLOCATOR_ITEMS) \
			or not C.integer(cursor_cap_bytes, 1024, MAX_CURSOR_BYTES) \
			or not C.integer(worksets_per_resume, 1, 64) \
			or not C.integer(r2c_parallel_workset_workers, 1, 8):
		return _failed("R3_ASYNC_PARAMETERS", t0)
	if _task_id >= 0:
		# A running generation has a frozen workset batching policy. Never
		# silently change it mid-tick (including after worker completion).
		if worksets_per_resume != _worker_worksets_per_resume:
			return _failed("R2B_WORKSET_BATCH_CHANGED", t0)
		if r2c_parallel_workset_workers != _r2c_parallel_workset_workers:
			return _failed("R2C_WORKER_BOUND_CHANGED", t0)
		if r2e_profile != _worker_r2e_profile:
			return _failed("R2E_PROFILER_POLICY_CHANGED", t0)
		if not WorkerThreadPool.is_task_completed(_task_id):
			return _pending(t0, "DRAINING" if _abandoned else "BACKGROUND")
		# Non-blocking by contract: the task is already completed. Always
		# wait exactly once so Godot releases the task's pool resources.
		var join_started_us: int = Time.get_ticks_usec()
		var joined: Error = WorkerThreadPool.wait_for_task_completion(_task_id)
		var join_wall_us: int = maxi(0, Time.get_ticks_usec() - join_started_us)
		_last_join_us = join_wall_us
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
			_clear_trusted_lease()
			# Cancelled work is discarded even when it finished before polling.
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
		# Worker must attest full validation of source AND candidate on the
		# frozen exact generation. A cheap hash is not a replacement.
		if not bool(payload.get("source_validated", false)) \
				or not bool(payload.get("candidate_validated", false)) \
				or String(payload.get("validated_source_hash", "")) != _source_hash \
				or int(payload.get("validated_source_tick", -1)) != _source_tick \
				or String(payload.get("validated_options_hash", "")) != _options_hash \
				or int(payload.get("validated_generation", -2)) != _trusted_generation:
			_jobs_failed += 1
			return _failed("R3_ASYNC_WORKER_VALIDATION_RECEIPT", t0)
		_last_worker_source_validate_us = int(payload.get("source_validate_us", 0))
		_last_worker_candidate_validate_us = int(payload.get("candidate_validate_us", 0))
		_last_worker_phase_profile = payload.get("phase_profile", {}).duplicate(true)
		_last_worker_worksets_per_resume = _worker_worksets_per_resume
		_last_r2c_parallel_workset_workers = _r2c_parallel_workset_workers
		_last_worker_r2e_profile = _worker_r2e_profile
		_last_projection_wall_us = int(payload.get("projection_wall_us", 0))
		var source_validation_started_us: int = Time.get_ticks_usec()
		var canonical_error := ""
		var admission_mode := "FULL_SOURCE_VALIDATE"
		if _trusted_owner != null:
			admission_mode = "TRUSTED_CONTROLLER_LEASE"
			if not _trusted_lease_current(state):
				_jobs_failed += 1
				return _failed("R3_ASYNC_TRUSTED_LEASE_REVOKED", t0)
		else:
			# Untrusted callers still require the full LAST-MOMENT check;
			# worker validation alone cannot protect a mutable caller alias.
			canonical_error = Runtime.validate(state)
		var source_admission_wall_us: int = maxi(0, Time.get_ticks_usec() - source_validation_started_us)
		_last_source_admission_us = source_admission_wall_us
		_peak_source_admission_us = maxi(_peak_source_admission_us, source_admission_wall_us)
		_last_admission_mode = admission_mode
		if not canonical_error.is_empty():
			_jobs_failed += 1
			return _failed("R3_ASYNC_SOURCE_INVALID:" + canonical_error, t0)
		_jobs_committed += 1
		_last_worker_wall_us = int(payload.get("worker_wall_us", 0))
		var result: Dictionary = payload.state
		var complete_poll_wall_us: int = maxi(0, Time.get_ticks_usec() - t0)
		_peak_complete_poll_us = maxi(_peak_complete_poll_us, complete_poll_wall_us)
		_source_hash = ""
		_options_hash = ""
		_source_tick = -1
		_clear_trusted_lease()
		return {
			"success": true, "complete": true, "pending": false,
			"phase": "COMPLETE", "state": result,
			"canonical_tick": int(result.tick),
			"replayed_ticks": 1, "resume_calls": int(payload.get("resumes", 0)),
			"cursor_bytes": 0,
			"wall_us": maxi(0, Time.get_ticks_usec() - t0),
			"overrun_us": 0,
			"worker_wall_us": _last_worker_wall_us,
			"join_wall_us": join_wall_us,
			"source_admission_wall_us": source_admission_wall_us,
			"source_admission_mode": admission_mode,
			"worker_source_validate_wall_us": _last_worker_source_validate_us,
			"worker_candidate_validate_wall_us": _last_worker_candidate_validate_us,
			"worker_projection_wall_us": _last_projection_wall_us,
			"worker_phase_profile": _last_worker_phase_profile.duplicate(true),
			"worker_worksets_per_resume": _last_worker_worksets_per_resume,
			"r2c_parallel_workset_workers": _last_r2c_parallel_workset_workers,
			"worker_r2e_profile_enabled": _last_worker_r2e_profile,
			"presentation_snapshot": payload.get("presentation_snapshot", {}),
			"complete_poll_wall_us": complete_poll_wall_us,
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
	var use_lease: bool = lease_owner != null or lease_token != null \
		or lease_generation >= 0
	if not projection_manifest.is_empty() and not use_lease:
		return _failed("R323_SNAPSHOT_REQUIRES_CONTROLLER_LEASE", t0)
	_clear_trusted_lease()
	_source_hash = anchor
	_options_hash = options_hash
	_source_tick = int(state.tick)
	if use_lease:
		if lease_owner == null or lease_token == null or lease_generation < 0 \
				or not lease_owner.has_method("_r322_source_lease_valid"):
			return _failed("R3_ASYNC_TRUSTED_LEASE_ARGUMENTS", t0)
		var owner_script: Script = lease_owner.get_script() as Script
		if owner_script == null or String(owner_script.resource_path) != \
				"res://scripts/ecology/workbench/experiment_controller_v1.gd":
			return _failed("R3_ASYNC_TRUSTED_LEASE_OWNER", t0)
		_trusted_owner = lease_owner
		_trusted_token = lease_token
		_trusted_generation = lease_generation
		if not _trusted_lease_current(state):
			_clear_trusted_lease()
			return _failed("R3_ASYNC_TRUSTED_LEASE_AT_DISPATCH", t0)
	_mutex.lock()
	_cancel_requested = false
	_worker_result = {}
	_mutex.unlock()
	_abandoned = false
	_source_hash = anchor
	_options_hash = options_hash
	_source_tick = int(state.tick)
	_job_started_us = Time.get_ticks_usec()
	_worker_worksets_per_resume = worksets_per_resume
	_r2c_parallel_workset_workers = r2c_parallel_workset_workers
	_worker_r2e_profile = r2e_profile
	# The worker is the only writer to this isolated outer dictionary; all
	# nested authoritative state remains read-only until Runtime duplicates it.
	var frozen_state: Dictionary = state.duplicate(false)
	var frozen_options: Dictionary = options.duplicate(true)
	# The LAB Controller passes its privately-owned detached manifest. No
	# scene references, mutable canonical aliases or UI Objects enter task.
	var detached_manifest: Dictionary = projection_manifest.duplicate(true)
	_task_id = WorkerThreadPool.add_task(
		Callable(self, "_compute").bind(
			frozen_state, frozen_options, max_members,
			allocator_items, cursor_cap_bytes,
			anchor, _source_tick, options_hash, _trusted_generation,
			detached_manifest, worksets_per_resume,
			r2c_parallel_workset_workers, r2e_profile),
		false, "eco-a146-r3-2-global-a4")
	if _task_id < 0:
		_clear_trusted_lease()
		return _failed("R3_ASYNC_SPAWN_FAILED", t0)
	_jobs_started += 1
	return _pending(t0, "BACKGROUND")

func _compute(frozen: Dictionary, options: Dictionary, members: int,
		items: int, cursor_cap: int, anchor: String, source_tick: int,
		options_hash: String, generation: int,
		projection_manifest: Dictionary,
		worksets_per_resume: int,
		r2c_parallel_workset_workers: int,
		r2e_profile: bool) -> void:
	var started_us: int = Time.get_ticks_usec()
	var payload: Dictionary = {}
	# Exact single task wall decomposition. These counters are host-only;
	# no per-organism ordering, quota, algorithm or state mutation changes.
	var phases := {"begin_us": 0, "cursor_encode_us": 0,
		"prepare_us": 0, "allocate_begin_us": 0, "allocate_resume_us": 0,
		"advance_us": 0, "finalize_us": 0, "unknown_resume_us": 0,
		"resume_total_us": 0,
		"prepare_calls": 0, "allocate_begin_calls": 0,
		"allocate_resume_calls": 0, "advance_calls": 0,
		"finalize_calls": 0, "max_single_resume_us": 0,
		"max_cursor_encode_us": 0, "max_cursor_bytes": 0,
		"r2c_peak_workers": 0, "r2c_parallel_threaded_worksets": 0,
		"r2c_parallel_resume_calls": 0}
	if r2e_profile:
		# Overlapping totals: A5 cost is a SUBSET of Runtime resume wall;
		# A5 checksum/source/copy/seal are SUBSETS of A5 lifecycle wall.
		for key in ["r2e_profiled_calls", "r2e_runtime_source_validate_us",
				"r2e_runtime_options_digest_us", "r2e_a5_lifecycle_us",
				"r2e_a5_cursor_verify_us", "r2e_a5_source_digest_us",
				"r2e_a5_cow_copy_us", "r2e_a5_seal_us"]:
			phases[key] = 0
	var begin_started_us: int = Time.get_ticks_usec()
	var started: Dictionary = Runtime.begin_staged_global_tick(
		frozen, options, 4, members, true)
	phases["begin_us"] = maxi(0, Time.get_ticks_usec() - begin_started_us)
	if not bool(started.get("success", false)) or not started.has("cursor"):
		payload = {"success": false,
			"error": "BEGIN:" + String(started.get("error", "?"))}
	else:
		var cursor: Dictionary = started.cursor
		for i in MAX_WORKER_RESUMES:
			if _is_cancel_requested():
				payload = {"success": false, "error": "CANCELLED"}
				break
			var phase: String = String(cursor.get("lifecycle", {}).get("phase", "UNKNOWN"))
			var bucket := "unknown"
			if phase == "PREPARE":
				bucket = "prepare"
			elif phase == "ADVANCE":
				bucket = "advance"
			elif phase == "ALLOCATE":
				bucket = "allocate_begin" if cursor.get("lifecycle", {}).get(
					"allocator_cursor", {}).is_empty() else "allocate_resume"
			var encode_started_us: int = Time.get_ticks_usec()
			var encoded: String = C.encode(cursor)
			var encoded_bytes: int = encoded.to_utf8_buffer().size()
			var encode_us: int = maxi(0, Time.get_ticks_usec() - encode_started_us)
			phases["cursor_encode_us"] += encode_us
			phases["max_cursor_encode_us"] = maxi(int(phases.max_cursor_encode_us), encode_us)
			phases["max_cursor_bytes"] = maxi(int(phases.max_cursor_bytes), encoded_bytes)
			if encoded.is_empty() or encoded_bytes > cursor_cap:
				payload = {"success": false, "error": "CURSOR_CAP"}
				break
			var resume_started_us: int = Time.get_ticks_usec()
			var step: Dictionary = Runtime.resume_staged_global_tick(
				frozen, options, cursor, worksets_per_resume, items, cursor_cap,
				r2c_parallel_workset_workers, r2e_profile)
			var resume_us: int = maxi(0, Time.get_ticks_usec() - resume_started_us)
			if r2e_profile and bool(step.get("success", false)):
				var detail: Dictionary = step.get("r2e_profile", {})
				var a5_detail: Dictionary = detail.get("a5", {})
				phases["r2e_profiled_calls"] += 1
				phases["r2e_runtime_source_validate_us"] += int(detail.get(
					"full_source_validate_us", 0))
				phases["r2e_runtime_options_digest_us"] += int(detail.get(
					"options_digest_us", 0))
				phases["r2e_a5_lifecycle_us"] += int(detail.get(
					"a5_lifecycle_us", 0))
				phases["r2e_a5_cursor_verify_us"] += int(a5_detail.get(
					"cursor_verify_us", 0))
				phases["r2e_a5_source_digest_us"] += int(a5_detail.get(
					"source_digest_us", 0))
				phases["r2e_a5_cow_copy_us"] += int(a5_detail.get(
					"cow_copy_us", 0))
				phases["r2e_a5_seal_us"] += int(a5_detail.get(
					"result_seal_us", 0))
			phases["resume_total_us"] += resume_us
			phases[bucket + "_us"] += resume_us
			phases[bucket + "_calls"] = int(phases.get(bucket + "_calls", 0)) + 1
			phases["max_single_resume_us"] = maxi(int(phases.max_single_resume_us), resume_us)
			var peak_parallel: int = int(step.get("r2c_peak_workers", 0))
			var completed_parallel: int = int(step.get("r2c_threaded_worksets", 0))
			phases["r2c_peak_workers"] = maxi(
				int(phases.r2c_peak_workers), peak_parallel)
			phases["r2c_parallel_threaded_worksets"] += completed_parallel
			if completed_parallel > 0:
				phases["r2c_parallel_resume_calls"] += 1
			if bool(step.get("complete", false)):
				phases["finalize_us"] += resume_us
				phases["finalize_calls"] += 1
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
	# Worker telemetry is detached and NO phase data participates in
	# canonical checksums, A4 demand reductions or adoption logic.
	payload["phase_profile"] = phases.duplicate(true)
	# The final full validation runs only on the CPU worker. Retain the
	# direct-service full MAIN check until an exclusive owner lease exists.
	if bool(payload.get("success", false)):
		var validation_started_us: int = Time.get_ticks_usec()
		var source_error: String = Runtime.validate(frozen)
		var source_validate_us: int = maxi(0, Time.get_ticks_usec() - validation_started_us)
		validation_started_us = Time.get_ticks_usec()
		var candidate_error: String = Runtime.validate(payload.state)
		var candidate_validate_us: int = maxi(0, Time.get_ticks_usec() - validation_started_us)
		if not source_error.is_empty():
			payload = {"success": false, "error": "FINAL_SOURCE:" + source_error}
		elif not candidate_error.is_empty():
			payload = {"success": false, "error": "FINAL_CANDIDATE:" + candidate_error}
		elif String(frozen.get("integrity_hash", "")) != anchor \
				or int(frozen.get("tick", -1)) != source_tick \
				or C.digest(options) != options_hash:
			payload = {"success": false, "error": "FINAL_SOURCE_FRONTIER"}
		elif _is_cancel_requested():
			payload = {"success": false, "error": "CANCELLED"}
		else:
			payload["source_validated"] = true
			payload["candidate_validated"] = true
			payload["validated_source_hash"] = anchor
			payload["validated_source_tick"] = source_tick
			payload["validated_options_hash"] = options_hash
			payload["validated_generation"] = generation
			payload["source_validate_us"] = source_validate_us
			payload["candidate_validate_us"] = candidate_validate_us
			# R3.2.3: perform the historical get_snapshot() read-only hash
			# and presentation computation on the CPU worker, never Node/GPU.
			if not projection_manifest.is_empty():
				var projection_started_us: int = Time.get_ticks_usec()
				var snapshot: Dictionary = SnapshotProjector.project_validated(
					payload.state, projection_manifest)
				if snapshot.is_empty() or not bool(snapshot.get("success", false)) \
						or int(snapshot.get("tick", -1)) != source_tick + 1 \
						or String(snapshot.get("canonical_state_hash", "")) != \
							String(payload.state.integrity_hash):
					payload = {"success": false, "error": "R323_SNAPSHOT_PROJECTION"}
				else:
					payload["presentation_snapshot"] = snapshot
					payload["projection_wall_us"] = maxi(
						0, Time.get_ticks_usec() - projection_started_us)
	payload["worker_wall_us"] = maxi(0, Time.get_ticks_usec() - started_us)
	_mutex.lock()
	_worker_result = payload
	_mutex.unlock()

func _is_cancel_requested() -> bool:
	_mutex.lock()
	var cancelled: bool = _cancel_requested
	_mutex.unlock()
	return cancelled

func _trusted_lease_current(state: Dictionary) -> bool:
	if _trusted_owner == null or _trusted_token == null:
		return false
	return bool(_trusted_owner._r322_source_lease_valid(
		state, _source_hash, _source_tick, _options_hash,
		_trusted_token, _trusted_generation))

func _clear_trusted_lease() -> void:
	_trusted_owner = null
	_trusted_token = null
	_trusted_generation = -1

func _pending(started_us: int, phase: String) -> Dictionary:
	var wall: int = maxi(0, Time.get_ticks_usec() - started_us)
	_max_poll_us = maxi(_max_poll_us, wall)
	if phase == "BACKGROUND" or phase == "DRAINING":
		_peak_background_poll_us = maxi(_peak_background_poll_us, wall)
	return {
		"success": true, "complete": false, "pending": true,
		"phase": phase, "replayed_ticks": 0, "resume_calls": 0,
		"cursor_bytes": 0, "wall_us": wall, "overrun_us": 0,
	}

func _failed(reason: String, started_us: int) -> Dictionary:
	_last_error = reason
	return {"success": false, "complete": false,
		"error": reason, "wall_us": maxi(0, Time.get_ticks_usec() - started_us)}
