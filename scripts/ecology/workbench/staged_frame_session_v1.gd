extends RefCounted
## ECO A14.5 R3 — host-private staged global-tick session.
##
## Uses accepted A14.5 R2 Runtime cursors. NEVER publishes intermediate
## biology: only a completely admitted global tick returns a state. Time,
## cancellation, speculative cursor and statistics are never checkpointed.
## The global A5 ALLOCATE barrier, one workset, cursor seal and final
## admission/feedback remain indivisible: this is a SOFT per-frame target,
## not a hard realtime guarantee.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")

const DEFAULT_SOFT_BUDGET_US := 30000
const DEFAULT_MAX_RESUMES := 1
const DEFAULT_MAX_WORKSETS := 1
const DEFAULT_MEMBERS := 8
const DEFAULT_CURSOR_BYTES := 8388608
const MAX_CURSOR_BYTES := 16777216
const MAX_RESUMES := 16
const MAX_WORKSETS := 64
const SAMPLE_HISTORY := 128
const PHASES := ["BEGIN", "PREPARE", "ALLOCATE", "ADVANCE"]
const SCHEMA := "dws.ecology.a14-5-r3-host-staged-session.v1"

var _cursor: Dictionary = {}
var _off_main: RefCounted = OffMain.new()
var _members := 0
var _r3_allocator := false
var _allocator_items := 0
var _r3_allocator_calls := 0
var _r3_phase_samples: Dictionary = {"BEGIN": [], "NORMALIZE": [],
	"BUILD_CLAIMS": [], "PRIMARY": [], "RESIDUAL": [], "FINALIZE": []}
var _cursor_bytes := 0
var _calls := 0
var _resume_calls := 0
var _completed_ticks := 0
var _cancelled := 0
var _memory_rejections := 0
var _overruns := 0
var _peak_call_us := 0
var _last_call_us := 0
var _peak_cursor_bytes := 0
var _last_error := ""
var _samples: Dictionary = {
	"BEGIN": [], "PREPARE": [], "ALLOCATE": [], "ADVANCE": [],
}

func has_pending() -> bool:
	return not _cursor.is_empty() or _off_main.has_pending()

func cancel() -> Dictionary:
	var was_pending := has_pending()
	_off_main.cancel()
	_cursor = {}
	_members = 0
	_r3_allocator = false
	_allocator_items = 0
	_cursor_bytes = 0
	if was_pending:
		_cancelled += 1
	return {"success": true, "cancelled": was_pending}

func reap_cancelled_off_main() -> bool:
	return _off_main.reap_discarded()

func reset_telemetry() -> void:
	cancel()
	_calls = 0
	_resume_calls = 0
	_r3_allocator_calls = 0
	_r3_phase_samples = {"BEGIN": [], "NORMALIZE": [], "BUILD_CLAIMS": [],
		"PRIMARY": [], "RESIDUAL": [], "FINALIZE": []}
	_completed_ticks = 0
	_cancelled = 0
	_memory_rejections = 0
	_overruns = 0
	_peak_call_us = 0
	_last_call_us = 0
	_peak_cursor_bytes = 0
	_last_error = ""
	_samples = {"BEGIN": [], "PREPARE": [], "ALLOCATE": [], "ADVANCE": []}

func advance(state: Dictionary, options: Dictionary,
		soft_budget_us: int = DEFAULT_SOFT_BUDGET_US,
		max_resumes: int = DEFAULT_MAX_RESUMES,
		max_worksets: int = DEFAULT_MAX_WORKSETS,
		max_members: int = DEFAULT_MEMBERS,
		cursor_cap_bytes: int = DEFAULT_CURSOR_BYTES,
		use_r3_allocator: bool = false,
		allocator_items_per_call: int = 16,
		use_off_main_r3: bool = false,
		lease_owner: Object = null, lease_token: RefCounted = null,
		lease_generation: int = -1) -> Dictionary:
	if not C.integer(soft_budget_us, 1, 1000000000) \
			or not C.integer(max_resumes, 1, MAX_RESUMES) \
			or not C.integer(max_worksets, 1, MAX_WORKSETS) \
			or not C.integer(max_members, 1, Spatial.MAX_MEMBERS) \
			or not C.integer(cursor_cap_bytes, 1024, MAX_CURSOR_BYTES) \
			or not C.integer(allocator_items_per_call, 1, 4096):
		return _error("STAGED_SESSION_PARAMETERS", false)
	# R3.2 is a separate LAB-only execution option. Existing R3/A14.5
	# behavior remains byte-for-byte unchanged unless this flag is set.
	if use_off_main_r3:
		if not use_r3_allocator:
			return _error("STAGED_SESSION_OFFMAIN_REQUIRES_R3", false)
		if not _cursor.is_empty():
			return _error("STAGED_SESSION_LEGACY_PENDING", false)
		_calls += 1
		var async_step: Dictionary = _off_main.advance(
			state, options, max_members, allocator_items_per_call, cursor_cap_bytes,
			lease_owner, lease_token, lease_generation)
		if not bool(async_step.get("success", false)):
			return _error("STAGED_SESSION_OFFMAIN:" +
				String(async_step.get("error", "?")), true)
		if bool(async_step.get("complete", false)):
			_completed_ticks += 1
		_last_call_us = int(async_step.get("wall_us", 0))
		_peak_call_us = maxi(_peak_call_us, _last_call_us)
		return async_step
	if _off_main.has_pending():
		return _error("STAGED_SESSION_OFFMAIN_PENDING", false)
	_off_main.reap_discarded()
	if has_pending() and max_members != _members:
		return _error("STAGED_SESSION_MEMBERS_CHANGED", true)
	if has_pending() and (use_r3_allocator != _r3_allocator \
			or allocator_items_per_call != _allocator_items):
		return _error("STAGED_SESSION_ALLOCATOR_MODE_CHANGED", true)
	_calls += 1
	var started_us: int = Time.get_ticks_usec()
	var resumed := 0
	if not has_pending():
		var begin_us: int = Time.get_ticks_usec()
		var begun: Dictionary = Runtime.begin_staged_global_tick(
			state, options, 4, max_members, use_r3_allocator)
		_record("BEGIN", Time.get_ticks_usec() - begin_us)
		if not bool(begun.get("success", false)) or not begun.has("cursor"):
			return _error("STAGED_SESSION_BEGIN:" + String(begun.get("error", "?")), true)
		_cursor = begun.cursor
		_members = max_members
		_r3_allocator = use_r3_allocator
		_allocator_items = allocator_items_per_call
		if not _bounded_cursor(cursor_cap_bytes):
			return _error("STAGED_SESSION_CURSOR_CAP", true)
		# Begin itself may exceed the requested soft wall budget. Yield
		# without starting another indivisible A5 stage this frame.
		if Time.get_ticks_usec() - started_us >= soft_budget_us:
			return _pending_result(started_us, soft_budget_us, 0)
	elif _cursor_bytes > cursor_cap_bytes:
		return _error("STAGED_SESSION_CURSOR_CAP", true)

	while resumed < max_resumes:
		# At least one stage runs on a *resume* call (forward progress).
		# Subsequent stages are gated by wall time read OUTSIDE biology.
		if resumed > 0 and Time.get_ticks_usec() - started_us >= soft_budget_us:
			break
		var phase := String(_cursor.lifecycle.get("phase", ""))
		if not phase in PHASES or phase == "BEGIN":
			return _error("STAGED_SESSION_PHASE", true)
		var allocator_subphase := ""
		if phase == "ALLOCATE" and _r3_allocator:
			var a4_cursor: Dictionary = _cursor.lifecycle.get("allocator_cursor", {})
			allocator_subphase = String(a4_cursor.get("phase", "BEGIN"))
		var step_started_us: int = Time.get_ticks_usec()
		var step: Dictionary = Runtime.resume_staged_global_tick(
			state, options, _cursor, max_worksets,
			allocator_items_per_call, cursor_cap_bytes)
		var duration: int = maxi(0, Time.get_ticks_usec() - step_started_us)
		_record(phase, duration)
		if not allocator_subphase.is_empty():
			_record_r3(allocator_subphase, duration)
		resumed += 1
		_resume_calls += 1
		if not bool(step.get("success", false)):
			return _error("STAGED_SESSION_RESUME:" + String(step.get("error", "?")), true)
		if bool(step.get("complete", false)):
			# One complete A5 allocation -> admission -> A6 feedback tick.
			# Caller may adopt this state only after the runtime succeeded.
			if not step.has("state") or not step.state is Dictionary:
				return _error("STAGED_SESSION_FINAL_STATE", true)
			if int(step.state.tick) != int(state.tick) + 1:
				return _error("STAGED_SESSION_FINAL_TICK", true)
			var completed: Dictionary = step.state
			# A successful commit closes the cursor, but is NOT cancellation.
			_cursor = {}
			_members = 0
			_r3_allocator = false
			_allocator_items = 0
			_cursor_bytes = 0
			_completed_ticks += 1
			var wall_us := _finish_wall(started_us, soft_budget_us)
			return {"success": true, "complete": true, "pending": false,
				"state": completed, "replayed_ticks": 1,
				"canonical_tick": int(completed.tick),
				"source_tick": int(state.tick), "phase": "COMPLETE",
				"resume_calls": resumed, "cursor_bytes": 0,
				"wall_us": wall_us, "overrun_us": maxi(0, wall_us - soft_budget_us)}
		if step.has("state") or not step.has("cursor"):
			return _error("STAGED_SESSION_PARTIAL_STATE", true)
		_cursor = step.cursor
		if not _bounded_cursor(cursor_cap_bytes):
			return _error("STAGED_SESSION_CURSOR_CAP", true)
	return _pending_result(started_us, soft_budget_us, resumed)

func status() -> Dictionary:
	_off_main.reap_discarded()
	var phase := "NONE"
	if not _cursor.is_empty():
		phase = String(_cursor.lifecycle.get("phase", "?"))
	elif _off_main.has_pending():
		phase = "BACKGROUND"
	var by_phase := {}
	for phase_name in PHASES:
		var values: Array = _samples[phase_name]
		var ordered: Array = values.duplicate()
		ordered.sort()
		var p95 := 0
		var peak := 0
		if not ordered.is_empty():
			p95 = int(ordered[maxi(0, int(ceil(0.95 * ordered.size())) - 1)])
			peak = int(ordered[ordered.size() - 1])
		by_phase[phase_name] = {"samples": ordered.size(), "p95_us": p95,
			"peak_us": peak}
	var allocator_subphase := "NONE"
	if has_pending() and _r3_allocator and phase == "ALLOCATE":
		var inner_a4: Dictionary = _cursor.lifecycle.get("allocator_cursor", {})
		allocator_subphase = String(inner_a4.get("phase", "BEGIN"))
	var r3_by_phase := {}
	for subphase in _r3_phase_samples:
		var values: Array = _r3_phase_samples[subphase]
		var ordered: Array = values.duplicate()
		ordered.sort()
		var p95 := 0
		var peak := 0
		if not ordered.is_empty():
			p95 = int(ordered[maxi(0, int(ceil(0.95 * ordered.size())) - 1)])
			peak = int(ordered.back())
		r3_by_phase[subphase] = {"samples": ordered.size(), "p95_us": p95, "peak_us": peak}
	return {"schema": SCHEMA, "pending": has_pending(), "phase": phase,
		"off_main": _off_main.status(),
		"r3_allocator_enabled": _r3_allocator,
		"r3_allocator_subphase": allocator_subphase,
		"r3_allocator_calls": _r3_allocator_calls,
		"r3_allocator_phase_stats": r3_by_phase,
		"cursor_bytes": _cursor_bytes,
		"peak_cursor_bytes": _peak_cursor_bytes,
		"calls": _calls, "resume_calls": _resume_calls,
		"completed_ticks": _completed_ticks,
		"cancellations": _cancelled,
		"memory_rejections": _memory_rejections,
		"overruns": _overruns,
		"last_call_wall_us": _last_call_us,
		"peak_call_wall_us": _peak_call_us,
		"last_error": _last_error, "phase_stats": by_phase}

func _bounded_cursor(limit_bytes: int) -> bool:
	var encoded: String = C.encode(_cursor)
	if encoded.is_empty():
		_memory_rejections += 1
		return false
	var bytes: int = encoded.to_utf8_buffer().size()
	if bytes > limit_bytes:
		_memory_rejections += 1
		return false
	_cursor_bytes = bytes
	_peak_cursor_bytes = maxi(_peak_cursor_bytes, bytes)
	return true

func _pending_result(started_us: int, soft_budget_us: int, resumes: int) -> Dictionary:
	var wall_us := _finish_wall(started_us, soft_budget_us)
	return {"success": true, "complete": false, "pending": true,
		"replayed_ticks": 0, "phase": String(_cursor.lifecycle.phase),
		"resume_calls": resumes, "cursor_bytes": _cursor_bytes,
		"wall_us": wall_us, "overrun_us": maxi(0, wall_us - soft_budget_us)}

func _finish_wall(started_us: int, soft_budget_us: int) -> int:
	var wall_us: int = maxi(0, Time.get_ticks_usec() - started_us)
	_last_call_us = wall_us
	_peak_call_us = maxi(_peak_call_us, wall_us)
	if wall_us > soft_budget_us:
		_overruns += 1
	return wall_us

func _record(phase: String, duration: int) -> void:
	var values: Array = _samples[phase]
	values.append(maxi(0, duration))
	if values.size() > SAMPLE_HISTORY:
		values.pop_front()

func _record_r3(phase: String, duration: int) -> void:
	if not _r3_phase_samples.has(phase):
		return
	_r3_allocator_calls += 1
	var values: Array = _r3_phase_samples[phase]
	values.append(maxi(0, duration))
	if values.size() > SAMPLE_HISTORY:
		values.pop_front()

func _error(reason: String, discard: bool) -> Dictionary:
	if discard:
		cancel()
	_last_error = reason
	return {"success": false, "error": reason, "cancelled": discard}
