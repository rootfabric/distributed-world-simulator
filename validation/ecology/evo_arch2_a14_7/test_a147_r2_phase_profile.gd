extends SceneTree
## ECO ARCH2 A14.7 R2 Stage A — real Controller CPU worker phase attribution.
## 4/32/96/256 exact accepted A14.7 R1 fixture, a SINGLE R3 A4 owner,
## canonical exact against original A13 full parallel-advance reference.
## This is an instrumented baseline, NOT a throughput optimization or SLA.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const LabHost = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")

const SIZES := [4, 32, 96, 256]
const HASHES := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const POLL_LIMIT := 12000
const INTERVAL := 0.02
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A147_R2_PROFILE_FAIL " + label)

func _manifest() -> Dictionary:
	var host = LabHost.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--r2-population" \
			or not String(args[1]) in ["4", "32", "96", "256"]:
		_check(false, "EXACT_SCALE_PARAMETER_REQUIRED")
		_finish()
		return
	var n: int = int(args[1])
	await _profile(n)
	_finish()

func _profile(n: int) -> void:
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"canonical stable source of required population")
	if source.is_empty():
		return
	var original: String = C.encode(source)
	var ctrl = Controller.new()
	var init: Dictionary = ctrl.initialize(_manifest(), {})
	_check(bool(init.get("success", false)), "real LAB Controller initialized")
	if not bool(init.get("success", false)):
		return
	# Source is cloned BEFORE a lease is issued; no shared mutable aliases.
	ctrl._runtime = source.duplicate(true)
	var opts: Dictionary = ctrl._canonical_step_options()
	_check(bool(opts.get("success", false)), "real canonical experiment options")
	if not bool(opts.get("success", false)):
		return
	# Accepted one-global-owner A13 reference, not a guessed target hash.
	var ref: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts.options, 4, 64, 4, 4)
	_check(bool(ref.get("success", false)), "historical original exact parallel advance")
	if not bool(ref.get("success", false)):
		return
	var initial_tick: int = ctrl.tick()
	var dispatched: Dictionary = ctrl.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096, true, true)
	_check(bool(dispatched.get("success", false)) \
		and ctrl.has_pending_staged_tick() and ctrl.tick() == initial_tick,
		"CPU worker single authoritative staged tick dispatched")
	if not bool(dispatched.get("success", false)):
		return
	var wall_start_us: int = Time.get_ticks_usec()
	var finished := false
	var pending_frames := 0
	var max_host_poll_us := 0
	for i in POLL_LIMIT:
		var started_us: int = Time.get_ticks_usec()
		var result: Dictionary = ctrl.run_staged_frame(
			1000000000, 1, 1, 64, 8388608, true, 4096, true, true)
		var poll_us: int = maxi(0, Time.get_ticks_usec() - started_us)
		max_host_poll_us = maxi(max_host_poll_us, poll_us)
		if not bool(result.get("success", false)):
			_check(false, "LAB worker returned failure:" +
				String(result.get("error", "?")))
			break
		if bool(result.get("complete", false)):
			finished = true
			break
		pending_frames += 1
		_check(int(ctrl.tick()) == initial_tick \
			and not result.has("state") and not result.has("grants"),
			"pending global A4 cannot expose speculative biology/grants")
		await create_timer(INTERVAL).timeout
	_check(finished and int(ctrl.tick()) == initial_tick + 1 \
		and not ctrl.has_pending_staged_tick(),
		"one complete admitted global canonical tick")
	if not finished:
		ctrl.cancel_staged_tick()
		return
	var host_wall_us: int = maxi(0, Time.get_ticks_usec() - wall_start_us)
	var got: Dictionary = ctrl.debug_state().runtime
	var hash: String = Runtime.state_hash(got)
	_check(hash == String(HASHES[n]) \
		and C.encode(got) == C.encode(ref.state),
		"full Runtime bytes and historical canonical hash exact")
	var anchor: String = C.digest({"schema": "a147-r2-phase-proof.v1", "population": n})
	var ck1: Dictionary = Checkpoint.create(anchor, ref.state)
	var ck2: Dictionary = Checkpoint.create(anchor, got)
	_check(not ck1.is_empty() and not ck2.is_empty() \
		and Checkpoint.serialize(ck1) == Checkpoint.serialize(ck2),
		"full A8 checkpoint serialized byte exact")
	_check(C.encode(source) == original, "detached input source was not mutated")
	var telemetry: Dictionary = ctrl.get_staged_telemetry().off_main
	var phases: Dictionary = telemetry.last_worker_phase_profile
	var resumes: int = int(phases.get("prepare_calls", 0)) \
		+ int(phases.get("allocate_begin_calls", 0)) \
		+ int(phases.get("allocate_resume_calls", 0)) \
		+ int(phases.get("advance_calls", 0))
	_check(phases.size() > 0 and resumes > 0 and
		int(phases.get("resume_total_us", 0)) > 0 and
		int(phases.get("begin_us", 0)) > 0,
		"all nonzero CPU phase counters published")
	_check(int(phases.get("prepare_calls", 0)) > 0 \
		and int(phases.get("advance_calls", 0)) > 0 \
		and int(phases.get("allocate_begin_calls", 0)) == 1 \
		and int(phases.get("finalize_calls", 0)) == 1,
		"all A5 PREPARE → single global A4 → ADVANCE → final publish phases")
	_check(int(phases.get("prepare_us", 0)) +
		int(phases.get("allocate_begin_us", 0)) +
		int(phases.get("allocate_resume_us", 0)) +
		int(phases.get("advance_us", 0)) ==
		int(phases.get("resume_total_us", -1)),
		"phase sums are exact, finalization is a subset of ADVANCE")
	_check(int(phases.get("max_cursor_bytes", 0)) > 0 \
		and int(phases.get("max_cursor_bytes", 0)) <= 8388608,
		"cursor size guard and phase instrumentation agree")
	_check(int(telemetry.jobs_started) == 1 \
		and int(telemetry.jobs_committed) == 1 \
		and int(telemetry.tasks_joined) == 1 \
		and int(telemetry.jobs_failed) == 0 \
		and not bool(telemetry.pending) and not bool(telemetry.abandoned_draining),
		"one exact worker, one commit and one join, no leaks")
	var recorded_us: int = int(phases.get("begin_us", 0)) + \
		int(phases.get("cursor_encode_us", 0)) + \
		int(phases.get("resume_total_us", 0)) + \
		int(telemetry.last_worker_source_validate_wall_us) + \
		int(telemetry.last_worker_candidate_validate_wall_us) + \
		int(telemetry.last_projection_wall_us)
	var unaccounted_us: int = int(telemetry.last_worker_wall_us) - recorded_us
	_check(unaccounted_us >= 0, "measured subphases never exceed worker total")
	print("A147_R2_CPU_PHASE_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-7-r2-stage-a-cpu-attribution.v1",
		"population": n, "canonical_hash": hash, "checkpoint_equal":
		not ck1.is_empty() and not ck2.is_empty() and
		Checkpoint.serialize(ck1) == Checkpoint.serialize(ck2),
		"source_unchanged": C.encode(source) == original,
		"phase": phases, "resumes": resumes,
		"source_full_validate_us": int(telemetry.last_worker_source_validate_wall_us),
		"candidate_full_validate_us": int(telemetry.last_worker_candidate_validate_wall_us),
		"snapshot_projection_us": int(telemetry.last_projection_wall_us),
		"worker_wall_us": int(telemetry.last_worker_wall_us),
		"worker_unattributed_us": unaccounted_us,
		"host_poll_peak_us": max_host_poll_us,
		"host_wall_us": host_wall_us, "pending_frames": pending_frames,
		"single_global_allocator": true,
		"canonical_biology_changed": false,
		"throughput_sla_met_claim": false, "phase_finalization_is_subset": true,
	}))

func _finish() -> void:
	print("A147_R2_PHASE_PROFILE checks=%d failed=%d" % [checks, failures])
	print("A147_R2_PHASE_PROFILE " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
