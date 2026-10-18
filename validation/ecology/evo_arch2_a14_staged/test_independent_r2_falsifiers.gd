extends SceneTree
## A14.5 R2 — FRESH verifier independent from product R2 implementation test.
## Only published product HEAD source is imported, never copied in the harness.
## No stage cursor is canonical, persisted or mutation/admission authority.
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

const SCHEMA := "dws.ecology.staged-global-tick.v2"
const COUNTS := [4, 32, 96]
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_5_R2_INDEPENDENT_FAIL " + label)

func options() -> Dictionary:
	return {"mutations_enabled": false, "seed": 20261018}

func fixture(founders: int) -> Dictionary:
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
	var genome := Genome.create(program, "independent A14.5 R2 staged fixture")
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
	var blueprint := Blueprint.create(genome, life)
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"eco.a14-5.r2.independent", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	if blueprint.is_empty() or field.is_empty():
		return {}
	var population: Array = []
	for i in founders:
		var pos := [(i % 8) * 1000 + 500, 0, (int(i / 8) % 8) * 1000 + 500]
		var individual := Lifecycle.individual(
			blueprint, "r2-independent-founder-%03d" % i, pos,
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		if individual.is_empty():
			return {}
		population.append(individual)
	var created := Runtime.create("eco/r2-independent/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if bool(created.get("success", false)) else {}

func _run() -> void:
	for founders in COUNTS:
		_falsify(founders)
	print("ECO_ARCH2_A14_5_R2_INDEPENDENT checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_5_R2_INDEPENDENT " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)

func _falsify(founders: int) -> void:
	var source := fixture(founders)
	check(not source.is_empty(), "n=%d founded exact state" % founders)
	if source.is_empty():
		return
	var canonical_before := C.encode(source)
	var opts := options()
	var members := 8 if founders == 4 else 16
	var baseline := Runtime.step_spatial_parallel_advance(source, opts, 4, members, 4, 4)
	check(bool(baseline.get("success", false)), "n=%d continuous canonical tick" % founders)
	if not bool(baseline.get("success", false)):
		return
	var begin := Runtime.begin_staged_global_tick(source, opts, 4, members)
	check(bool(begin.get("success", false)) and not bool(begin.get("complete", true)),
		"n=%d transient cursor ready" % founders)
	if not bool(begin.get("success", false)):
		return
	var cursor: Dictionary = begin.cursor
	var beginning := C.encode(cursor)
	check(not beginning.is_empty() and String(cursor.schema) == SCHEMA,
		"n=%d versioned compact cursor" % founders)
	check(cursor.checksum == C.digest({
		"schema": SCHEMA, "source_hash": cursor.source_hash,
		"options_hash": cursor.options_hash,
		"lifecycle_checksum": cursor.lifecycle.checksum,
	}), "n=%d compact envelope independently recomputed" % founders)
	var old: Dictionary = cursor.duplicate(true)
	old.schema = "dws.ecology.staged-global-tick.v1"
	check(String(Runtime.resume_staged_global_tick(
		source, opts, old, 1).get("error", "")) == "RUNTIME_STAGED_CURSOR_SCHEMA",
		"n=%d v1 transient schema rejected" % founders)
	var invalid: Dictionary = cursor.duplicate(true)
	invalid.lifecycle.index = 200
	var bad: Dictionary = Runtime.resume_staged_global_tick(source, opts, invalid, 1)
	check(not bool(bad.get("success", false)) and
		"A5_STAGED_CURSOR_CHECKSUM" in String(bad.get("error", "")),
		"n=%d inner nested data protected after outer checksum passes" % founders)
	var corrupted_digest: Dictionary = cursor.duplicate(true)
	corrupted_digest.lifecycle.checksum = "0".repeat(64)
	bad = Runtime.resume_staged_global_tick(source, opts, corrupted_digest, 1)
	check(String(bad.get("error", "")) == "RUNTIME_STAGED_CURSOR_CHECKSUM",
		"n=%d outer checksum binds nested checksum" % founders)
	var changed_opts := opts.duplicate(true)
	changed_opts.seed = 123
	check(String(Runtime.resume_staged_global_tick(
		source, changed_opts, cursor, 1).get("error", "")) == "RUNTIME_STAGED_OPTIONS_CHANGED",
		"n=%d cannot replay with changed options" % founders)
	check(String(Runtime.resume_staged_global_tick(
		baseline.state, opts, cursor, 1).get("error", "")) == "RUNTIME_STAGED_SOURCE_CHANGED",
		"n=%d moved canonical frontier rejected" % founders)
	check(not bool(Runtime.resume_staged_global_tick(
		source, opts, cursor, 0).get("success", false)),
		"n=%d zero quota rejected" % founders)
	check(C.encode(cursor) == beginning and C.encode(source) == canonical_before,
		"n=%d invalid inputs did not mutate source/cursor" % founders)

	# Alternative independent resumptions of same immutable checkpoint.
	var first := Runtime.resume_staged_global_tick(source, opts, cursor, 1)
	var repeat := Runtime.resume_staged_global_tick(source, opts, cursor, 1)
	check(bool(first.get("success", false)) and
		C.encode(first) == C.encode(repeat) and C.encode(cursor) == beginning,
		"n=%d detached deterministic repeat of first stage" % founders)

	var witnessed := {"PREPARE": false, "ALLOCATE": false, "ADVANCE": false}
	var output: Dictionary = {}
	for step in 64:
		var phase := String(cursor.lifecycle.phase)
		if witnessed.has(phase):
			witnessed[phase] = true
		var resumed := Runtime.resume_staged_global_tick(source, opts, cursor, 1)
		check(bool(resumed.get("success", false)), "n=%d stage=%d succeeds" % [founders, step])
		if not bool(resumed.get("success", false)):
			return
		check(C.encode(source) == canonical_before,
			"n=%d stage=%d source untouched" % [founders, step])
		if bool(resumed.get("complete", false)):
			output = resumed
			break
		check(not resumed.has("state") and resumed.has("cursor"),
			"n=%d stage=%d publishes no partial state" % [founders, step])
		cursor = resumed.cursor
		check(C.encode(cursor).to_utf8_buffer().size() <= 2097152,
			"n=%d stage=%d transient cursor bounded size" % [founders, step])
	check(bool(output.get("complete", false)), "n=%d stage terminates" % founders)
	if not bool(output.get("complete", false)):
		return
	check(witnessed.PREPARE and witnessed.ALLOCATE and witnessed.ADVANCE,
		"n=%d all barriers explicitly executed" % founders)
	check(int(output.state.tick) == int(source.tick) + 1,
		"n=%d exactly one canonical tick commits" % founders)
	check(C.encode(output.state) == C.encode(baseline.state),
		"n=%d staged final state byte-identical" % founders)
	check(Runtime.state_hash(output.state) == Runtime.state_hash(baseline.state),
		"n=%d staged final state hash equal" % founders)
	var anchor := C.digest({"schema": "independent-frozen-r2", "founders": founders})
	var cpA := Checkpoint.create(anchor, baseline.state)
	var cpB := Checkpoint.create(anchor, output.state)
	check(not cpA.is_empty() and not cpB.is_empty(), "n=%d two checkpoints valid" % founders)
	if not cpA.is_empty() and not cpB.is_empty():
		check(Checkpoint.serialize(cpA) == Checkpoint.serialize(cpB),
			"n=%d full checkpoint bytes equal" % founders)
	check(C.encode(source) == canonical_before,
		"n=%d source never advanced speculatively" % founders)
