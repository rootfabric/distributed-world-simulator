extends SceneTree
## ECO A14.7 R2E3 R1. Real LAB Controller paired proof:
##   E2 owned CPU + old speculative A4 AND original reference
##   E3 owned CPU + ONE ORIGINAL authoritative Field.allocate_demands
## Both MUST match unchanged historical A13 complete Runtime & A8 bytes.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const A5 = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const A4_HASHES := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const POLLS := 12000
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2E3_FAIL " + label)

func _manifest() -> Dictionary:
	var host = Lab.new()
	host._build_manifest()
	var manifest: Dictionary = host.manifest.duplicate(true)
	host.free()
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = false
	return manifest

func _controller(source: Dictionary) -> Object:
	var controller = Controller.new()
	var started: Dictionary = controller.initialize(_manifest(), {})
	_check(bool(started.get("success", false)), "real LAB controller initialized")
	if bool(started.get("success", false)):
		# Test-only source replaced BEFORE any source ownership lease.
		controller._runtime = source.duplicate(true)
	return controller

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["4", "32", "96", "256"]:
		_check(false, "require exact n4/32/96/256 CLI")
		_finish()
		return
	var n: int = int(args[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"historical canonical population fixture")
	if source.is_empty():
		_finish()
		return
	var source_before: String = C.encode(source)
	var reference_controller = _controller(source)
	var step: Dictionary = reference_controller._canonical_step_options()
	_check(bool(step.get("success", false)), "canonical A13 LAB options")
	if not bool(step.get("success", false)):
		_finish()
		return
	var opts: Dictionary = step.options
	var original: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts, 4, 64, 4, 4)
	_check(bool(original.get("success", false)), "authoritative A13 Runtime reference")
	if not bool(original.get("success", false)):
		_finish()
		return

	# Host-independent negative input falsifiers: no caller-provided
	# Boolean may grant single-authority privileges.
	var denied_controller = _controller(source)
	var invalid: Dictionary = denied_controller.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096,
		true, false, false, true)
	_check(not bool(invalid.get("success", true)) and
		String(invalid.get("error", "")) == "CONTROLLER_R2E3_REQUIRES_OWNED_E2",
		"cannot enable original A4 fast without E2 deep owner")
	var direct = OffMain.new()
	var denied: Dictionary = direct.advance(
		source, opts, 64, 4096, 8388608, null, null, -1, {},
		1, 1, false, false, true)
	_check(not bool(denied.get("success", true)) and
		String(denied.get("error", "")) == "R2E3_REQUIRES_DEEP_OWNED_CONTROLLER" \
		and int(direct.status().jobs_started) == 0,
		"direct untrusted E3 refused before spawning CPU pool task")
	var forged: Dictionary = Runtime.resume_staged_global_tick(
		source, opts, {}, 1, 4096, 8388608, 1, false, null, true)
	_check(not bool(forged.get("success", true)) and
		String(forged.get("error", "")) == "RUNTIME_R2E3_REQUIRES_OWNED_WORKER",
		"Runtime public entrypoint cannot skip original staged A4 on a boolean")

	var legacy: Dictionary = await _run_controller(_controller(source), false)
	var fast: Dictionary = await _run_controller(_controller(source), true)
	if legacy.is_empty() or fast.is_empty():
		_finish()
		return
	var old_state: Dictionary = legacy.state
	var new_state: Dictionary = fast.state
	var reference_bytes: String = C.encode(original.state)
	_check(C.encode(old_state) == reference_bytes \
		and C.encode(new_state) == reference_bytes \
		and Runtime.state_hash(old_state) == String(A4_HASHES[n]) \
		and Runtime.state_hash(new_state) == String(A4_HASHES[n]),
		"complete old/new canonical Runtime exact original A13 bytes/hash")
	var anchor: String = C.digest({
		"schema":"dws.ecology.a147-r2e3-original-a4.v1",
		"population": n})
	var orig_ck: Dictionary = Checkpoint.create(anchor, original.state)
	var old_ck: Dictionary = Checkpoint.create(anchor, old_state)
	var new_ck: Dictionary = Checkpoint.create(anchor, new_state)
	var ck_exact: bool = not orig_ck.is_empty() \
		and not old_ck.is_empty() and not new_ck.is_empty() \
		and Checkpoint.serialize(orig_ck) == Checkpoint.serialize(old_ck) \
		and Checkpoint.serialize(old_ck) == Checkpoint.serialize(new_ck)
	_check(ck_exact, "full A8 checkpoints serial bytes exact original/E2/E3")
	_check(C.encode(source) == source_before,
		"original external canonical source untouched")
	var old_status: Dictionary = legacy.telemetry
	var new_status: Dictionary = fast.telemetry
	var old_phase: Dictionary = old_status.last_worker_phase_profile
	var fast_phase: Dictionary = new_status.last_worker_phase_profile
	_check(int(old_phase.get("r2e3_original_global_a4_barriers", -1)) == 0 \
		and int(fast_phase.get("r2e3_original_global_a4_barriers", -1)) == 1,
		"old R2 speculative path 0 E3 barriers, E3 EXACTLY ONE original A4")
	_check(int(old_phase.get("allocate_begin_calls", -1)) == 1 \
		and int(old_phase.get("allocate_resume_calls", -1)) > 0 \
		and int(fast_phase.get("allocate_begin_calls", -1)) == 1 \
		and int(fast_phase.get("allocate_resume_calls", -1)) == 0,
		"E3 does not repeat speculative A4 normalize/claim/primary/residual")
	_check(bool(old_status.last_worker_r2e2_owned_fast) \
		and bool(new_status.last_worker_r2e2_owned_fast) \
		and not bool(old_status.last_worker_r2e3_original_a4) \
		and bool(new_status.last_worker_r2e3_original_a4),
		"E3 explicit opt-in attached to same owned Controller generation")
	_check(int(old_status.last_worker_source_validate_wall_us) > 0 \
		and int(new_status.last_worker_source_validate_wall_us) > 0 \
		and int(old_status.last_worker_candidate_validate_wall_us) > 0 \
		and int(new_status.last_worker_candidate_validate_wall_us) > 0,
		"unchanged final full source+candidate Runtime.validate both paths")
	for data in [old_status, new_status]:
		_check(String(data.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE" \
			and int(data.jobs_started) == 1 and int(data.jobs_committed) == 1 \
			and int(data.tasks_joined) == 1 and int(data.jobs_failed) == 0 \
			and not bool(data.pending) and not bool(data.abandoned_draining),
			"one authoritative tick/adopt per genuine LAB lease, worker joined")
	print("A147_R2E3_ORIGINAL_A4_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a147-r2e3-single-original-a4.v1",
		"population": n, "canonical_hash": String(A4_HASHES[n]),
		"all_original_exact": C.encode(new_state) == reference_bytes,
		"checkpoint_equal": ck_exact,
		"source_unchanged": C.encode(source) == source_before,
		"baseline_e2_worker_wall_us": int(old_status.last_worker_wall_us),
		"single_a4_worker_wall_us": int(new_status.last_worker_wall_us),
		"observed_worker_ratio": float(old_status.last_worker_wall_us) /
			maxf(1.0, float(new_status.last_worker_wall_us)),
		"baseline_host_wall_us": int(legacy.host_wall_us),
		"single_a4_host_wall_us": int(fast.host_wall_us),
		"baseline_phase": old_phase, "single_a4_phase": fast_phase,
		"single_original_a4_barriers": int(fast_phase.r2e3_original_global_a4_barriers),
		"global_original_authority_only": true,
		"public_strict_mode_unchanged": true,
		"direct_untrusted_rejected": true,
		"both_source_and_candidate_fully_validated": true,
		"claim_under_one_second": false,
	}))
	_finish()

func _run_controller(controller: Object, single_a4: bool) -> Dictionary:
	var started_at: int = Time.get_ticks_usec()
	var finished := false
	for i in POLLS:
		var result: Dictionary = controller.run_staged_frame(
			1000000000, 1, 1, 64, 8388608, true, 4096,
			true, false, true, single_a4)
		if not bool(result.get("success", false)):
			_check(false, "Controller staged tick failed: " +
				String(result.get("error", "?")))
			break
		if bool(result.get("complete", false)):
			finished = true
			break
		_check(int(controller.tick()) == 0, "no speculative tick before A4 barrier")
		await create_timer(0.02).timeout
	_check(finished and int(controller.tick()) == 1,
		"completed original globally-coupled A4 + biology whole tick")
	if not finished:
		controller.cancel_staged_tick()
		return {}
	var elapsed: int = maxi(0, Time.get_ticks_usec() - started_at)
	return {"state":controller.debug_state().runtime,
		"host_wall_us":elapsed,"telemetry":controller.get_staged_telemetry().off_main}

func _finish() -> void:
	print("A147_R2E3_ORIGINAL_A4 checks=%d failed=%d" % [checks, failed])
	print("A147_R2E3_ORIGINAL_A4 " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
