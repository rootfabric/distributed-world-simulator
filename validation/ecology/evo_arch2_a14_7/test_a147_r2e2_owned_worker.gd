extends SceneTree
## ECO A14.7 R2 Stage E2 experimental, LAB-only.
## Real Controller exact pair: original R3 single worker with full public
## Runtime.validate each resume vs deep-detached worker-owned source.
## Public/untrusted OffMain cannot opt-in. No global A4/biology schema change.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

const HASHES := {
	4:"7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32:"62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96:"23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256:"f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const POLL_MAX := 12000
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2E2_FAIL " + label)

func _manifest() -> Dictionary:
	var h = Host.new()
	h._build_manifest()
	var manifest: Dictionary = h.manifest.duplicate(true)
	h.free()
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = false
	return manifest

func _controller(source: Dictionary) -> Object:
	var c = Controller.new()
	var initialized: Dictionary = c.initialize(_manifest(), {})
	_check(bool(initialized.get("success", false)), "LAB-only original Controller initialized")
	if bool(initialized.get("success", false)):
		# Research fixture injection BEFORE the Controller creates any
		# exclusive source lease. Original input remains deeply detached.
		c._runtime = source.duplicate(true)
	return c

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["4", "32", "96", "256"]:
		_check(false, "required fresh 4/32/96/256 population")
		_finish()
		return
	var n: int = int(args[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"same accepted canonical R1 population exact")
	if source.is_empty():
		_finish()
		return
	var original_source: String = C.encode(source)
	var ref_controller = _controller(source)
	var opts: Dictionary = ref_controller._canonical_step_options()
	_check(bool(opts.get("success", false)), "original LAB options")
	if not bool(opts.get("success", false)):
		_finish()
		return
	var reference: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts.options, 4, 64, 4, 4)
	_check(bool(reference.get("success", false)), "accepted original full global tick")
	if not bool(reference.get("success", false)):
		_finish()
		return
	# No direct untrusted bypass. Even a syntactically valid, mutable A5
	# source is NOT eligible to invoke the leased owned-worker fast path.
	var direct = OffMain.new()
	var denied: Dictionary = direct.advance(
		source, opts.options, 64, 4096, 8388608,
		null, null, -1, {}, 1, 1, false, true)
	_check(not bool(denied.get("success", true)) \
		and String(denied.get("error", "")) == "R2E2_REQUIRES_CONTROLLER_LEASE" \
		and int(direct.status().jobs_started) == 0,
		"untrusted direct source cannot request owned fast lease")
	var wrong_mode = _controller(source)
	var wrongly_enabled: Dictionary = wrong_mode.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096,
		false, false, true)
	_check(not bool(wrongly_enabled.get("success", true)) \
		and String(wrongly_enabled.get("error", "")) == \
			"CONTROLLER_R2E2_REQUIRES_R3_OFFMAIN",
		"fast owned worker disallowed without real staged R3")
	var strict: Dictionary = await _execute(_controller(source), false)
	var owned: Dictionary = await _execute(_controller(source), true)
	if strict.is_empty() or owned.is_empty():
		_finish()
		return
	var strict_state: Dictionary = strict.canonical
	var fast_state: Dictionary = owned.canonical
	var ref_bytes: String = C.encode(reference.state)
	_check(C.encode(strict_state) == ref_bytes \
		and C.encode(fast_state) == ref_bytes \
		and Runtime.state_hash(strict_state) == String(HASHES[n]) \
		and Runtime.state_hash(fast_state) == String(HASHES[n]),
		"FULL Runtime field/grants/pop/feedback/outbox exact original approved hash")
	var anchor: String = C.digest({
		"schema":"dws.ecology.a147-r2e2-comparison.v1","population":n})
	var ref_ck: Dictionary = Checkpoint.create(anchor, reference.state)
	var strict_ck: Dictionary = Checkpoint.create(anchor, strict_state)
	var fast_ck: Dictionary = Checkpoint.create(anchor, fast_state)
	var ck_exact: bool = not ref_ck.is_empty() and not strict_ck.is_empty() \
		and not fast_ck.is_empty() and
		Checkpoint.serialize(ref_ck) == Checkpoint.serialize(strict_ck) \
		and Checkpoint.serialize(strict_ck) == Checkpoint.serialize(fast_ck)
	_check(ck_exact, "original A8 full serialized checkpoint byte exact")
	_check(C.encode(source) == original_source,
		"untrusted original fixture cannot be mutated by both workers")
	var strict_status: Dictionary = strict.telemetry
	var owned_status: Dictionary = owned.telemetry
	_check(String(strict_status.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE" \
		and String(owned_status.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE",
		"both variants originate from actual exclusive LAB Controller")
	_check(not bool(strict_status.last_worker_r2e2_owned_fast) \
		and bool(owned_status.last_worker_r2e2_owned_fast),
		"owned fast path explicitly opt-in and frozen per generation")
	var phases: Dictionary = owned_status.last_worker_phase_profile
	_check(bool(phases.get("r2e2_owned_lease_admitted", false)) \
		and int(phases.get("r2e2_initial_full_source_validate_us", 0)) > 0 \
		and int(phases.get("r2e2_deep_detach_us", -1)) >= 0,
		"real deep clone and FULL source validation before worker-owned resume")
	_check(int(strict_status.last_worker_source_validate_wall_us) > 0 \
		and int(strict_status.last_worker_candidate_validate_wall_us) > 0 \
		and int(owned_status.last_worker_source_validate_wall_us) > 0 \
		and int(owned_status.last_worker_candidate_validate_wall_us) > 0,
		"both source+candidate fully revalidated at FINAL worker gate")
	_check(int(strict_status.jobs_committed) == 1 \
		and int(owned_status.jobs_committed) == 1 \
		and int(strict_status.tasks_joined) == 1 \
		and int(owned_status.tasks_joined) == 1,
		"one global canonical commit and worker join in each variant")
	print("A147_R2E2_OWNED_PROFILE_JSON " + JSON.stringify({
		"schema":"dws.ecology.a147-r2e2-owned-worker-fast.v1",
		"population":n,"canonical_hash":String(HASHES[n]),
		"original_exact": C.encode(fast_state) == ref_bytes,
		"checkpoint_equal": ck_exact,
		"source_unchanged": C.encode(source) == original_source,
		"strict_worker_wall_us": int(strict_status.last_worker_wall_us),
		"owned_worker_wall_us": int(owned_status.last_worker_wall_us),
		"observed_ratio": float(strict_status.last_worker_wall_us) /
			maxf(1.0, float(owned_status.last_worker_wall_us)),
		"strict_host_wall_us": int(strict.host_wall_us),
		"owned_host_wall_us": int(owned.host_wall_us),
		"deep_detach_us": int(phases.r2e2_deep_detach_us),
		"owned_first_full_validate_us": int(phases.r2e2_initial_full_source_validate_us),
		"strict_final_source_validate_us":
			int(strict_status.last_worker_source_validate_wall_us),
		"owned_final_source_validate_us":
			int(owned_status.last_worker_source_validate_wall_us),
		"owned_final_candidate_validate_us":
			int(owned_status.last_worker_candidate_validate_wall_us),
		"single_global_a4":true,
		"direct_untrusted_fast_rejected":true,
		"worker_owned_deep_detached":true,
		"default_original_strict":true,
		"guaranteed_subsecond":false,
	}))
	_finish()

func _execute(controller: Object, use_fast: bool) -> Dictionary:
	var host_started_us: int = Time.get_ticks_usec()
	var finished := false
	var polls := 0
	for i in POLL_MAX:
		var response: Dictionary = controller.run_staged_frame(
			1000000000, 1, 1, 64, 8388608, true, 4096,
			true, false, use_fast)
		if not bool(response.get("success", false)):
			_check(false, "LAB stage worker failed:" +
				String(response.get("error", "?")))
			break
		if bool(response.get("complete", false)):
			finished = true
			break
		polls += 1
		_check(int(controller.tick()) == 0,
			"no speculative global biological tick before full owned worker proof")
		await create_timer(0.02).timeout
	_check(finished and int(controller.tick()) == 1,
		"single full deterministic global tick admitted from LAB")
	if not finished:
		controller.cancel_staged_tick()
		return {}
	var elapsed_us: int = maxi(0, Time.get_ticks_usec() - host_started_us)
	var telemetry: Dictionary = controller.get_staged_telemetry().off_main
	_check(int(telemetry.jobs_started) == 1 \
		and int(telemetry.jobs_committed) == 1 \
		and int(telemetry.tasks_joined) == 1 \
		and int(telemetry.jobs_failed) == 0 \
		and not bool(telemetry.pending) and not bool(telemetry.abandoned_draining),
		"one CPU task started, joined and committed, zero leaked workers")
	return {"canonical":controller.debug_state().runtime,
		"telemetry":telemetry,"host_wall_us":elapsed_us,"polls":polls}

func _finish() -> void:
	print("A147_R2E2_OWNED checks=%d failed=%d" % [checks,failed])
	print("A147_R2E2_OWNED " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
