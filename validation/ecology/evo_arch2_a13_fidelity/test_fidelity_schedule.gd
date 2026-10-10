extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
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
		push_error("A13_FIDELITY_FAIL " + message)

func _run() -> void:
	var initial := _dynamic_runtime()
	check(not initial.is_empty(), "fidelity runtime fixture starts")
	if not initial.is_empty():
		_plan_contract(initial)
		_runtime_contract(initial)
	print("EVO_ARCH2_A13_FIDELITY checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A13_FIDELITY " + ("PASS" if failures.is_empty() else "FAIL"))
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
	var genome := Genome.create(program, "A13 fidelity scheduling reproductive fixture")
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
	check(not blueprint.is_empty(), "fidelity blueprint validates")
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a13.fidelity.dynamic", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "fidelity field validates")
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
			blueprint, "fidelity-founder-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		check(not individual.is_empty(), "fidelity founder %d valid" % i)
		population.append(individual)
	var created := Runtime.create(
		"eco/a13/fidelity-runtime/v1", field, population,
		Feedback.default_policy(), false)
	check(created.success, "fidelity runtime canonical")
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
		"seed": 20261006,
		"mutation_key_prefix": "eco-a13-fidelity-r1",
	}

func _continuous(initial: Dictionary, count: int) -> Dictionary:
	var state := initial.duplicate(true)
	for tick_index in count:
		var stepped := Runtime.step_spatial_parallel_advance(
			state, _options(), 4, 64, 4, 4)
		check(stepped.success, "continuous parallel reference tick %d succeeds" % (tick_index + 1))
		if not stepped.success:
			return {}
		state = stepped.state
	return state

func _all_mode(addresses: Array, mode: String) -> Dictionary:
	var out := {}
	for raw_address in addresses:
		out[String(raw_address)] = mode
	return out

func _plan_contract(initial: Dictionary) -> void:
	var addresses := _addresses(initial)
	check(addresses == [
		"tile/0000/0000", "tile/0000/0001",
		"tile/0001/0000", "tile/0001/0001",
	], "fixture occupies four canonical spatial tiles")

	var mixed_overrides := {
		"tile/0001/0000": Fidelity.MODE_PATCH,
		"tile/0000/0001": Fidelity.MODE_REDUCED,
	}
	var early := Fidelity.create(
		initial.field, initial.population, mixed_overrides,
		0, 1, 4, 4, 4, 64)
	check(not early.is_empty(), "mixed fidelity plan created")
	check(Fidelity.validate(early, initial.field, initial.population).is_empty(),
		"mixed fidelity plan validates")
	check(String(early.schema) == Fidelity.SCHEMA, "fidelity schema exact")
	check(int(early.full_tile_count) == 2, "two unspecified tiles default FULL")
	check(int(early.reduced_tile_count) == 1, "one tile REDUCED")
	check(int(early.patch_tile_count) == 1, "one tile PATCH")
	check(not bool(early.global_commit_ready), "PATCH presence blocks partial canonical commit")
	check(not bool(early.refinement_required), "PATCH below cadence defers before refinement request")
	check(int(early.catch_up_ticks) == 0, "blocked mixed plan has no partial catch-up")
	check(early.fidelity_overrides == [
		{"address": "tile/0000/0001", "fidelity": Fidelity.MODE_REDUCED},
		{"address": "tile/0001/0000", "fidelity": Fidelity.MODE_PATCH},
	], "fidelity overrides canonicalized by address")

	var modes := {}
	for tile in early.tiles:
		modes[String(tile.address)] = String(tile.fidelity)
		check(int(tile.member_count) == 1, "fixture tile member count exact")
		check(int(tile.shard_count) == 1, "fixture tile shard count exact")
		if String(tile.fidelity) == Fidelity.MODE_FULL:
			check(int(tile.cadence_ticks) == 1 and bool(tile.exact_history_retained),
				"FULL retains exact history at cadence one")
		elif String(tile.fidelity) == Fidelity.MODE_REDUCED:
			check(int(tile.cadence_ticks) == 4 and bool(tile.exact_history_retained),
				"REDUCED retains exact history at reduced cadence")
		else:
			check(int(tile.cadence_ticks) == 4 and not bool(tile.exact_history_retained),
				"PATCH explicitly lacks exact history")
	check(String(modes["tile/0000/0000"]) == Fidelity.MODE_FULL, "default tile FULL")
	check(String(modes["tile/0000/0001"]) == Fidelity.MODE_REDUCED, "override tile REDUCED")
	check(String(modes["tile/0001/0000"]) == Fidelity.MODE_PATCH, "override tile PATCH")

	var patch_due := Fidelity.create(
		initial.field, initial.population, mixed_overrides,
		0, 4, 4, 4, 4, 64)
	check(not patch_due.is_empty(), "PATCH cadence boundary plan created")
	check(bool(patch_due.refinement_required), "due PATCH explicitly requests refinement")
	check(patch_due.refinement_addresses == ["tile/0001/0000"],
		"refinement address list canonical")
	check(not bool(patch_due.global_commit_ready), "due PATCH never authorizes exact commit")
	check(int(patch_due.catch_up_ticks) == 0, "due PATCH cannot claim exact replay")

	var all_full := Fidelity.create(
		initial.field, initial.population, {}, 0, 1, 4, 4, 4, 64)
	check(not all_full.is_empty(), "all-FULL plan created")
	check(int(all_full.full_tile_count) == 4, "all-FULL covers all tiles")
	check(bool(all_full.global_commit_ready), "all-FULL commits immediately")
	check(int(all_full.catch_up_ticks) == 1, "all-FULL one debt tick replays one exact tick")

	var reduced_early := Fidelity.create(
		initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_REDUCED},
		0, 3, 4, 16, 4, 64)
	var reduced_due := Fidelity.create(
		initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_REDUCED},
		0, 4, 4, 16, 4, 64)
	check(not reduced_early.is_empty() and not reduced_due.is_empty(),
		"REDUCED cadence plans created")
	check(not bool(reduced_early.global_commit_ready), "REDUCED below cadence defers globally")
	check(bool(reduced_due.global_commit_ready), "REDUCED cadence opens exact replay")
	check(int(reduced_due.catch_up_ticks) == 4, "REDUCED wake owes complete exact debt")

	var all_reduced := Fidelity.create(
		initial.field, initial.population, _all_mode(addresses, Fidelity.MODE_REDUCED),
		0, 4, 4, 16, 4, 64)
	check(bool(all_reduced.global_commit_ready) and int(all_reduced.catch_up_ticks) == 4,
		"all-REDUCED wakes at exact cadence")

	var patch_early := Fidelity.create(
		initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_PATCH},
		0, 3, 4, 4, 4, 64)
	check(not patch_early.is_empty(), "PATCH below cadence plan created")
	check(not bool(patch_early.global_commit_ready) and not bool(patch_early.refinement_required),
		"PATCH below cadence only defers")

	var noop_patch := Fidelity.create(
		initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_PATCH},
		0, 0, 4, 4, 4, 64)
	check(bool(noop_patch.global_commit_ready) and not bool(noop_patch.refinement_required),
		"zero-debt PATCH plan is canonical no-op")

	var unordered_a := {}
	unordered_a["tile/0001/0000"] = Fidelity.MODE_PATCH
	unordered_a["tile/0000/0001"] = Fidelity.MODE_REDUCED
	var unordered_b := {}
	unordered_b["tile/0000/0001"] = Fidelity.MODE_REDUCED
	unordered_b["tile/0001/0000"] = Fidelity.MODE_PATCH
	var canonical_a := Fidelity.create(initial.field, initial.population, unordered_a, 0, 1, 4, 4, 4, 64)
	var canonical_b := Fidelity.create(initial.field, initial.population, unordered_b, 0, 1, 4, 4, 4, 64)
	check(C.encode(canonical_a) == C.encode(canonical_b),
		"override insertion order cannot affect fidelity plan bytes")
	var implicit_full := Fidelity.create(initial.field, initial.population, {}, 0, 1, 4, 4, 4, 64)
	var explicit_full := Fidelity.create(
		initial.field, initial.population,
		{"tile/0000/0000": Fidelity.MODE_FULL},
		0, 1, 4, 4, 4, 64)
	check(C.encode(implicit_full) == C.encode(explicit_full),
		"redundant explicit FULL override canonicalizes to default plan bytes")

	var reversed_population: Array = initial.population.duplicate(true)
	reversed_population.reverse()
	var permuted := Fidelity.create(
		initial.field, reversed_population, mixed_overrides, 0, 1, 4, 4, 4, 64)
	check(C.encode(permuted) == C.encode(early),
		"population input permutation cannot affect fidelity plan")

	check(Fidelity.create(
		initial.field, initial.population,
		{"tile/9999/9999": Fidelity.MODE_REDUCED},
		0, 1, 4, 4, 4, 64).is_empty(), "unknown fidelity address rejected")
	check(Fidelity.create(
		initial.field, initial.population,
		{"tile/0000/0000": "AGGREGATE"},
		0, 1, 4, 4, 4, 64).is_empty(), "AGGREGATE not admitted as scheduling mode")
	check(Fidelity.create(initial.field, initial.population, {}, 0, 1, 0, 4, 4, 64).is_empty(),
		"zero REDUCED cadence rejected")
	check(Fidelity.create(initial.field, initial.population, {}, 0, 1, 4, 0, 4, 64).is_empty(),
		"zero PATCH cadence rejected")
	check(Fidelity.create(
		initial.field, initial.population, {}, 0,
		Fidelity.MAX_CATCH_UP_TICKS + 1, 4, 4, 4, 64).is_empty(),
		"unbounded fidelity debt rejected")

	var tampered := reduced_due.duplicate(true)
	tampered.tiles[0].fidelity = Fidelity.MODE_PATCH
	check(Fidelity.validate(tampered, initial.field, initial.population) == "FIDELITY_PLAN_HISTORY" 			or Fidelity.validate(tampered, initial.field, initial.population) == "FIDELITY_PLAN_CONTENT",
		"tampered fidelity tile rejected")

	var moved: Array = initial.population.duplicate(true)
	var original: Dictionary = moved[1]
	var replacement := Lifecycle.individual(
		original.blueprint, String(original.state.individual_id), [4500, 0, 4500],
		original.state.metabolic_reserves.duplicate(true))
	check(not replacement.is_empty(), "stale fidelity replacement valid")
	moved[1] = replacement
	check(not Fidelity.validate(reduced_due, initial.field, moved).is_empty(),
		"position migration invalidates fidelity plan")

func _runtime_contract(initial: Dictionary) -> void:
	var addresses := _addresses(initial)
	var before_hash := Runtime.state_hash(initial)
	var before_bytes := C.encode(initial)

	var continuous1 := _continuous(initial, 1)
	var continuous4 := _continuous(initial, 4)
	var continuous8 := _continuous(initial, 8)
	check(not continuous1.is_empty() and not continuous4.is_empty() and not continuous8.is_empty(),
		"continuous references complete")
	if continuous1.is_empty() or continuous4.is_empty() or continuous8.is_empty():
		return

	var full_plan := Fidelity.create(initial.field, initial.population, {}, 0, 1, 4, 16, 4, 64)
	var full := Runtime.advance_spatial_fidelity(initial, _options(), full_plan, 4, 4)
	check(full.success and not bool(full.deferred), "all-FULL fidelity executes immediately")
	check(int(full.replayed_ticks) == 1 and bool(full.exact_catch_up),
		"all-FULL executes one exact replay tick")
	check(C.encode(full.state) == C.encode(continuous1),
		"all-FULL scheduling exact to continuous Parallel Advance")

	var reduced_overrides := {"tile/0000/0000": Fidelity.MODE_REDUCED}
	var reduced_early_plan := Fidelity.create(
		initial.field, initial.population, reduced_overrides, 0, 1, 4, 16, 4, 64)
	var reduced_early := Runtime.advance_spatial_fidelity(
		initial, _options(), reduced_early_plan, 4, 4)
	check(reduced_early.success and bool(reduced_early.deferred),
		"REDUCED below cadence returns deferred")
	check(int(reduced_early.replayed_ticks) == 0 and bool(reduced_early.exact_catch_up),
		"REDUCED defer executes zero ticks but retains exact catch-up capability")
	check(Runtime.state_hash(reduced_early.state) == before_hash,
		"REDUCED defer preserves runtime hash")
	check(C.encode(reduced_early.state) == before_bytes,
		"REDUCED defer mutates zero canonical bytes")

	var reduced4_plan := Fidelity.create(
		initial.field, initial.population, reduced_overrides, 0, 4, 4, 16, 4, 64)
	var reduced4 := Runtime.advance_spatial_fidelity(initial, _options(), reduced4_plan, 4, 4)
	check(reduced4.success and not bool(reduced4.deferred),
		"REDUCED wake executes")
	check(int(reduced4.replayed_ticks) == 4 and int(reduced4.canonical_tick) == 4,
		"REDUCED wake replays complete debt")
	check(C.encode(reduced4.state) == C.encode(continuous4),
		"REDUCED wake byte-exact to continuous execution")
	check(Runtime.state_hash(reduced4.state) == Runtime.state_hash(continuous4),
		"REDUCED wake hash-exact to continuous execution")

	var reduced8_plan := Fidelity.create(
		initial.field, initial.population, reduced_overrides, 0, 8, 4, 16, 4, 64)
	var reduced8 := Runtime.advance_spatial_fidelity(initial, _options(), reduced8_plan, 4, 4)
	check(reduced8.success and int(reduced8.replayed_ticks) == 8,
		"late REDUCED wake replays all debt")
	check(C.encode(reduced8.state) == C.encode(continuous8),
		"late REDUCED wake exact to continuous eight ticks")
	check(reduced8.state.population.size() > initial.population.size(),
		"REDUCED exact catch-up includes real reproduction/mutation")

	var addresses4 := _addresses(reduced4.state)
	check(not addresses4.is_empty(), "post-wake spatial addresses recomputed")
	var reduced4_next := {}
	reduced4_next[String(addresses4[0])] = Fidelity.MODE_REDUCED
	var second_plan := Fidelity.create(
		reduced4.state.field, reduced4.state.population,
		reduced4_next, 4, 8, 4, 16, 4, 64)
	var segmented8 := Runtime.advance_spatial_fidelity(
		reduced4.state, _options(), second_plan, 4, 4)
	check(segmented8.success and int(segmented8.replayed_ticks) == 4,
		"segmented REDUCED epoch replays only new debt")
	check(C.encode(segmented8.state) == C.encode(continuous8),
		"segmented REDUCED catch-up exact to continuous reference")

	var patch_overrides := {"tile/0000/0000": Fidelity.MODE_PATCH}
	var patch_early_plan := Fidelity.create(
		initial.field, initial.population, patch_overrides, 0, 1, 4, 4, 4, 64)
	var patch_early := Runtime.advance_spatial_fidelity(
		initial, _options(), patch_early_plan, 4, 4)
	check(patch_early.success and bool(patch_early.deferred),
		"PATCH below cadence defers without pretending to execute")
	check(not bool(patch_early.exact_catch_up),
		"PATCH defer reports exact history unavailable")
	check(C.encode(patch_early.state) == before_bytes,
		"PATCH defer mutates zero canonical bytes")

	var patch_due_plan := Fidelity.create(
		initial.field, initial.population, patch_overrides, 0, 4, 4, 4, 4, 64)
	var patch_due := Runtime.advance_spatial_fidelity(
		initial, _options(), patch_due_plan, 4, 4)
	check(not patch_due.success and String(patch_due.error) == "RUNTIME_FIDELITY_REFINEMENT_REQUIRED",
		"due PATCH fails closed with explicit refinement requirement")
	check(bool(patch_due.refinement_required), "PATCH failure carries refinement flag")
	check(patch_due.refinement_addresses == ["tile/0000/0000"],
		"PATCH failure carries canonical refinement address")
	check(int(patch_due.canonical_tick) == 0, "PATCH refinement failure commits zero canonical ticks")
	check(Runtime.state_hash(initial) == before_hash and C.encode(initial) == before_bytes,
		"PATCH refinement requirement leaves source runtime untouched")

	# Simulate completion of the external A9 refinement contract: exact history
	# is restored at the same canonical frontier, so the caller explicitly
	# reclassifies that address as REDUCED and creates a new plan.
	var refined_overrides := {"tile/0000/0000": Fidelity.MODE_REDUCED}
	var refined_plan := Fidelity.create(
		initial.field, initial.population, refined_overrides, 0, 4, 4, 4, 4, 64)
	var refined := Runtime.advance_spatial_fidelity(
		initial, _options(), refined_plan, 4, 4)
	check(refined.success and int(refined.replayed_ticks) == 4,
		"explicitly refined PATCH source may resume exact catch-up")
	check(C.encode(refined.state) == C.encode(continuous4),
		"refined PATCH-to-REDUCED catch-up exact to continuous reference")

	var all_patch_plan := Fidelity.create(
		initial.field, initial.population, _all_mode(addresses, Fidelity.MODE_PATCH),
		0, 4, 4, 4, 4, 64)
	var all_patch := Runtime.advance_spatial_fidelity(initial, _options(), all_patch_plan, 4, 4)
	check(not all_patch.success and all_patch.refinement_addresses == addresses,
		"all-PATCH due reports every refinement address in canonical order")

	var manifest_hash := C.digest({
		"schema": "dws.ecology.a13-fidelity-fixture.v1",
		"seed": 20261006,
	})
	var cp_continuous := Checkpoint.create(manifest_hash, continuous4)
	var cp_reduced := Checkpoint.create(manifest_hash, reduced4.state)
	var cp_refined := Checkpoint.create(manifest_hash, refined.state)
	check(not cp_continuous.is_empty() and not cp_reduced.is_empty() and not cp_refined.is_empty(),
		"fidelity comparison checkpoints canonical")
	check(Checkpoint.serialize(cp_reduced) == Checkpoint.serialize(cp_continuous),
		"REDUCED scheduler metadata absent from checkpoint bytes")
	check(Checkpoint.serialize(cp_refined) == Checkpoint.serialize(cp_continuous),
		"refined PATCH scheduler metadata absent from checkpoint bytes")
	check(not C.encode(reduced4.state).contains(Fidelity.SCHEMA),
		"fidelity plan schema absent from runtime truth")
	check(not Checkpoint.serialize(cp_reduced).contains(Fidelity.SCHEMA),
		"fidelity plan schema absent from checkpoint serialization")

	var tampered := reduced4_plan.duplicate(true)
	tampered.catch_up_ticks = 3
	var rejected := Runtime.advance_spatial_fidelity(initial, _options(), tampered, 4, 4)
	check(not rejected.success and String(rejected.error) == "RUNTIME_FIDELITY_PLAN:FIDELITY_PLAN_CONTENT",
		"tampered fidelity plan fails closed")
	check(Runtime.state_hash(initial) == before_hash,
		"tampered fidelity plan leaves source unchanged")

	var state1 := continuous1
	var addresses1 := _addresses(state1)
	var wrong_overrides := {}
	wrong_overrides[String(addresses1[0])] = Fidelity.MODE_REDUCED
	var wrong_frontier_plan := Fidelity.create(
		state1.field, state1.population, wrong_overrides, 0, 1, 4, 16, 4, 64)
	check(not wrong_frontier_plan.is_empty(), "wrong-frontier fidelity plan structurally valid")
	var wrong_frontier := Runtime.advance_spatial_fidelity(
		state1, _options(), wrong_frontier_plan, 4, 4)
	check(not wrong_frontier.success and String(wrong_frontier.error) == "RUNTIME_FIDELITY_FRONTIER",
		"runtime rejects fidelity frontier not anchored to canonical tick")

	var bad_options := {
		"mutations_enabled": true,
		"operator": "not-an-operator",
		"seed": 1,
	}
	var catchup_failure := Runtime.advance_spatial_fidelity(
		initial, bad_options, reduced4_plan, 4, 4)
	check(not catchup_failure.success and String(catchup_failure.error).begins_with("RUNTIME_FIDELITY_CATCH_UP:"),
		"failed fidelity replay is surfaced atomically")
	check(Runtime.state_hash(initial) == before_hash and C.encode(initial) == before_bytes,
		"failed fidelity replay publishes no partial canonical state")

	var invalid_prepare := Runtime.advance_spatial_fidelity(initial, _options(), reduced4_plan, 0, 4)
	var invalid_advance := Runtime.advance_spatial_fidelity(initial, _options(), reduced4_plan, 4, 0)
	check(not invalid_prepare.success and String(invalid_prepare.error) == "RUNTIME_PARALLEL_PREPARE_WORKERS",
		"fidelity runtime validates prepare worker bound")
	check(not invalid_advance.success and String(invalid_advance.error) == "RUNTIME_PARALLEL_ADVANCE_WORKERS",
		"fidelity runtime validates advance worker bound")
