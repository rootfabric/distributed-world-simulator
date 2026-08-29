extends RefCounted

class_name Par1WorkerThreadRecruitmentBackend

## ECO.EVO7 PAR1 — direct WorkerThreadPool recruitment backend (v1).
##
## Evaluates the canonical LS3.3 recruitment batch through Godot
## WorkerThreadPool.add_group_task() with the shared pure Par0Kernel — the
## SAME single implementation the serial path and the process workers use.
##
## Safety rules (PAR1 mission section 8):
##   - results/errors arrays are resized BEFORE group submission and are
##     never resized/appended/erased inside worker tasks;
##   - every worker writes ONLY its own index;
##   - the worker object is RefCounted, never Node; no SceneTree, no
##     rendering, no physics, no persistence, no global RNG anywhere in the
##     kernel path;
##   - after wait_for_group_task_completion() the coordinator validates every
##     slot, stamps/keeps the canonical event hash, sorts by candidate_hash
##     and recomputes the aggregate hash;
##   - FAIL CLOSED: any slot error -> success=false, no canonical result.
##
## No serial oracle runs inside this backend.

const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd")

const BACKEND := "WORKER_THREAD_POOL"
const SCHEMA := "distributed_world_simulator.ecology.evo7_par1.worker_thread_recruitment_backend.v1"
const VERSION := "1.0.0"

const FAIL_INPUTS := "PAR1_INPUTS_INVALID"
const FAIL_TASK := "PAR1_WORKER_TASK_FAILURE"
const FAIL_SLOT := "PAR1_RESULT_SLOT_INVALID"

var _configured := false
var _worker_count := 0
var _group_calls := 0
var _last_report: Dictionary = {}

func setup(config: Dictionary) -> bool:
	_configured = false
	_worker_count = int(config.get("worker_count", 0))
	if _worker_count < 1:
		return false
	_configured = true
	return true

func worker_count() -> int:
	return _worker_count

func group_calls() -> int:
	return _group_calls

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

func is_pool_active() -> bool:
	return true

func shutdown() -> void:
	## Nothing to tear down: WorkerThreadPool groups are fully awaited inside
	## evaluate_generation; no persistent worker lifecycle exists here.
	pass

## One parallel-only generation through WorkerThreadPool.
func evaluate_generation(
	generation: int,
	candidates: Array[Dictionary],
	routes: Array[Dictionary],
	immutable_context: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _configured:
		return _failure(FAIL_TASK, "backend not configured", generation, 0.0)
	if candidates.is_empty() or candidates.size() != routes.size():
		return _failure(FAIL_INPUTS, "candidate/route size mismatch", generation, _elapsed_ms(started_usec))

	var schedule_started := Time.get_ticks_usec()
	var items: Array = Contract.canonical_items(candidates, routes)
	if items.size() != candidates.size():
		return _failure(FAIL_INPUTS, "candidate/route identity mismatch", generation, _elapsed_ms(started_usec))
	var results: Array = []
	results.resize(items.size())
	var errors: Array = []
	errors.resize(items.size())
	for index in items.size():
		results[index] = null
		errors[index] = false
	var worker := Par1ThreadWorker.new(items, results, errors, immutable_context)
	var schedule_ms := _elapsed_ms(schedule_started)

	## Group task: one element per candidate item; Godot spreads elements
	## over at most worker_count threads. The callable receives the element
	## index and writes only results[index]/errors[index].
	var compute_started := Time.get_ticks_usec()
	var group := WorkerThreadPool.add_group_task(
		Callable(worker, "evaluate_index"), items.size(), _worker_count,
		true, "par1_recruitment")
	WorkerThreadPool.wait_for_group_task_completion(group)
	var compute_ms := _elapsed_ms(compute_started)
	_group_calls += 1

	## Coordinator-side validation + canonical merge + aggregate hash.
	var merge_started := Time.get_ticks_usec()
	var events: Array[Dictionary] = []
	for index in items.size():
		if bool(errors[index]):
			return _failure(FAIL_SLOT, "worker slot %d evaluation failed" % index, generation, _elapsed_ms(started_usec))
		var event_value = results[index]
		if not event_value is Dictionary:
			return _failure(FAIL_SLOT, "worker slot %d result missing" % index, generation, _elapsed_ms(started_usec))
		events.append(event_value)
	if events.size() != items.size():
		return _failure(FAIL_SLOT, "result count mismatch", generation, _elapsed_ms(started_usec))
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	var canonical_hash := Contract.recruitment_hash(events, immutable_context)
	var merge_ms := _elapsed_ms(merge_started)

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"backend": BACKEND,
		"generation": generation,
		"worker_count": _worker_count,
		"candidate_count": items.size(),
		"canonical_hash": canonical_hash,
		"timings_ms": {
			"schedule_ms": schedule_ms,
			"compute_ms": compute_ms,
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

func _failure(code: String, detail: String, generation: int, total_ms: float) -> Dictionary:
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
		"timings_ms": {"total_ms": total_ms},
		"report": _last_report.duplicate(true),
	}

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


## Internal RefCounted worker body. Holds ONLY immutable references set at
## construction; evaluate_index writes exactly one slot per call.
class Par1ThreadWorker:
	extends RefCounted

	var _items: Array
	var _results: Array
	var _errors: Array
	var _context: Dictionary
	var _schema := ""
	var _version := ""

	func _init(items: Array, results: Array, errors: Array, context: Dictionary) -> void:
		_items = items
		_results = results
		_errors = errors
		_context = context
		_schema = String(context.get("schema", ""))
		_version = String(context.get("version", ""))

	func evaluate_index(index: int) -> void:
		## Pure per-candidate evaluation via the shared kernel. No container
		## size mutation, no shared RNG, no engine state access.
		var item: Dictionary = _items[index]
		var event := KernelRef.evaluate_recruitment_event(
			item["candidate"], item["route"], _context)
		if event.is_empty():
			_errors[index] = true
			return
		event["recruitment_event_hash"] = KernelRef.recruitment_event_hash(
			event, _schema, _version)
		_results[index] = event

	const KernelRef = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
