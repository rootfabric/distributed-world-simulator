extends SceneTree

## ECO.EVO7 STREAM1 R1 — bounded deterministic generation stream acceptance.
##
## Proves:
##   A. chunk-size invariance of the full generation proposal;
##   B. end-to-end canonical parity vs the legacy monolithic LS3.3 path:
##      3 physical recipes x chunk sizes 1/7/64 x 12 generations = 108
##      exact state/hash comparisons;
##   C. bounded working-set telemetry;
##   D. generation-based audit schedule (gen1 + gen10);
##   E. fail-closed chunk/audit/stale-base/proposal-hash faults with NO commit;
##   F. STREAM1 is mutually exclusive with PAR2/PAR3 stage executors;
##   G. the public Workbench -> LS3.4 -> LS3.3 facade works without private
##      topology access.
##
## This acceptance intentionally does NOT claim remote/distributed transport:
## STREAM1 R1 proves proposal/authority semantics first.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const Executor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")

const RECIPES := [
	"MIXED_PHYSICAL_HETEROGENEITY",
	"WATER_GRADIENT_STRONG",
	"RELIEF_DRAINAGE_STRONG",
]
const CHUNK_SIZES := [1, 7, 64]
const GENERATIONS := 12
const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const INITIAL_RECORDS := 64

var assertions := 0
var failures: Array[String] = []
var exact_comparisons := 0

func _init() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes")
	var patch := PlanetPatch.new().build(
		world,
		Vector3(-0.5, -0.86602540378444, 0.0).normalized(),
		32,
		16.0
	)
	_check(not patch.is_empty(), "STREAM1 acceptance patch builds")

	var fields := {}
	for recipe in RECIPES:
		var field := EnvironmentField.new().generate(patch, recipe, ENV_SEED)
		_check(not field.is_empty(), "%s environment field builds" % recipe)
		fields[recipe] = field

	_test_proposal_chunk_invariance(patch, fields[RECIPES[0]])
	_test_end_to_end_parity(patch, fields)
	_test_fail_closed(patch, fields[RECIPES[0]])
	_test_executor_exclusion(patch, fields[RECIPES[0]])
	_test_public_workbench(world)

	world.queue_free()
	_finish()

func _test_proposal_chunk_invariance(patch: Dictionary, field: Dictionary) -> void:
	var sim = LS33.new()
	_check(sim.setup(
		patch, field, FOUNDER_SEED, PLACEMENT_SEED,
		EVOLUTION_SEED, INITIAL_RECORDS
	), "proposal-invariance LS3.3 initializes")
	var parents_before: Array = sim.records.duplicate(true)
	var context := _stream_context(sim)
	var reference_proposal: Dictionary = {}

	for chunk_size in CHUNK_SIZES:
		var executor := Executor.new()
		_check(executor.setup({
			"parents_per_chunk": chunk_size,
			"audit_interval": 1000000,
			"audit_generation_1": false,
		}), "proposal executor setup chunk=%d" % chunk_size)
		var result: Dictionary = executor.execute_generation(
			sim.records.duplicate(true), 1, context.duplicate(true))
		_check(bool(result.get("success", false)),
			"proposal executes chunk=%d" % chunk_size)
		if not bool(result.get("success", false)):
			continue
		var proposal: Dictionary = result["proposal"]
		_check(Executor.validate_proposal_shape(proposal),
			"proposal shape/hash valid chunk=%d" % chunk_size)
		var telemetry: Dictionary = executor.get_telemetry()
		_check(int(telemetry.get("max_parent_chunk_seen", 0)) <= chunk_size,
			"parent working set bounded chunk=%d" % chunk_size)
		_check(int(telemetry.get("max_candidate_chunk_seen", 0)) <= chunk_size * int(LS33.OFFSPRING_PER_PARENT),
			"candidate working set bounded chunk=%d" % chunk_size)
		if reference_proposal.is_empty():
			reference_proposal = proposal.duplicate(true)
		else:
			_check(String(proposal["proposal_hash"]) == String(reference_proposal["proposal_hash"]),
				"proposal_hash invariant to chunk=%d" % chunk_size)
			_check(Array(proposal["candidates"]) == Array(reference_proposal["candidates"]),
				"candidate evidence exact across chunk=%d" % chunk_size)
			_check(Array(proposal["routes"]) == Array(reference_proposal["routes"]),
				"route evidence exact across chunk=%d" % chunk_size)
			_check(Array(proposal["recruitment"]) == Array(reference_proposal["recruitment"]),
				"recruitment evidence exact across chunk=%d" % chunk_size)

	_check(sim.generation == 0, "proposal execution alone cannot advance LS3.3 generation")
	_check(sim.records == parents_before, "proposal execution alone cannot mutate LS3.3 parents")

func _test_end_to_end_parity(patch: Dictionary, fields: Dictionary) -> void:
	for recipe in RECIPES:
		var baseline := _serial_baseline(patch, fields[recipe], GENERATIONS)
		if baseline.size() != GENERATIONS:
			_check(false, "%s serial baseline completes %d generations" % [recipe, GENERATIONS])
			continue

		for chunk_size in CHUNK_SIZES:
			var executor := Executor.new()
			_check(executor.setup(_stream_config(chunk_size)),
				"%s STREAM1 setup chunk=%d" % [recipe, chunk_size])
			_check(not executor.is_audit_generation(0),
				"generation zero never audited (%s chunk=%d)" % [recipe, chunk_size])
			_check(executor.is_audit_generation(1)
				and executor.is_audit_generation(10)
				and not executor.is_audit_generation(2),
				"audit schedule gen1+positive multiples of 10 (%s chunk=%d)" % [recipe, chunk_size])

			var sim = LS33.new()
			_check(sim.setup(
				patch, fields[recipe], FOUNDER_SEED, PLACEMENT_SEED,
				EVOLUTION_SEED, INITIAL_RECORDS
			), "%s streamed LS3.3 initializes chunk=%d" % [recipe, chunk_size])
			_check(sim.set_generation_stream_executor(executor),
				"%s STREAM1 injected chunk=%d" % [recipe, chunk_size])
			_check(sim.has_generation_stream_executor(),
				"%s LS3.3 reports STREAM1 executor chunk=%d" % [recipe, chunk_size])

			var mismatch := ""
			for step in GENERATIONS:
				var snapshot: Dictionary = sim.step_generation()
				if snapshot.is_empty():
					mismatch = "generation %d failed" % (step + 1)
					break
				if not _rows_equal(_hash_row(snapshot), baseline[step]):
					mismatch = "generation %d canonical divergence" % (step + 1)
					break
				exact_comparisons += 1

			if mismatch.is_empty():
				var telemetry: Dictionary = executor.get_telemetry()
				_check(int(telemetry["stream_calls"]) == GENERATIONS,
					"%s every generation used STREAM1 chunk=%d" % [recipe, chunk_size])
				_check(int(telemetry["serial_audit_calls"]) == 2,
					"%s audits are exactly gen1+gen10 chunk=%d" % [recipe, chunk_size])
				_check(int(telemetry["max_parent_chunk_seen"]) <= chunk_size,
					"%s bounded parents respected chunk=%d" % [recipe, chunk_size])
				_check(int(telemetry["max_candidate_chunk_seen"]) <= chunk_size * int(LS33.OFFSPRING_PER_PARENT),
					"%s bounded candidates respected chunk=%d" % [recipe, chunk_size])
				_check(bool(telemetry["last_audit_pass"]),
					"%s last STREAM1 audit passed chunk=%d" % [recipe, chunk_size])
			else:
				_check(false, "%s chunk=%d %s" % [recipe, chunk_size, mismatch])

	_check(exact_comparisons >= 108,
		"STREAM1 exact canonical comparisons >=108 (got %d)" % exact_comparisons)

func _test_fail_closed(patch: Dictionary, field: Dictionary) -> void:
	_forced_failure(
		patch, field,
		"FORCE_CHUNK_FAILURE",
		{"chunk_index": 0},
		"STREAM1_CHUNK_FAILURE"
	)
	_forced_failure(
		patch, field,
		"FORCE_AUDIT_MISMATCH",
		{},
		"STREAM1_AUDIT_PARITY_FAILURE"
	)
	_forced_failure(
		patch, field,
		"FORCE_STALE_BASE",
		{},
		"STREAM1_STALE_BASE"
	)
	_forced_failure(
		patch, field,
		"FORCE_PARENT_BINDING_CORRUPTION",
		{},
		"STREAM1_CANDIDATE_PARENT_BINDING_INVALID"
	)
	_forced_failure(
		patch, field,
		"FORCE_PROPOSAL_HASH_CORRUPTION",
		{},
		"STREAM1_PROPOSAL_INVALID"
	)

func _forced_failure(
	patch: Dictionary,
	field: Dictionary,
	kind: String,
	params: Dictionary,
	expected_code: String
) -> void:
	var executor := Executor.new()
	_check(executor.setup(_stream_config(7)), "%s executor setup" % kind)
	executor.set_test_fault_injection(kind, params)
	var sim = LS33.new()
	_check(sim.setup(
		patch, field, FOUNDER_SEED, PLACEMENT_SEED,
		EVOLUTION_SEED, 32
	), "%s sim initializes" % kind)
	_check(sim.set_generation_stream_executor(executor),
		"%s STREAM1 executor injected" % kind)
	var before := sim.get_snapshot()
	var result := sim.step_generation()
	_check(result.is_empty(), "%s generation fails closed" % kind)
	var after := sim.get_snapshot()
	_check(int(sim.generation) == 0, "%s generation counter unchanged" % kind)
	_check(String(after.get("state_hash", "")) == String(before.get("state_hash", "")),
		"%s state_hash unchanged" % kind)
	_check(String(after.get("population_hash", "")) == String(before.get("population_hash", "")),
		"%s population_hash unchanged" % kind)
	var profile := sim.get_last_profile()
	_check(String(profile.get("failure_code", "")) == expected_code,
		"%s named failure code %s (got %s)" % [
			kind, expected_code, String(profile.get("failure_code", ""))
		])

func _test_executor_exclusion(patch: Dictionary, field: Dictionary) -> void:
	var sim = LS33.new()
	_check(sim.setup(
		patch, field, FOUNDER_SEED, PLACEMENT_SEED,
		EVOLUTION_SEED, 16
	), "executor-exclusion sim initializes")
	var stream := Executor.new()
	_check(stream.setup(_stream_config(7)), "executor-exclusion STREAM1 setup")
	_check(sim.set_generation_stream_executor(stream), "STREAM1 seam accepts executor")
	_check(not sim.set_candidate_executor(RefCounted.new()),
		"PAR3 executor cannot coexist with STREAM1")
	_check(not sim.set_recruitment_executor(RefCounted.new()),
		"PAR2 executor cannot coexist with STREAM1")
	sim.clear_generation_stream_executor()
	_check(not sim.has_generation_stream_executor(), "STREAM1 seam clears")
	_check(sim.set_candidate_executor(RefCounted.new()),
		"legacy candidate seam remains usable after STREAM1 clear")
	_check(not sim.set_generation_stream_executor(stream),
		"STREAM1 refuses pre-existing stage executor")
	sim.clear_candidate_executor()
	_check(sim.set_generation_stream_executor(stream),
		"STREAM1 can be re-injected after stage executor clear")

func _test_public_workbench(world) -> void:
	var workbench := Workbench.new()
	_check(workbench.setup(world), "Workbench initializes for STREAM1 public facade")
	var executor := Executor.new()
	_check(executor.setup(_stream_config(16)), "Workbench STREAM1 executor setup")
	_check(workbench.set_generation_stream_executor(executor),
		"Workbench -> LS3.4 -> LS3.3 STREAM1 facade injects")
	_check(workbench.has_generation_stream_executor(),
		"Workbench reports STREAM1 executor")
	var snapshot := workbench.advance_generations(1)
	_check(not snapshot.is_empty(), "Workbench advances one STREAM1 generation")
	if not snapshot.is_empty():
		var profile := workbench.get_last_generation_profile()
		var ecology_profile: Dictionary = Dictionary(profile.get("ecology", {}))
		var ls33_profile: Dictionary = Dictionary(ecology_profile.get("ls33", {}))
		_check(String(ls33_profile.get("stream_mode", "")) == "STREAM1_BOUNDED_PROPOSAL",
			"Workbench profile proves public STREAM1 execution path")
	workbench.clear_generation_stream_executor()
	_check(not workbench.has_generation_stream_executor(),
		"Workbench STREAM1 facade clears")

func _serial_baseline(
	patch: Dictionary,
	field: Dictionary,
	generations: int
) -> Array[Dictionary]:
	var sim = LS33.new()
	if not sim.setup(
		patch, field, FOUNDER_SEED, PLACEMENT_SEED,
		EVOLUTION_SEED, INITIAL_RECORDS
	):
		return []
	var rows: Array[Dictionary] = []
	for _step in generations:
		var snapshot := sim.step_generation()
		if snapshot.is_empty():
			return []
		rows.append(_hash_row(snapshot))
	return rows

func _stream_context(sim) -> Dictionary:
	return {
		"schema": String(sim.SCHEMA),
		"version": String(sim.VERSION),
		"revision": String(sim.REVISION),
		"evolution_seed": int(sim.evolution_seed),
		"offspring_per_parent": int(sim.OFFSPRING_PER_PARENT),
		"cell_size_m": float(sim.cell_size_m),
		"grid_size": int(sim.GRID_SIZE),
		"environment_seed": int(sim.environment_seed),
		"environment_field_hash": String(sim.environment_field_hash),
		"environment_cells": sim.environment_cells.duplicate(true),
		"base_generation": int(sim.generation),
		"base_population_hash": String(sim.population_hash),
	}

func _stream_config(chunk_size: int) -> Dictionary:
	return {
		"parents_per_chunk": chunk_size,
		"audit_interval": 10,
		"audit_generation_1": true,
	}

func _hash_row(snapshot: Dictionary) -> Dictionary:
	return {
		"candidate_pool_hash": snapshot.get("candidate_pool_hash", ""),
		"dispersal_pool_hash": snapshot.get("dispersal_pool_hash", ""),
		"recruitment_hash": snapshot.get("recruitment_hash", ""),
		"occupied_map_hash": snapshot.get("occupied_map_hash", ""),
		"hereditary_pool_hash": snapshot.get("hereditary_pool_hash", ""),
		"population_hash": snapshot.get("population_hash", ""),
		"state_hash": snapshot.get("state_hash", ""),
	}

func _rows_equal(a: Dictionary, b: Dictionary) -> bool:
	for field in a.keys():
		if String(a[field]) != String(b.get(field, "\u0001")):
			return false
	return true

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("STREAM1 CHECK FAIL: " + label)

func _finish() -> void:
	print("STREAM1 exact generation comparisons: %d" % exact_comparisons)
	if failures.is_empty():
		print("ECO.EVO7 STREAM1 Bounded Generation Stream: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("STREAM1 FAIL: " + failure)
	print("ECO.EVO7 STREAM1 Bounded Generation Stream: FAIL (%d/%d assertions failed)" % [
		failures.size(), assertions
	])
	quit(1)
