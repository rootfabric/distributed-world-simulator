extends RefCounted
## A14.7 R2E2 research: one DEEP-DETACHED, fully validated CPU
## worker-owned source for a single global R3/A4 tick.
##
## This object is instantiated ONLY inside OffMain._compute, never exposed
## to main/GUI, never persisted and never used by untrusted direct callers.
## It is not adversarial authentication against arbitrary code execution
## inside the trusted CPU process. Public Runtime.resume and A5 remain strict.
## No canonical field/grant/organism data is ever written here.
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")

const SCHEMA := "dws.ecology.r2e2-worker-owned-source.v1"

var _admitted := false
var _source: Dictionary = {}
var _options: Dictionary = {}
var _anchor := ""
var _tick := -1
var _options_hash := ""
var _a5_source_fingerprint := ""
var _generation := -1

func admit(input_source: Dictionary, input_options: Dictionary,
		expected_anchor: String, expected_tick: int,
		expected_options_hash: String, generation: int) -> Dictionary:
	if _admitted or Thread.is_main_thread():
		return {"success": false, "error": "R2E2_OWNED_NOT_CPU_WORKER"}
	# All recursive copies are made IN the WorkerThreadPool job. After this
	# deep detach no mutable nested alias exists in the original Controller
	# or direct external caller. The original untrusted state is still
	# admitted against its header on MAIN after the worker fully finishes.
	var copied_at_us: int = Time.get_ticks_usec()
	var candidate_source: Dictionary = input_source.duplicate(true)
	var candidate_options: Dictionary = input_options.duplicate(true)
	var clone_us: int = maxi(0, Time.get_ticks_usec() - copied_at_us)
	var validation_at_us: int = Time.get_ticks_usec()
	var source_error: String = Runtime.validate(candidate_source)
	var source_validation_us: int = maxi(0, Time.get_ticks_usec() - validation_at_us)
	if not source_error.is_empty() or String(candidate_source.get(
			"integrity_hash", "")) != expected_anchor \
			or int(candidate_source.get("tick", -1)) != expected_tick:
		return {"success": false, "error": "R2E2_OWNED_INVALID_SOURCE:" + source_error}
	var options_hash_now: String = C.digest(candidate_options)
	if options_hash_now.is_empty() or options_hash_now != expected_options_hash:
		return {"success": false, "error": "R2E2_OWNED_OPTIONS"}
	var a5_fingerprint: String = C.digest({
		"field": candidate_source.field, "population": candidate_source.population})
	if a5_fingerprint.is_empty():
		return {"success": false, "error": "R2E2_OWNED_A5_FINGERPRINT"}
	_source = candidate_source
	_options = candidate_options
	_anchor = expected_anchor
	_tick = expected_tick
	_options_hash = options_hash_now
	_a5_source_fingerprint = a5_fingerprint
	_generation = generation
	_admitted = true
	return {"success": true, "schema": SCHEMA,
		"deep_clone_us": clone_us,
		"first_full_source_validate_us": source_validation_us,
		"first_a5_source_hash_valid": true,
		"generation": generation}

## These borrowed references remain local to the CPU worker. Never return
## either in a task receipt, snapshot, checkpoint or host status.
func source_for_worker() -> Dictionary:
	return _source if _admitted and not Thread.is_main_thread() else {}

func options_for_worker() -> Dictionary:
	return _options if _admitted and not Thread.is_main_thread() else {}

## Runtime calls this ONLY for the experimental owned CPU fast path.
## Every original outer sealed cursor check still occurs in Runtime,
## every nested A5 and A4 checksum is still verified, including the
## FULL C.digest({field,population}) in A5.staged_resume. The source
## identity/generation is fixed for the entire worker lifecycle.
func _r2e2_owns(source: Dictionary, options: Dictionary,
		cursor: Dictionary) -> bool:
	if not _admitted or Thread.is_main_thread() \
			or not is_same(source, _source) or not is_same(options, _options) \
			or String(source.get("integrity_hash", "")) != _anchor \
			or int(source.get("tick", -1)) != _tick \
			or String(cursor.get("source_hash", "")) != _anchor \
			or String(cursor.get("options_hash", "")) != _options_hash:
		return false
	var lifecycle: Variant = cursor.get("lifecycle", null)
	return lifecycle is Dictionary and String(lifecycle.get(
		"source_hash", "")) == _a5_source_fingerprint

## E3: authorize the ORIGINAL single global A4 allocation exactly once
## at an owned CPU worker's ALLOCATE frontier. A5 still validates the full
## incoming sealed cursor and the detached field+population digest before
## calling this method. No A4 result is returned without accepted Runtime
## final state and worker full source/candidate validation.
func _r2e3_allows_original_a4(source_field: Dictionary,
		source_population: Array, a5_cursor: Dictionary) -> bool:
	if not _admitted or Thread.is_main_thread() or _generation < 0 \
			or not is_same(source_field, _source.get("field", null)) \
			or not is_same(source_population, _source.get("population", null)) \
			or String(_source.get("integrity_hash", "")) != _anchor \
			or String(a5_cursor.get("schema", "")) != \
				"dws.ecology.a5-staged-r3-global-allocator.v1" \
			or String(a5_cursor.get("source_hash", "")) != _a5_source_fingerprint \
			or String(a5_cursor.get("phase", "")) != "ALLOCATE" \
			or int(a5_cursor.get("index", -1)) != 0 \
			or not a5_cursor.get("allocator_cursor", null) is Dictionary:
		return false
	# Only before the original speculative A4 cursor has been started.
	return a5_cursor.allocator_cursor.is_empty()

func source_anchor() -> String:
	return _anchor

func generation() -> int:
	return _generation
