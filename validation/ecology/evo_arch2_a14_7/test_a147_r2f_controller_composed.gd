extends SceneTree
## A14.7 R2F P1 review closure — actual LAB Controller, E2 owned source
## and original E3 global A4, combined Stage B batch16 and Stage C
## nested4. Legacy 1/1 remains default OFF. Exactly one canonical tick.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const ACCEPTED := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const POLL_LIMIT := 12000
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A147_R2F_COMPOSE_FAIL " + why)

func _manifest() -> Dictionary:
	var lab = Lab.new()
	lab._build_manifest()
	var m: Dictionary = lab.manifest.duplicate(true)
	lab.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _controller(source: Dictionary) -> Object:
	var controller = Controller.new()
	var started: Dictionary = controller.initialize(_manifest(), {})
	check(bool(started.get("success", false)), "real LAB initialized")
	if bool(started.get("success", false)):
		controller._runtime = source.duplicate(true)
	return controller

func _run() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() != 2 or String(argv[0]) != "--population" \
			or not String(argv[1]) in ["4", "32", "96", "256"]:
		check(false, "require exact n4/32/96/256")
		_finish()
		return
	var n: int = int(argv[1])
	var source: Dictionary = Fixture.new().create_population(n)
	check(not source.is_empty() and source.population.size() == n, "historical fixture")
	if source.is_empty():
		_finish()
		return
	var before: String = C.encode(source)
	var ref_controller = _controller(source)
	var opts: Dictionary = ref_controller._canonical_step_options().options
	var original: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts, 4, 64, 4, 4)
	check(bool(original.get("success", false)), "unmodified A13 authoritative reference")
	if not bool(original.get("success", false)):
		_finish()
		return
	var invalid_ctrl = _controller(source)
	var bad_count: Dictionary = invalid_ctrl.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096,
		true, false, true, true, 65, 4)
	var bad_workers: Dictionary = invalid_ctrl.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096,
		true, false, true, true, 16, 9)
	var unauthorized: Dictionary = invalid_ctrl.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096,
		true, false, false, false, 16, 4)
	check(not bool(bad_count.get("success", true)) \
		and String(bad_count.get("error", "")) == "CONTROLLER_R2F_WORKSET_POLICY" \
		and not bool(bad_workers.get("success", true)) \
		and String(bad_workers.get("error", "")) == "CONTROLLER_R2F_WORKSET_POLICY" \
		and not bool(unauthorized.get("success", true)) \
		and String(unauthorized.get("error", "")) == "CONTROLLER_R2F_REQUIRES_OWNED_E3" \
		and not invalid_ctrl.has_pending_staged_tick() \
		and int(invalid_ctrl.get_staged_telemetry().off_main.jobs_started) == 0,
		"bounds and privilege rejected BEFORE LAB task dispatch")
	var old: Dictionary = await _run_controller(_controller(source), 1, 1)
	var combined: Dictionary = await _run_controller(_controller(source), 16, 4)
	if old.is_empty() or combined.is_empty():
		_finish()
		return
	var reference_bytes: String = C.encode(original.state)
	check(C.encode(old.state) == reference_bytes \
		and C.encode(combined.state) == reference_bytes \
		and Runtime.state_hash(old.state) == String(ACCEPTED[n]) \
		and Runtime.state_hash(combined.state) == String(ACCEPTED[n]),
		"both complete global Runtime states byte-exact original A13 hash")
	var anchor: String = C.digest({"schema":"dws.ecology.a147-r2f-composed.v1","population":n})
	var cp_ref: Dictionary = Checkpoint.create(anchor, original.state)
	var cp_old: Dictionary = Checkpoint.create(anchor, old.state)
	var cp_new: Dictionary = Checkpoint.create(anchor, combined.state)
	var exact_ck: bool = not cp_ref.is_empty() and not cp_old.is_empty() \
		and not cp_new.is_empty() \
		and Checkpoint.serialize(cp_ref) == Checkpoint.serialize(cp_old) \
		and Checkpoint.serialize(cp_old) == Checkpoint.serialize(cp_new)
	check(exact_ck, "entire serialized A8 checkpoint byte equality")
	check(C.encode(source) == before, "source deeply immutable after all candidates")
	var oa: Dictionary = old.telemetry
	var ca: Dictionary = combined.telemetry
	check(int(oa.last_worker_worksets_per_resume) == 1 \
		and int(oa.last_r2c_parallel_workset_workers) == 1 \
		and int(ca.last_worker_worksets_per_resume) == 16 \
		and int(ca.last_r2c_parallel_workset_workers) == 4,
		"real Controller forwarded 1/1 vs 16/4 to frozen CPU worker")
	for task in [oa, ca]:
		var phase: Dictionary = task.last_worker_phase_profile
		check(int(phase.get("r2e3_original_global_a4_barriers", -1)) == 1 \
			and int(phase.get("allocate_begin_calls", -1)) == 1 \
			and int(phase.get("allocate_resume_calls", -1)) == 0 \
			and String(task.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE" \
			and bool(task.last_worker_r2e2_owned_fast) \
			and bool(task.last_worker_r2e3_original_a4) \
			and int(task.last_worker_source_validate_wall_us) > 0 \
			and int(task.last_worker_candidate_validate_wall_us) > 0 \
			and int(task.jobs_started) == 1 and int(task.jobs_committed) == 1 \
			and int(task.tasks_joined) == 1 and int(task.jobs_failed) == 0,
			"one fully validated original A4 and exactly one joined canonical tick")
	var fast: Dictionary = ca.last_worker_phase_profile
	if n >= 96:
		check(int(fast.get("r2c_parallel_threaded_worksets", 0)) > 0 \
			and int(fast.get("r2c_peak_workers", 0)) >= 2,
			"actual nested A13 parallelism executed in real Controller")
	check(int(oa.last_worker_phase_profile.get("r2c_parallel_threaded_worksets", 0)) == 0,
		"legacy 1/1 did not activate nested workers")
	print("A147_R2F_COMPOSE_JSON " + JSON.stringify({
		"schema":"dws.ecology.a147-r2f-composed-controller.v1",
		"population":n, "canonical_hash":String(ACCEPTED[n]),
		"checkpoint_exact":exact_ck,
		"source_unchanged":C.encode(source) == before,
		"legacy_worker_wall_us":int(oa.last_worker_wall_us),
		"composed_worker_wall_us":int(ca.last_worker_wall_us),
		"ratio":float(oa.last_worker_wall_us) / maxf(1.0,float(ca.last_worker_wall_us)),
		"legacy_worksets_per_resume":int(oa.last_worker_worksets_per_resume),
		"new_worksets_per_resume":int(ca.last_worker_worksets_per_resume),
		"legacy_nested_workers":int(oa.last_r2c_parallel_workset_workers),
		"new_nested_workers":int(ca.last_r2c_parallel_workset_workers),
		"new_phase":fast,"one_authoritative_a4":true,
		"direct_untrusted_fast_default_off":true,
		"fully_validated_source_and_candidate":true,
		"subsecond_not_proven":true,
	}))
	_finish()

func _run_controller(c: Object, worksets: int, workers: int) -> Dictionary:
	var complete := false
	for i in POLL_LIMIT:
		var step: Dictionary = c.run_staged_frame(
			1000000000, 1, 1, 64, 8388608, true, 4096,
			true, false, true, true, worksets, workers)
		if not bool(step.get("success", false)):
			check(false, "real staged worker returned error: " + String(step.get("error","?")))
			break
		if bool(step.get("complete", false)):
			complete = true
			break
		check(c.tick() == 0, "no partial grants or tick before joined worker")
		await create_timer(0.02).timeout
	check(complete and c.tick() == 1, "real Controller exactly one completed global tick")
	if not complete:
		c.cancel_staged_tick()
		return {}
	return {"state": c.debug_state().runtime,
		"telemetry": c.get_staged_telemetry().off_main}

func _finish() -> void:
	print("A147_R2F_COMPOSE checks=%d failed=%d" % [checks,failures])
	print("A147_R2F_COMPOSE " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
