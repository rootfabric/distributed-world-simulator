extends RefCounted

class_name Par02DualRecruitmentExecutor

## ECO.EVO7 PERF1-PAR0.2 — canonical dual recruitment executor.
##
## Owns the authority handover proof: the same immutable generation input is
## evaluated by the serial kernel (oracle, single implementation) and by the
## PAR0 persistent process pool. Only an EXACT byte-level match promotes the
## PARALLEL result to the canonical recruitment source returned to LS3.3.
##
## Ownership boundaries:
##   - owns: serial oracle replay, PAR0 pool lifecycle, generation/job
##     identity, response validation, canonical merge, exact comparison,
##     fail-closed evidence dumps, noncanonical telemetry;
##   - does NOT own: ecology state. It never mutates LS3.3 state and its
##     telemetry never enters any canonical hash.
##
## Pool lifecycle contract (one persistent pool per coordinator process):
##   Pool.warmup()  once   (static per-process guard)
##   Pool.setup()   once   (lazy, at the first evaluated generation)
##   generation 1..N through the SAME pool
##   Pool.shutdown() once
##
## Failure policy — FAIL-CLOSED, no fallback to serial:
##   parity mismatch, worker timeout/crash, stale job_id, wrong generation,
##   wrong input_hash, missing/duplicate response, context divergence ->
##   named failure code + persisted evidence; no canonical result returned.

const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Pool = preload("res://scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_par02_dual_recruitment_executor.v1"
const VERSION := "1.0.0"

const SOURCE_SERIAL := "SERIAL_ORACLE"
const SOURCE_PARALLEL := "PARALLEL_VERIFIED"

const FAIL_PARITY := "PAR02_RECRUITMENT_PARITY_FAILURE"
const FAIL_STALE := "STALE_WORKER_RESULT"
const FAIL_GENERATION := "GENERATION_MISMATCH"
const FAIL_INPUT_HASH := "INPUT_HASH_MISMATCH"
const FAIL_DUPLICATE := "DUPLICATE_WORKER_RESULT"
const FAIL_MISSING := "MISSING_WORKER_RESULT"
const FAIL_CONTEXT := "CONTEXT_MISMATCH"
const FAIL_POOL := "POOL_FAILURE"
const FAIL_INPUTS := "INPUTS_INVALID"

## Test-only fault injection kinds (never set by production code):
##   ALTER_PARALLEL_EVENT      {index, field, value}  post-merge, pre-compare
##   INJECT_STALE_RESPONSE     {worker_index}         pre-validation
##   INJECT_WRONG_GENERATION   {worker_index}         pre-validation
##   INJECT_WRONG_INPUT_HASH   {worker_index}         pre-validation
##   INJECT_DUPLICATE_RESPONSE {}                     pre-validation
const FAULT_KINDS := [
	"ALTER_PARALLEL_EVENT", "INJECT_STALE_RESPONSE", "INJECT_WRONG_GENERATION",
	"INJECT_WRONG_INPUT_HASH", "INJECT_DUPLICATE_RESPONSE",
]

var _configured := false
var _worker_count := 0
var _godot_bin := ""
var _project_root := ""
var _session_root := ""
var _evidence_dir := ""
var _job_timeout_ms := 180_000
var _pool = null
var _setup_context := {}
var _setup_context_hash := ""
var _warmup_done := false
var _generation_jobs := 0
var _last_pool_error := ""

var pool_setup_count := 0
var pool_shutdown_count := 0
var _last_report: Dictionary = {}
var _fault_kind := ""
var _fault_params: Dictionary = {}

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
		_session_root = _project_root.path_join("artifacts/par02_sessions")
	_evidence_dir = String(config.get("evidence_dir", _project_root.path_join("artifacts/par02/evidence")))
	_job_timeout_ms = int(config.get("job_timeout_ms", 180_000))
	_configured = true
	return true

## Test-only fault injection hook. Pass empty kind to clear.
func set_test_fault_injection(kind: String, params: Dictionary = {}) -> void:
	if kind.is_empty():
		_fault_kind = ""
		_fault_params = {}
		return
	if not kind in FAULT_KINDS:
		push_error("PAR02 executor: unknown fault injection kind %s" % kind)
		return
	_fault_kind = kind
	_fault_params = params.duplicate(true)

func is_pool_active() -> bool:
	return _pool != null

func generation_jobs() -> int:
	return _generation_jobs

func get_lifetime_counters() -> Dictionary:
	return {
		"pool_setup_count": pool_setup_count,
		"pool_shutdown_count": pool_shutdown_count,
		"generation_jobs": _generation_jobs,
		"worker_count": _worker_count,
	}

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

## One dual-verified generation. Immutable inputs: candidates and routes are
## the canonical LS3.3 arrays (already sorted by candidate_hash); context is
## the exact Par0Kernel context LS3.3 builds for its own serial evaluation.
func evaluate_generation(
	generation: int,
	candidates: Array[Dictionary],
	routes: Array[Dictionary],
	immutable_context: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _configured:
		return _failure(FAIL_POOL, "executor not configured", generation, {})
	if candidates.is_empty() or candidates.size() != routes.size():
		return _failure(FAIL_INPUTS, "candidate/route size mismatch", generation, {})

	## 1) Canonicalize inputs (never trust caller ordering).
	var items: Array = _canonical_items(candidates, routes)
	if items.size() != candidates.size():
		return _failure(FAIL_INPUTS, "candidate/route identity mismatch", generation, {})

	## Pool lifecycle: lazy one-time setup pinned to the first context.
	if _pool == null:
		if not _ensure_pool(immutable_context, generation):
			return _failure(FAIL_POOL, "pool setup failed: " + _last_pool_error, generation, {})

	## Context pinned at setup must match every evaluated generation.
	var context_hash := _context_hash(immutable_context)
	if context_hash != _setup_context_hash:
		return _failure(FAIL_CONTEXT, "evaluate context diverged from pool setup context", generation, {
			"setup_context_hash": _setup_context_hash,
			"evaluate_context_hash": context_hash,
		})

	## 2) Per-slice input hashes (same formula the worker reports).
	var bounds: Array[int] = Pool.partition(items.size(), _worker_count)
	var slices: Array = []
	var slice_input_hashes: Array[String] = []
	for index in _worker_count:
		var slice: Array = items.slice(bounds[index], bounds[index + 1])
		slices.append(slice)
		slice_input_hashes.append(_slice_input_hash(slice))

	## 3) Parallel submission FIRST so workers compute concurrently.
	var serialize_started := Time.get_ticks_usec()
	var base_id: String = _pool.submit_generation(generation, slices)
	var serialize_ms := _elapsed_ms(serialize_started)
	if base_id.is_empty():
		return _failure(FAIL_POOL, "submit failed: " + _pool.last_error(), generation, {})
	_generation_jobs += 1

	## 4) Serial oracle over the SAME immutable input, concurrently with
	## the worker processes.
	var serial_started := Time.get_ticks_usec()
	var serial_events := _serial_oracle(items, immutable_context)
	var serial_oracle_ms := _elapsed_ms(serial_started)
	if serial_events.is_empty():
		return _failure(FAIL_POOL, "serial oracle evaluation failed", generation, {})
	var serial_hash := _recruitment_hash(serial_events, immutable_context)

	## 5) Collect worker responses.
	var collect_started := Time.get_ticks_usec()
	var collected: Dictionary = _pool.collect_all()
	var ipc_ms := _elapsed_ms(collect_started)
	if collected.is_empty():
		return _failure(FAIL_POOL, "collect failed: " + _pool.last_error(), generation, {})

	## 6) Validate worker responses (identity, generation, input_hash...).
	var validation := _validate_responses(
		collected["responses"], generation, base_id, slice_input_hashes)
	if not validation.get("ok", false):
		return _failure(String(validation["code"]), String(validation["detail"]), generation, {
			"job_id": base_id,
			"input_hashes": slice_input_hashes,
			"worker_count": _worker_count,
		})
	var responses: Array = validation["responses"]

	## 7) Canonical merge (frozen PAR0 ordering: sort by candidate_hash).
	var merge_started := Time.get_ticks_usec()
	var parallel_events := _canonical_merge(responses, items.size())
	var merge_ms := _elapsed_ms(merge_started)
	if parallel_events.is_empty():
		return _failure(FAIL_POOL, "canonical merge/validation failed", generation, {"job_id": base_id})
	parallel_events = _apply_parallel_fault(parallel_events)
	var parallel_hash := _recruitment_hash(parallel_events, immutable_context)

	## 8) EXACT compare: serial oracle vs parallel result.
	var compare_started := Time.get_ticks_usec()
	var exact := _events_exact(serial_events, parallel_events) and serial_hash == parallel_hash
	var compare_ms := _elapsed_ms(compare_started)

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"mode": "DUAL_VERIFY",
		"generation": generation,
		"job_id": base_id,
		"worker_count": _worker_count,
		"candidate_count": items.size(),
		"serial_oracle_used": true,
		"parallel_used": true,
		"comparison_passed": exact,
		"canonical_source": SOURCE_PARALLEL if exact else SOURCE_SERIAL,
		"serial_hash": serial_hash,
		"parallel_hash": parallel_hash,
		"input_hash": _slice_input_hash(items),
		"context_hash": context_hash,
		"timings_ms": {
			"serial_oracle_ms": serial_oracle_ms,
			"serialize_ms": serialize_ms,
			"ipc_ms": ipc_ms,
			"merge_ms": merge_ms,
			"compare_ms": compare_ms,
			"dual_total_ms": _elapsed_ms(started_usec),
		},
	}

	## 9)/10) Authority decision. No fallback: mismatch is fail-closed.
	if not exact:
		var first_mismatch := _first_mismatch(serial_events, parallel_events)
		var evidence := {
			"schema": SCHEMA + ".parity_failure.v1",
			"generation": generation,
			"job_id": base_id,
			"input_hash": String(report["input_hash"]),
			"worker_count": _worker_count,
			"first_mismatch": first_mismatch,
			"serial_recruitment_hash": serial_hash,
			"parallel_recruitment_hash": parallel_hash,
			"serial_context_hash": context_hash,
			"parallel_context_hash": context_hash,
			"timings_ms": report["timings_ms"].duplicate(true),
		}
		if not serial_events.is_empty() and not parallel_events.is_empty():
			var mismatch_index := _first_mismatch_index(serial_events, parallel_events)
			if mismatch_index >= 0:
				if mismatch_index < serial_events.size():
					evidence["serial_event"] = serial_events[mismatch_index]
				if mismatch_index < parallel_events.size():
					evidence["parallel_event"] = parallel_events[mismatch_index]
		report["canonical_source"] = ""
		report["comparison_passed"] = false
		_last_report = report
		return _failure(FAIL_PARITY, first_mismatch, generation, {
			"job_id": base_id,
			"input_hash": String(report["input_hash"]),
			"evidence": evidence,
		})

	_last_report = report
	return {
		"success": true,
		"canonical_events": parallel_events,
		"canonical_recruitment_hash": parallel_hash,
		"serial_hash": serial_hash,
		"parallel_hash": parallel_hash,
		"comparison_passed": true,
		"canonical_source": SOURCE_PARALLEL,
		"report": report,
	}

func shutdown() -> void:
	if _pool != null:
		_pool.shutdown()
		_pool = null
		pool_shutdown_count += 1

## ---------- pool lifecycle ----------

func _ensure_pool(context: Dictionary, generation: int) -> bool:
	if not _warmup_done:
		## One warm-up lifecycle per coordinator process stabilises every
		## subsequent pool spawn (PAR0.1 dual-bisect evidence).
		if not Pool.warmup(_godot_bin, _project_root, _session_root):
			_last_pool_error = "warm-up lifecycle failed"
			return false
		_warmup_done = true
	var pool := Pool.new()
	var session_dir := _session_root.path_join("dual_%d_wc%d_%d" % [
		generation, _worker_count, Time.get_ticks_usec()])
	if not pool.setup(_godot_bin, _project_root, session_dir, _worker_count, context, _job_timeout_ms):
		_last_pool_error = pool.last_error()
		return false
	_pool = pool
	_setup_context = context.duplicate(true)
	_setup_context_hash = _context_hash(context)
	pool_setup_count += 1
	return true

## ---------- input canonicalization ----------

func _canonical_items(candidates: Array[Dictionary], routes: Array[Dictionary]) -> Array:
	var route_by_hash := {}
	for route_value in routes:
		var route: Dictionary = route_value
		route_by_hash[String(route["candidate_hash"])] = route
	var items: Array = []
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var candidate_hash := String(candidate["candidate_hash"])
		if not route_by_hash.has(candidate_hash):
			return []
		items.append({"candidate": candidate, "route": route_by_hash[candidate_hash]})
	## Candidates arrive canonically sorted; enforce the frozen order.
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate"]["candidate_hash"]) < String(b["candidate"]["candidate_hash"])
	)
	return items

## ---------- serial oracle ----------

func _serial_oracle(items: Array, context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_value in items:
		var item: Dictionary = item_value
		var event_result := Kernel.evaluate_recruitment_event(
			item["candidate"], item["route"], context)
		if event_result.is_empty():
			return []
		var event: Dictionary = event_result
		event["recruitment_event_hash"] = Kernel.recruitment_event_hash(
			event, String(context["schema"]), String(context["version"]))
		out.append(event)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return out

## ---------- response validation ----------

func _validate_responses(
	responses: Array,
	generation: int,
	base_id: String,
	slice_input_hashes: Array[String]
) -> Dictionary:
	if responses.size() != _worker_count:
		return {"ok": false, "code": FAIL_MISSING,
			"detail": "expected %d responses, got %d" % [_worker_count, responses.size()], "responses": []}
	var seen_workers := {}
	var validated: Array = []
	for response_value in responses:
		var response: Dictionary = _apply_response_fault(response_value)
		var worker_index := int(response.get("worker_index", -1))
		if seen_workers.has(worker_index):
			return {"ok": false, "code": FAIL_DUPLICATE,
				"detail": "duplicate response for worker %d" % worker_index, "responses": []}
		seen_workers[worker_index] = true
		if String(response.get("protocol_version", "")) != Pool.Transport.PROTOCOL_VERSION:
			return {"ok": false, "code": FAIL_POOL,
				"detail": "protocol mismatch on worker %d" % worker_index, "responses": []}
		var expected_job_id := "%s_w%d" % [base_id, worker_index]
		if String(response.get("job_id", "")) != expected_job_id:
			return {"ok": false, "code": FAIL_STALE,
				"detail": "worker %d job_id %s != current %s" % [
					worker_index, String(response.get("job_id", "")), expected_job_id],
				"responses": []}
		if int(response.get("generation", -1)) != generation:
			return {"ok": false, "code": FAIL_GENERATION,
				"detail": "worker %d generation %d != current %d" % [
					worker_index, int(response.get("generation", -1)), generation],
				"responses": []}
		if response.has("error"):
			return {"ok": false, "code": FAIL_POOL,
				"detail": "worker %d evaluation error %s" % [worker_index, String(response["error"])],
				"responses": []}
		if worker_index < 0 or worker_index >= slice_input_hashes.size():
			return {"ok": false, "code": FAIL_POOL,
				"detail": "worker index %d out of range" % worker_index, "responses": []}
		if String(response.get("input_hash", "")) != slice_input_hashes[worker_index]:
			return {"ok": false, "code": FAIL_INPUT_HASH,
				"detail": "worker %d input_hash mismatch" % worker_index, "responses": []}
		var events_value = response.get("events")
		if not events_value is Array:
			return {"ok": false, "code": FAIL_POOL,
				"detail": "worker %d response missing events" % worker_index, "responses": []}
		validated.append(response)
	for index in _worker_count:
		if not seen_workers.has(index):
			return {"ok": false, "code": FAIL_MISSING,
				"detail": "no response from worker %d" % index, "responses": []}
	return {"ok": true, "code": "", "detail": "", "responses": validated}

## ---------- canonical merge + comparison ----------

func _canonical_merge(responses: Array, expected_count: int) -> Array[Dictionary]:
	## Frozen PAR0 merge ordering: never trust arrival order; concatenate,
	## sort by candidate_hash, require exact event count.
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

func _events_exact(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	## Byte-for-byte semantics of the PAR0 runner comparator.
	if a.size() != b.size():
		return false
	for index in a.size():
		var left: Dictionary = a[index]
		var right: Dictionary = b[index]
		for key in left.keys():
			if not right.has(key) or left[key] != right[key]:
				return false
		if left.keys().size() != right.keys().size():
			return false
	return true

func _first_mismatch(a: Array[Dictionary], b: Array[Dictionary]) -> String:
	for index in mini(a.size(), b.size()):
		if a[index].get("candidate_hash", "") != b[index].get("candidate_hash", ""):
			return "position %d candidate order" % index
		for key in a[index].keys():
			if not b[index].has(key) or a[index][key] != b[index][key]:
				return "candidate %s field %s" % [String(a[index].get("candidate_hash", "")), key]
	return "count %d vs %d" % [a.size(), b.size()]

func _first_mismatch_index(a: Array[Dictionary], b: Array[Dictionary]) -> int:
	for index in mini(a.size(), b.size()):
		if a[index].get("candidate_hash", "") != b[index].get("candidate_hash", ""):
			return index
		for key in a[index].keys():
			if not b[index].has(key) or a[index][key] != b[index][key]:
				return index
	return mini(a.size(), b.size())

## ---------- hashes ----------

func _slice_input_hash(slice: Array) -> String:
	## Same formula the PAR0 worker reports per response.
	var input_keys := PackedStringArray()
	for item_value in slice:
		var item: Dictionary = item_value
		input_keys.append(String(item["candidate"].get("candidate_hash", "")))
		input_keys.append(String(item["route"].get("route_hash", "")))
	return "|".join(input_keys).sha256_text()

func _context_hash(context: Dictionary) -> String:
	return String(JSON.stringify(context, "", false)).sha256_text()

func _recruitment_hash(events: Array[Dictionary], context: Dictionary) -> String:
	## Identical formula to LS3.3 _recruitment_hash over stamped events.
	var hashes := PackedStringArray()
	for event in events:
		hashes.append(String(event.get("recruitment_event_hash", "")))
	hashes.sort()
	return (String(context["schema"]) + "|" + String(context["version"]) + "|recruitment-pool|" + "|".join(hashes)).sha256_text()

## ---------- fail-closed plumbing ----------

func _failure(code: String, detail: String, generation: int, extra: Dictionary) -> Dictionary:
	var failure := {
		"success": false,
		"failure_code": code,
		"failure_detail": detail,
		"generation": generation,
		"canonical_source": "",
		"comparison_passed": false,
	}
	for key in extra.keys():
		failure[key] = extra[key]
	if extra.has("evidence"):
		failure["evidence_path"] = _persist_evidence(extra["evidence"],
			"%s_gen%d" % [code.to_lower(), generation])
	_last_report = {
		"schema": SCHEMA, "version": VERSION, "mode": "DUAL_VERIFY",
		"generation": generation, "worker_count": _worker_count,
		"failure_code": code, "failure_detail": detail,
		"serial_oracle_used": code != FAIL_POOL,
		"parallel_used": true,
		"comparison_passed": false, "canonical_source": "",
	}
	return failure

func _persist_evidence(evidence: Dictionary, tag: String) -> String:
	DirAccess.make_dir_recursive_absolute(_evidence_dir)
	var path := _evidence_dir.path_join("par02_%s_%d.json" % [tag, Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(_jsonable(evidence), "  "))
	file.close()
	return path

func _jsonable(value):
	if value is Dictionary:
		var out := {}
		for key in value.keys():
			out[String(key)] = _jsonable(value[key])
		return out
	if value is Array:
		var out_array: Array = []
		for item in value:
			out_array.append(_jsonable(item))
		return out_array
	return value

## ---------- test-only fault application ----------

func _apply_response_fault(response_value):
	if _fault_kind.is_empty() or not response_value is Dictionary:
		return response_value
	var response: Dictionary = response_value
	var target := int(_fault_params.get("worker_index", 0))
	match _fault_kind:
		"INJECT_STALE_RESPONSE":
			if int(response.get("worker_index", -1)) == target:
				var stale: Dictionary = response.duplicate(true)
				stale["job_id"] = "gen_00000000_0_w%d" % target
				stale["generation"] = int(stale.get("generation", 1)) - 1
				return stale
		"INJECT_WRONG_GENERATION":
			if int(response.get("worker_index", -1)) == target:
				var wrong_gen: Dictionary = response.duplicate(true)
				wrong_gen["generation"] = int(wrong_gen.get("generation", 1)) + 1
				return wrong_gen
		"INJECT_WRONG_INPUT_HASH":
			if int(response.get("worker_index", -1)) == target:
				var wrong_hash: Dictionary = response.duplicate(true)
				wrong_hash["input_hash"] = String(wrong_hash.get("input_hash", "")).substr(0, 63) + "0"
				return wrong_hash
		"INJECT_DUPLICATE_RESPONSE":
			if int(response.get("worker_index", -1)) == 1 and _worker_count > 1:
				var duplicate: Dictionary = response.duplicate(true)
				duplicate["worker_index"] = 0
				return duplicate
	return response

func _apply_parallel_fault(events: Array[Dictionary]) -> Array[Dictionary]:
	## Post-collect, pre-compare alteration of ONE parallel event copy —
	## simulates a divergent parallel result without touching production
	## biology (mission section 10, safe variant).
	if _fault_kind != "ALTER_PARALLEL_EVENT" or events.is_empty():
		return events
	var index := int(_fault_params.get("index", 0))
	if index < 0 or index >= events.size():
		return events
	var altered: Dictionary = events[index].duplicate(true)
	var field := String(_fault_params.get("field", "shadow_fitness"))
	altered[field] = _fault_params.get("value", -123.0)
	altered["recruitment_event_hash"] = Kernel.recruitment_event_hash(
		altered, String(_setup_context.get("schema", "")), String(_setup_context.get("version", "")))
	var out: Array[Dictionary] = []
	for event_index in events.size():
		out.append(altered if event_index == index else events[event_index])
	return out

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0
