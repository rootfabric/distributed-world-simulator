extends RefCounted

class_name Par3CandidateBuildExecutor

## ECO.EVO7 PAR3 — parallel deterministic candidate reproduction executor.
##
## Builds LS3.3 candidates every generation through the persistent process
## pool (the PAR1-selected backend) using the SINGLE pure candidate kernel —
## the same implementation the serial path calls. The worker protocol is
## extended minimally with a "phase": "CANDIDATE_BUILD" job kind; framing,
## mailbox transport, lifecycle and failure policy are reused verbatim
## (no second transport implementation).
##
## Work-item identity: parent record_id + generation. Each parent yields
## exactly OFFSPRING_PER_PARENT candidates. Canonical partitioning sorts
## parents by record_id and slices contiguously; the merge NEVER trusts
## worker completion order (final sort by candidate_hash).
##
## Audit policy (generation-based only): generation 1 and every 10th
## generation run the serial candidate oracle and require byte-exact
## candidate_pool_hash equality AND byte-exact candidate records.
##
## FAIL CLOSED: backend failure, count mismatch, hash mismatch, audit
## divergence -> named PAR3 failure code, NO candidates returned, the
## generation commits nothing. Never a silent serial fallback.

const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd")
const Pool = preload("res://scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_par3.candidate_build_executor.v1"
const VERSION := "1.0.0"

const SOURCE_PARALLEL_ONLY := "PAR3_PARALLEL_ONLY"
const SOURCE_PARALLEL_AUDITED := "PAR3_PARALLEL_AUDITED"

const FAIL_BACKEND := "PAR3_BACKEND_FAILURE"
const FAIL_AUDIT := "PAR3_AUDIT_PARITY_FAILURE"
const FAIL_INPUTS := "PAR3_INPUT_MISMATCH"
const FAIL_COUNT := "PAR3_RESULT_COUNT_MISMATCH"
const FAIL_HASH := "PAR3_CANDIDATE_HASH_INVALID"

## Test-only fault injection kinds (never set by production code):
##   FORCE_BACKEND_FAILURE     {}
##   FORCE_PARALLEL_CORRUPTION {index, field, value}
##   FORCE_AUDIT_MISMATCH      {}
const FAULT_KINDS := ["FORCE_BACKEND_FAILURE", "FORCE_PARALLEL_CORRUPTION", "FORCE_AUDIT_MISMATCH"]

var _configured := false
var _worker_count := 0
var _ls33_schema := ""
var _ls33_version := ""
var _evolution_seed := 0
var _offspring_per_parent := 2
var _audit_interval := 10
var _audit_generation_1 := true
var _godot_bin := ""
var _project_root := ""
var _session_root := ""
var _job_timeout_ms := 240_000
var _pool = null
var _warmup_done := false
var _last_pool_error := ""
var _fault_kind := ""
var _fault_params: Dictionary = {}

## Telemetry (noncanonical).
var parallel_calls := 0
var serial_audit_calls := 0
var oracle_elided_generations := 0
var last_audit_generation := -1
var last_audit_pass := false
var parallel_ms_total := 0.0
var audit_serial_ms_total := 0.0
var _last_report: Dictionary = {}

func setup(config: Dictionary) -> bool:
	_configured = false
	_worker_count = int(config.get("worker_count", 0))
	if _worker_count < 1:
		return false
	_ls33_schema = String(config.get("ls33_schema", ""))
	_ls33_version = String(config.get("ls33_version", ""))
	_evolution_seed = int(config.get("evolution_seed", 0))
	_offspring_per_parent = int(config.get("offspring_per_parent", 2))
	if _ls33_schema.is_empty() or _ls33_version.is_empty() or _offspring_per_parent < 1:
		return false
	_audit_interval = int(config.get("audit_interval", 10))
	_audit_generation_1 = bool(config.get("audit_generation_1", true))
	_project_root = String(config.get("project_root", ProjectSettings.globalize_path("res://")))
	_godot_bin = String(config.get("godot_bin", ""))
	if _godot_bin.is_empty():
		_godot_bin = OS.get_environment("GODOT_BIN")
	if _godot_bin.is_empty():
		_godot_bin = "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	_session_root = String(config.get("session_root", ""))
	if _session_root.is_empty():
		_session_root = OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if _session_root.is_empty():
		_session_root = _project_root.path_join("artifacts/par0_sessions")
	_job_timeout_ms = int(config.get("job_timeout_ms", 240_000))
	_configured = true
	return true

func is_pool_active() -> bool:
	return _pool != null

func shutdown() -> void:
	if _pool != null:
		_pool.shutdown()
		_pool = null

func get_telemetry() -> Dictionary:
	return {
		"parallel_calls": parallel_calls,
		"serial_audit_calls": serial_audit_calls,
		"oracle_elided_generations": oracle_elided_generations,
		"audit_interval": _audit_interval,
		"last_audit_generation": last_audit_generation,
		"last_audit_pass": last_audit_pass,
		"parallel_ms_total": parallel_ms_total,
		"audit_serial_ms_total": audit_serial_ms_total,
	}

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

func set_test_fault_injection(kind: String, params: Dictionary = {}) -> void:
	if kind.is_empty():
		_fault_kind = ""
		_fault_params = {}
		return
	if not kind in FAULT_KINDS:
		push_error("PAR3 executor: unknown fault injection kind %s" % kind)
		return
	_fault_kind = kind
	_fault_params = params.duplicate(true)

func is_audit_generation(generation: int) -> bool:
	if _audit_generation_1 and generation == 1:
		return true
	return _audit_interval > 0 and generation % _audit_interval == 0

## One parallel candidate build (audited on deterministic generations).
func build_candidates(parents: Array, generation: int) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _configured:
		return _failure(FAIL_BACKEND, "executor not configured", generation)
	if parents.is_empty():
		return _failure(FAIL_INPUTS, "parents empty", generation)
	var ordered: Array[Dictionary] = Kernel.ordered_parents(parents)
	if ordered.size() != parents.size():
		return _failure(FAIL_INPUTS, "parent records invalid", generation)

	if _pool == null and not _ensure_pool():
		return _failure(FAIL_BACKEND, "pool setup failed: " + _last_pool_error, generation)

	var audit := is_audit_generation(generation)

	## Canonical contiguous partition of the ordered parents.
	var bounds: Array[int] = Pool.partition(ordered.size(), _worker_count)
	var slices: Array = []
	var slice_input_hashes: Array[String] = []
	for index in _worker_count:
		var slice: Array = ordered.slice(bounds[index], bounds[index + 1])
		## Empty slices are legal (parent count < worker count): the worker
		## returns zero candidates for them.
		slices.append(slice)
		slice_input_hashes.append(_parents_input_hash(slice))

	var parallel_started := Time.get_ticks_usec()
	var base_id: String = _pool.submit_generation(generation, slices, {
		"phase": "CANDIDATE_BUILD",
		"schema": _ls33_schema,
		"version": _ls33_version,
		"evolution_seed": _evolution_seed,
		"offspring_per_parent": _offspring_per_parent,
	})
	if base_id.is_empty():
		return _failure(FAIL_BACKEND, "submit failed: " + _pool.last_error(), generation)
	var collected: Dictionary = _pool.collect_all()
	var parallel_ms := _elapsed_ms(parallel_started)
	parallel_calls += 1
	if _fault_kind == "FORCE_BACKEND_FAILURE":
		return _failure(FAIL_BACKEND, "forced backend failure (test)", generation)
	if collected.is_empty():
		return _failure(FAIL_BACKEND, "collect failed: " + _pool.last_error(), generation)

	## Validate responses + canonical merge.
	var candidates: Array[Dictionary] = []
	var seen_workers := {}
	for response_value in collected["responses"]:
		var response: Dictionary = response_value
		var worker_index := int(response.get("worker_index", -1))
		if seen_workers.has(worker_index):
			return _failure(FAIL_COUNT, "duplicate response for worker %d" % worker_index, generation)
		seen_workers[worker_index] = true
		if String(response.get("phase", "")) != "CANDIDATE_BUILD":
			return _failure(FAIL_BACKEND, "worker %d wrong phase" % worker_index, generation)
		var expected_job_id := "%s_w%d" % [base_id, worker_index]
		if String(response.get("job_id", "")) != expected_job_id:
			return _failure(FAIL_BACKEND, "worker %d stale job_id" % worker_index, generation)
		if int(response.get("generation", -1)) != generation:
			return _failure(FAIL_BACKEND, "worker %d generation mismatch" % worker_index, generation)
		if response.has("error"):
			return _failure(FAIL_BACKEND, "worker %d error %s" % [worker_index, String(response["error"])], generation)
		if String(response.get("input_hash", "")) != slice_input_hashes[worker_index]:
			return _failure(FAIL_INPUTS, "worker %d input_hash mismatch" % worker_index, generation)
		var events_value = response.get("events")
		if not events_value is Array:
			return _failure(FAIL_COUNT, "worker %d missing candidates" % worker_index, generation)
		var events: Array = events_value
		if events.size() != int(response.get("parent_count", 0)) * _offspring_per_parent:
			return _failure(FAIL_COUNT, "worker %d candidate count mismatch" % worker_index, generation)
		for candidate_value in events:
			if not candidate_value is Dictionary:
				return _failure(FAIL_COUNT, "worker %d candidate type invalid" % worker_index, generation)
			candidates.append(candidate_value)
	if candidates.size() != ordered.size() * _offspring_per_parent:
		return _failure(FAIL_COUNT, "total candidate count mismatch (%d != %d)" % [candidates.size(), ordered.size() * _offspring_per_parent], generation)
	## Coordinator-side canonical validation: every candidate_hash must match
	## the kernel recompute; canonical sort by candidate_hash.
	for candidate in candidates:
		if String(candidate.get("candidate_hash", "")) != Kernel.candidate_hash(_ls33_schema, _ls33_version, candidate):
			return _failure(FAIL_HASH, "candidate_hash failed kernel recompute", generation)
	Kernel.sort_candidates(candidates)
	var parallel_pool_hash := Kernel.candidate_pool_hash(candidates, _ls33_schema, _ls33_version)
	if _fault_kind == "FORCE_PARALLEL_CORRUPTION" and not candidates.is_empty():
		var index := int(_fault_params.get("index", 0))
		if index >= 0 and index < candidates.size():
			var altered: Dictionary = candidates[index].duplicate(true)
			altered[String(_fault_params.get("field", "mutation_seed"))] = _fault_params.get("value", -999)
			candidates[index] = altered
			parallel_pool_hash = Kernel.candidate_pool_hash(candidates, _ls33_schema, _ls33_version)

	## Bounded deterministic serial audit.
	var serial_pool_hash := ""
	var audit_serial_ms := 0.0
	if audit:
		var audit_started := Time.get_ticks_usec()
		var serial_candidates := Kernel.build_all(
			ordered, generation, _ls33_schema, _ls33_version, _evolution_seed, _offspring_per_parent)
		audit_serial_ms = _elapsed_ms(audit_started)
		serial_audit_calls += 1
		if serial_candidates.is_empty():
			return _failure(FAIL_AUDIT, "serial audit build failed", generation)
		serial_pool_hash = Kernel.candidate_pool_hash(serial_candidates, _ls33_schema, _ls33_version)
		if _fault_kind == "FORCE_AUDIT_MISMATCH":
			serial_pool_hash = String(serial_pool_hash.substr(0, serial_pool_hash.length() - 1)) + ("0" if serial_pool_hash.substr(-1) != "0" else "1")
		if serial_pool_hash != parallel_pool_hash or not _candidates_exact(serial_candidates, candidates):
			last_audit_generation = generation
			last_audit_pass = false
			return _failure(FAIL_AUDIT, "candidate audit divergence (pool hash or records)", generation, {
				"serial_pool_hash": serial_pool_hash,
				"parallel_pool_hash": parallel_pool_hash,
			})
		last_audit_generation = generation
		last_audit_pass = true
	else:
		oracle_elided_generations += 1

	parallel_ms_total += parallel_ms
	audit_serial_ms_total += audit_serial_ms
	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"generation": generation,
		"worker_count": _worker_count,
		"parent_count": ordered.size(),
		"candidate_count": candidates.size(),
		"audited": audit,
		"canonical_source": SOURCE_PARALLEL_AUDITED if audit else SOURCE_PARALLEL_ONLY,
		"candidate_pool_hash": parallel_pool_hash,
		"timings_ms": {
			"parallel_ms": parallel_ms,
			"audit_serial_ms": audit_serial_ms,
			"total_ms": _elapsed_ms(started_usec),
		},
	}
	_last_report = report
	return {
		"success": true,
		"candidates": candidates,
		"candidate_pool_hash": parallel_pool_hash,
		"canonical_source": report["canonical_source"],
		"comparison_passed": true,
		"serial_pool_hash": serial_pool_hash,
		"parallel_pool_hash": parallel_pool_hash,
		"audited": audit,
		"failure_code": "",
		"report": report,
	}

func _ensure_pool() -> bool:
	if not _warmup_done:
		if not Pool.warmup(_godot_bin, _project_root, _session_root):
			_last_pool_error = "warm-up lifecycle failed"
			return false
		_warmup_done = true
	var pool := Pool.new()
	var session_dir := _session_root.path_join("par3_%d_wc%d_%d" % [
		Time.get_ticks_usec(), _worker_count, Time.get_ticks_msec()])
	## The candidate-build pool carries no recruitment context; SETUP pins a
	## minimal immutable identity (CANDIDATE_BUILD jobs never read it).
	if not pool.setup(_godot_bin, _project_root, session_dir, _worker_count, {}, _job_timeout_ms):
		_last_pool_error = pool.last_error()
		return false
	_pool = pool
	return true

func _parents_input_hash(slice: Array) -> String:
	var keys := PackedStringArray()
	for parent_value in slice:
		keys.append(String(Dictionary(parent_value).get("record_id", "")))
	return "|".join(keys).sha256_text()

func _candidates_exact(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		var left: Dictionary = a[index]
		var right: Dictionary = b[index]
		## Deep structural equality (recursive Dictionary/Array ==) plus the
		## frozen identity check.
		if String(left.get("candidate_hash", "")) != String(right.get("candidate_hash", "")):
			return false
		if left != right:
			return false
	return true

func _failure(code: String, detail: String, generation: int, extra: Dictionary = {}) -> Dictionary:
	_last_report = {
		"schema": SCHEMA, "version": VERSION, "generation": generation,
		"failure_code": code, "failure_detail": detail,
	}
	var failure := {
		"success": false,
		"failure_code": code,
		"failure_detail": detail,
		"generation": generation,
		"canonical_source": "",
		"comparison_passed": false,
		"serial_pool_hash": String(extra.get("serial_pool_hash", "")),
		"parallel_pool_hash": String(extra.get("parallel_pool_hash", "")),
	}
	return failure

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0
