extends RefCounted

class_name Par2CanonicalRecruitmentExecutor

## ECO.EVO7 PAR2 — canonical PARALLEL-ONLY recruitment executor (v1).
##
## Replaces the PAR0.2 dual-verification runtime shape:
##
##   PAR0.2:  serial oracle + parallel every generation (duplicate work);
##   PAR2:    SELECTED PARALLEL BACKEND every generation,
##            serial audit ONLY on deterministic audit generations.
##
## Audit schedule is GENERATION-BASED only (never wall-clock):
##   audit_generation := generation == 1 or generation % interval == 0
##
## Failure policy — FAIL CLOSED, never a serial fallback:
##   backend failure               -> PAR2_BACKEND_FAILURE
##   audit parity mismatch         -> PAR2_AUDIT_PARITY_FAILURE
##   candidate/route input mismatch-> PAR2_INPUT_MISMATCH
##   context divergence            -> PAR2_CONTEXT_MISMATCH (from backend)
##   result count mismatch         -> PAR2_RESULT_COUNT_MISMATCH
## Any failure returns success=false; LS3.3 then commits NOTHING for the
## generation (existing seam semantics).
##
## The selected backend (PAR1: PROCESS_POOL via the direct PAR1 adapter)
## owns the worker lifecycle. LS3.3 stays backend-ignorant: it receives this
## executor through the existing set_recruitment_executor seam.
##
## Telemetry is profile-only and never enters any canonical hash.

const Contract = preload("res://scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd")
const ProcessBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_process_recruitment_backend_v1.gd")
const WorkerThreadBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_worker_thread_recruitment_backend_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_par2.canonical_recruitment_executor.v1"
const VERSION := "1.0.0"

const SOURCE_PARALLEL_ONLY := "PARALLEL_ONLY"
const SOURCE_PARALLEL_AUDITED := "PARALLEL_AUDITED"

const FAIL_BACKEND := "PAR2_BACKEND_FAILURE"
const FAIL_AUDIT := "PAR2_AUDIT_PARITY_FAILURE"
const FAIL_INPUTS := "PAR2_INPUT_MISMATCH"
const FAIL_CONTEXT := "PAR2_CONTEXT_MISMATCH"
const FAIL_COUNT := "PAR2_RESULT_COUNT_MISMATCH"

## Test-only fault injection kinds (never set by production code):
##   FORCE_BACKEND_FAILURE    {}  backend result replaced by failure
##   FORCE_PARALLEL_CORRUPTION {index, field, value}  post-merge, pre-audit
##   FORCE_AUDIT_MISMATCH     {}  alter the serial audit copy
const FAULT_KINDS := ["FORCE_BACKEND_FAILURE", "FORCE_PARALLEL_CORRUPTION", "FORCE_AUDIT_MISMATCH"]

var _configured := false
var _backend_id := "PROCESS_POOL"
var _backend = null
var _audit_interval := 10
var _audit_generation_1 := true
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
var merge_ms_total := 0.0
var _last_report: Dictionary = {}

func setup(config: Dictionary) -> bool:
	_configured = false
	_backend_id = String(config.get("backend", "PROCESS_POOL"))
	if _backend_id != "PROCESS_POOL" and _backend_id != "WORKER_THREAD_POOL":
		return false
	_audit_interval = int(config.get("audit_interval", 10))
	if _audit_interval < 1:
		return false
	_audit_generation_1 = bool(config.get("audit_generation_1", true))
	if _backend_id == "PROCESS_POOL":
		_backend = ProcessBackend.new()
	else:
		_backend = WorkerThreadBackend.new()
	var backend_config: Dictionary = {
		"worker_count": int(config.get("worker_count", 4)),
		"project_root": String(config.get("project_root", ProjectSettings.globalize_path("res://"))),
		"job_timeout_ms": int(config.get("job_timeout_ms", 240_000)),
	}
	if _backend_id == "PROCESS_POOL":
		backend_config["godot_bin"] = String(config.get("godot_bin", ""))
		backend_config["session_root"] = String(config.get("session_root", ""))
	if not _backend.setup(backend_config):
		_backend = null
		return false
	_configured = true
	return true

func is_pool_active() -> bool:
	return _backend != null and _backend.is_pool_active()

func shutdown() -> void:
	if _backend != null:
		_backend.shutdown()

func get_telemetry() -> Dictionary:
	return {
		"backend": _backend_id,
		"parallel_calls": parallel_calls,
		"serial_audit_calls": serial_audit_calls,
		"oracle_elided_generations": oracle_elided_generations,
		"audit_interval": _audit_interval,
		"last_audit_generation": last_audit_generation,
		"last_audit_pass": last_audit_pass,
		"parallel_ms_total": parallel_ms_total,
		"audit_serial_ms_total": audit_serial_ms_total,
		"merge_ms_total": merge_ms_total,
	}

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

## Test-only fault injection hook. Pass empty kind to clear.
func set_test_fault_injection(kind: String, params: Dictionary = {}) -> void:
	if kind.is_empty():
		_fault_kind = ""
		_fault_params = {}
		return
	if not kind in FAULT_KINDS:
		push_error("PAR2 executor: unknown fault injection kind %s" % kind)
		return
	_fault_kind = kind
	_fault_params = params.duplicate(true)

func is_audit_generation(generation: int) -> bool:
	if _audit_generation_1 and generation == 1:
		return true
	return _audit_interval > 0 and generation % _audit_interval == 0

## One parallel-only (or audited) generation.
func evaluate_generation(
	generation: int,
	candidates: Array[Dictionary],
	routes: Array[Dictionary],
	immutable_context: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _configured:
		return _failure(FAIL_BACKEND, "executor not configured", generation)
	if candidates.is_empty() or candidates.size() != routes.size():
		return _failure(FAIL_INPUTS, "candidate/route size mismatch", generation)
	var items: Array = Contract.canonical_items(candidates, routes)
	if items.size() != candidates.size():
		return _failure(FAIL_INPUTS, "candidate/route identity mismatch", generation)

	var audit := is_audit_generation(generation)

	## 1) Parallel evaluation through the SELECTED backend (canonical path).
	var parallel_started := Time.get_ticks_usec()
	var parallel_result: Dictionary = _backend.evaluate_generation(
		generation, candidates, routes, immutable_context)
	var parallel_ms := _elapsed_ms(parallel_started)
	parallel_calls += 1
	if _fault_kind == "FORCE_BACKEND_FAILURE":
		return _failure(FAIL_BACKEND, "forced backend failure (test)", generation)
	if not bool(parallel_result.get("success", false)):
		var code := String(parallel_result.get("failure_code", ""))
		if code == "PAR1_CONTEXT_MISMATCH":
			return _failure(FAIL_CONTEXT, String(parallel_result.get("failure_detail", "")), generation)
		return _failure(FAIL_BACKEND, String(parallel_result.get("failure_detail", code)), generation)
	var events: Array = parallel_result.get("canonical_events", [])
	if events.size() != candidates.size():
		return _failure(FAIL_COUNT, "parallel result count %d != candidates %d" % [events.size(), candidates.size()], generation)
	var parallel_hash := String(parallel_result.get("canonical_hash", ""))
	if _fault_kind == "FORCE_PARALLEL_CORRUPTION" and not events.is_empty():
		var index := int(_fault_params.get("index", 0))
		if index >= 0 and index < events.size():
			var altered: Dictionary = events[index].duplicate(true)
			altered[String(_fault_params.get("field", "shadow_fitness"))] = _fault_params.get("value", -321.0)
			events[index] = altered
			parallel_hash = Contract.recruitment_hash(events, immutable_context)

	## 2) Bounded deterministic serial audit (audit generations only).
	var serial_hash := ""
	var audit_serial_ms := 0.0
	if audit:
		var audit_started := Time.get_ticks_usec()
		var serial_events := Contract.serial_evaluate(items, immutable_context)
		audit_serial_ms = _elapsed_ms(audit_started)
		serial_audit_calls += 1
		if serial_events.is_empty():
			return _failure(FAIL_AUDIT, "serial audit evaluation failed", generation)
		serial_hash = Contract.recruitment_hash(serial_events, immutable_context)
		if _fault_kind == "FORCE_AUDIT_MISMATCH":
			serial_hash = String(serial_hash.substr(0, serial_hash.length() - 1)) + ("0" if serial_hash.substr(-1) != "0" else "1")
		if serial_hash != parallel_hash or not Contract.events_exact(serial_events, events):
			last_audit_generation = generation
			last_audit_pass = false
			return _failure(FAIL_AUDIT, _first_mismatch(serial_events, events), generation, {
				"serial_hash": serial_hash,
				"parallel_hash": parallel_hash,
			})
		last_audit_generation = generation
		last_audit_pass = true
	else:
		oracle_elided_generations += 1

	parallel_ms_total += parallel_ms
	audit_serial_ms_total += audit_serial_ms
	merge_ms_total += float(Dictionary(parallel_result.get("timings_ms", {})).get("merge_ms", 0.0))

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"backend": _backend_id,
		"generation": generation,
		"worker_count": int(parallel_result.get("worker_count", 0)),
		"candidate_count": candidates.size(),
		"audited": audit,
		"canonical_source": SOURCE_PARALLEL_AUDITED if audit else SOURCE_PARALLEL_ONLY,
		"parallel_hash": parallel_hash,
		"serial_hash": serial_hash,
		"timings_ms": {
			"parallel_ms": parallel_ms,
			"audit_serial_ms": audit_serial_ms,
			"total_ms": _elapsed_ms(started_usec),
		},
	}
	_last_report = report
	return {
		"success": true,
		"canonical_events": events,
		"canonical_recruitment_hash": parallel_hash,
		"canonical_source": report["canonical_source"],
		"comparison_passed": true,
		"serial_hash": serial_hash,
		"parallel_hash": parallel_hash,
		"audited": audit,
		"failure_code": "",
		"report": report,
	}

func _first_mismatch(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "count %d vs %d" % [a.size(), b.size()]
	for index in a.size():
		var left: Dictionary = a[index]
		var right: Dictionary = b[index]
		if String(left.get("candidate_hash", "")) != String(right.get("candidate_hash", "")):
			return "position %d candidate order" % index
		for key in left.keys():
			if not right.has(key) or left[key] != right[key]:
				return "candidate %s field %s" % [String(left.get("candidate_hash", "")), key]
	return "hash-only divergence"

func _failure(code: String, detail: String, generation: int, extra: Dictionary = {}) -> Dictionary:
	var failure := {
		"success": false,
		"failure_code": code,
		"failure_detail": detail,
		"generation": generation,
		"canonical_source": "",
		"comparison_passed": false,
		"serial_hash": String(extra.get("serial_hash", "")),
		"parallel_hash": String(extra.get("parallel_hash", "")),
	}
	_last_report = {
		"schema": SCHEMA, "version": VERSION, "backend": _backend_id,
		"generation": generation, "failure_code": code, "failure_detail": detail,
	}
	return failure

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0
