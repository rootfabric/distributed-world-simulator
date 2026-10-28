extends SceneTree
## ECO A14.7 R2 Stage B (EXPERIMENT): 1 workset per resume vs 16.
## BOTH use identical canonical R3.2.3 global R2 staged A4 worker and
## existing strict UNTRUSTED direct-service admission at completion.
## Never claim R2 256 <1s without pinned native 10-minute GUI soak.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

const HASHES := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const POLLS := 12000
const BATCH := 16
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A147_R2B_FAIL " + label)

func _manifest() -> Dictionary:
	var host = Host.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _run() -> void:
	var argv = OS.get_cmdline_user_args()
	if argv.size() != 2 or String(argv[0]) != "--r2-population" \
			or not String(argv[1]) in ["4", "32", "96", "256"]:
		_check(false, "A147_R2B_EXACT_SCALE_REQUIRED")
		_finish()
		return
	var n: int = int(argv[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"exact A14.7 R1 fixture")
	if source.is_empty():
		_finish()
		return
	var before_bytes: String = C.encode(source)
	var c = Controller.new()
	var init: Dictionary = c.initialize(_manifest(), {})
	_check(bool(init.get("success", false)), "LAB Controller options available")
	if not bool(init.get("success", false)):
		_finish()
		return
	var options: Dictionary = c._canonical_step_options().options
	var reference: Dictionary = Runtime.step_spatial_parallel_advance(
		source, options, 4, 64, 4, 4)
	_check(bool(reference.get("success", false)), "accepted serial exact reference")
	if not bool(reference.get("success", false)):
		_finish()
		return
	# Negative parameter falsifiers: neither case may allocate a worker.
	var parameters = OffMain.new()
	var bad_zero: Dictionary = parameters.advance(
		source, options, 64, 4096, 8388608, null, null, -1, {}, 0)
	var bad_large: Dictionary = parameters.advance(
		source, options, 64, 4096, 8388608, null, null, -1, {}, 65)
	_check(not bool(bad_zero.get("success", true)) \
		and not bool(bad_large.get("success", true)) \
		and int(parameters.status().jobs_started) == 0,
		"no unbounded quota or invalid direct worker spawn")
	var old: Dictionary = await _exact_run(source, options, 1)
	var batched: Dictionary = await _exact_run(source, options, BATCH)
	if old.is_empty() or batched.is_empty():
		_finish()
		return
	var a: Dictionary = old.done
	var b: Dictionary = batched.done
	var ref_bytes: String = C.encode(reference.state)
	_check(C.encode(a.state) == ref_bytes \
		and C.encode(b.state) == ref_bytes \
		and Runtime.state_hash(a.state) == String(HASHES[n]) \
		and Runtime.state_hash(b.state) == String(HASHES[n]),
		"both workers exact accepted original canonical Runtime bytes/hash")
	var anchor: String = C.digest({"schema":"dws.ecology.r2b-paired-checkpoint.v1","n":n})
	var serial_ck: Dictionary = Checkpoint.create(anchor, reference.state)
	var old_ck: Dictionary = Checkpoint.create(anchor, a.state)
	var batch_ck: Dictionary = Checkpoint.create(anchor, b.state)
	var checkpoint_exact: bool = not serial_ck.is_empty() and \
		not old_ck.is_empty() and not batch_ck.is_empty() \
		and Checkpoint.serialize(serial_ck) == Checkpoint.serialize(old_ck) \
		and Checkpoint.serialize(old_ck) == Checkpoint.serialize(batch_ck)
	_check(checkpoint_exact, "full A8 checkpoint bytes identical in both")
	_check(C.encode(source) == before_bytes, "immutable shared source unchanged")
	var phases_old: Dictionary = a.worker_phase_profile
	var phases_batch: Dictionary = b.worker_phase_profile
	_check(int(a.worker_worksets_per_resume) == 1 \
		and int(b.worker_worksets_per_resume) == BATCH,
		"batch opt-in pinned, default original 1 unchanged")
	_check(int(phases_old.get("allocate_begin_calls", 0)) == 1 \
		and int(phases_batch.get("allocate_begin_calls", 0)) == 1,
		"one globally coupled R2 A4 stage in both executions")
	_check(int(phases_batch.get("prepare_calls", -1)) <= \
		int(phases_old.get("prepare_calls", -2)) \
		and int(phases_batch.get("advance_calls", -1)) <= \
			int(phases_old.get("advance_calls", -2)),
		"batched processing never adds duplicate PREPARE/ADVANCE calls")
	_check(String(a.source_admission_mode) == "FULL_SOURCE_VALIDATE" \
		and String(b.source_admission_mode) == "FULL_SOURCE_VALIDATE",
		"direct untrusted service keeps full main-thread validation")
	var elapsed_old: int = int(a.worker_wall_us)
	var elapsed_batch: int = int(b.worker_wall_us)
	print("A147_R2B_BATCH_COMPARE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-7-r2b-batching-observation.v1",
		"population": n, "canonical_hash": String(HASHES[n]),
		"checkpoint_equal": checkpoint_exact,
		"source_unchanged": C.encode(source) == before_bytes,
		"old_worker_wall_us": elapsed_old,
		"batch_worker_wall_us": elapsed_batch,
		"worksets_per_resume": BATCH,
		"improvement_ratio": float(elapsed_old) / maxf(1.0, float(elapsed_batch)),
		"old_phase": phases_old, "batch_phase": phases_batch,
		"new_canonical_owner": false,
		"requires_native_windows_exact": true,
		"target_one_second_not_claimed": true,
	} ))
	_finish()

func _exact_run(source: Dictionary, options: Dictionary, quota: int) -> Dictionary:
	var job = OffMain.new()
	var initial: Dictionary = job.advance(
		source, options, 64, 4096, 8388608, null, null, -1, {}, quota)
	_check(bool(initial.get("success", false)) and job.has_pending(),
		"one CPU worker queued worksets_per_resume=%d" % quota)
	if not bool(initial.get("success", false)):
		return {}
	var changed: Dictionary = job.advance(
		source, options, 64, 4096, 8388608, null, null, -1, {}, 1 if quota == BATCH else BATCH)
	_check(not bool(changed.get("success", true)) \
		and String(changed.get("error", "")) == "R2B_WORKSET_BATCH_CHANGED",
		"altering quota during active worker is rejected")
	var done: Dictionary = {}
	for i in POLLS:
		var step: Dictionary = job.advance(
			source, options, 64, 4096, 8388608, null, null, -1, {}, quota)
		if not bool(step.get("success", false)):
			_check(false, "worker failed:" + String(step.get("error", "?")))
			break
		if bool(step.get("complete", false)):
			done = step
			break
		_check(not step.has("state") and not step.has("grants"),
			"no partial grants or state through staged session")
		await create_timer(0.02).timeout
	_check(not done.is_empty() and int(job.status().tasks_joined) == 1 \
		and int(job.status().jobs_committed) == 1 and
		int(job.status().jobs_failed) == 0,
		"one fully reaped worker and no hidden errors")
	return {"done": done} if not done.is_empty() else {}

func _finish() -> void:
	print("A147_R2B_BATCH checks=%d failed=%d" % [checks, failures])
	print("A147_R2B_BATCH " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
