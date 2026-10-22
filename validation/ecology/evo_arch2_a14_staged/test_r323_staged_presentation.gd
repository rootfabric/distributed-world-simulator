extends SceneTree
## A14.6 R3.2.3 — test-only 4/32/96/256 Controller-owned fast admission.
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
		push_error("ECO_A14_6_R323_PRESENTATION_FAIL " + label)

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
			_check(false, "R323_INVALID_POPULATION_ARGUMENT")
			_finish()
			return
		sizes = [int(args[1])]
	for n in sizes:
		print("ECO_A14_6_R323_PRESENTATION_BEGIN population=%d" % n)
		await _profile(n, blueprint)
	_finish()

func _profile(n: int, blueprint: Dictionary) -> void:
	var source: Dictionary = _fixture(n, blueprint)
	_check(not source.is_empty() and source.population.size() == n,
		"n=%d exact canonical fixture" % n)
	if source.is_empty():
		return
	var original_source: String = C.encode(source)
	var ctrl = Controller.new()
	var started: Dictionary = ctrl.initialize(_manifest(), {})
	_check(bool(started.get("success", false)), "n=%d actual LAB initialized" % n)
	if not bool(started.get("success", false)):
		return
	# Test-only exact source adoption occurs BEFORE controller lease creation.
	# This branch never changes the production LAB manifest or world authority.
	ctrl._runtime = source.duplicate(true)
	var opts: Dictionary = ctrl._canonical_step_options()
	_check(bool(opts.get("success", false)), "n=%d canonical options" % n)
	if not bool(opts.get("success", false)):
		return
	var serial: Dictionary = Runtime.step_spatial_parallel_advance(
		source, opts.options, 4, 64, 4, 4)
	_check(bool(serial.get("success", false)), "n=%d serial reference" % n)
	if not bool(serial.get("success", false)):
		return
	var bench = Workbench.new()
	bench.controller = ctrl
	bench._markers_root = Node3D.new()
	bench._markers_root.name = "TestMarkers"
	bench.add_child(bench._markers_root)
	bench._morphology_root = Node3D.new()
	bench._morphology_root.name = "TestMorphology"
	bench.add_child(bench._morphology_root)
	bench._status_bar = Label.new()
	bench.running = true
	bench.ticks_per_second = 1.0
	bench.pending_target = {"kind": "tick", "value": 1}
	var deliveries: Array = []
	bench.snapshot_updated.connect(func(snapshot: Dictionary) -> void:
		deliveries.append(snapshot)
	)
	_check(not bench.configure_staged_live(true, 1000000000, 1, 1,
		64, 8388608, true, 4096, false, true),
		"n=%d R3.2.3 denied without off-main + R3" % n)
	_check(bench.configure_staged_live(true, 1000000000, 1, 1,
		64, 8388608, true, 4096, true, true),
		"n=%d R3.2.3 explicitly LAB-only opt-in" % n)
	var gui_commit_us := -1
	var max_pending_frame_us := 0
	var pending_frames := 0
	for frame in 12000:
		var started_us: int = Time.get_ticks_usec()
		bench._process(1.0 if frame == 0 else 0.0)
		var elapsed_us: int = maxi(0, Time.get_ticks_usec() - started_us)
		if ctrl.tick() == 1:
			gui_commit_us = elapsed_us
			break
		max_pending_frame_us = maxi(max_pending_frame_us, elapsed_us)
		pending_frames += 1
		_check(ctrl.tick() == 0 and ctrl.has_pending_staged_tick() \
			and deliveries.is_empty(), "n=%d no speculative UI publication" % n)
		await create_timer(0.02).timeout
	_check(ctrl.tick() == 1 and gui_commit_us >= 0 \
		and bench.get_r323_ui_telemetry().pending,
		"n=%d one tick committed, bounded UI geometry still pending" % n)
	var ui_frames := 0
	var ui_peak_us := 0
	for frame in 2000:
		if not bool(bench.get_r323_ui_telemetry().pending):
			break
		var started_us: int = Time.get_ticks_usec()
		bench._process(0.0)
		ui_peak_us = maxi(ui_peak_us, maxi(0, Time.get_ticks_usec() - started_us))
		ui_frames += 1
		# Finishing UI must not advance logical simulation time by itself.
		_check(int(ctrl.tick()) == 1, "n=%d UI pump cannot replay biology" % n)
	var presentation: Dictionary = bench.get_r323_ui_telemetry()
	_check(not bool(presentation.pending) and int(presentation.completed) == 1 \
		and int(presentation.abandoned) == 0 \
		and int(presentation.fallbacks) == 0,
		"n=%d bounded geometry eventually completes without full-snapshot fallback" % n)
	_check(bench._marker_by_id.size() == n and bench._morphology_by_id.size() == n \
		and bench.organism_views.size() == n,
		"n=%d all P3 markers and P6 morphology synchronized" % n)
	_check(deliveries.size() == 1 \
		and int(deliveries[0].tick) == 1 \
		and String(deliveries[0].canonical_state_hash) == String(ctrl._runtime.integrity_hash),
		"n=%d one complete-tick snapshot_updated signal, no partial snapshot" % n)
	# Off-main projector MUST be an exact replacement for legacy get_snapshot.
	# Full legacy computation occurs only OUTSIDE the measured GUI frame.
	var cached: Dictionary = ctrl.get_r323_snapshot()
	var historical: Dictionary = ctrl.get_snapshot()
	_check(bool(cached.get("success", false)) and C.encode(cached) == C.encode(historical),
		"n=%d historical public snapshot bytes equal CPU worker projection" % n)
	var current: Dictionary = ctrl.debug_state().runtime
	_check(C.encode(current) == C.encode(serial.state) \
		and Runtime.state_hash(current) == Runtime.state_hash(serial.state),
		"n=%d exact canonical runtime equality with original serial A4/A5/A6" % n)
	var anchor: String = C.digest({"schema": "dws.eco.r323.presentation.v1", "n": n})
	var serial_ck: Dictionary = Checkpoint.create(anchor, serial.state)
	var worker_ck: Dictionary = Checkpoint.create(anchor, current)
	_check(not serial_ck.is_empty() and not worker_ck.is_empty() \
		and Checkpoint.serialize(serial_ck) == Checkpoint.serialize(worker_ck),
		"n=%d A8 full serialized checkpoint byte exact" % n)
	_check(C.encode(source) == original_source and int(source.tick) == 0,
		"n=%d external canonical fixture immutable" % n)
	var offmain: Dictionary = ctrl.get_staged_telemetry().off_main
	_check(String(offmain.last_admission_mode) == "TRUSTED_CONTROLLER_LEASE" \
		and int(offmain.jobs_started) == 1 and int(offmain.jobs_committed) == 1 \
		and int(offmain.tasks_joined) == 1 \
		and int(offmain.last_projection_wall_us) > 0,
		"n=%d off-main projection uses exact generation, one worker and join" % n)
	print("ECO_A14_6_R323_PRESENTATION_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-6-r323-presentation-profile.v1",
		"population": n,
		"canonical_hash": Runtime.state_hash(current),
		"checkpoint_equal": not serial_ck.is_empty() and not worker_ck.is_empty() \
			and Checkpoint.serialize(serial_ck) == Checkpoint.serialize(worker_ck),
		"snapshot_equal": C.encode(cached) == C.encode(historical),
		"source_unchanged": C.encode(source) == original_source,
		"main_commit_process_wall_us": gui_commit_us,
		"main_pending_process_peak_wall_us": max_pending_frame_us,
		"main_presentation_pump_peak_us": ui_peak_us,
		"main_presentation_begin_peak_us": int(presentation.peak_begin_us),
		"worker_projection_wall_us": int(offmain.last_projection_wall_us),
		"ui_frames": ui_frames, "pending_frames": pending_frames,
		"ui_completed": int(presentation.completed),
		"fallbacks": int(presentation.fallbacks),
		"hard_frame_deadline_claim": false,
		"throughput_improvement_claim": false,
		"fixture_injected_test_only": true,
	}))
	bench._status_bar.free()
	bench.free()

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R323_PRESENTATION checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_6_R323_PRESENTATION " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
