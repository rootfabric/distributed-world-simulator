extends SceneTree
## ECO ARCH2 A14.6 R3.2 — REAL LAB async CPU worker, UI poll, cancellation.
## Pure Runtime/A5/R2 work runs off main; only one FULL canonical tick may
## publish, and only after original global A4 proof and complete A6 feedback.
## Host wall timings are observational, never accepted CPU scheduling inputs.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Async = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")

const POLL_LIMIT := 600
const POLL_INTERVAL := 0.02
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_ARCH2_A14_6_R32_OFFMAIN_FAIL " + label)

func _manifest() -> Dictionary:
	var host = Host.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	return m

func _controller(m: Dictionary) -> Object:
	var c = Controller.new()
	var started: Dictionary = c.initialize(m, {})
	_check(bool(started.get("success", false)), "real LAB controller initialized")
	return c

func _run() -> void:
	var m: Dictionary = _manifest()
	_check(not m.is_empty() and String(m.get("mode", "")) == "LAB",
		"real LAB manifest, not WORLD_COMPAT")
	if m.is_empty():
		_finish()
		return
	await _test_direct_service(m)
	await _test_real_workbench(m)
	await _test_cancel_and_resume(m)
	_finish()

func _test_direct_service(m: Dictionary) -> void:
	var ctrl = _controller(m)
	var reference = _controller(m)
	var source: Dictionary = ctrl.debug_state().runtime
	var opts: Dictionary = ctrl._canonical_step_options()
	_check(bool(opts.get("success", false)), "real canonical seed and options")
	if not bool(opts.get("success", false)):
		return
	var frozen_bytes: String = C.encode(source)
	var own = Async.new()
	var started_us := Time.get_ticks_usec()
	var first: Dictionary = own.advance(source, opts.options, 8, 4096, 8388608)
	var dispatch_us := maxi(0, Time.get_ticks_usec() - started_us)
	_check(bool(first.get("success", false))
		and not bool(first.get("complete", true))
		and own.has_pending(), "CPU task starts asynchronously, never publishes state")
	_check(not first.has("state") and not first.has("grants")
		and int(ctrl.tick()) == 0, "no speculative grants/biology in controller")
	_check(not bool(own.status().abandoned_draining)
		and int(own.status().jobs_started) == 1,
		"one host worker is started for one full global tick")
	var done: Dictionary = {}
	var peak_poll_us := 0
	var polls := 0
	for i in POLL_LIMIT:
		var start := Time.get_ticks_usec()
		var result: Dictionary = own.advance(source, opts.options, 8, 4096, 8388608)
		var poll_us := maxi(0, Time.get_ticks_usec() - start)
		peak_poll_us = maxi(peak_poll_us, poll_us)
		polls += 1
		_check(bool(result.get("success", false)),
			"nonblocking pool poll: " + String(result.get("error", "")))
		if not bool(result.get("success", false)):
			break
		if bool(result.get("complete", false)):
			done = result
			break
		_check(not result.has("state") and int(ctrl.tick()) == 0,
			"unfinished CPU tick cannot publish canonical state")
		await create_timer(POLL_INTERVAL).timeout
	_check(not done.is_empty(), "async CPU worker finishes real R3 global A4/A5/A6")
	if done.is_empty():
		own.cancel()
		return
	_check(not own.has_pending() and not own.is_draining()
		and int(own.status().tasks_joined) == 1,
		"completed worker joined exactly once before exposing result")
	_check(bool(reference.step().get("success", false)),
		"original canonical reference tick")
	_check(C.encode(done.state) == C.encode(reference.debug_state().runtime),
		"full completed Runtime exact to original serial controller")
	_check(Runtime.state_hash(done.state) == Runtime.state_hash(reference.debug_state().runtime),
		"canonical state hash independent of worker threading")
	_check(C.encode(source) == frozen_bytes and int(ctrl.tick()) == 0,
		"source biology remains untouched by background task")
	print("ECO_A14_6_R32_OFFMAIN_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-6-r3-2-offmain-observation.v1",
		"scenario": "cpu-only-real-global-tick",
		"dispatch_wall_us": dispatch_us, "peak_poll_wall_us": peak_poll_us,
		"polls": polls, "worker_wall_us": int(done.worker_wall_us),
		"peak_background_poll_us": int(own.status().peak_background_poll_us),
		"main_join_wall_us": int(done.join_wall_us),
		"main_source_admission_wall_us": int(done.source_admission_wall_us),
		"main_complete_poll_wall_us": int(done.complete_poll_wall_us),
		"canonical_hash": Runtime.state_hash(done.state),
		"state_equal": C.encode(done.state) == C.encode(reference.debug_state().runtime),
		"hard_frame_deadline_claim": false,
	}))

func _test_real_workbench(m: Dictionary) -> void:
	var actual = _controller(m)
	var ref = _controller(m)
	var bench = Workbench.new()
	bench.controller = actual
	bench.ticks_per_second = 1.0
	bench.running = true
	bench.pending_target = {"kind": "tick", "value": 1}
	bench._status_bar = Label.new()
	_check(not bench.configure_staged_live(true, 1000000000, 1, 1,
		8, 8388608, false, 4096, true),
		"off-main cannot enable without the versioned R3 allocator")
	_check(bench.configure_staged_live(true, 1000000000, 1, 1,
		8, 8388608, true, 4096, true),
		"real Workbench allows explicit LAB R3.2 opt-in")
	var checkpoint: Dictionary = actual.serialize_state()
	var frames := 0
	var pending := 0
	var gui_peak_us := 0
	var gui_pending_peak_us := 0
	var gui_commit_us := -1
	for i in POLL_LIMIT:
		var began := Time.get_ticks_usec()
		bench._process(1.0 if i == 0 else 0.0)
		var gui_wall := maxi(0, Time.get_ticks_usec() - began)
		gui_peak_us = maxi(gui_peak_us, gui_wall)
		frames += 1
		if actual.tick() == 1:
			gui_commit_us = gui_wall
			break
		gui_pending_peak_us = maxi(gui_pending_peak_us, gui_wall)
		pending += 1
		_check(actual.tick() == 0
			and String(actual.serialize_state().state_text) == String(checkpoint.state_text),
			"real GUI pending frame cannot commit or checkpoint speculative A4")
		_check(not String(bench._status_bar.text).is_empty(),
			"UI updates without rebuilding full canonical snapshot on pending worker")
		await create_timer(POLL_INTERVAL).timeout
	_check(actual.tick() == 1 and not bench.running,
		"real Workbench._process commits exactly one tick and stops at target")
	_check(bool(ref.step().get("success", false)),
		"historical LAB reference tick after worker path")
	_check(String(actual.serialize_state().state_text) ==
		String(ref.serialize_state().state_text),
		"real Workbench async A4 full Runtime/A8 checkpoint bytes exact")
	_check(pending > 0 and frames > 1
		and int(actual.get_staged_telemetry().off_main.jobs_committed) == 1,
		"actual GUI witnessed offmain async deferral and one atomic commit")
	print("ECO_A14_6_R32_OFFMAIN_PROFILE_JSON " + JSON.stringify({
		"scenario": "real-workbench-process",
		"frames": frames, "pending_frames": pending,
		"main_process_peak_wall_us": gui_peak_us,
		"main_pending_process_peak_wall_us": gui_pending_peak_us,
		"main_commit_process_wall_us": gui_commit_us,
		"main_source_admission_wall_us": int(actual.get_staged_telemetry().off_main.last_source_admission_wall_us),
		"checkpoint_equal": String(actual.serialize_state().state_text) ==
			String(ref.serialize_state().state_text),
		"hard_frame_deadline_claim": false,
	}))
	bench._status_bar.free()
	bench.free()

func _test_cancel_and_resume(m: Dictionary) -> void:
	var ctrl = _controller(m)
	var reference = _controller(m)
	var state_before: Dictionary = ctrl.serialize_state()
	var initial: Dictionary = ctrl.run_staged_frame(
		1000000000, 1, 1, 8, 8388608, true, 4096, true)
	_check(bool(initial.get("success", false))
		and ctrl.has_pending_staged_tick() and ctrl.tick() == 0,
		"versioned R3.2 CPU-only pending controller has zero canonical mutation")
	_check(String(ctrl.serialize_state().state_text) == String(state_before.state_text),
		"background scratch entirely absent from A8 checkpoint bytes")
	var denied: Dictionary = ctrl.step()
	_check(not bool(denied.get("success", false))
		and String(denied.get("error", "")).contains("STAGED_PENDING"),
		"legacy synchronous entrypoint blocked while CPU worker is authoritative")
	var paused: Dictionary = ctrl.pause()
	_check(bool(paused.get("success", false))
		and not ctrl.has_pending_staged_tick() and ctrl.tick() == 0,
		"PAUSE immediately discards pending worker publication")
	_check(String(ctrl.serialize_state().state_text) == String(state_before.state_text),
		"PAUSE preserves global checkpoint bytes exactly")
	_check(bool(ctrl.step().get("success", false))
		and bool(reference.step().get("success", false)),
		"legacy tick can run from trusted state after abort")
	_check(String(ctrl.serialize_state().state_text) ==
		String(reference.serialize_state().state_text),
		"abandoned CPU task does not contaminate subsequent canonical tick")
	var drained := false
	for i in POLL_LIMIT:
		ctrl.reap_cancelled_staged_worker()
		var background: Dictionary = ctrl.get_staged_telemetry().off_main
		if not bool(background.abandoned_draining):
			drained = true
			break
		await create_timer(POLL_INTERVAL).timeout
	_check(drained, "abandoned worker is reaped without blocking UI")
	_check(int(ctrl.get_staged_telemetry().off_main.jobs_abandoned) == 1
		and int(ctrl.get_staged_telemetry().off_main.tasks_joined) == 1,
		"no leaked background task after PAUSE/reap")
	var old_tick: int = ctrl.tick()
	var restore: Dictionary = ctrl.load_state(
		String(state_before.state_text), String(state_before.manifest_hash),
		String(state_before.state_checksum))
	_check(bool(restore.get("success", false)) and int(ctrl.tick()) == 0
		and old_tick == 1,
		"external anchored restore rewinds canonical tick safely")
	_check(not ctrl.has_pending_staged_tick(),
		"restore never recovers speculative off-main cursor")

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R32_OFFMAIN checks=%d failed=%d" %
		[checks, failures])
	print("ECO_ARCH2_A14_6_R32_OFFMAIN " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
