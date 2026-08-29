extends RefCounted

class_name Par1ProcessRecruitmentBackend

## ECO.EVO7 PAR1 — direct persistent process-pool recruitment backend (v1).
##
## Reuses the accepted PAR0 pool/transport/worker protocol VERBATIM (no fork
## of the pipe protocol) but runs PARALLEL-ONLY: no serial oracle inside
## this backend. Canonical partitions are submitted to persistent OS worker
## processes; responses are validated (job_id, generation, input_hash,
## duplicates, stale, missing) and merged canonically by candidate_hash;
## the aggregate hash is recomputed on the coordinator. FAIL CLOSED on any
## worker failure — never a serial fallback.
##
## PAR0.2 evidence (dual executor) remains untouched; this adapter shares
## the same pool implementation, which is the point of the fair comparison:
## identical kernel, identical transport, no oracle.

const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Pool = preload("res://scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd")

const BACKEND := "PROCESS_POOL"
const SCHEMA := "distributed_world_simulator.ecology.evo7_par1.process_recruitment_backend.v1"
const VERSION := "1.0.0"

const FAIL_POOL := "PAR1_POOL_FAILURE"
const FAIL_INPUTS := "PAR1_INPUTS_INVALID"
const FAIL_CONTEXT := "PAR1_CONTEXT_MISMATCH"
const FAIL_STALE := "STALE_WORKER_RESULT"
const FAIL_GENERATION := "GENERATION_MISMATCH"
const FAIL_INPUT_HASH := "INPUT_HASH_MISMATCH"
const FAIL_DUPLICATE := "DUPLICATE_WORKER_RESULT"
const FAIL_MISSING := "MISSING_WORKER_RESULT"
const FAIL_MERGE := "PAR1_MERGE_FAILURE"

var _configured := false
var _worker_count := 0
var _godot_bin := ""
var _project_root := ""
var _session_root := ""
var _job_timeout_ms := 180_000
var _pool = null
var _setup_context_hash := ""
var _warmup_done := false
var _generation_jobs := 0
var _last_pool_error := ""
var _last_report: Dictionary = {}

func setup(config: Dictionary) -> bool:
	_configured = false
	_worker_count = int(config.get("worker_count", 0))
	if _worker_count < 1:
		return false
	_project_root = String(config.get("project_root", ProjectSettings.globalize_path("res://")))
	_godot_bin = String(config.get("godot_bin", ""))
	if _godot_bin.is_empty():
		_godot_bin = OS.get_environment("GODOT_BIN")
	if _godot_bin.is_empty():
		_godot_bin = "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	_session_root = String(config.get("session_root", ""))
	if _session_root.is_empty():
		_session_root = OS.get_environment("ECO_PAR02_SESSION_ROOT")
	if _session_root.is_empty():
		_session_root = OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if _session_root.is_empty():
		_session_root = _project_root.path_join("artifacts/par1_sessions")
	_job_timeout_ms = int(config.get("job_timeout_ms", 180_000))
	_configured = true
	return true

func worker_count() -> int:
	return _worker_count

func generation_jobs() -> int:
	return _generation_jobs

func is_pool_active() -> bool:
	return _pool != null

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

## One parallel-only generation through the persistent process pool.
func evaluate_generation(
	generation: int,
	candidates: Array[Dictionary],
	routes: Array[Dictionary],
	immutable_context: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _configured:
		return _failure(FAIL_POOL, "backend not configured", generation)
	if candidates.is_empty() or candidates.size() != routes.size():
		return _failure(FAIL_INPUTS, "candidate/route size mismatch", generation)

	var items: Array = Contract.canonical_items(candidates, routes)
	if items.size() != candidates.size():
		return _failure(FAIL_INPUTS, "candidate/route identity mismatch", generation)

	if _pool == null:
		if not _ensure_pool(immutable_context, generation):
			return _failure(FAIL_POOL, "pool setup failed: " + _last_pool_error, generation)

	var context_hash := _context_hash(immutable_context)
	if context_hash != _setup_context_hash:
		return _failure(FAIL_CONTEXT, "evaluate context diverged from pool setup context", generation)

	var bounds: Array[int] = Pool.partition(items.size(), _worker_count)
	var slices: Array = []
	var slice_input_hashes: Array[String] = []
	for index in _worker_count:
		var slice: Array = items.slice(bounds[index], bounds[index + 1])
		slices.append(slice)
		slice_input_hashes.append(_slice_input_hash(slice))

	var serialize_started := Time.get_ticks_usec()
	var base_id: String = _pool.submit_generation(generation, slices)
	var serialize_ms := _elapsed_ms(serialize_started)
	if base_id.is_empty():
		return _failure(FAIL_POOL, "submit failed: " + _pool.last_error(), generation)
	_generation_jobs += 1

	var ipc_started := Time.get_ticks_usec()
	var collected: Dictionary = _pool.collect_all()
	var ipc_ms := _elapsed_ms(ipc_started)
	if collected.is_empty():
		return _failure(FAIL_POOL, "collect failed: " + _pool.last_error(), generation)

	var validation := _validate_responses(
		collected["responses"], generation, base_id, slice_input_hashes)
	if not validation.get("ok", false):
		return _failure(String(validation["code"]), String(validation["detail"]), generation)
	var responses: Array = validation["responses"]

	var merge_started := Time.get_ticks_usec()
	var events: Array[Dictionary] = _canonical_merge(responses, items.size())
	if events.is_empty():
		return _failure(FAIL_MERGE, "canonical merge/validation failed", generation)
	var canonical_hash := Contract.recruitment_hash(events, immutable_context)
	var merge_ms := _elapsed_ms(merge_started)

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"backend": BACKEND,
		"generation": generation,
		"job_id": base_id,
		"worker_count": _worker_count,
		"candidate_count": items.size(),
		"canonical_hash": canonical_hash,
		"input_hash": _slice_input_hash(items),
		"timings_ms": {
			"serialize_ms": serialize_ms,
			"ipc_ms": ipc_ms,
			"merge_ms": merge_ms,
			"total_ms": _elapsed_ms(started_usec),
		},
	}
	_last_report = report
	return {
		"success": true,
		"backend": BACKEND,
		"worker_count": _worker_count,
		"canonical_events": events,
		"canonical_hash": canonical_hash,
		"failure_code": "",
		"failure_detail": "",
		"timings_ms": report["timings_ms"],
		"report": report,
	}

func shutdown() -> void:
	if _pool != null:
		_pool.shutdown()
		_pool = null

## ---------- pool lifecycle ----------

func _ensure_pool(context: Dictionary, generation: int) -> bool:
	if not _warmup_done:
		if not Pool.warmup(_godot_bin, _project_root, _session_root):
			_last_pool_error = "warm-up lifecycle failed"
			return false
		_warmup_done = true
	var pool := Pool.new()
	var session_dir := _session_root.path_join("par1_%d_wc%d_%d" % [
		generation, _worker_count, Time.get_ticks_usec()])
	if not pool.setup(_godot_bin, _project_root, session_dir, _worker_count, context, _job_timeout_ms):
		_last_pool_error = pool.last_error()
		return false
	_pool = pool
	_setup_context_hash = _context_hash(context)
	return true

## ---------- response validation (PAR0.2 semantics, oracle-free) ----------

func _validate_responses(
	responses: Array,
	generation: int,
	base_id: String,
	slice_input_hashes: Array[String]
) -> Dictionary:
	if responses.size() != _worker_count:
		return {"ok": false, "code": FAIL_MISSING,
			"detail": "expected %d responses, got %d" % [_worker_count, responses.size()]}
	var seen_workers := {}
	for response_value in responses:
		var response: Dictionary = response_value
		var worker_index := int(response.get("worker_index", -1))
		if seen_workers.has(worker_index):
			return {"ok": false, "code": FAIL_DUPLICATE,
				"detail": "duplicate response for worker %d" % worker_index}
		seen_workers[worker_index] = true
		if String(response.get("protocol_version", "")) != Pool.Transport.PROTOCOL_VERSION:
			return {"ok": false, "code": FAIL_POOL,
				"detail": "protocol mismatch on worker %d" % worker_index}
		var expected_job_id := "%s_w%d" % [base_id, worker_index]
		if String(response.get("job_id", "")) != expected_job_id:
			return {"ok": false, "code": FAIL_STALE,
				"detail": "worker %d job_id %s != current %s" % [
					worker_index, String(response.get("job_id", "")), expected_job_id]}
		if int(response.get("generation", -1)) != generation:
			return {"ok": false, "code": FAIL_GENERATION,
				"detail": "worker %d generation %d != current %d" % [
					worker_index, int(response.get("generation", -1)), generation]}
		if response.has("error"):
			return {"ok": false, "code": FAIL_POOL,
				"detail": "worker %d evaluation error %s" % [worker_index, String(response["error"])]}
		if worker_index < 0 or worker_index >= slice_input_hashes.size():
			return {"ok": false, "code": FAIL_POOL,
				"detail": "worker index %d out of range" % worker_index}
		if String(response.get("input_hash", "")) != slice_input_hashes[worker_index]:
			return {"ok": false, "code": FAIL_INPUT_HASH,
				"detail": "worker %d input_hash mismatch" % worker_index}
		if not response.get("events") is Array:
			return {"ok": false, "code": FAIL_POOL,
				"detail": "worker %d response missing events" % worker_index}
	var validated: Array = []
	for response_value in responses:
		validated.append(response_value)
	for index in _worker_count:
		if not seen_workers.has(index):
			return {"ok": false, "code": FAIL_MISSING,
				"detail": "no response from worker %d" % index}
	return {"ok": true, "code": "", "detail": "", "responses": validated}

func _canonical_merge(responses: Array, expected_count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for response_value in responses:
		var response: Dictionary = response_value
		for event_value in response.get("events", []):
			if not event_value is Dictionary:
				return []
			events.append(event_value)
	if events.size() != expected_count:
		return []
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return events

func _slice_input_hash(slice: Array) -> String:
	var input_keys := PackedStringArray()
	for item_value in slice:
		var item: Dictionary = item_value
		input_keys.append(String(item["candidate"].get("candidate_hash", "")))
		input_keys.append(String(item["route"].get("route_hash", "")))
	return "|".join(input_keys).sha256_text()

func _context_hash(context: Dictionary) -> String:
	return String(JSON.stringify(context, "", false)).sha256_text()

func _failure(code: String, detail: String, generation: int) -> Dictionary:
	_last_report = {
		"schema": SCHEMA, "version": VERSION, "backend": BACKEND,
		"generation": generation, "worker_count": _worker_count,
		"failure_code": code, "failure_detail": detail,
	}
	return {
		"success": false,
		"backend": BACKEND,
		"worker_count": _worker_count,
		"canonical_events": [],
		"canonical_hash": "",
		"failure_code": code,
		"failure_detail": detail,
		"timings_ms": {},
		"report": _last_report.duplicate(true),
	}

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0
