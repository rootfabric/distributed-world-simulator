extends SceneTree
## A14.6 R3.2.2 — test-only 4/32/96/256 Controller-owned fast admission.
## The fixture is injected BEFORE the trusted lease exists, into a deep-
## detached private Controller Runtime. This measures the real Controller /
## Workbench execution path on a large canonical fixture, NOT a user-facing
## 256-founder LAB manifest or production-scale approval.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const LabHost = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

const SIZES := [4, 32, 96, 256]
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_6_R322_TRUSTED_FAIL " + label)

func _stable_blueprint() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA, "entry": "grow", "max_age": 64,
		"max_depth": 1,
		"rules": [Program.rule("grow", [
			Program.action("differentiate", "collector", [0, 2, 0], 1, 10000),
			Program.action("differentiate", "absorber", [0, -2, 0], 1, 0, 100),
			Program.action("differentiate", "reproductive", [2, 0, 0], 1),
			Program.action("retire"),
		])],
	}
	var genome := Genome.create(program, "a14-4 scale profile stable founder")
	var life := LifeHistory.create_default()
	life.regulation.growth_light_min = 0
	life.regulation.growth_water_min = 0
	life.regulation.growth_competition_max = 1000
	life.regulation.growth_temperature_min = 0
	life.regulation.growth_temperature_max = 1000
	life.metabolism.maintenance_energy_per_module_mj = 0
	life.metabolism.maintenance_water_per_module_mg = 0
	life.growth.transfer_permille = 500
	life.reproduction.maturity_ticks = 1000
	life.reproduction.interval_ticks = 2
	life.reproduction.required_reproductive_modules = 1
	life.reproduction.offspring_per_event = 1
	life.reproduction.endowment = {"material_mg": 100, "water_mg": 100, "energy_mj": 100}
	life.reproduction.fee_energy_mj = 0
	return Blueprint.create(genome, life)

func _fixture(n: int, blueprint: Dictionary) -> Dictionary:
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a14-4.profile", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	if field.is_empty():
		return {}
	var population: Array = []
	for i in n:
		var pos := [(i % 8) * 1000 + 500, 0, (int(i / 8) % 8) * 1000 + 500]
		var member := Lifecycle.individual(
			blueprint, "a14-4-founder-%03d" % i, pos,
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		if member.is_empty():
			return {}
		population.append(member)
	var created := Runtime.create("eco/a14-4/stress/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if bool(created.get("success", false)) else {}


func _manifest() -> Dictionary:
	var host = LabHost.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	# Deterministic, mutation-disabled options for the exact stress fixture.
	m.seed = 20261015
	m.mutation.mutations_enabled = false
	return m

func _run() -> void:
	var blueprint: Dictionary = _stable_blueprint()
	_check(not blueprint.is_empty(), "canonical legal stable founder")
	if blueprint.is_empty():
		_finish()
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var sizes: Array = SIZES.duplicate()
	if not args.is_empty():
		if args.size() != 2 or String(args[0]) != "--r32-population" \
				or not String(args[1]) in ["4", "32", "96", "256"]:
			_check(false, "R322_INVALID_POPULATION_ARGUMENT")
			_finish()
			return
		sizes = [int(args[1])]
	for n in sizes:
		print("ECO_A14_6_R322_TRUSTED_BEGIN population=%d" % n)
		await _profile(n, blueprint)
	_finish()

func _profile(n: int, blueprint: Dictionary) -> void:
	var source: Dictionary = _fixture(n, blueprint)
	_check(not source.is_empty() and source.population.size() == n,
		"n=%d canonical fixture" % n)
	if source.is_empty():
		return
	var original_bytes: String = C.encode(source)
	var ctrl = Controller.new()
	var initialized: Dictionary = ctrl.initialize(_manifest(), {})
	_check(bool(initialized.get("success", false)), "n=%d real LAB Controller initialized" % n)
	if not bool(initialized.get("success", false)):
		return
	# Test-only fixture replacement, BEFORE lease dispatch. Deep copy ensures
	# the active Controller frontier has no fixture-owned mutable alias.
	ctrl._runtime = source.duplicate(true)
	var opts: Dictionary = ctrl._canonical_step_options()
	_check(bool(opts.get("success", false)), "n=%d accepted controller options" % n)
	if not bool(opts.get("success", false)):
		return
	var baseline: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts.options, 4, 64, 4, 4)
	_check(bool(baseline.get("success", false)), "n=%d accepted serial reference" % n)
	if not bool(baseline.get("success", false)):
		return
	var bench = Workbench.new()
	bench.controller = ctrl
	bench.ticks_per_second = 1.0
	bench.running = true
	bench.pending_target = {"kind": "tick", "value": 1}
	bench._status_bar = Label.new()
	_check(bench.configure_staged_live(true, 1000000000, 1, 1,
		64, 8388608, true, 4096, true),
		"n=%d explicit LAB-only fast worker opt-in" % n)
	var gui_pending_peak := 0
	var gui_commit_us := -1
	var frame_count := 0
	var pending_frames := 0
	for frame in 12000:
		var started_us: int = Time.get_ticks_usec()
		bench._process(1.0 if frame == 0 else 0.0)
		var gui_wall_us: int = maxi(0, Time.get_ticks_usec() - started_us)
		frame_count += 1
		if ctrl.tick() == 1:
			gui_commit_us = gui_wall_us
			break
		gui_pending_peak = maxi(gui_pending_peak, gui_wall_us)
		pending_frames += 1
		_check(ctrl.tick() == 0 and ctrl.has_pending_staged_tick(),
			"n=%d pending frame cannot publish tick or grants" % n)
		await create_timer(0.02).timeout
	_check(ctrl.tick() == 1 and not bench.running and pending_frames > 0,
		"n=%d exactly one atomic LAB Controller + Workbench commit" % n)
	var actual: Dictionary = ctrl.debug_state().runtime
	_check(C.encode(actual) == C.encode(baseline.state) \
		and Runtime.state_hash(actual) == Runtime.state_hash(baseline.state),
		"n=%d full Runtime bytes/hash equal serial reference" % n)
	var anchor: String = C.digest({
		"schema": "dws.ecology.a14-6-r322-trusted-scale.v1",
		"population": n})
	var ck1: Dictionary = Checkpoint.create(anchor, baseline.state)
	var ck2: Dictionary = Checkpoint.create(anchor, actual)
	_check(not ck1.is_empty() and not ck2.is_empty() \
		and Checkpoint.serialize(ck1) == Checkpoint.serialize(ck2),
		"n=%d A8 checkpoint serialized bytes exact" % n)
	_check(C.encode(source) == original_bytes and int(source.tick) == 0,
		"n=%d external fixture remains untouched by trusted worker" % n)
	var telemetry: Dictionary = ctrl.get_staged_telemetry().off_main
	_check(String(telemetry.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE" \
		and int(telemetry.jobs_started) == 1 \
		and int(telemetry.jobs_committed) == 1 \
		and int(telemetry.tasks_joined) == 1 \
		and not bool(telemetry.pending) and not bool(telemetry.abandoned_draining),
		"n=%d one trusted worker, one complete commit, one join" % n)
	_check(int(telemetry.last_worker_source_validate_wall_us) > 0 \
		and int(telemetry.last_worker_candidate_validate_wall_us) > 0,
		"n=%d full source and candidate validation occurred on worker" % n)
	print("ECO_A14_6_R322_TRUSTED_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-6-r322-trusted-scale-observation.v1",
		"population": n,
		"canonical_hash": Runtime.state_hash(actual),
		"checkpoint_equal": not ck1.is_empty() and not ck2.is_empty() \
			and Checkpoint.serialize(ck1) == Checkpoint.serialize(ck2),
		"source_unchanged": C.encode(source) == original_bytes,
		"main_source_admission_wall_us": int(telemetry.last_source_admission_wall_us),
		"worker_source_validate_wall_us": int(telemetry.last_worker_source_validate_wall_us),
		"worker_candidate_validate_wall_us": int(telemetry.last_worker_candidate_validate_wall_us),
		"main_commit_process_wall_us": gui_commit_us,
		"main_pending_process_peak_wall_us": gui_pending_peak,
		"frames": frame_count, "pending_frames": pending_frames,
		"hard_frame_deadline_claim": false,
		"cpu_throughput_speedup_claim": false,
		"fixture_injected_test_only": true,
	}))
	bench._status_bar.free()
	bench.free()

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R322_TRUSTED checks=%d failed=%d" %
		[checks, failed])
	print("ECO_ARCH2_A14_6_R322_TRUSTED " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
