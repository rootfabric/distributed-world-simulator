extends SceneTree
## A14.5 R3 descriptive stage latency, cancellation/memory and exactness.
## Each sample is host wall time (NOT CPU-time/hard deadline), separate
## from the canonical field/population/checkpoint and all RNG seeds.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Session = preload("res://scripts/ecology/workbench/staged_frame_session_v1.gd")
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
		push_error("ECO_A14_5_R3_SCALE_FAIL " + label)

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
	var blueprint := _stable_blueprint()
	_check(not blueprint.is_empty(), "stable fixture blueprint")
	if blueprint.is_empty():
		_finish()
		return
	for n in SIZES:
		_evaluate(n, blueprint)
	_finish()

func _evaluate(n: int, blueprint: Dictionary) -> void:
	var initial := _fixture(n, blueprint)
	_check(not initial.is_empty() and initial.population.size() == n,
		"n=%d valid real-scale fixture" % n)
	if initial.is_empty():
		return
	var original := C.encode(initial)
	var source_hash := Runtime.state_hash(initial)
	var start_ref := Time.get_ticks_usec()
	var baseline := Runtime.step_spatial_parallel_advance(initial, _options(), 4, 64, 4, 4)
	var baseline_us := maxi(0, Time.get_ticks_usec() - start_ref)
	_check(bool(baseline.get("success", false)), "n=%d canonical parallel reference" % n)
	if not bool(baseline.get("success", false)):
		return
	var session = Session.new()
	var output: Dictionary = {}
	var phase_calls := 0
	var total_wall_us := 0
	for i in 32:
		var result: Dictionary = session.advance(
			initial, _options(), 1000000000, 1, 2, 64, 8388608)
		_check(bool(result.get("success", false)), "n=%d bounded session call %d" % [n, i])
		if not bool(result.get("success", false)):
			return
		phase_calls += 1
		total_wall_us += int(result.wall_us)
		if bool(result.complete):
			output = result.state
			break
		_check(int(result.replayed_ticks) == 0 and not result.has("state"),
			"n=%d partial stage cannot publish canonical truth" % n)
		_check(C.encode(initial) == original, "n=%d source unchanged" % n)
	_check(not output.is_empty(), "n=%d full staged tick finishes" % n)
	if output.is_empty():
		return
	_check(int(output.tick) == 1 and C.encode(output) == C.encode(baseline.state),
		"n=%d staged canonical state equals exact parallel bytewise" % n)
	_check(Runtime.state_hash(output) == Runtime.state_hash(baseline.state),
		"n=%d deterministic final hash equality" % n)
	var anchor := C.digest({"schema": "dws.ecology.a14-5-r3-profile.v1", "n": n})
	var cp_a := Checkpoint.create(anchor, output)
	var cp_b := Checkpoint.create(anchor, baseline.state)
	_check(not cp_a.is_empty() and not cp_b.is_empty()
		and Checkpoint.serialize(cp_a) == Checkpoint.serialize(cp_b),
		"n=%d exact serialized A8 checkpoint bytes" % n)
	_check(C.encode(initial) == original and Runtime.state_hash(initial) == source_hash,
		"n=%d speculative timeline never changed original" % n)
	var status: Dictionary = session.status()
	_check(not bool(status.pending) and int(status.completed_ticks) == 1
		and int(status.cancellations) == 0,
		"n=%d completion not cancellation" % n)
	_check(int(status.peak_cursor_bytes) > 0
		and int(status.peak_cursor_bytes) <= 8388608,
		"n=%d cursor memory cap enforced" % n)
	var phase_stats: Dictionary = status.phase_stats
	for phase in ["BEGIN", "PREPARE", "ALLOCATE", "ADVANCE"]:
		_check(int(phase_stats[phase].samples) > 0,
			"n=%d phase %s observed" % [n, phase])
	print("ECO_A14_5_R3_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-5-r3-stage-wall.v1",
		"population": n,
		"baseline_wall_us": baseline_us,
		"staged_total_wall_us": total_wall_us,
		"staged_peak_call_wall_us": int(status.peak_call_wall_us),
		"phase_calls": phase_calls,
		"phase_stats": phase_stats,
		"peak_cursor_bytes": int(status.peak_cursor_bytes),
		"soft_budget_overruns": int(status.overruns),
		"checkpoint_equal": not cp_a.is_empty() and not cp_b.is_empty()
			and Checkpoint.serialize(cp_a) == Checkpoint.serialize(cp_b),
		"hash": Runtime.state_hash(output),
	}))
func _finish() -> void:
	print("ECO_ARCH2_A14_5_R3_SCALE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_5_R3_SCALE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
