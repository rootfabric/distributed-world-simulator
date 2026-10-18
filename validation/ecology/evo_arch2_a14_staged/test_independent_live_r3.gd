extends SceneTree
## Fresh independent A14.5 R3 proof. The host-only cursor and metrics
## must NEVER enter the published runtime or persistent A8 checkpoint.
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_test")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A14_5_R3_INDEPENDENT_FAIL " + label)

func manifest() -> Dictionary:
	var host = Host.new()
	host._build_manifest()
	var model: Dictionary = host.manifest.duplicate(true)
	host.free()
	return model

func controller(model: Dictionary) -> Object:
	var c = Controller.new()
	var result: Dictionary = c.initialize(model, {})
	check(bool(result.get("success", false)), "initial real LAB controller")
	return c

func bytes(c: Object) -> String:
	var result: Dictionary = c.serialize_state()
	check(bool(result.get("success", false)), "anchored A8 checkpoint valid")
	return String(result.get("state_text", ""))

func verify_equivalent(a: Object, b: Object, label: String) -> void:
	check(bytes(a) == bytes(b), label + " exact checkpoint bytes")

func _test() -> void:
	var model := manifest()
	check(not model.is_empty(), "shipped polygon host canonical manifest")
	if model.is_empty():
		_finish()
		return
	var baseline: Object = controller(model)
	var staged: Object = controller(model)
	var initial := bytes(staged)
	# Partial PREPARE cannot publish a source. No second state enters host.
	var first: Dictionary = staged.run_staged_frame(1000000000, 1, 1, 1, 8388608)
	check(bool(first.get("success", false)) and not bool(first.get("complete", true)),
		"new staged transaction is explicitly incomplete")
	check(staged.has_pending_staged_tick() and int(staged.tick()) == 0,
		"speculative state is host-owned and pending")
	check(bytes(staged) == initial, "checkpoint still original after begin")
	check(not bool(staged.run(1).get("success", false)),
		"legacy cannot race an unfinished staged tick")
	var telemetry: Dictionary = staged.get_staged_telemetry()
	check(String(telemetry.schema) == "dws.ecology.a14-5-r3-host-staged-session.v1"
		and int(telemetry.cursor_bytes) > 0,
		"cursor size accounted as host telemetry")
	telemetry.cursor_bytes = 0
	check(int(staged.get_staged_telemetry().cursor_bytes) > 0,
		"mutating detached telemetry cannot change real cursor")
	var cancelled: Dictionary = staged.cancel_staged_tick()
	check(bool(cancelled.cancelled) and not staged.has_pending_staged_tick(),
		"explicit cancellation discards cursor only")
	check(bytes(staged) == initial and staged.tick() == 0,
		"rollback kept canonical source byte-identical")

	var had_stage := {"ALLOCATE": false, "ADVANCE": false}
	var done := false
	for attempt in 40:
		var next: Dictionary = staged.run_staged_frame(1000000000, 1, 1, 1, 8388608)
		check(bool(next.get("success", false)), "new session resume #%d" % attempt)
		if not bool(next.get("success", false)):
			break
		if had_stage.has(String(next.phase)):
			had_stage[String(next.phase)] = true
		if bool(next.complete):
			done = true
			break
		check(bytes(staged) == initial, "no partial state at #%d" % attempt)
	check(done and had_stage.ALLOCATE and had_stage.ADVANCE,
		"full PREPARE/ALLOCATE/ADVANCE completes over frames")
	check(bool(baseline.step().get("success", false)), "legacy first tick valid")
	verify_equivalent(baseline, staged, "poststage canonical commit")
	var stats: Dictionary = staged.get_staged_telemetry()
	check(int(stats.completed_ticks) == 1 and int(stats.cancellations) == 1,
		"exactly one user cancel, not one per successful commit")
	check(int(stats.peak_cursor_bytes) > 1024 and int(stats.peak_cursor_bytes) <= 8388608,
		"bounded speculative memory")

	# Small cursors denied before an atomically published tick.
	var trusted := bytes(staged)
	var tiny: Dictionary = staged.run_staged_frame(1000000000, 1, 1, 1, 1024)
	check(not bool(tiny.get("success", false)) and
		String(tiny.get("error", "")).contains("CURSOR_CAP"),
		"tiny capacity refuses owned speculative data")
	check(not staged.has_pending_staged_tick() and bytes(staged) == trusted,
		"small cap aborts without changing persistent canonical truth")

	# A paused unfinished tick is cancelled; after pause a real legacy tick
	# can resume from the exact SAME accepted source frontier.
	var begun: Dictionary = staged.run_staged_frame(1, 1, 1, 1, 8388608)
	check(bool(begun.get("success", false)) and staged.has_pending_staged_tick(),
		"under-soft-budget call retains speculative cursor")
	staged.pause()
	check(not staged.has_pending_staged_tick() and bytes(staged) == trusted,
		"pause discards only speculative work")
	check(bool(staged.step().get("success", false))
		and bool(baseline.step().get("success", false)),
		"legacy fallback runs on accepted canonical truth")
	verify_equivalent(baseline, staged, "safe fallback after pause")

	# Real default LAB _process with explicit staged opt-in; each frame runs
	# at most one stage and cannot consume uncommitted clock debt.
	var parallel: Object = controller(model)
	var ui = Workbench.new()
	ui.controller = parallel
	ui.running = true
	ui.ticks_per_second = 1.0
	ui.pending_target = {"kind": "tick", "value": 2}
	check(ui.configure_staged_live(true, 1000000000, 1, 1, 1, 8388608),
		"LAB staged opt-in accepted")
	var last_tick := 0
	var frames := 0
	for i in 48:
		ui._process(2.0 if i == 0 else 0.0)
		frames += 1
		check(int(parallel.tick()) >= last_tick and int(parallel.tick()) <= last_tick + 1,
			"frame #%d cannot commit an unfinished or multiple ticks" % i)
		last_tick = int(parallel.tick())
		if int(parallel.tick()) == 2 and not ui.running:
			break
	check(int(parallel.tick()) == 2 and not ui.running and frames > 2,
		"real LAB frame debt drained via staggered tick commits")
	check(ui._elapsed < 0.001, "only committed logical clock ticks consumed")
	verify_equivalent(baseline, parallel, "LAB frame result matches legacy")
	ui.free()

	# Successful trusted restore strips all host-only telemetry and cursor.
	var snap: Dictionary = staged.serialize_state()
	var pending: Dictionary = staged.run_staged_frame(1, 1, 1, 1, 8388608)
	check(bool(pending.get("success", false)) and staged.has_pending_staged_tick(),
		"replay active before checkpoint restore")
	var loaded: Dictionary = staged.load_state(
		String(snap.state_text), String(snap.manifest_hash),
		String(snap.state_checksum))
	check(bool(loaded.get("success", false))
		and not staged.has_pending_staged_tick()
		and int(staged.get_staged_telemetry().calls) == 0,
		"restored canonical state resets all host-only cursor/metrics")
	verify_equivalent(baseline, staged, "trusted restore exact final")
	_finish()

func _finish() -> void:
	print("ECO_ARCH2_A14_5_R3_INDEPENDENT checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_5_R3_INDEPENDENT " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
