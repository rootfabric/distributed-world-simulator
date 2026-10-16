extends SceneTree
## ECO A14.4 — real ExperimentController + EcologyWorkbench._process.
## Compares old single-truth sequential runtime to budgeted globally exact ticks
## and checks checkpoint purity, real frame debt, reset/restore, no silent loss.
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const LabHost = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_4_LIVE_FAIL " + label)

func _manifest() -> Dictionary:
	# The exact manifest of the shipped A10.5 lab host.
	var host = LabHost.new()
	host._build_manifest()
	var manifest: Dictionary = host.manifest.duplicate(true)
	host.free()
	return manifest

func _controller(manifest: Dictionary) -> Object:
	var controller = Controller.new()
	var started: Dictionary = controller.initialize(manifest, {})
	_check(bool(started.get("success", false)), "controller initialize")
	return controller

func _compare_checkpoints(a: Object, b: Object, label: String) -> void:
	var ca: Dictionary = a.serialize_state()
	var cb: Dictionary = b.serialize_state()
	_check(bool(ca.get("success", false)) and bool(cb.get("success", false)),
		label + " checkpoints valid")
	if bool(ca.get("success", false)) and bool(cb.get("success", false)):
		_check(String(ca.state_hash) == String(cb.state_hash),
			label + " canonical runtime hashes equal")
		_check(String(ca.state_text) == String(cb.state_text),
			label + " checkpoint text byte-equal")

func _run() -> void:
	var manifest := _manifest()
	_check(not manifest.is_empty(), "real LAB manifest")
	if manifest.is_empty():
		_finish()
		return
	_controller_contract(manifest)
	_live_frame_contract(manifest)
	_deferred_debt_contract(manifest)
	_finish()

func _controller_contract(manifest: Dictionary) -> void:
	var continuous: Object = _controller(manifest)
	var integrated: Object = _controller(manifest)
	_compare_checkpoints(continuous, integrated, "genesis")
	for invocation in 3:
		var advanced: Dictionary = integrated.run_budgeted_to_tick(6, 1000000000, 2, 1000)
		_check(bool(advanced.get("success", false)), "controller slice=%d" % invocation)
		if not bool(advanced.get("success", false)):
			return
		_check(int(advanced.replayed_ticks) == 2 and int(advanced.tick) == 2 * (invocation + 1),
			"controller slice=%d commits two full ticks" % invocation)
		_check(int(advanced.remaining_debt_ticks) == 6 - int(advanced.tick),
			"controller tracks uncommitted future ticks")
		var baseline: Dictionary = continuous.run_to_tick(int(integrated.tick()))
		_check(bool(baseline.get("success", false)), "legacy to same frontier")
		_compare_checkpoints(continuous, integrated, "controller slice=%d" % invocation)
	var telemetry: Dictionary = integrated.get_budget_telemetry()
	_check(int(telemetry.calls) == 3 and int(telemetry.replayed_ticks) == 6,
		"telemetry records actual committed ticks")
	_check(int(telemetry.total_call_wall_us) >= int(telemetry.last_call_wall_us)
		and int(telemetry.peak_call_wall_us) >= int(telemetry.last_call_wall_us)
		and int(telemetry.estimated_tick_us) >= 1,
		"monotonic measured latency and calibrated estimate")
	var before: Dictionary = integrated.serialize_state()
	var measurement: Dictionary = integrated.get_budget_telemetry()
	measurement.calls = 9001
	_check(int(integrated.get_budget_telemetry().calls) == 3,
		"host telemetry reads are detached")
	var after: Dictionary = integrated.serialize_state()
	_check(String(before.state_text) == String(after.state_text)
		and String(before.state_hash) == String(after.state_hash),
		"wall-time telemetry absent from canonical checkpoint")

	# A too-small estimated credit grants zero ticks, does not throw away
	# the old frontier or falsely advance the requested scheduler target.
	var starved: Dictionary = integrated.run_budgeted_to_tick(7, 1, 2, 1000)
	_check(bool(starved.get("success", false)) and int(starved.replayed_ticks) == 0
		and int(starved.remaining_debt_ticks) == 1,
		"insufficient budget explicitly retains debt")
	_compare_checkpoints(continuous, integrated, "budget defer")
	_check(integrated.tick() == 6, "budget defer has no canonical tick")
	var invalid: Dictionary = integrated.run_budgeted_to_tick(7, 0, 2, 1000)
	_check(not bool(invalid.get("success", false))
		and integrated.tick() == 6, "invalid budget is rejected without mutation")
	_check(String(before.state_text) == String(integrated.serialize_state().state_text),
		"invalid budget no state change")
	var completed: Dictionary = integrated.run_budgeted_to_tick(7, 1000000000, 2, 1000)
	_check(bool(completed.get("success", false)) and int(completed.replayed_ticks) == 1,
		"budget recovery commits deferred tick")
	var expected: Dictionary = continuous.step()
	_check(bool(expected.get("success", false)), "legacy baseline at 7")
	_compare_checkpoints(continuous, integrated, "recovered debt")

	var snapshot: Dictionary = integrated.serialize_state()
	var manifest_hash := String(snapshot.get("manifest_hash", ""))
	var checksum := String(snapshot.get("state_checksum", ""))
	var reset: Dictionary = integrated.initialize(manifest, {})
	_check(bool(reset.get("success", false)) and integrated.tick() == 0,
		"reinitialize resets canonical tick")
	_check(int(integrated.get_budget_telemetry().calls) == 0,
		"reinitialize resets noncanonical measurements")
	var restored: Dictionary = integrated.load_state(
		String(snapshot.get("state_text", "")), manifest_hash, checksum)
	_check(bool(restored.get("success", false)) and integrated.tick() == 7,
		"externally anchored checkpoint restores canonical frontier")
	_check(int(integrated.get_budget_telemetry().calls) == 0,
		"restore does not resurrect host wall-clock statistics")
	_compare_checkpoints(continuous, integrated, "restore")

func _live_frame_contract(manifest: Dictionary) -> void:
	var live: Object = _controller(manifest)
	var baseline: Object = _controller(manifest)
	var workbench = Workbench.new()
	workbench.controller = live
	workbench.running = true
	workbench.ticks_per_second = 1.0
	workbench.pending_target = {"kind": "tick", "value": 5}
	_check(workbench.configure_live_cpu_budget(true, 1000000000, 2),
		"real workbench accepts budget configuration")
	workbench._process(5.0)
	_check(live.tick() == 2 and workbench.running,
		"frame #1 clamps five owed ticks to two")
	workbench._process(0.0)
	_check(live.tick() == 4 and workbench.running,
		"frame #2 replays two more while retaining debt")
	workbench._process(0.0)
	_check(live.tick() == 5 and not workbench.running,
		"frame #3 finishes without overshooting target")
	_check(bool(baseline.run_to_tick(5).get("success", false)),
		"legacy reference workbench run")
	_compare_checkpoints(baseline, live, "real _process frame loop")
	_check(float(workbench._elapsed) < 0.001,
		"every owed frame tick accounted after completion")
	workbench.free()

func _deferred_debt_contract(manifest: Dictionary) -> void:
	var live: Object = _controller(manifest)
	var baseline: Object = _controller(manifest)
	var workbench = Workbench.new()
	workbench.controller = live
	workbench.running = true
	workbench.ticks_per_second = 1.0
	workbench.pending_target = {"kind": "tick", "value": 3}
	_check(workbench.configure_live_cpu_budget(true, 1, 2),
		"low-budget configuration accepted")
	workbench._process(3.0)
	_check(live.tick() == 0 and workbench.running
		and float(workbench._elapsed) >= 3.0,
		"zero-credit frame keeps exact logical debt")
	_check(workbench.configure_live_cpu_budget(true, 1000000000, 2),
		"budget can be increased without changing biology")
	workbench._process(0.0)
	workbench._process(0.0)
	_check(live.tick() == 3 and not workbench.running,
		"queued logical time fully drains after more credits")
	_check(bool(baseline.run_to_tick(3).get("success", false)),
		"legacy reference after debt recovery")
	_compare_checkpoints(baseline, live, "defer then resume")
	workbench.free()

func _finish() -> void:
	print("ECO_ARCH2_A14_4_LIVE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_4_LIVE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
