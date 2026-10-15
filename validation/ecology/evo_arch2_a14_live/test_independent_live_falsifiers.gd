extends SceneTree
## ECO A14.4 fresh independent contract on the real live ExperimentController.
## Uses its own control flow, data checks and workbench frame replays;
## never derives expected results from the budgeted algorithm itself.
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var fails := 0

func _initialize() -> void:
	call_deferred("_audit")

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		push_error("A14_4_FRESH_VERIFIER_FAIL " + name)

func build_manifest() -> Dictionary:
	var host = Host.new()
	host._build_manifest()
	var manifest: Dictionary = host.manifest.duplicate(true)
	host.free()
	return manifest

func start(manifest: Dictionary) -> Object:
	var c = Controller.new()
	var init: Dictionary = c.initialize(manifest, {})
	check(bool(init.get("success", false)), "start LAB controller")
	return c

func equivalence(a: Object, b: Object, name: String) -> void:
	var left: Dictionary = a.serialize_state()
	var right: Dictionary = b.serialize_state()
	check(bool(left.get("success", false)) and bool(right.get("success", false)),
		name + " both checkpoints valid")
	if bool(left.get("success", false)) and bool(right.get("success", false)):
		check(String(left.state_text) == String(right.state_text),
			name + " serialized checkpoints identical")
		check(String(left.state_hash) == String(right.state_hash),
			name + " canonical hash identical")

func _audit() -> void:
	var manifest := build_manifest()
	check(not manifest.is_empty(), "real LAB host manifest")
	if manifest.is_empty():
		_finish()
		return
	var reference: Object = start(manifest)
	var actual: Object = start(manifest)
	equivalence(reference, actual, "genesis")
	for endpoint in [1, 3, 4, 6]:
		var before: Dictionary = actual.serialize_state()
		var credits: Dictionary = actual.run_budgeted_to_tick(endpoint, 1000000000, 2, 1000)
		check(bool(credits.get("success", false)), "budgeted endpoint %d success" % endpoint)
		if not bool(credits.get("success", false)):
			_finish()
			return
		check(int(credits.replayed_ticks) > 0 and int(credits.replayed_ticks) <= 2,
			"budgeted endpoint %d max two whole ticks" % endpoint)
		check(int(credits.remaining_debt_ticks) == endpoint - int(actual.tick()),
			"budgeted endpoint %d debt accounting" % endpoint)
		var legacy: Dictionary = reference.run_to_tick(int(actual.tick()))
		check(bool(legacy.get("success", false)), "legacy endpoint %d" % endpoint)
		equivalence(reference, actual, "endpoint %d" % endpoint)
		check(String(before.state_hash) != String(actual.serialize_state().state_hash),
			"endpoint %d was a true canonical transition" % endpoint)
	# Headroom denied: zero replay and exact retained debt, no fake state.
	var zero: Dictionary = actual.run_budgeted_to_tick(7, 1, 2, 1000)
	check(bool(zero.get("success", false))
		and int(zero.get("replayed_ticks", -1)) == 0
		and int(zero.get("remaining_debt_ticks", -1)) == 1,
		"zero-credit deferral")
	equivalence(reference, actual, "zero-credit original state")
	var trusted: Dictionary = actual.serialize_state()
	var telemetry: Dictionary = actual.get_budget_telemetry()
	check(int(telemetry.get("calls", 0)) > 0
		and int(telemetry.get("last_call_wall_us", -1)) >= 0,
		"real wall-clock statistics visible")
	check(String(trusted.state_text) == String(actual.serialize_state().state_text),
		"telemetry does not change checkpoint truth")

	# Drive production LAB UI _process, not just detached scheduler calls.
	var bench = Workbench.new()
	bench.controller = actual
	bench.running = true
	bench.ticks_per_second = 1.0
	bench.pending_target = {"kind": "tick", "value": 9}
	check(bench.configure_live_cpu_budget(true, 1000000000, 1),
		"workbench accepts one-tick frame clamp")
	bench._process(2.0)
	check(int(actual.tick()) == 7 and bench.running,
		"first frame advances exactly one tick")
	bench._process(0.0)
	check(int(actual.tick()) == 8 and bench.running,
		"second frame consumes accumulated debt")
	bench._process(1.0)
	check(int(actual.tick()) == 9 and not bench.running,
		"third frame completes requested absolute target")
	check(bool(reference.run_to_tick(9).get("success", false)),
		"sequential reference reaches same tick")
	equivalence(reference, actual, "real UI frame accumulation")
	check(bench._elapsed < 0.001, "no logical frame debt discarded")
	bench.free()

	var anchor: Dictionary = actual.serialize_state()
	check(bool(actual.initialize(manifest, {}).get("success", false)),
		"reset controller")
	check(int(actual.get_budget_telemetry().get("calls", -1)) == 0,
		"reset wipes only noncanonical telemetry")
	var restore: Dictionary = actual.load_state(
		String(anchor.state_text), String(anchor.manifest_hash),
		String(anchor.state_checksum))
	check(bool(restore.get("success", false)) and int(actual.tick()) == 9,
		"checkpoint external anchor restored")
	equivalence(reference, actual, "trusted restore")
	_finish()

func _finish() -> void:
	print("ECO_ARCH2_A14_4_INDEPENDENT checks=%d failed=%d" % [checks, fails])
	print("ECO_ARCH2_A14_4_INDEPENDENT " + ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
