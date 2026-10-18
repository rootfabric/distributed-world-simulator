extends SceneTree
## ECO ARCH2 A14.5 R3 — real LAB controller, UI frame, cancellation,
## speculative memory and checkpoint exactness. No intermediate truth.
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const LabHost = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_5_R3_LIVE_FAIL " + label)

func _manifest() -> Dictionary:
	var host = LabHost.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	return m

func _new_controller(m: Dictionary) -> Object:
	var controller = Controller.new()
	var started: Dictionary = controller.initialize(m, {})
	_check(bool(started.get("success", false)), "LAB genesis valid")
	return controller

func _cp(controller: Object) -> Dictionary:
	return controller.serialize_state()

func _equal(a: Object, b: Object, label: String) -> void:
	var left: Dictionary = _cp(a)
	var right: Dictionary = _cp(b)
	_check(bool(left.get("success", false)) and bool(right.get("success", false)),
		label + " two checkpoints valid")
	if bool(left.get("success", false)) and bool(right.get("success", false)):
		_check(String(left.state_text) == String(right.state_text),
			label + " checkpoint bytes exact")
		_check(String(left.state_hash) == String(right.state_hash),
			label + " Runtime hash exact")

func _run() -> void:
	var manifest := _manifest()
	_check(not manifest.is_empty(), "production LAB manifest available")
	if manifest.is_empty():
		_finish()
		return
	_test_direct_controller(manifest)
	_test_cancel_memory_restore(manifest)
	_test_actual_frame_path(manifest)
	_finish()

func _test_direct_controller(m: Dictionary) -> void:
	var baseline = _new_controller(m)
	var stage = _new_controller(m)
	var origin: Dictionary = _cp(stage)
	var phases := {}
	var completed := false
	for i in 40:
		var slice: Dictionary = stage.run_staged_frame(1000000000, 1, 1, 1, 8388608)
		_check(bool(slice.get("success", false)), "direct resume #%d" % i)
		if not bool(slice.get("success", false)):
			return
		phases[String(slice.phase)] = true
		_check(int(slice.replayed_ticks) >= 0 and int(slice.replayed_ticks) <= 1,
			"direct frame commits at most one global tick")
		if bool(slice.complete):
			completed = true
			_check(stage.tick() == 1 and not stage.has_pending_staged_tick(),
				"completed global tick publishes exactly once")
			break
		_check(int(stage.tick()) == 0 and stage.has_pending_staged_tick(),
			"partial stage never changes canonical frontier")
		_check(not slice.has("state"), "no staged state leaks to caller")
		_check(String(_cp(stage).state_text) == String(origin.state_text),
			"canonical checkpoint unchanged while speculating")
		if i == 0:
			_check(not bool(stage.run(1).get("success", false)),
				"legacy run cannot race staged cursor")
			_check(not bool(stage.run_budgeted_to_tick(1).get("success", false)),
				"budgeted executor cannot race staged cursor")
			_check(not bool(stage.run_to_tick(0).get("success", false)),
				"legacy no-op frontier cannot bypass cursor gate")
	_check(completed, "direct staged tick completed within bounded resume calls")
	_check(phases.has("PREPARE") and phases.has("ALLOCATE") and phases.has("ADVANCE")
		and phases.has("COMPLETE"), "all canonical A5 barriers witnessed")
	var metrics: Dictionary = stage.get_staged_telemetry()
	_check(not bool(metrics.pending)
		and int(metrics.completed_ticks) == 1
		and int(metrics.cancellations) == 0,
		"completion is not counted as cancellation")
	_check(int(metrics.peak_cursor_bytes) > 0 and int(metrics.resume_calls) >= 3,
		"measured memory and resumes visible")
	_check(bool(baseline.step().get("success", false)), "legacy single tick complete")
	_equal(baseline, stage, "first committed staged tick")
	for tick_target in [2, 3]:
		var finished := false
		for j in 40:
			var resumed: Dictionary = stage.run_staged_frame(1000000000, 1, 1, 1, 8388608)
			_check(bool(resumed.get("success", false)),
				"staged resumed global tick %d" % tick_target)
			if not bool(resumed.get("success", false)):
				return
			if int(resumed.replayed_ticks) == 1:
				finished = true
				break
		_check(finished, "tick %d finishes" % tick_target)
		_check(bool(baseline.step().get("success", false)),
			"legacy tick %d finishes" % tick_target)
		_equal(baseline, stage, "consecutive staged tick %d" % tick_target)

func _test_cancel_memory_restore(m: Dictionary) -> void:
	var baseline = _new_controller(m)
	var actual = _new_controller(m)
	var before: Dictionary = _cp(actual)
	# An independently imposed very small cursor memory limit must reject
	# allocation, discard all speculation and leave the canonical state safe.
	var capped: Dictionary = actual.run_staged_frame(1000000000, 1, 1, 1, 1024)
	_check(not bool(capped.get("success", false))
		and String(capped.get("error", "")).contains("CURSOR_CAP"),
		"small cursor memory cap fails closed")
	_check(not actual.has_pending_staged_tick() and actual.tick() == 0,
		"failed memory admission leaves no speculative cursor")
	_check(String(_cp(actual).state_text) == String(before.state_text),
		"memory rejection cannot modify canonical checkpoint")
	_check(int(actual.get_staged_telemetry().memory_rejections) >= 1,
		"failed admission counted only as telemetry")

	# A tiny soft budget may allow begin but not one stage: correct deferral.
	var first: Dictionary = actual.run_staged_frame(1, 1, 1, 1, 8388608)
	_check(bool(first.get("success", false)) and actual.has_pending_staged_tick()
		and int(first.replayed_ticks) == 0,
		"soft-budget begin yields with pending global tick")
	_check(String(_cp(actual).state_text) == String(before.state_text),
		"checkpoint while pending contains only committed canonical state")
	var paused: Dictionary = actual.pause()
	_check(bool(paused.get("success", false)) and not actual.has_pending_staged_tick()
		and actual.tick() == 0, "PAUSE cancels speculative cursor and no tick")
	_check(int(actual.get_staged_telemetry().cancellations) >= 1,
		"cancel recorded separately from completion")
	_check(bool(actual.step().get("success", false))
		and bool(baseline.step().get("success", false)),
		"legacy single tick works after cancellation")
	_equal(baseline, actual, "cancel then fallback legacy")

	# Starting a new speculative tick, then externally anchored restore,
	# must discard its *entire* cursor and host telemetry.
	var committed: Dictionary = _cp(actual)
	var pending: Dictionary = actual.run_staged_frame(1, 1, 1, 1, 8388608)
	_check(bool(pending.get("success", false)) and actual.has_pending_staged_tick(),
		"second speculative tick exists")
	var restored: Dictionary = actual.load_state(
		String(committed.state_text), String(committed.manifest_hash),
		String(committed.state_checksum))
	_check(bool(restored.get("success", false))
		and actual.tick() == 1 and not actual.has_pending_staged_tick(),
		"restore discards transient cursor")
	_check(int(actual.get_staged_telemetry().calls) == 0,
		"trusted restore resets host telemetry")
	_equal(baseline, actual, "anchor restore remains exact")
	var regen: Dictionary = actual.reset()
	_check(bool(regen.get("success", false)) and actual.tick() == 0
		and not actual.has_pending_staged_tick(),
		"reset disposes cursor and rebuilds canonical genesis")

func _test_actual_frame_path(m: Dictionary) -> void:
	var baseline = _new_controller(m)
	var actual = _new_controller(m)
	var bench = Workbench.new()
	bench.controller = actual
	bench.running = true
	bench.ticks_per_second = 1.0
	bench.pending_target = {"kind": "tick", "value": 4}
	_check(bench.configure_staged_live(true, 1000000000, 1, 1, 1, 8388608),
		"LAB host chooses staged frame engine")
	var old_tick := 0
	var complete := false
	var partial_frames := 0
	# A single frame arrives with four owed canonical ticks; later frames
	# have zero wall delta, yet staged progress must drain the backlog.
	for frame_index in 80:
		bench._process(4.0 if frame_index == 0 else 0.0)
		var next_tick: int = int(actual.tick())
		_check(next_tick >= old_tick and next_tick <= old_tick + 1,
			"real _process frame #%d never commits half or multiple ticks" % frame_index)
		if next_tick == old_tick:
			partial_frames += 1
		old_tick = next_tick
		if next_tick == 4 and not bench.running:
			complete = true
			break
	_check(complete, "real _process reaches target and stops")
	_check(partial_frames > 0, "real _process crossed multiple speculative frames")
	_check(actual.tick() == 4 and not actual.has_pending_staged_tick(),
		"real _process final frontier exact and no cursor")
	_check(bench._elapsed < 0.001, "all logical owed ticks consumed exactly")
	_check(bool(baseline.run_to_tick(4).get("success", false)),
		"legacy reference reaches exact same LAB horizon")
	_equal(baseline, actual, "real LAB _process staged vs legacy")
	bench.free()

	# User-visible disabling during a pending staged tick must discard the
	# speculative cursor without touching canonical state or owed cadence.
	var pausedController = _new_controller(m)
	var pausedBench = Workbench.new()
	pausedBench.controller = pausedController
	pausedBench.running = true
	pausedBench.ticks_per_second = 1.0
	pausedBench.pending_target = {"kind": "tick", "value": 1}
	_check(pausedBench.configure_staged_live(true, 1, 1, 1, 1, 8388608),
		"start short LAB staged mode")
	pausedBench._process(1.0)
	_check(pausedController.has_pending_staged_tick() and pausedController.tick() == 0,
		"workbench pending before disable")
	_check(pausedBench.configure_staged_live(false)
		and not pausedController.has_pending_staged_tick(),
		"disable cancels in-flight speculative cursor")
	_check(float(pausedBench._elapsed) >= 1.0,
		"disable does not discard logical uncommitted tick debt")
	pausedBench.free()

func _finish() -> void:
	print("ECO_ARCH2_A14_5_R3_LIVE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_5_R3_LIVE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
