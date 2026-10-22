extends SceneTree
## FRESH INDEPENDENT R3.2.2 — direct child of frozen product ee9daa93.
## Does NOT import/use the product R3.2.2 test scripts. Only accepted
## Controller/Runtime/OffMain code is under test. No product source edit.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

const MAX_POLLS := 1200
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, where: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_R322_FRESH_VERIFY_FAIL " + where)

func _manifest() -> Dictionary:
	var host = Host.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	return m

func _controller(m: Dictionary) -> Object:
	var c = Controller.new()
	var r: Dictionary = c.initialize(m, {})
	_check(bool(r.get("success", false)), "real LAB controller initialized")
	return c

func _dispatch(c: Object) -> Dictionary:
	return c.run_staged_frame(1000000000, 1, 1, 8, 8388608, true, 4096, true)

func _until_commit(c: Object) -> bool:
	for frame in MAX_POLLS:
		var step: Dictionary = _dispatch(c)
		_check(bool(step.get("success", false)), "progress worker on real Controller")
		if not bool(step.get("success", false)):
			return false
		if bool(step.get("complete", false)):
			return true
		_check(int(c.tick()) == 0 and int(step.get("replayed_ticks", -1)) == 0 \
			and not step.has("grants") and not step.has("state"),
			"speculative frames have no biological authority")
		await create_timer(0.02).timeout
	return false

func _run() -> void:
	var m: Dictionary = _manifest()
	_check(String(m.get("mode", "")) == "LAB", "real LAB manifest")
	if not m.is_empty():
		await _test_normal(m)
		await _test_cancel_after_worker_complete(m)
		await _test_restore_while_pending(m)
		await _test_direct_late_tamper(m)
	_finish()

func _test_normal(m: Dictionary) -> void:
	var c = _controller(m)
	var ref = _controller(m)
	var initial: Dictionary = c.serialize_state()
	var complete: bool = await _until_commit(c)
	_check(complete and int(c.tick()) == 1, "controller publishes exactly one tick")
	_check(bool(ref.step().get("success", false)), "accepted serial reference tick")
	_check(String(c.serialize_state().state_text) == String(ref.serialize_state().state_text),
		"complete checkpoint/state exact to synchronous reference")
	var status: Dictionary = c.get_staged_telemetry().off_main
	_check(String(status.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE" \
		and int(status.tasks_joined) == 1 and int(status.jobs_committed) == 1,
		"exact controller-only admission and single join")
	_check(int(status.last_worker_source_validate_wall_us) > 0 \
		and int(status.last_worker_candidate_validate_wall_us) > 0,
		"worker truly validates both source and candidate")
	_check(String(initial.state_text) != String(c.serialize_state().state_text),
		"actual canonical tick advanced (not a no-op)")
	_check(c._r322_lease_token == null,
		"controller dropped old capability after one canonical commit")

func _test_cancel_after_worker_complete(m: Dictionary) -> void:
	var c = _controller(m)
	var ref = _controller(m)
	var started: Dictionary = _dispatch(c)
	_check(bool(started.get("success", false)) and c.has_pending_staged_tick(),
		"worker started before cancel-on-complete test")
	var old_token: RefCounted = c._r322_lease_token
	var old_epoch: int = c._r322_generation
	var checkpoint: Dictionary = c.serialize_state()
	var task = c._staged_session._off_main
	var finished := false
	for frame in MAX_POLLS:
		if WorkerThreadPool.is_task_completed(task._task_id):
			finished = true
			break
		await create_timer(0.02).timeout
	_check(finished, "worker finished without Controller polling its result")
	if not finished:
		c.cancel_staged_tick()
		return
	var cancelled: Dictionary = c.cancel_staged_tick()
	_check(bool(cancelled.get("success", false)) and int(c.tick()) == 0,
		"cancel rejects an already-completed but unpublished CPU candidate")
	_check(not c._r322_source_lease_valid(
		c._runtime, String(c._runtime.integrity_hash), c.tick(),
		C.digest(c._canonical_step_options().options), old_token, old_epoch),
		"old opaque lease cannot be reused after cancel")
	_check(String(checkpoint.state_text) == String(c.serialize_state().state_text),
		"cancel never touches canonical checkpoint")
	for i in MAX_POLLS:
		c.reap_cancelled_staged_worker()
		if not bool(c.get_staged_telemetry().off_main.abandoned_draining):
			break
		await create_timer(0.02).timeout
	var s: Dictionary = c.get_staged_telemetry().off_main
	_check(int(s.jobs_abandoned) == 1 and int(s.tasks_joined) == 1 \
		and int(s.jobs_committed) == 0,
		"late-cancel task joined once and zero partial commits")
	var retried: bool = await _until_commit(c)
	_check(retried and int(c.tick()) == 1 and bool(ref.step().get("success", false)),
		"fresh generation can execute after cancelled completed task")
	_check(String(c.serialize_state().state_text) == String(ref.serialize_state().state_text),
		"post-cancel new generation is canonical exact")

func _test_restore_while_pending(m: Dictionary) -> void:
	var c = _controller(m)
	var checkpoint: Dictionary = c.serialize_state()
	var start: Dictionary = _dispatch(c)
	_check(bool(start.get("success", false)) and c.has_pending_staged_tick(),
		"restore witness has live background job")
	var restored: Dictionary = c.load_state(String(checkpoint.state_text),
		String(checkpoint.manifest_hash), String(checkpoint.state_checksum))
	_check(bool(restored.get("success", false)) and int(c.tick()) == 0,
		"anchored trusted restore retires generation")
	_check(String(c.serialize_state().state_text) == String(checkpoint.state_text),
		"restored canonical checkpoint is exact")
	for i in MAX_POLLS:
		c.reap_cancelled_staged_worker()
		if not bool(c.get_staged_telemetry().off_main.abandoned_draining):
			break
		await create_timer(0.02).timeout
	_check(not bool(c.get_staged_telemetry().off_main.abandoned_draining) \
		and int(c.get_staged_telemetry().off_main.jobs_committed) == 0,
		"restore abandons and reaps old source without commit")

func _test_direct_late_tamper(m: Dictionary) -> void:
	var ctrl = _controller(m)
	var source: Dictionary = ctrl.debug_state().runtime
	var options: Dictionary = ctrl._canonical_step_options().options
	var worker = OffMain.new()
	var dispatch: Dictionary = worker.advance(source, options, 8, 4096, 8388608)
	_check(bool(dispatch.get("success", false)), "untrusted direct worker started")
	if not bool(dispatch.get("success", false)):
		return
	var finished := false
	for frame in MAX_POLLS:
		if WorkerThreadPool.is_task_completed(worker._task_id):
			finished = true
			break
		await create_timer(0.02).timeout
	_check(finished, "direct task completes before nested source tamper")
	if not finished:
		worker.cancel()
		return
	var anchor: String = String(source.integrity_hash)
	var tick: int = int(source.tick)
	source.population[0].state.age_ticks = int(source.population[0].state.age_ticks) + 1
	_check(String(source.integrity_hash) == anchor and int(source.tick) == tick,
		"nested mutation bypasses header/tick hash (adversarial test)")
	var denied: Dictionary = worker.advance(source, options, 8, 4096, 8388608)
	_check(not bool(denied.get("success", true)) \
		and String(denied.get("error", "")).begins_with("R3_ASYNC_SOURCE_INVALID:"),
		"direct caller STILL fails on late nested mutation after worker validation")
	_check(not denied.has("state") and int(worker.status().jobs_committed) == 0,
		"corrupt source cannot publish a single partial/global state")

func _finish() -> void:
	print("ECO_A14_6_R322_FRESH_VERIFIER checks=%d failed=%d" % [checks, failed])
	print("ECO_A14_6_R322_FRESH_VERIFIER " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
