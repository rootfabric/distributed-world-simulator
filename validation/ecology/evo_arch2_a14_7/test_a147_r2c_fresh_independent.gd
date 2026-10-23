extends SceneTree
## A14.7 R2C FRESH independent verifier. Test-only direct child of the
## FROZEN PRODUCT HEAD, no product source edits.
## Separately exercises the public A5 Lifecycle staged contract and
## accepted A13 parallel-advance equivalence, including negative security.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var errors := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error("A147_R2C_FRESH_FAIL " + label)

func _manifest() -> Dictionary:
	var h = Host.new()
	h._build_manifest()
	var m: Dictionary = h.manifest.duplicate(true)
	h.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["32", "96"]:
		_check(false, "independent test requires 32 or 96")
		_finish()
		return
	var n: int = int(args[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty(), "valid canonical independent fixture")
	if source.is_empty():
		_finish()
		return
	var source_bytes: String = C.encode(source)
	var field: Dictionary = source.field
	var pop: Array = source.population
	var canonical: Dictionary = Lifecycle.step_population_spatial_parallel_advance(
		field, pop, String(field.owner_token), int(field.owner_epoch),
		int(field.revision), 4, 64, 4, 4)
	_check(bool(canonical.get("success", false)), "accepted A13 original A5 parallel full-step reference")
	if not bool(canonical.get("success", false)):
		_finish()
		return
	var launched: Dictionary = Lifecycle.staged_begin(
		field, pop, String(field.owner_token), int(field.owner_epoch),
		int(field.revision), 4, 64, true)
	_check(bool(launched.get("success", false)), "A5 R3 staged lifecycle begins")
	if not bool(launched.get("success", false)):
		_finish()
		return
	var header: Dictionary = launched.cursor
	var tampered: Dictionary = header.duplicate(true)
	tampered.index = 777
	var reject: Dictionary = Lifecycle.staged_resume(
		tampered, field, pop, 16, 4096, 8388608, 4)
	_check(not bool(reject.get("success", true)) \
		and String(reject.get("error", "")).contains("CHECKSUM"),
		"nested A5 cursor tamper rejected before speculative work")
	var invalid_bound: Dictionary = Lifecycle.staged_resume(
		header, field, pop, 16, 4096, 8388608, 9)
	_check(not bool(invalid_bound.get("success", true)),
		"invalid concurrency limit rejected before work")
	var cursor: Dictionary = header
	var results: Dictionary = {}
	var threaded_worksets := 0
	var peak_parallel := 0
	var a4_begins := 0
	var transition_order: Array = []
	for i in 4096:
		var phase: String = String(cursor.phase)
		if transition_order.is_empty() or transition_order.back() != phase:
			transition_order.append(phase)
		if phase == "ALLOCATE" and cursor.allocator_cursor.is_empty():
			a4_begins += 1
		var step: Dictionary = Lifecycle.staged_resume(
			cursor, field, pop, 16, 4096, 8388608, 4)
		_check(bool(step.get("success", false)),
			"R2C lifecycle step succeeds:" + String(step.get("error", "")))
		if not bool(step.get("success", false)):
			break
		threaded_worksets += int(step.get("r2c_threaded_worksets", 0))
		peak_parallel = maxi(peak_parallel, int(step.get("r2c_peak_workers", 0)))
		if bool(step.get("complete", false)):
			results = step
			break
		_check(not step.has("field") and not step.has("population")
			and not step.has("grants") and step.has("cursor"),
			"no canonical field/population/grants in incomplete CPU work")
		cursor = step.cursor
	_check(not results.is_empty(), "A5 complete globally staged tick")
	if results.is_empty():
		_finish()
		return
	_check(transition_order == ["PREPARE", "ALLOCATE", "ADVANCE"]
		and a4_begins == 1,
		"immutable phase order PREPARE→SINGLE A4→ADVANCE")
	_check(peak_parallel >= 2 and threaded_worksets >= 2,
		"actual nested worker threads evaluated in parallel")
	_check(C.encode(results.field) == C.encode(canonical.field) \
		and C.encode(results.population) == C.encode(canonical.population) \
		and C.encode(results.propagules) == C.encode(canonical.propagules),
		"independent exact full field/population/propagule output, not only state hash")
	_check(C.encode(source) == source_bytes, "no source mutation during lifecycle threads")
	await _late_nested_source_tamper(source, n)
	await _cancel_after_finished(source, n)
	print("A147_R2C_FRESH_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a147-r2c-independent-falsifier.v1",
		"population": n, "peak_nested_workers": peak_parallel,
		"threaded_worksets": threaded_worksets, "a4_begins": a4_begins,
		"exact_field": C.encode(results.field) == C.encode(canonical.field),
		"exact_population": C.encode(results.population) == C.encode(canonical.population),
		"exact_propagules": C.encode(results.propagules) == C.encode(canonical.propagules),
		"source_unchanged": C.encode(source) == source_bytes,
	}))
	_finish()

func _options() -> Dictionary:
	var c = Controller.new()
	var r: Dictionary = c.initialize(_manifest(), {})
	_check(bool(r.get("success", false)), "real canonical options fixture")
	return c._canonical_step_options().options if bool(r.get("success", false)) else {}

func _late_nested_source_tamper(source: Dictionary, n: int) -> void:
	var opts: Dictionary = _options()
	if opts.is_empty():
		return
	var copy: Dictionary = source.duplicate(true)
	var s = OffMain.new()
	var begun: Dictionary = s.advance(copy, opts, 64, 4096, 8388608,
		null, null, -1, {}, 16, 4)
	_check(bool(begun.get("success", false)), "late source tamper: worker starts")
	if not bool(begun.get("success", false)):
		return
	var ready := false
	for i in 12000:
		if WorkerThreadPool.is_task_completed(s._task_id):
			ready = true
			break
		await create_timer(0.02).timeout
	_check(ready, "late source tamper: FULL worker finishes before attack")
	if not ready:
		s.cancel()
		return
	var previous_hash: String = String(copy.integrity_hash)
	var previous_tick: int = int(copy.tick)
	copy.population[0].state.age_ticks = int(copy.population[0].state.age_ticks) + 1
	_check(String(copy.integrity_hash) == previous_hash and int(copy.tick) == previous_tick,
		"adversarial nested mutation leaves headers unchanged")
	var denied: Dictionary = s.advance(copy, opts, 64, 4096, 8388608,
		null, null, -1, {}, 16, 4)
	_check(not bool(denied.get("success", true)) \
		and String(denied.get("error", "")).begins_with("R3_ASYNC_SOURCE_INVALID:") \
		and not denied.has("state") and not denied.has("grants"),
		"full direct-service main admission rejects late nested source mutation")
	_check(int(s.status().jobs_committed) == 0 and int(s.status().tasks_joined) == 1,
		"mutated source never publishes and still joins CPU task exactly once")

func _cancel_after_finished(source: Dictionary, n: int) -> void:
	var opts: Dictionary = _options()
	if opts.is_empty():
		return
	var s = OffMain.new()
	var begin: Dictionary = s.advance(source, opts, 64, 4096, 8388608,
		null, null, -1, {}, 16, 4)
	_check(bool(begin.get("success", false)), "late cancel: worker starts")
	if not bool(begin.get("success", false)):
		return
	var ready := false
	for i in 12000:
		if WorkerThreadPool.is_task_completed(s._task_id):
			ready = true
			break
		await create_timer(0.02).timeout
	_check(ready, "late cancel after completed worker payload")
	if not ready:
		s.cancel()
		return
	_check(s.cancel(), "late cancel revokes speculative result")
	_check(s.reap_discarded(), "cancelled native task is drained without main blocking")
	var st: Dictionary = s.status()
	_check(int(st.jobs_committed) == 0 and int(st.tasks_joined) == 1 \
		and int(st.jobs_abandoned) == 1 \
		and not bool(st.pending) and not bool(st.abandoned_draining),
		"late cancel result cannot publish, one join, zero leaks")

func _finish() -> void:
	print("A147_R2C_FRESH checks=%d failed=%d" % [checks, errors])
	print("A147_R2C_FRESH " + ("PASS" if errors == 0 else "FAIL"))
	quit(0 if errors == 0 else 1)
