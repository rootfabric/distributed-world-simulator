extends SceneTree
## Fresh TEST-ONLY adversarial check on frozen A14.7 R2F 9a1a986.
## Do not import the product R2F tests. No product source edits.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Session = preload("res://scripts/ecology/workbench/staged_frame_session_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const MAX_POLLS := 5000

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A147_R2F_FRESH_POLICY_FAIL " + reason)

func _controller(source: Dictionary) -> Object:
	var lab = Lab.new()
	lab._build_manifest()
	var manifest: Dictionary = lab.manifest.duplicate(true)
	lab.free()
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = true
	manifest.mutation.operator = "module_parameter"
	var c = Controller.new()
	var init: Dictionary = c.initialize(manifest, {})
	_check(bool(init.get("success", false)), "LAB initializes")
	if bool(init.get("success", false)):
		c._runtime = source.duplicate(true)
	return c

func _call(c: Object, batch: int, workers: int,
		e2: bool = true, e3: bool = true,
		offmain: bool = true, allocator: bool = true) -> Dictionary:
	return c.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, allocator, 4096,
		offmain, false, e2, e3, batch, workers)

func _drain(c: Object) -> bool:
	for i in MAX_POLLS:
		c.reap_cancelled_staged_worker()
		if not bool(c.get_staged_telemetry().off_main.abandoned_draining):
			return true
		await create_timer(0.02).timeout
	return false

func _run() -> void:
	var source: Dictionary = Fixture.new().create_population(32)
	_check(not source.is_empty() and Runtime.validate(source).is_empty(),
		"unaltered original A13 32-organism fixture")
	if source.is_empty():
		_finish({})
		return
	var original_bytes: String = C.encode(source)
	var denied = _controller(source)
	var opts: Dictionary = denied._canonical_step_options().options
	# Numeric bounds and authorization take precedence over any job/lease.
	var cases := [
		[0, 4, true, true, "CONTROLLER_R2F_WORKSET_POLICY"],
		[65, 4, true, true, "CONTROLLER_R2F_WORKSET_POLICY"],
		[16, 0, true, true, "CONTROLLER_R2F_WORKSET_POLICY"],
		[16, 9, true, true, "CONTROLLER_R2F_WORKSET_POLICY"],
		[0, 9, false, false, "CONTROLLER_R2F_WORKSET_POLICY"],
		[16, 4, false, false, "CONTROLLER_R2F_REQUIRES_OWNED_E3"],
		[16, 4, true, false, "CONTROLLER_R2F_REQUIRES_OWNED_E3"],
		[16, 4, false, true, "CONTROLLER_R2F_REQUIRES_OWNED_E3"],
	]
	for row in cases:
		var outcome: Dictionary = _call(denied,
			int(row[0]), int(row[1]), bool(row[2]), bool(row[3]))
		_check(not bool(outcome.get("success", true))
			and String(outcome.get("error", "")) == String(row[4]),
			"fail-before-spawn bound/authorization %s" % [str(row)])
	_check(int(denied.get_staged_telemetry().off_main.jobs_started) == 0
		and not denied.has_pending_staged_tick()
		and C.encode(denied._runtime) == original_bytes,
		"invalid entries never lease, dispatch or mutate source")

	# Check host-private session and direct public worker cannot invent a
	# valid E2/E3 lease merely by supplying fast-policy arguments.
	var direct_session = Session.new()
	var no_lease: Dictionary = direct_session.advance(
		source, opts, 30000, 1, 1, 64, 8388608,
		true, 4096, true, null, null, -1, {}, true, true, 16, 4)
	_check(not bool(no_lease.get("success", true))
		and String(no_lease.get("error", "")) ==
			"R2E2_STAGED_REQUIRES_CONTROLLER_LEASE"
		and int(direct_session.status().off_main.jobs_started) == 0,
		"host-private Session cannot dispatch a fake owned E3 generation")
	var direct_worker = OffMain.new()
	var no_owner: Dictionary = direct_worker.advance(
		source, opts, 64, 4096, 8388608,
		null, null, -1, {}, 16, 4, false, true, true)
	_check(not bool(no_owner.get("success", true))
		and String(no_owner.get("error", "")) == "R2E2_REQUIRES_CONTROLLER_LEASE"
		and int(direct_worker.status().jobs_started) == 0,
		"public OffMain cannot bypass exclusive LAB lease")

	var c = _controller(source)
	var opts2: Dictionary = c._canonical_step_options().options
	var original: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts2, 4, 64, 4, 4)
	_check(bool(original.get("success", false)),
		"independent full original A13 reference successful")
	if not bool(original.get("success", false)):
		_finish({})
		return
	var anchor: Dictionary = c.serialize_state()
	_check(bool(anchor.get("success", false)), "external A8 checkpoint before work")
	if not bool(anchor.get("success", false)):
		_finish({})
		return
	# Test both independently frozen knobs. A rejected change must
	# abandon an in-flight generation; it may never publish partial A4.
	for axis in ["batch", "workers"]:
		var first: Dictionary = _call(c, 16, 4)
		_check(bool(first.get("success", false))
			and bool(first.get("pending", false))
			and not bool(first.get("complete", true))
			and c.tick() == 0, "real 16/4 leased worker initially pending")
		if not bool(first.get("success", false)):
			_finish({})
			return
		var illegal: Dictionary = _call(c, 8 if axis == "batch" else 16,
			4 if axis == "batch" else 2)
		var suffix: String = "R2B_WORKSET_BATCH_CHANGED" if axis == "batch" 			else "R2C_WORKER_BOUND_CHANGED"
		_check(not bool(illegal.get("success", true))
			and String(illegal.get("error", "")) ==
				"CONTROLLER_STAGED:STAGED_SESSION_OFFMAIN:" + suffix,
			"mid-flight " + axis + " mutation rejects frozen generation")
		var t: Dictionary = c.get_staged_telemetry().off_main
		_check(int(t.jobs_abandoned) == (1 if axis == "batch" else 2)
			and int(t.jobs_committed) == 0
			and c.tick() == 0 and C.encode(c._runtime) == original_bytes,
			"rejected " + axis + " cannot partially adopt global field/grants")
		var drained: bool = await _drain(c)
		_check(drained and not c.has_pending_staged_tick(),
			"rejected generation joined without creating a zombie task")
		if not drained:
			_finish({})
			return
	# Revoked generations cannot be accidentally resumed. Restore the
	# same externally anchored original checkpoint into the real Controller.
	var restored: Dictionary = c.load_state(
		String(anchor.state_text), String(anchor.manifest_hash),
		String(anchor.state_checksum))
	_check(bool(restored.get("success", false))
		and c.tick() == 0 and C.encode(c._runtime) == original_bytes,
		"external A8 restore after two abandoned work generations")
	if not bool(restored.get("success", false)):
		_finish({})
		return
	var committed := false
	for i in MAX_POLLS:
		var next: Dictionary = _call(c, 16, 4)
		if not bool(next.get("success", false)):
			_check(false, "restored generation rejected: " +
				String(next.get("error", "?")))
			break
		if bool(next.get("complete", false)):
			committed = true
			break
		_check(c.tick() == 0 and C.encode(c._runtime) == original_bytes,
			"no early Runtime/grants adoption while final CPU worker pending")
		await create_timer(0.02).timeout
	_check(committed and c.tick() == 1, "restored generation fully adopted once")
	if not committed:
		c.cancel_staged_tick()
		_finish({})
		return
	var actual: Dictionary = c.debug_state().runtime
	var canonical_equal: bool = C.encode(actual) == C.encode(original.state) 		and Runtime.state_hash(actual) == Runtime.state_hash(original.state)
	_check(canonical_equal, "whole canonical A13 Runtime byte-for-byte identical")
	var checkpoint_id: String = C.digest({
		"schema": "dws.ecology.a147-r2f-fresh-policy.v1", "population": 32})
	var expected_cp: Dictionary = Checkpoint.create(checkpoint_id, original.state)
	var actual_cp: Dictionary = Checkpoint.create(checkpoint_id, actual)
	var a8_equal: bool = not expected_cp.is_empty() 		and not actual_cp.is_empty() 		and Checkpoint.serialize(expected_cp) == Checkpoint.serialize(actual_cp)
	_check(a8_equal, "full A8 checkpoint equal after policy failures and restore")
	var telemetry: Dictionary = c.get_staged_telemetry().off_main
	var phases: Dictionary = telemetry.last_worker_phase_profile
	_check(int(telemetry.jobs_started) == 3
		and int(telemetry.jobs_abandoned) == 2
		and int(telemetry.jobs_committed) == 1
		and int(telemetry.tasks_joined) == 3
		and int(telemetry.jobs_failed) == 0
		and not bool(telemetry.pending)
		and not bool(telemetry.abandoned_draining),
		"exactly 2 abandoned, 1 committed, 3 joined tasks, zero leaked jobs")
	_check(int(telemetry.last_worker_worksets_per_resume) == 16
		and int(telemetry.last_r2c_parallel_workset_workers) == 4
		and bool(telemetry.last_worker_r2e2_owned_fast)
		and bool(telemetry.last_worker_r2e3_original_a4)
		and int(phases.get("r2e3_original_global_a4_barriers", -1)) == 1
		and int(phases.get("allocate_resume_calls", -1)) == 0
		and int(telemetry.last_worker_source_validate_wall_us) > 0
		and int(telemetry.last_worker_candidate_validate_wall_us) > 0,
		"new generation 16/4 actually executed exactly one original A4")
	_check(C.encode(source) == original_bytes,
		"external canonical fixture immutable throughout hostile operations")
	_finish({
		"schema": "dws.ecology.a147-r2f-fresh-policy.v1",
		"population": 32,
		"canonical_equal": canonical_equal, "checkpoint_equal": a8_equal,
		"jobs_started": int(telemetry.jobs_started),
		"jobs_abandoned": int(telemetry.jobs_abandoned),
		"jobs_committed": int(telemetry.jobs_committed),
		"tasks_joined": int(telemetry.tasks_joined),
		"one_original_a4":
			int(phases.get("r2e3_original_global_a4_barriers", -1)) == 1,
		"full_source_validation":
			int(telemetry.last_worker_source_validate_wall_us) > 0,
		"full_candidate_validation":
			int(telemetry.last_worker_candidate_validate_wall_us) > 0,
	})

func _finish(receipt: Dictionary) -> void:
	print("A147_R2F_FRESH_POLICY_JSON " + JSON.stringify(receipt))
	print("A147_R2F_FRESH_POLICY checks=%d failed=%d" % [checks, failures])
	print("A147_R2F_FRESH_POLICY " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
