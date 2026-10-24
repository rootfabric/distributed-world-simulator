extends SceneTree
## A14.7 R2E2 independently-authored security and lifecycle verifier.
## Exactly one human-owned LAB Controller, actual on-worker deep source
## and original A4 allocation. Product test not imported/reused.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Owned = preload("res://scripts/research/ecology/v2/ecology_owned_worker_source_r2e2_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2E2_FRESH_FAIL " + label)

func _controller(source: Dictionary) -> Object:
	var host = Lab.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	var c = Controller.new()
	var begin: Dictionary = c.initialize(m, {})
	_check(bool(begin.get("success", false)), "original LAB Controller initialized")
	if bool(begin.get("success", false)):
		c._runtime = source.duplicate(true)
	return c

func _run() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() != 2 or String(argv[0]) != "--population" \
			or not String(argv[1]) in ["32", "96"]:
		_check(false, "independent n32/96 required")
		_finish()
		return
	var n: int = int(argv[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty(), "accepted real canonical fixture")
	if source.is_empty():
		_finish()
		return
	var c = _controller(source)
	var opts: Dictionary = c._canonical_step_options().options
	var original: String = C.encode(source)
	# No direct fast entrypoint. No RefCounted without exact trusted CPU
	# worker source context can bypass FULL public Runtime.validate().
	var generic = RefCounted.new()
	var fake: Dictionary = Runtime.resume_staged_global_tick(
		source, opts, {}, 1, 4096, 8388608, 1, false, generic)
	_check(not bool(fake.get("success", true)) and
		String(fake.get("error", "")) == "RUNTIME_R2E2_OWNED_SOURCE_LEASE",
		"forged Runtime owned context rejected on MAIN")
	var claimed = Owned.new()
	var bad_worker: Dictionary = claimed.admit(source, opts,
		String(source.integrity_hash), int(source.tick), C.digest(opts), 123)
	_check(not bool(bad_worker.get("success", true)) and
		String(bad_worker.get("error", "")) == "R2E2_OWNED_NOT_CPU_WORKER",
		"source owner cannot be instantiated by user on MAIN")
	var direct = OffMain.new()
	var denied: Dictionary = direct.advance(source, opts,
		64, 4096, 8388608, null, null, -1, {}, 1, 1, true, true)
	_check(not bool(denied.get("success", true)) and
		String(denied.get("error", "")) == "R2E2_REQUIRES_CONTROLLER_LEASE" \
		and int(direct.status().jobs_started) == 0,
		"direct untrusted external service cannot opt into owned-worker path")
	var checkpoint: Dictionary = c.serialize_state()
	_check(bool(checkpoint.get("success", false)) and c.tick() == 0,
		"A8 anchored original source available")
	var first: Dictionary = c.run_staged_frame(
		1000000000, 1, 1, 64, 8388608, true, 4096, true, false, true)
	_check(bool(first.get("success", false)) \
		and not bool(first.get("complete", true)) and c.has_pending_staged_tick(),
		"real LAB leased CPU task pending without source publication")
	var detached: Dictionary = c.debug_state().runtime
	detached.population[0].state.age_ticks += 1
	_check(C.encode(c._runtime) == C.encode(source),
		"debug snapshot is deep detached, cannot mutate exclusive canonical frontier")
	var cancelled: Dictionary = c.cancel_staged_tick()
	_check(bool(cancelled.get("success", false)) and
		bool(cancelled.get("cancelled", false)) and c.tick() == 0,
		"explicit cancel revokes owned source before state adoption")
	var drained := false
	for i in 12000:
		c.reap_cancelled_staged_worker()
		var tele: Dictionary = c.get_staged_telemetry().off_main
		if not bool(tele.abandoned_draining):
			drained = true
			break
		await create_timer(0.02).timeout
	_check(drained and int(c.get_staged_telemetry().off_main.jobs_committed) == 0,
		"cancelled worker drained without committing any global A4 or candidate")
	_check(C.encode(c._runtime) == original,
		"cancelled CPU work leaves exact canonical field/population/checkpoint intact")
	if bool(checkpoint.get("success", false)):
		var restored: Dictionary = c.load_state(
			String(checkpoint.state_text), String(checkpoint.manifest_hash),
			String(checkpoint.state_checksum))
		_check(bool(restored.get("success", false)) and c.tick() == 0,
			"externally anchored restore cleanly revokes prior generation and reuses old A8")
	var settled := false
	for i in 12000:
		var progress: Dictionary = c.run_staged_frame(
			1000000000, 1, 1, 64, 8388608, true, 4096, true, false, true)
		if not bool(progress.get("success", false)):
			_check(false, "restored owned worker fails:" +
				String(progress.get("error", "?")))
			break
		if bool(progress.get("complete", false)):
			settled = true
			break
		_check(c.tick() == 0, "restored owned worker has no partial canonical grants")
		await create_timer(0.02).timeout
	_check(settled and c.tick() == 1 and
		C.encode(c._runtime) != original,
		"one verified complete canonical tick can be adopted AFTER restore")
	if not settled:
		_finish()
		return
	var original_reference: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts, 4, 64, 4, 4)
	_check(bool(original_reference.get("success", false)) \
		and C.encode(c._runtime) == C.encode(original_reference.state),
		"restored leased CPU result identical to original A13 full canonical Runtime")
	_check(C.encode(source) == original,
		"original external fixture never mutated by cancelled/restored workers")
	var final_status: Dictionary = c.get_staged_telemetry().off_main
	_check(int(final_status.jobs_committed) == 1 \
		and int(final_status.tasks_joined) == 1 \
		and int(final_status.jobs_failed) == 0,
		"new generation exactly one worker joined and committed")
	_check(bool(final_status.last_worker_r2e2_owned_fast) \
		and int(final_status.last_worker_source_validate_wall_us) > 0 \
		and int(final_status.last_worker_candidate_validate_wall_us) > 0,
		"full final source/candidate validations and owned fast receipt")
	print("A147_R2E2_FRESH_RECEIPT_JSON " + JSON.stringify({
		"schema": "dws.ecology.a147-r2e2-fresh-security.v1",
		"population": n, "original_exact": C.encode(c._runtime) == C.encode(
			original_reference.state), "late_cancel_reaped": drained,
		"external_source_unchanged": C.encode(source) == original,
		"full_final_validation": true,
		"direct_untrusted_rejected": true,
		"restored_generation_committed_once": true,
	}))
	_finish()

func _finish() -> void:
	print("A147_R2E2_FRESH checks=%d failed=%d" % [checks, failed])
	print("A147_R2E2_FRESH " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
