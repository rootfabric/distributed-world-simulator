extends SceneTree
## ECO ARCH2 A14.5 R1: controlled, interruption-safe staged GLOBAL tick.
## Red/green falsifiers: no intermediate canonical state, same global allocation,
## exact final checkpoint/Runtime bytes, stale source/options/cursor rejection.
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

const SIZES := [4, 32, 96, 256]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_A14_5_STAGED_FAIL " + label)

func _options() -> Dictionary:
	return {"mutations_enabled": false, "seed": 20261015}

func _stable_blueprint() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA, "entry": "grow", "max_age": 64,
		"max_depth": 1, "rules": [Program.rule("grow", [
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
	life.reproduction.endowment = {
		"material_mg": 100, "water_mg": 100, "energy_mj": 100}
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
		var x: int = (i % 8) * 1000 + 500
		var z: int = (int(i / 8) % 8) * 1000 + 500
		var entry := Lifecycle.individual(
			blueprint, "a14-4-founder-%03d" % i, [x, 0, z],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		if entry.is_empty():
			return {}
		population.append(entry)
	var created := Runtime.create("eco/a14-4/stress/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if bool(created.get("success", false)) else {}


func _run() -> void:
	var blueprint := _stable_blueprint()
	_check(not blueprint.is_empty(), "stable canonical blueprint")
	if blueprint.is_empty():
		_finish()
		return
	for n in SIZES:
		_test_at_scale(n, blueprint)
	_finish()

func _test_at_scale(n: int, blueprint: Dictionary) -> void:
	var initial := _fixture(n, blueprint)
	_check(not initial.is_empty(), "n=%d canonical fixture" % n)
	if initial.is_empty():
		return
	var opts := _options()
	var original_bytes := C.encode(initial)
	var reference := Runtime.step_spatial_parallel_advance(
		initial, opts, 4, 16, 4, 4)
	_check(bool(reference.get("success", false)), "n=%d reference global tick" % n)
	if not bool(reference.get("success", false)):
		return
	var started := Runtime.begin_staged_global_tick(initial, opts, 4, 16)
	_check(bool(started.get("success", false))
		and not bool(started.get("complete", true)), "n=%d stage begins" % n)
	if not bool(started.get("success", false)):
		return

	# Reject incompatible contracts before performing even one workset.
	var invalid_quota := Runtime.resume_staged_global_tick(
		initial, opts, started.cursor, 0)
	_check(not bool(invalid_quota.get("success", false))
		and C.encode(initial) == original_bytes, "n=%d zero quota fail closed" % n)
	var modified_options := opts.duplicate(true)
	modified_options.seed = int(modified_options.seed) + 1
	var wrong_options := Runtime.resume_staged_global_tick(
		initial, modified_options, started.cursor, 1)
	_check(not bool(wrong_options.get("success", false)),
		"n=%d in-flight options change rejected" % n)
	var stale_source := Runtime.resume_staged_global_tick(
		reference.state, opts, started.cursor, 1)
	_check(not bool(stale_source.get("success", false)),
		"n=%d source frontier changed rejected" % n)
	var forged := started.cursor.duplicate(true)
	forged.lifecycle.index = 987
	var forged_result := Runtime.resume_staged_global_tick(
		initial, opts, forged, 1)
	_check(not bool(forged_result.get("success", false)),
		"n=%d forged cursor rejected" % n)

	var seen := {"PREPARE": true}
	var cursor: Dictionary = started.cursor
	var finished: Dictionary = {}
	var rounds := 0
	while rounds < 128:
		rounds += 1
		var result := Runtime.resume_staged_global_tick(initial, opts, cursor, 1)
		_check(bool(result.get("success", false)),
			"n=%d resume %d" % [n, rounds])
		if not bool(result.get("success", false)):
			return
		seen[String(result.get("phase", "?"))] = true
		_check(C.encode(initial) == original_bytes,
			"n=%d never modifies source during staging" % n)
		if bool(result.get("complete", false)):
			finished = result
			break
		_check(not result.has("state") and result.has("cursor"),
			"n=%d pending stage has no published canonical state" % n)
		cursor = result.cursor
	_check(bool(finished.get("complete", false)),
		"n=%d completes in bounded number of calls" % n)
	if not bool(finished.get("complete", false)):
		return
	_check(seen.has("PREPARE") and seen.has("ALLOCATE")
		and seen.has("ADVANCE") and seen.has("COMPLETE"),
		"n=%d all staged barriers witnessed" % n)
	_check(rounds >= 3 and int(finished.state.tick) == 1,
		"n=%d A5 phases cross calls, only one canonical tick" % n)
	_check(Runtime.validate(finished.state).is_empty(),
		"n=%d completed canonical state sealed and valid" % n)
	_check(C.encode(reference.state) == C.encode(finished.state),
		"n=%d reference and staged global tick byte equal" % n)
	_check(Runtime.state_hash(reference.state) == Runtime.state_hash(finished.state),
		"n=%d reference and staged state hash equal" % n)
	var anchor := C.digest({"schema": "dws.ecology.a14-5-checkpoint.v1", "n": n})
	var a := Checkpoint.create(anchor, reference.state)
	var b := Checkpoint.create(anchor, finished.state)
	_check(not a.is_empty() and not b.is_empty(),
		"n=%d checkpoints valid" % n)
	if not a.is_empty() and not b.is_empty():
		_check(Checkpoint.serialize(a) == Checkpoint.serialize(b),
			"n=%d persisted checkpoint bytes unchanged" % n)

	# A second consecutive tick must also match the accepted global path.
	var next_reference := Runtime.step_spatial_parallel_advance(
		reference.state, opts, 4, 16, 4, 4)
	_check(bool(next_reference.get("success", false)),
		"n=%d canonical reference tick two" % n)
	if not bool(next_reference.get("success", false)):
		return
	var second := Runtime.begin_staged_global_tick(finished.state, opts, 4, 16)
	_check(bool(second.get("success", false)),
		"n=%d stages restart only after first commit" % n)
	if not bool(second.get("success", false)):
		return
	var second_cursor: Dictionary = second.cursor
	for attempt in 128:
		var advanced := Runtime.resume_staged_global_tick(
			finished.state, opts, second_cursor, 2)
		_check(bool(advanced.get("success", false)), "n=%d tick two stage" % n)
		if not bool(advanced.get("success", false)):
			return
		if bool(advanced.get("complete", false)):
			_check(C.encode(advanced.state) == C.encode(next_reference.state),
				"n=%d second tick exact bytes" % n)
			return
		second_cursor = advanced.cursor
	_check(false, "n=%d second tick terminated" % n)

func _finish() -> void:
	print("ECO_ARCH2_A14_5_STAGED checks=%d failed=%d" % [checks, failures])
	print("ECO_ARCH2_A14_5_STAGED " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
