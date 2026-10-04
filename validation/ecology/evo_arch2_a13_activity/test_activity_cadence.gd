extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Activity = preload("res://scripts/research/ecology/v2/population_activity_cadence_plan_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A13_ACTIVITY_FAIL " + message)

func _run() -> void:
	var initial := _dynamic_runtime()
	check(not initial.is_empty(), "activity fixture starts")
	if not initial.is_empty():
		_plan_contract(initial)
		_runtime_contract(initial)
	print("EVO_ARCH2_A13_ACTIVITY checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A13_ACTIVITY " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _reproductive_blueprint() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA,
		"entry": "grow",
		"max_age": 64,
		"max_depth": 1,
		"rules": [Program.rule("grow", [
			Program.action("differentiate", "collector", [0, 2, 0], 1, 10000),
			Program.action("differentiate", "absorber", [0, -2, 0], 1, 0, 100),
			Program.action("differentiate", "reproductive", [2, 0, 0], 1),
			Program.action("retire"),
		])],
	}
	var genome := Genome.create(program, "A13 activity cadence reproductive fixture")
	var policy := LifeHistory.create_default()
	policy.regulation.growth_light_min = 0
	policy.regulation.growth_water_min = 0
	policy.regulation.growth_competition_max = 1000
	policy.regulation.growth_temperature_min = 0
	policy.regulation.growth_temperature_max = 1000
	policy.metabolism.maintenance_energy_per_module_mj = 0
	policy.metabolism.maintenance_water_per_module_mg = 0
	policy.growth.transfer_permille = 500
	policy.reproduction.maturity_ticks = 2
	policy.reproduction.interval_ticks = 2
	policy.reproduction.required_reproductive_modules = 1
	policy.reproduction.offspring_per_event = 1
	policy.reproduction.endowment = {"material_mg": 100, "water_mg": 100, "energy_mj": 100}
	policy.reproduction.fee_energy_mj = 0
	return Blueprint.create(genome, policy)

func _dynamic_runtime() -> Dictionary:
	var blueprint := _reproductive_blueprint()
	check(not blueprint.is_empty(), "activity blueprint validates")
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.activity.dynamic", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "activity field validates")
	if blueprint.is_empty() or field.is_empty():
		return {}
	var positions := [
		[500, 0, 500],
		[4500, 0, 500],
		[500, 0, 4500],
		[4500, 0, 4500],
	]
	var population: Array = []
	for i in positions.size():
		var individual := Lifecycle.individual(
			blueprint, "activity-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		check(not individual.is_empty(), "activity founder %d valid" % i)
		population.append(individual)
	var created := Runtime.create(
		"eco/a13/activity-runtime/v1", field, population,
		Feedback.default_policy(), false)
	check(created.success, "activity runtime canonical")
	return created.state if created.success else {}

func _addresses(state: Dictionary) -> Array:
	var spatial := Spatial.create(state.field, state.population, 4, 64)
	if spatial.is_empty():
		return []
	var seen := {}
	for unit in spatial.worksets:
		seen[String(unit.address)] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func _options() -> Dictionary:
	return {
		"mutations_enabled": true,
		"operator": "module_parameter",
		"seed": 20261004,
		"mutation_key_prefix": "eco-a13-activity-r1",
	}

func _plan_contract(initial: Dictionary) -> void:
	var addresses := _addresses(initial)
	check(addresses.size() == 4, "fixture occupies four stable spatial tiles")
	check(addresses == [
		"tile/0000/0000", "tile/0000/0001",
		"tile/0001/0000", "tile/0001/0001",
	], "fixture tile addresses canonical")

	var active := ["tile/0000/0000"]
	var deferred := Activity.create(initial.field, initial.population, active, 0, 1, 4, 4, 64)
	check(not deferred.is_empty(), "mixed activity plan created before sleeping cadence")
	check(Activity.validate(deferred, initial.field, initial.population).is_empty(), "mixed activity plan validates")
	check(String(deferred.schema) == Activity.SCHEMA, "activity plan schema exact")
	check(int(deferred.debt_ticks) == 1, "one scheduler tick becomes one deferred debt tick")
	check(int(deferred.active_tile_count) == 1, "one tile classified ACTIVE")
	check(int(deferred.sleeping_tile_count) == 3, "three tiles classified SLEEPING")
	check(not bool(deferred.global_commit_ready), "global canonical commit blocked before sleeping cadence")
	check(int(deferred.catch_up_ticks) == 0, "blocked plan cannot report canonical catch-up")
	check(deferred.active_addresses == active, "active address canonicalized")
	check(int(deferred.tile_count) == 4, "activity plan covers every spatial tile")

	var tile_classes := {}
	for tile in deferred.tiles:
		tile_classes[String(tile.address)] = String(tile.classification)
		check(int(tile.member_count) == 1, "each fixture tile contains one member")
		check(int(tile.shard_count) == 1, "each fixture tile contains one shard")
		check(int(tile.cadence_ticks) == (1 if tile.classification == Activity.CLASS_ACTIVE else 4),
			"tile cadence follows classification")
	check(String(tile_classes["tile/0000/0000"]) == Activity.CLASS_ACTIVE, "requested tile ACTIVE")
	check(String(tile_classes["tile/0000/0001"]) == Activity.CLASS_SLEEPING, "unrequested tile SLEEPING")
	check(String(tile_classes["tile/0001/0000"]) == Activity.CLASS_SLEEPING, "second unrequested tile SLEEPING")
	check(String(tile_classes["tile/0001/0001"]) == Activity.CLASS_SLEEPING, "third unrequested tile SLEEPING")

	var wake := Activity.create(initial.field, initial.population, active, 0, 4, 4, 4, 64)
	check(not wake.is_empty(), "wake plan created at deterministic cadence")
	check(bool(wake.global_commit_ready), "sleeping cadence due opens exact global commit")
	check(int(wake.catch_up_ticks) == 4, "wake owes all four canonical ticks")
	check(int(wake.debt_ticks) == 4, "wake debt exact")
	for tile in wake.tiles:
		if String(tile.classification) == Activity.CLASS_SLEEPING:
			check(bool(tile.due), "every sleeping tile due at cadence boundary")
			check(int(tile.next_due_scheduler_tick) == 4, "sleeping next due tick deterministic")

	var all_active := Activity.create(initial.field, initial.population, addresses, 0, 1, 4, 4, 64)
	check(not all_active.is_empty(), "all-active plan created")
	check(int(all_active.sleeping_tile_count) == 0, "all-active plan has no sleeping tiles")
	check(bool(all_active.global_commit_ready), "all-active plan can commit every scheduler tick")
	check(int(all_active.catch_up_ticks) == 1, "all-active one tick commits one canonical tick")

	var all_sleeping_early := Activity.create(initial.field, initial.population, [], 0, 3, 4, 4, 64)
	var all_sleeping_due := Activity.create(initial.field, initial.population, [], 0, 4, 4, 4, 64)
	check(not all_sleeping_early.is_empty() and not all_sleeping_due.is_empty(), "all-sleeping plans created")
	check(not bool(all_sleeping_early.global_commit_ready), "all-sleeping state remains deferred before cadence")
	check(bool(all_sleeping_due.global_commit_ready), "all-sleeping state wakes at cadence")
	check(int(all_sleeping_due.catch_up_ticks) == 4, "all-sleeping wake catches exact debt")

	var late := Activity.create(initial.field, initial.population, active, 0, 7, 4, 4, 64)
	check(not late.is_empty() and bool(late.global_commit_ready), "late wake remains deterministically catch-up eligible")
	check(int(late.catch_up_ticks) == 7, "late wake replays every missed canonical tick")

	var noop := Activity.create(initial.field, initial.population, active, 0, 0, 4, 4, 64)
	check(not noop.is_empty(), "zero-debt plan valid")
	check(bool(noop.global_commit_ready) and int(noop.catch_up_ticks) == 0, "zero-debt plan is canonical no-op")

	var unordered_active := ["tile/0001/0001", "tile/0000/0000"]
	var canonical_active := Activity.create(initial.field, initial.population, unordered_active, 0, 1, 4, 4, 64)
	check(canonical_active.active_addresses == ["tile/0000/0000", "tile/0001/0001"],
		"active address input order cannot affect plan")

	var reversed_population: Array = initial.population.duplicate(true)
	reversed_population.reverse()
	var permuted := Activity.create(initial.field, reversed_population, active, 0, 4, 4, 4, 64)
	check(C.encode(permuted) == C.encode(wake), "population input permutation cannot affect activity plan")

	check(Activity.create(initial.field, initial.population, ["tile/9999/9999"], 0, 1, 4, 4, 64).is_empty(),
		"unknown active address rejected")
	check(Activity.create(initial.field, initial.population, active, 4, 3, 4, 4, 64).is_empty(),
		"backward scheduler frontier rejected")
	check(Activity.create(initial.field, initial.population, active, 0, 1, 0, 4, 64).is_empty(),
		"zero sleeping cadence rejected")
	check(Activity.create(initial.field, initial.population, active, 0, Activity.MAX_CATCH_UP_TICKS + 1, 4, 4, 64).is_empty(),
		"unbounded deferred debt rejected")

	var tampered := wake.duplicate(true)
	tampered.tiles[0].classification = Activity.CLASS_SLEEPING
	check(Activity.validate(tampered, initial.field, initial.population) == "ACTIVITY_PLAN_CONTENT",
		"tampered activity classification rejected")

	var moved: Array = initial.population.duplicate(true)
	var original: Dictionary = moved[1]
	var replacement := Lifecycle.individual(
		original.blueprint,
		String(original.state.individual_id),
		[4500, 0, 4500],
		original.state.metabolic_reserves.duplicate(true))
	check(not replacement.is_empty(), "stale-plan replacement valid")
	moved[1] = replacement
	check(not Activity.validate(wake, initial.field, moved).is_empty(),
		"canonical position migration invalidates activity plan")

func _continuous(initial: Dictionary, count: int) -> Dictionary:
	var state := initial.duplicate(true)
	for tick_index in count:
		var stepped := Runtime.step_spatial_scheduled(state, _options(), 4, 64)
		check(stepped.success, "continuous reference tick %d succeeds" % (tick_index + 1))
		if not stepped.success:
			return {}
		state = stepped.state
	return state

func _runtime_contract(initial: Dictionary) -> void:
	var active := ["tile/0000/0000"]
	var before_hash := Runtime.state_hash(initial)
	var before_bytes := C.encode(initial)

	var defer_plan := Activity.create(initial.field, initial.population, active, 0, 1, 4, 4, 64)
	var deferred := Runtime.advance_spatial_activity_cadence(initial, _options(), defer_plan)
	check(deferred.success, "runtime accepts pre-wake cadence plan")
	check(bool(deferred.deferred), "runtime reports sleeping debt as deferred")
	check(int(deferred.replayed_ticks) == 0, "deferred runtime executes no canonical tick")
	check(int(deferred.canonical_tick) == 0, "deferred runtime canonical tick unchanged")
	check(int(deferred.scheduler_tick) == 1, "deferred result exposes caller-owned scheduler tick")
	check(Runtime.state_hash(deferred.state) == before_hash, "deferred runtime hash unchanged")
	check(C.encode(deferred.state) == before_bytes, "deferred runtime bytes unchanged")
	check(Runtime.state_hash(initial) == before_hash, "defer leaves source state untouched")

	var continuous8 := _continuous(initial, 8)
	check(not continuous8.is_empty(), "eight-tick continuous reference completes")
	if continuous8.is_empty():
		return

	var wake8_plan := Activity.create(initial.field, initial.population, active, 0, 8, 4, 4, 64)
	var wake8 := Runtime.advance_spatial_activity_cadence(initial, _options(), wake8_plan)
	check(wake8.success, "mixed active/sleeping wake executes")
	check(not bool(wake8.deferred), "due wake is not deferred")
	check(int(wake8.replayed_ticks) == 8, "wake replays complete canonical debt")
	check(int(wake8.scheduler_tick) == 8 and int(wake8.canonical_tick) == 8,
		"scheduler and canonical frontiers meet after catch-up")
	check(bool(wake8.exact_catch_up), "runtime labels R1 path exact catch-up")
	check(Runtime.state_hash(wake8.state) == Runtime.state_hash(continuous8),
		"wake state hash exact-equivalent to continuous execution")
	check(C.encode(wake8.state) == C.encode(continuous8),
		"wake canonical bytes exact-equivalent to continuous execution")
	check(wake8.state.population.size() > initial.population.size(),
		"exact catch-up includes real reproduction, not a synthetic tick jump")

	var wake4_plan := Activity.create(initial.field, initial.population, active, 0, 4, 4, 4, 64)
	var wake4 := Runtime.advance_spatial_activity_cadence(initial, _options(), wake4_plan)
	check(wake4.success and int(wake4.canonical_tick) == 4, "first segmented wake reaches canonical tick 4")
	var active4 := _addresses(wake4.state)
	check(not active4.is_empty(), "post-wake spatial addresses recompute from canonical state")
	var second_wake_plan := Activity.create(
		wake4.state.field, wake4.state.population, active4, 4, 8, 4, 4, 64)
	check(not second_wake_plan.is_empty(), "second cadence epoch anchors at committed canonical tick 4")
	var segmented8 := Runtime.advance_spatial_activity_cadence(wake4.state, _options(), second_wake_plan)
	check(segmented8.success and int(segmented8.replayed_ticks) == 4,
		"second cadence epoch replays only its bounded debt")
	check(C.encode(segmented8.state) == C.encode(continuous8),
		"segmented 0->4->8 cadence is byte-identical to continuous execution")

	var repeated := Runtime.advance_spatial_activity_cadence(initial, _options(), wake8_plan)
	check(repeated.success, "repeated exact catch-up succeeds")
	check(C.encode(repeated.state) == C.encode(wake8.state), "same input/plan produces deterministic catch-up bytes")

	var manifest_hash := C.digest({
		"schema": "dws.ecology.a13-activity-fixture.v1",
		"seed": 20261004,
	})
	var cp_continuous := Checkpoint.create(manifest_hash, continuous8)
	var cp_wake := Checkpoint.create(manifest_hash, wake8.state)
	check(not cp_continuous.is_empty() and not cp_wake.is_empty(), "continuous/wake checkpoints canonical")
	check(Checkpoint.serialize(cp_continuous) == Checkpoint.serialize(cp_wake),
		"activity cadence metadata absent from checkpoint bytes")
	check(not C.encode(wake8.state).contains(Activity.SCHEMA), "activity scheduler schema absent from runtime truth")
	check(not Checkpoint.serialize(cp_wake).contains(Activity.SCHEMA),
		"activity scheduler schema absent from serialized checkpoint")

	var all_addresses := _addresses(initial)
	var continuous1 := _continuous(initial, 1)
	var all_active_plan := Activity.create(initial.field, initial.population, all_addresses, 0, 1, 4, 4, 64)
	var all_active := Runtime.advance_spatial_activity_cadence(initial, _options(), all_active_plan)
	check(all_active.success and not bool(all_active.deferred), "all-active runtime commits immediately")
	check(int(all_active.replayed_ticks) == 1, "all-active runtime advances one exact tick")
	check(C.encode(all_active.state) == C.encode(continuous1), "all-active cadence path exact at one tick")

	var continuous4 := _continuous(initial, 4)
	var all_sleeping_plan := Activity.create(initial.field, initial.population, [], 0, 4, 4, 4, 64)
	var all_sleeping := Runtime.advance_spatial_activity_cadence(initial, _options(), all_sleeping_plan)
	check(all_sleeping.success, "all-sleeping wake executes")
	check(C.encode(all_sleeping.state) == C.encode(continuous4), "all-sleeping wake exact-equivalent at cadence")

	var tampered := wake8_plan.duplicate(true)
	tampered.catch_up_ticks = 7
	var rejected := Runtime.advance_spatial_activity_cadence(initial, _options(), tampered)
	check(not rejected.success, "tampered catch-up plan fails closed")
	check(String(rejected.error) == "RUNTIME_ACTIVITY_PLAN:ACTIVITY_PLAN_CONTENT",
		"tampered catch-up rejection identifies activity plan")
	check(Runtime.state_hash(initial) == before_hash, "tampered plan rejection leaves source runtime unchanged")

	var bad_options := {
		"mutations_enabled": true,
		"operator": "not-an-operator",
		"seed": 1,
	}
	var catchup_failure := Runtime.advance_spatial_activity_cadence(
		initial, bad_options,
		Activity.create(initial.field, initial.population, [], 0, 4, 4, 4, 64))
	check(not catchup_failure.success, "failed replay aborts catch-up")
	check(String(catchup_failure.error).begins_with("RUNTIME_ACTIVITY_CATCH_UP:"),
		"replay failure is surfaced as atomic catch-up failure")
	check(Runtime.state_hash(initial) == before_hash, "failed replay leaves original runtime unchanged")

	var state1 := continuous1
	var addresses1 := _addresses(state1)
	var wrong_frontier_plan := Activity.create(
		state1.field, state1.population, addresses1, 0, 1, 4, 4, 64)
	check(not wrong_frontier_plan.is_empty(), "wrong-frontier plan structurally valid against current biology")
	var wrong_frontier := Runtime.advance_spatial_activity_cadence(state1, _options(), wrong_frontier_plan)
	check(not wrong_frontier.success and String(wrong_frontier.error) == "RUNTIME_ACTIVITY_FRONTIER",
		"runtime rejects scheduler frontier not anchored to canonical tick")
	check(Runtime.state_hash(state1) == Runtime.state_hash(continuous1),
		"frontier rejection leaves current canonical runtime unchanged")
