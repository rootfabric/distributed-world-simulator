extends SceneTree
## ECO ARCH2 A14.6 R2: frozen A5 global-allocator lifecycle parity.
## Each sample is host wall time (NOT CPU-time/hard deadline), separate
## from the canonical field/population/checkpoint and all RNG seeds.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const R2 = preload("res://scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

const SIZES := [4, 32, 96, 256]
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_6_R2_LIFECYCLE_FAIL " + label)

func _options() -> Dictionary:
	return {"mutations_enabled": false, "seed": 20261015}

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

func _run() -> void:
	var blueprint: Dictionary = _stable_blueprint()
	_check(not blueprint.is_empty(), "accepted 4/96/256 biological founder fixture")
	if blueprint.is_empty():
		_finish()
		return
	for n in [4, 96, 256]:
		_check_in_real_global_tick(n, blueprint)
	_finish()

func _check_in_real_global_tick(n: int, blueprint: Dictionary) -> void:
	var initial: Dictionary = _fixture(n, blueprint)
	_check(not initial.is_empty(), "n=%d valid actual Runtime source" % n)
	if initial.is_empty():
		return
	var immutable_bytes: String = C.encode(initial)
	var opts: Dictionary = _options()
	var baseline: Dictionary = Runtime.step_spatial_parallel_advance(
		initial, opts, 4, 64, 4, 4)
	_check(bool(baseline.get("success", false)), "n=%d accepted global Parallel Advance" % n)
	if not bool(baseline.get("success", false)):
		return
	var begun: Dictionary = Runtime.begin_staged_global_tick(initial, opts, 4, 64)
	_check(bool(begun.get("success", false)), "n=%d accepted A5 staged begin" % n)
	if not bool(begun.get("success", false)):
		return
	var cursor: Dictionary = begun.cursor
	var prepare_calls := 0
	for i in 32:
		if String(cursor.lifecycle.phase) != "PREPARE":
			break
		var next: Dictionary = Runtime.resume_staged_global_tick(
			initial, opts, cursor, 1)
		_check(bool(next.get("success", false))
			and not bool(next.get("complete", true)), "n=%d real A5 PREPARE stage" % n)
		if not bool(next.get("success", false)):
			return
		cursor = next.cursor
		prepare_calls += 1
	_check(prepare_calls > 0 and String(cursor.lifecycle.phase) == "ALLOCATE",
		"n=%d A5 reached unique global ALLOCATE frontier" % n)
	if String(cursor.lifecycle.phase) != "ALLOCATE":
		return
	var demands: Array = cursor.lifecycle.demands.duplicate(true)
	_check(not demands.is_empty() and demands.size() <= FieldContract.MAX_BATCH,
		"n=%d original A5 generated real A4 demand batch" % n)
	if demands.is_empty():
		return
	var field: Dictionary = initial.field
	var start: Dictionary = R2.begin(field, demands,
		String(field.owner_token), int(field.owner_epoch), int(field.revision),
		16777216)
	_check(bool(start.get("success", false)),
		"n=%d detached A4 staged prototype accepted A5 demands" % n)
	if not bool(start.get("success", false)):
		return
	var prototype_cursor: Dictionary = start.cursor
	var completed: Dictionary = {}
	var observed := {"NORMALIZE": false, "BUILD_CLAIMS": false,
		"PRIMARY": false, "RESIDUAL": false, "FINALIZE": false}
	var peak_bytes := 0
	for iteration in 80:
		var phase: String = String(prototype_cursor.phase)
		observed[phase] = true
		var progressed: Dictionary = R2.resume(field, demands, String(field.owner_token),
			int(field.owner_epoch), int(field.revision), prototype_cursor, 256,
			16777216)
		_check(bool(progressed.get("success", false)),
			"n=%d detached A4 phase=%s: %s" %
			[n, phase, String(progressed.get("error", ""))])
		if not bool(progressed.get("success", false)):
			return
		_check(C.encode(initial) == immutable_bytes and not progressed.has("runtime"),
			"n=%d original full Runtime remains unchanged" % n)
		if bool(progressed.get("complete", false)):
			completed = progressed
			break
		_check(not progressed.has("state") and not progressed.has("grants"),
			"n=%d partial A4 scratch is never a canonical grant result" % n)
		prototype_cursor = progressed.cursor
		var serialized: String = C.encode(prototype_cursor)
		peak_bytes = maxi(peak_bytes, serialized.to_utf8_buffer().size())
	_check(not completed.is_empty() and bool(completed.get("reference_equal", false)),
		"n=%d original A4 and staged full grant/field proof successful" % n)
	if completed.is_empty():
		return
	_check(observed.NORMALIZE and observed.BUILD_CLAIMS and observed.PRIMARY
		and observed.RESIDUAL and observed.FINALIZE,
		"n=%d all staged allocator barriers observed" % n)
	var real_alloc: Dictionary = Runtime.resume_staged_global_tick(
		initial, opts, cursor, 1)
	_check(bool(real_alloc.get("success", false))
		and String(real_alloc.get("phase", "")) == "ADVANCE",
		"n=%d original A5 global allocation runs once" % n)
	if not bool(real_alloc.get("success", false)):
		return
	_check(C.encode(completed.state) ==
		C.encode(real_alloc.cursor.lifecycle.allocated_field),
		"n=%d A5 ALLOCATE Field and standalone staged A4 Field byte exact" % n)
	# A5 aggregates every grant into the recipient resource intake.
	var intake := {}
	for individual in cursor.lifecycle.entries:
		intake[String(individual.state.individual_id)] = FieldContract.stock()
	for grant in completed.grants:
		var id: String = String(grant.organism_id)
		var resource: String = String(grant.resource)
		_check(intake.has(id), "n=%d every A4 recipient exists in A5" % n)
		if intake.has(id):
			intake[id][resource] += int(grant.granted)
	_check(C.encode(intake) ==
		C.encode(real_alloc.cursor.lifecycle.intake_by_id),
		"n=%d original A5 intake map and detached A4 grants exactly match" % n)
	var finished: Dictionary = {}
	cursor = real_alloc.cursor
	for i in 64:
		var step: Dictionary = Runtime.resume_staged_global_tick(initial, opts, cursor, 1)
		_check(bool(step.get("success", false)), "n=%d canonical A5 ADVANCE" % n)
		if not bool(step.get("success", false)):
			return
		if bool(step.get("complete", false)):
			finished = step.state
			break
		_check(not step.has("state"),
			"n=%d no intermediate whole-world Runtime state published" % n)
		cursor = step.cursor
	_check(not finished.is_empty(), "n=%d complete global Runtime tick" % n)
	if finished.is_empty():
		return
	_check(C.encode(finished) == C.encode(baseline.state)
		and Runtime.state_hash(finished) == Runtime.state_hash(baseline.state),
		"n=%d A5/A6 biological state unchanged by detached A4 prototype" % n)
	var anchor: String = C.digest({"schema": "dws.ecology.a14-6-r2-a5-exact.v1",
		"population": n})
	var cpA: Dictionary = Checkpoint.create(anchor, baseline.state)
	var cpB: Dictionary = Checkpoint.create(anchor, finished)
	_check(not cpA.is_empty() and not cpB.is_empty()
		and Checkpoint.serialize(cpA) == Checkpoint.serialize(cpB),
		"n=%d A8 checkpoint bytes identical to existing canonical reference" % n)
	_check(C.encode(initial) == immutable_bytes,
		"n=%d original biological snapshot immutable throughout" % n)
	print("ECO_A14_6_R2_LIFECYCLE_JSON " + JSON.stringify({
		"population": n, "a4_demands": demands.size(),
		"prepare_worksets": prepare_calls,
		"prototype_peak_cursor_bytes": peak_bytes,
		"allocator_grants_hash": String(completed.grants_hash),
		"field_hash": String(completed.state_hash),
		"runtime_hash": Runtime.state_hash(finished),
		"checkpoint_equal": not cpA.is_empty() and not cpB.is_empty() and
			Checkpoint.serialize(cpA) == Checkpoint.serialize(cpB),
	}))

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R2_LIFECYCLE checks=%d failed=%d" %
		[checks, failed])
	print("ECO_ARCH2_A14_6_R2_LIFECYCLE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
