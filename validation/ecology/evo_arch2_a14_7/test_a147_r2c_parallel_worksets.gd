extends SceneTree
## ECO A14.7 R2 Stage C — EXACT bounded nested A13 worker experiment.
## Compares SAME staged global A4 with batch16 serial (1 nested worker)
## against batch16 + 4 CPU-only detached workset Threads. One A4 global
## authority; canonical member outcomes consumed in historical workset order.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

const SCHEMA := "dws.ecology.a14-7-r2c-parallel-ordered-reduction.v1"
const BATCH := 16
const PARALLEL := 4
const POLL_LIMIT := 12000
const ACCEPTED := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2C_FAILED " + name)

func _manifest() -> Dictionary:
	var h = Lab.new()
	h._build_manifest()
	var m: Dictionary = h.manifest.duplicate(true)
	h.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--r2-population" \
			or not String(args[1]) in ["4", "32", "96", "256"]:
		_check(false, "exact scale required")
		_finish()
		return
	var n: int = int(args[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"historical canonical A14.7 fixture")
	if source.is_empty():
		_finish()
		return
	var bytes_before: String = C.encode(source)
	var controller = Controller.new()
	var init: Dictionary = controller.initialize(_manifest(), {})
	_check(bool(init.get("success", false)), "actual LAB options")
	if not bool(init.get("success", false)):
		_finish()
		return
	var options: Dictionary = controller._canonical_step_options().options
	var baseline: Dictionary = Runtime.step_spatial_parallel_advance(
		source, options, 4, 64, 4, 4)
	_check(bool(baseline.get("success", false)), "accepted global original R13 reference")
	if not bool(baseline.get("success", false)):
		_finish()
		return
	# A bad bound is rejected BEFORE spawning a pool task.
	var bounds = OffMain.new()
	var under: Dictionary = bounds.advance(source, options,
		64, 4096, 8388608, null, null, -1, {}, BATCH, 0)
	var over: Dictionary = bounds.advance(source, options,
		64, 4096, 8388608, null, null, -1, {}, BATCH, 9)
	_check(not bool(under.get("success", true)) and not bool(over.get("success", true))
		and int(bounds.status().jobs_started) == 0,
		"nested workers bound 1 to 8, rejection before dispatch")
	# Two FULL canonical ticks in separate CPU workers; source unchanged.
	var serial: Dictionary = await _run_worker(source, options, 1)
	var parallel: Dictionary = await _run_worker(source, options, PARALLEL)
	if serial.is_empty() or parallel.is_empty():
		_finish()
		return
	var a: Dictionary = serial.result
	var b: Dictionary = parallel.result
	var reference_bytes: String = C.encode(baseline.state)
	var ha: String = Runtime.state_hash(a.state)
	var hb: String = Runtime.state_hash(b.state)
	_check(C.encode(a.state) == reference_bytes \
		and C.encode(b.state) == reference_bytes \
		and ha == String(ACCEPTED[n]) and hb == String(ACCEPTED[n]),
		"full Runtime bytes/hash exact across serial parallel A13 reference")
	var anchor: String = C.digest({
		"schema": "dws.ecology.a14-7-r2c-checkpoint.v1",
		"population": n})
	var ref_check: Dictionary = Checkpoint.create(anchor, baseline.state)
	var serial_check: Dictionary = Checkpoint.create(anchor, a.state)
	var parallel_check: Dictionary = Checkpoint.create(anchor, b.state)
	var exact_ck: bool = not ref_check.is_empty() and \
		not serial_check.is_empty() and not parallel_check.is_empty() \
		and Checkpoint.serialize(ref_check) == Checkpoint.serialize(serial_check) \
		and Checkpoint.serialize(serial_check) == Checkpoint.serialize(parallel_check)
	_check(exact_ck, "A8 full serialized checkpoint original/serial/parallel byte equality")
	_check(C.encode(source) == bytes_before, "immutable source never changed")
	_check(int(a.worker_worksets_per_resume) == BATCH \
		and int(b.worker_worksets_per_resume) == BATCH \
		and int(a.r2c_parallel_workset_workers) == 1 \
		and int(b.r2c_parallel_workset_workers) == PARALLEL,
		"explicit thread bound differs, workset batch and single A4 identical")
	_check(String(a.source_admission_mode) == "FULL_SOURCE_VALIDATE" \
		and String(b.source_admission_mode) == "FULL_SOURCE_VALIDATE",
		"direct CPU service keeps full main-thread final source validation")
	var base_phase: Dictionary = a.worker_phase_profile
	var r2c_phase: Dictionary = b.worker_phase_profile
	_check(int(base_phase.get("allocate_begin_calls", 0)) == 1 \
		and int(r2c_phase.get("allocate_begin_calls", 0)) == 1,
		"EXACTLY one global A4 allocator begin for each worker")
	_check(int(base_phase.get("r2c_parallel_threaded_worksets", -1)) == 0 \
		and int(base_phase.get("r2c_peak_workers", -1)) == 0,
		"historical serial baseline never starts a nested worker")
	if n >= 32:
		_check(int(r2c_phase.get("r2c_peak_workers", 0)) >= 2 \
			and int(r2c_phase.get("r2c_parallel_threaded_worksets", 0)) > 0 \
			and int(r2c_phase.get("r2c_parallel_resume_calls", 0)) > 0,
			"actual multithreaded execution occurred for multiple spatial worksets")
	_check(int(r2c_phase.get("prepare_calls", -1)) == \
		int(base_phase.get("prepare_calls", -2)) \
		and int(r2c_phase.get("advance_calls", -1)) == \
		int(base_phase.get("advance_calls", -2)),
		"same number of stage calls; only per-unit evaluation uses threads")
	_check(int(serial.status.jobs_committed) == 1 and
		int(parallel.status.jobs_committed) == 1 and
		int(serial.status.tasks_joined) == 1 and
		int(parallel.status.tasks_joined) == 1,
		"exactly once join and no task leak for both candidates")
	print("A147_R2C_PARALLEL_PROFILE_JSON " + JSON.stringify({
		"schema": SCHEMA, "population": n,
		"canonical_hash": String(ACCEPTED[n]),
		"checkpoint_equal": exact_ck,
		"source_unchanged": C.encode(source) == bytes_before,
		"serial_worker_wall_us": int(a.worker_wall_us),
		"parallel_worker_wall_us": int(b.worker_wall_us),
		"speedup_ratio": float(a.worker_wall_us) / \
			maxf(1.0, float(b.worker_wall_us)),
		"worksets_per_resume": BATCH,
		"parallel_workers": PARALLEL,
		"serial_phases": base_phase, "parallel_phases": r2c_phase,
		"single_global_allocator": true,
		"untrusted_full_main_validation_preserved": true,
		"canonical_biology_unchanged": true,
		"windows_native_speedup_unproven": true,
		"target_one_second_not_claimed": true,
	}))
	_finish()

func _run_worker(source: Dictionary, options: Dictionary, workers: int) -> Dictionary:
	var task = OffMain.new()
	var first: Dictionary = task.advance(source, options,
		64, 4096, 8388608, null, null, -1, {}, BATCH, workers)
	_check(bool(first.get("success", false)) and task.has_pending(),
		"one actual CPU worker started, nested bound=%d" % workers)
	if not bool(first.get("success", false)):
		return {}
	# Negative: no change in concurrency while a generation is in flight.
	var wrong_workers: int = PARALLEL if workers == 1 else 1
	var changed: Dictionary = task.advance(source, options,
		64, 4096, 8388608, null, null, -1, {}, BATCH, wrong_workers)
	_check(not bool(changed.get("success", true)) \
		and String(changed.get("error", "")) == "R2C_WORKER_BOUND_CHANGED",
		"nested concurrency policy immutable for in-flight generation")
	var complete: Dictionary = {}
	for i in POLL_LIMIT:
		var poll: Dictionary = task.advance(source, options,
			64, 4096, 8388608, null, null, -1, {}, BATCH, workers)
		if not bool(poll.get("success", false)):
			_check(false, "R2C worker failed: " + String(poll.get("error", "?")))
			break
		if bool(poll.get("complete", false)):
			complete = poll
			break
		_check(not poll.has("grants") and not poll.has("state"),
			"pending result never exposes partially allocated resources")
		await create_timer(0.02).timeout
	var status: Dictionary = task.status()
	_check(not complete.is_empty() and
		int(status.jobs_started) == 1 and
		int(status.jobs_committed) == 1 and
		int(status.jobs_failed) == 0 and
		int(status.tasks_joined) == 1 and not bool(status.pending),
		"whole tick completed, worker reaped once without leakage")
	return {"result": complete, "status": status} if not complete.is_empty() else {}

func _finish() -> void:
	print("A147_R2C_PARALLEL checks=%d failed=%d" % [checks, failed])
	print("A147_R2C_PARALLEL " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
