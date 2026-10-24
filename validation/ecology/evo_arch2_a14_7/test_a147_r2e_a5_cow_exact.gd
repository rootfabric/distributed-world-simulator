extends SceneTree
## ECO A14.7 R2 Stage E. Exact frozen Stage D R3 A5 vs phase-local COW.
## Public A5 source digest, full cursor checksum, owner/cap, A4 reference
## and full final Runtime/A8 remain UNCHANGED. Timing is research-only.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const A5 = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Frozen = preload("res://validation/ecology/evo_arch2_a14_7/a147_r2e_frozen_a5_reference.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const HASHES := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const CAP := 8388608
const QUOTA := 4096
const WORKSETS := 16
const NESTED_WORKERS := 4
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2E_FAILED " + label)

func _manifest() -> Dictionary:
	var h = Host.new()
	h._build_manifest()
	var m: Dictionary = h.manifest.duplicate(true)
	h.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["4", "32", "96", "256"]:
		_check(false, "population exact 4/32/96/256")
		_finish()
		return
	var n: int = int(args[1])
	var state: Dictionary = Fixture.new().create_population(n)
	_check(not state.is_empty() and state.population.size() == n, "canonical n source")
	if state.is_empty():
		_finish()
		return
	var source_before: String = C.encode(state)
	var field: Dictionary = state.field
	var population: Array = state.population
	var direct_A13: Dictionary = Lifecycle.step_population_spatial_parallel_advance(
		field, population, String(field.owner_token), int(field.owner_epoch),
		int(field.revision), 4, 64, NESTED_WORKERS, NESTED_WORKERS)
	_check(bool(direct_A13.get("success", false)), "real original parallel A13 lifecycle")
	if not bool(direct_A13.get("success", false)):
		_finish()
		return
	var frozen: Dictionary = _run_lifecycle(Frozen, field, population, false)
	var candidate: Dictionary = _run_lifecycle(A5, field, population, true)
	if frozen.is_empty() or candidate.is_empty():
		_finish()
		return
	var old: Dictionary = frozen.result
	var new: Dictionary = candidate.result
	_check(C.encode(old.field) == C.encode(direct_A13.field) \
		and C.encode(new.field) == C.encode(direct_A13.field),
		"global original A4 full field/ledger/revision bytes exact")
	_check(C.encode(old.population) == C.encode(direct_A13.population) \
		and C.encode(new.population) == C.encode(direct_A13.population) \
		and C.encode(old.propagules) == C.encode(new.propagules) \
		and C.encode(new.propagules) == C.encode(direct_A13.propagules),
		"all A5 organism states/propagules original exact")
	_check(frozen.phases == candidate.phases \
		and frozen.phases == ["PREPARE", "ALLOCATE", "ADVANCE"] \
		and frozen.calls == candidate.calls,
		"same original 3 A5 stages and resume count")
	_check(bool(frozen.immutable) and bool(candidate.immutable),
		"both R2C/R2E previous cursors deeply immutable at EVERY resume")
	_check(C.encode(state) == source_before,
		"source field/population never modified by original or copy-on-write")
	_check(int(candidate.profiled_calls) == int(candidate.calls) \
		and int(candidate.substeps.cursor_verify_us) > 0 \
		and int(candidate.substeps.source_digest_us) > 0 \
		and int(candidate.substeps.cow_copy_us) > 0,
		"new CPU profile records old full cursor and source checks for all calls")
	# Also compare complete whole ecological Runtime and its A8 checkpoint.
	var c = Controller.new()
	var initialization: Dictionary = c.initialize(_manifest(), {})
	_check(bool(initialization.get("success", false)), "real Controller options")
	if not bool(initialization.get("success", false)):
		_finish()
		return
	var options: Dictionary = c._canonical_step_options().options
	var full_original: Dictionary = Runtime.step_spatial_parallel_advance(
		state, options, 4, 64, NESTED_WORKERS, NESTED_WORKERS)
	_check(bool(full_original.get("success", false)), "full original Runtime A5/A4/A6")
	if not bool(full_original.get("success", false)):
		_finish()
		return
	var worker: Dictionary = await _run_profiled_worker(state, options)
	if worker.is_empty():
		_finish()
		return
	var result: Dictionary = worker.receipt
	var accepted_bytes: String = C.encode(full_original.state)
	var accepted_hash: String = Runtime.state_hash(full_original.state)
	_check(C.encode(result.state) == accepted_bytes \
		and Runtime.state_hash(result.state) == accepted_hash \
		and accepted_hash == String(HASHES[n]), "full biology Runtime exact approved hash")
	var anchor: String = C.digest({"schema":"dws.ecology.r2e-a5-cow.v1", "population":n})
	var ck1: Dictionary = Checkpoint.create(anchor, full_original.state)
	var ck2: Dictionary = Checkpoint.create(anchor, result.state)
	var exact_ck: bool = not ck1.is_empty() and not ck2.is_empty() \
		and Checkpoint.serialize(ck1) == Checkpoint.serialize(ck2)
	_check(exact_ck, "full A8 checksum and serialized bytes exact")
	_check(String(result.source_admission_mode) == "FULL_SOURCE_VALIDATE" \
		and result.worker_r2e_profile_enabled \
		and int(worker.status.tasks_joined) == 1 \
		and int(worker.status.jobs_committed) == 1,
		"untrusted full final main source validation and worker join remain")
	var steps: Dictionary = result.worker_phase_profile
	_check(int(steps.get("r2e_profiled_calls", 0)) > 0 \
		and int(steps.get("r2e_runtime_source_validate_us", 0)) > 0 \
		and int(steps.get("r2e_a5_source_digest_us", 0)) > 0,
		"all nested Runtime/A5 source validation still executed")
	print("A147_R2E_A5_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-7-r2e-a5-cow-exact.v1",
		"population": n, "canonical_hash": accepted_hash,
		"exact_a8": exact_ck,
		"frozen_a5_wall_us": int(frozen.wall_us),
		"r2e_a5_wall_us": int(candidate.wall_us),
		"a5_observed_ratio": float(frozen.wall_us) / maxf(1.0, float(candidate.wall_us)),
		"worksets_per_call": WORKSETS,
		"nested_workers": NESTED_WORKERS,
		"same_phase_order": frozen.phases == candidate.phases,
		"same_number_of_calls": frozen.calls == candidate.calls,
		"deep_immutability": bool(frozen.immutable) and bool(candidate.immutable),
		"source_unchanged": C.encode(state) == source_before,
		"cpu_profile": steps,
		"a5_cow_profile": candidate.substeps,
		"worker_wall_us": int(result.worker_wall_us),
		"worker_source_full_validate_us": int(result.worker_source_validate_wall_us),
		"worker_candidate_full_validate_us": int(result.worker_candidate_validate_wall_us),
		"single_global_a4": true,
		"direct_untrusted_full_validation": true,
		"source_checks_disabled": false,
		"checkpoint_formula_changed": false,
		"full_tick_one_second_claim": false,
	}))
	_finish()

func _run_lifecycle(script: Script, field: Dictionary,
		pop: Array, profile: bool) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var begun: Dictionary = script.staged_begin(
		field, pop, String(field.owner_token), int(field.owner_epoch),
		int(field.revision), 4, 64, true)
	_check(bool(begun.get("success", false)), "frozen/new A5 staged begin")
	if not bool(begun.get("success", false)):
		return {}
	var work_us: int = maxi(0, Time.get_ticks_usec() - t0)
	var cursor: Dictionary = begun.cursor
	var phases: Array = []
	var count := 0
	var immutable := true
	var metrics: Dictionary = {"cursor_verify_us": 0, "source_digest_us": 0,
		"cow_copy_us": 0, "result_seal_us": 0}
	var measured := 0
	for i in 4096:
		var current_phase: String = String(cursor.phase)
		if phases.is_empty() or String(phases.back()) != current_phase:
			phases.append(current_phase)
		# Deliberately EXCLUDE test's full C.encode(cursor) from timed A5.
		var before: String = C.encode(cursor)
		var t: int = Time.get_ticks_usec()
		var step: Dictionary = script.staged_resume(
			cursor, field, pop, WORKSETS, QUOTA, CAP, NESTED_WORKERS, profile) if profile \
			else script.staged_resume(
				cursor, field, pop, WORKSETS, QUOTA, CAP, NESTED_WORKERS)
		work_us += maxi(0, Time.get_ticks_usec() - t)
		immutable = immutable and C.encode(cursor) == before
		count += 1
		if not bool(step.get("success", false)):
			_check(false, "A5 original/new stage fails: " + String(step.get("error", "?")))
			break
		if profile:
			var sub: Dictionary = step.get("r2e_profile", {})
			_check(sub.has("source_digest_us") and sub.has("cursor_verify_us"),
				"every R2E CPU profile has nested strict checks")
			for key in metrics:
				metrics[key] = int(metrics[key]) + int(sub.get(key, 0))
			measured += 1
		if bool(step.get("complete", false)):
			return {"result": step, "wall_us": work_us, "calls": count,
				"phases": phases, "immutable": immutable,
				"substeps": metrics, "profiled_calls": measured}
		_check(not step.has("state") and not step.has("grants"),
			"no incomplete canonical state/grants output")
		cursor = step.cursor
	_check(false, "A5 PREPARE/A4/ADVANCE failed to finish")
	return {}

func _run_profiled_worker(source: Dictionary,
		options: Dictionary) -> Dictionary:
	var job = OffMain.new()
	var first: Dictionary = job.advance(source, options, 64, QUOTA, CAP,
		null, null, -1, {}, WORKSETS, NESTED_WORKERS, true)
	_check(bool(first.get("success", false)) and job.has_pending(),
		"opt-in R2E profiling CPU job started")
	if not bool(first.get("success", false)):
		return {}
	var switched: Dictionary = job.advance(source, options, 64, QUOTA, CAP,
		null, null, -1, {}, WORKSETS, NESTED_WORKERS, false)
	_check(not bool(switched.get("success", true)) and
		String(switched.get("error", "")) == "R2E_PROFILER_POLICY_CHANGED",
		"cannot change R2E profiler generation after job dispatch")
	var done: Dictionary = {}
	for i in 12000:
		var poll: Dictionary = job.advance(source, options, 64, QUOTA, CAP,
			null, null, -1, {}, WORKSETS, NESTED_WORKERS, true)
		if not bool(poll.get("success", false)):
			_check(false, "real CPU worker failed: " + String(poll.get("error", "?")))
			break
		if bool(poll.get("complete", false)):
			done = poll
			break
		_check(not poll.has("state") and not poll.has("grants"),
			"CPU worker pending cannot expose speculative biology")
		await create_timer(0.02).timeout
	_check(not done.is_empty() and int(job.status().tasks_joined) == 1 \
		and int(job.status().jobs_failed) == 0,
		"entire instrumented task always joined exactly once")
	return {"receipt":done, "status":job.status()} if not done.is_empty() else {}

func _finish() -> void:
	print("A147_R2E_A5 checks=%d failed=%d" % [checks, failed])
	print("A147_R2E_A5 " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
