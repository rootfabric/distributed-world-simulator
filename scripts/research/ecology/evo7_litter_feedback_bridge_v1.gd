extends RefCounted

## ECO.EVO7 FFF5 - litter / soil-memory feedback bridge: plants deposit litter,
## litter builds an organic legacy in the soil, and the SAME seed pool grows
## differently on the modified versus the pristine plot (spec sections 10, 17
## Experiment D, 19 FFF5).
##
## Community microcosm: the same 5x5 positions on a 0.35 m grid as FFF3/FFF4,
## one plant per position. Single scenario:
##   loam_legacy - loam cells over the wet_lowland control point (mesic, so the
##   slow organic signal is not drowned by water stress).
## Causal order per generation (legacy phase):
##   1. realize every plant under the base environment, publish geometry,
##      transpiration demand AND litter flux;
##   2. aggregate the soil water field against the CURRENT organic map
##      (retention slows evaporation; generation 1 sees a pristine map);
##   3. aggregate the soil organic field: deposits + texture decay -> next map;
##   4. score each plant under its own cell moisture (derived EnvironmentSample);
##      fitness = net_resource_proxy + ESTABLISHMENT_BONUS * establishment_capacity
##      * cell_organic (documented R1 constant, see below); cell_organic is the
##      POST-update state of the plant's cell - the plot its offspring will
##      establish on (the legacy the current generation hands over);
##   5. reproduce ONLY through LineageExtension (single authority), global
##      truncation selection, survivors claim positions along the fixed coprime
##      stride (7, coprime to 25) - deterministic, one plant per position.
##
## EXPERIMENT D (stage gate, spec section 17):
##   phase 1: grow the community for LEGACY_GENERATIONS cycles - organic legacy
##            builds (ecological memory);
##   phase 2: CLEAR all plants;
##   phase 3: introduce TWO IDENTICAL fresh seed pools (copies of the same
##            ancestor bundle, same mutation stream formula) for
##            POOL_GENERATIONS equal generations:
##              pool A on the MODIFIED organic map (legacy + its own deposits),
##              pool B on a PRISTINE map (zeros + its own deposits).
##            Assertion targets: populations diverge AND the establishment /
##            moisture metrics move in the direction "modified soil helps the
##            next generation".
## ON/OFF counterfactual (as in FFF3/FFF4): the same modified-map pool is re-run
## with feedback OFF (base-moisture scoring, no establishment bonus) - the
## mutation stream formula "EVO7-LITTER|seed|gen|parent|off" is identical in
## every run; only the environment assignment differs (that difference IS the
## tested causality).
##
## ESTABLISHMENT_BONUS = 0.05: with mesic net balances O(0.01-0.03) and organic
## O(0.1-0.5), the bonus contributes O(0.002-0.012) - the same order as the net
## spread between morphologies, so it measurably steers truncation ranking while
## staying far below the net scale itself (no runaway).
## RETENTION_PER_ORGANIC = 0.35 lives in soil_organic_field_v1 (moisture side).
## Nutrient availability (spec section 10 branch) is DEFERRED: organic affects
## moisture retention and establishment only in R1.
##
## Texture enters ONLY as water/organic field parameters - never a morphology
## rule (G9 source boundary discipline). No RNG anywhere.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const OrganicField = preload("res://scripts/research/ecology/soil_organic_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_litter_feedback_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF5.1"

const GRID_SIDE := 5
const SPACING_M := 0.35
const POPULATION_SIZE := GRID_SIDE * GRID_SIDE
const OFFSPRING_PER_PARENT := 4
const LEGACY_GENERATIONS := 10
const POOL_GENERATIONS := 8
const MUTATION_STREAM_FORMULA := "EVO7-LITTER|seed|gen|parent|off"

## Establishment bonus constant (documented above; spec section 11
## establishment_component realized for the litter channel).
const ESTABLISHMENT_BONUS := 0.05

const BASE_EVAPORATION_RATE_PPM := 20000.0
const SCENARIOS: Array[String] = ["loam_legacy"]

const MEAN_FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment", "root_shoot_ratio", "establishment_capacity",
]

static func run_all(lineage_seed := 20260823) -> Dictionary:
	var policy := LineageExtension.default_policy()
	if LineageExtension.policy_hash(policy).is_empty():
		return {}
	var ancestor := default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	var positions := _grid_positions()
	var fixture := scenario_fixture(lineage_seed, positions)
	if fixture.is_empty():
		return {}

	# Phase 1: community builds the organic legacy (feedback ON).
	var legacy := _run_legacy_phase(ancestor, positions, fixture, lineage_seed, LEGACY_GENERATIONS, policy)
	if legacy.is_empty():
		return {}

	# Phase 2+3: clear the plot, introduce two IDENTICAL fresh seed pools.
	var pool_modified := _run_pool(
		ancestor, positions, fixture, lineage_seed, POOL_GENERATIONS, policy,
		legacy["final_organic_map"], true)
	var pool_pristine := _run_pool(
		ancestor, positions, fixture, lineage_seed, POOL_GENERATIONS, policy,
		{}, true)
	var feedback_off := _run_pool(
		ancestor, positions, fixture, lineage_seed, POOL_GENERATIONS, policy,
		legacy["final_organic_map"], false)
	if pool_modified.is_empty() or pool_pristine.is_empty() or feedback_off.is_empty():
		return {}

	# Identical-pool precondition of Experiment D: both pools start from the
	# very same ancestor bundle checksums.
	var seed_pools_identical: bool = String(pool_modified["initial_seed_pool_hash"]) == String(pool_pristine["initial_seed_pool_hash"])

	# Same-genomes cross-evaluation: score the pooled final genomes of both
	# pools under the modified-final moisture map versus the pristine moisture
	# map (net balance is monotonically increasing in cell moisture for a fixed
	# genome, so a positive delta means "modified soil helps these genomes").
	var cross := _cross_evaluation(pool_modified, pool_pristine, fixture)
	if cross.is_empty():
		return {}

	var divergence := {
		"populations_differ_modified_vs_pristine": String(pool_modified["final_population_hash"]) != String(pool_pristine["final_population_hash"]),
		"population_differs_feedback_on_vs_off": String(pool_modified["final_population_hash"]) != String(feedback_off["final_population_hash"]),
		"moisture_modified_minus_pristine": snappedf(float(pool_modified["mean_cell_moisture"]) - float(pool_pristine["mean_cell_moisture"]), 1e-9),
		"organic_modified_minus_pristine": snappedf(float(pool_modified["mean_cell_organic"]) - float(pool_pristine["mean_cell_organic"]), 1e-9),
		"establishment_component_modified_minus_pristine": snappedf(float(pool_modified["mean_establishment_component"]) - float(pool_pristine["mean_establishment_component"]), 1e-9),
		"net_balance_same_genomes_modified_minus_pristine": float(cross["net_balance_delta"]),
	}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"lineage_seed": lineage_seed,
		"legacy_generations": LEGACY_GENERATIONS,
		"pool_generations": POOL_GENERATIONS,
		"population_size": POPULATION_SIZE,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"mutation_stream_formula": MUTATION_STREAM_FORMULA,
		"establishment_bonus": ESTABLISHMENT_BONUS,
		"scenario": fixture,
		"legacy_phase": legacy,
		"experiment_d": {
			"generations": POOL_GENERATIONS,
			"seed_pool_hash": String(pool_modified["initial_seed_pool_hash"]),
			"seed_pools_identical": seed_pools_identical,
			"pool_modified": pool_modified,
			"pool_pristine": pool_pristine,
			"feedback_off_on_modified": feedback_off,
			"divergence": divergence,
			"cross_evaluation": cross,
		},
	}
	result["result_hash"] = _result_hash(result)
	return result

static func default_ancestor_bundle(lineage_seed: int) -> Dictionary:
	var genome := Genome.create_default()
	var dev_traits := Traits.create(
		"plant-development/evo7-ancestor-ref", 3.2, 0.32, 0.62, 0.9, 42.0, 0.78, 4, 6.0)
	var ext_traits := ExtensionTraits.create("plant-development-extension/evo7-litter-ancestor", 0.65, 0.50, 0.40, 1.60, 0.50)
	return LineageExtension.create_ancestor_bundle(genome, dev_traits, ext_traits, lineage_seed)

## loam_legacy fixture variant over the given positions (plateau rejected during
## calibration: too dry - water stress drowned the slow organic signal).
static func scenario_fixture(lineage_seed: int, positions: Array[Dictionary]) -> Dictionary:
	var control_point := "wet_lowland"
	var texture := "loam"
	var base_env := Fixture.control_point(control_point, lineage_seed)
	if base_env.is_empty():
		return {}
	var textures := {}
	var base_moisture := {}
	for position in positions:
		var cell_id := WaterField.cell_identity_for(float(position["world_x_m"]), float(position["world_z_m"]))
		textures[cell_id] = texture
		base_moisture[cell_id] = snappedf(float(base_env["soil_moisture"]), 1e-9)
	var field_inputs := {
		"fixture_id": "eco-soil-texture/fff5-loam-legacy",
		"fixture_version": "1.0.0",
		"textures": textures,
		"base_moisture": base_moisture,
		"base_evaporation_rate": BASE_EVAPORATION_RATE_PPM,
	}
	var probe_ancestor := default_ancestor_bundle(lineage_seed)
	if probe_ancestor.is_empty():
		return {}
	var probe_features := _population_features(probe_ancestor, positions, base_env)
	if probe_features.is_empty():
		return {}
	var probe_records := _water_records(probe_features)
	if WaterField.compute(probe_records, field_inputs).is_empty():
		return {}
	if OrganicField.compute(_litter_records(probe_features), OrganicField.field_inputs_for("fff5-loam-legacy", textures)).is_empty():
		return {}
	return {
		"scenario": "loam_legacy",
		"texture": texture,
		"control_point": control_point,
		"base_env": base_env,
		"base_soil_moisture": snappedf(float(base_env["soil_moisture"]), 1e-9),
		"base_evaporation_rate": BASE_EVAPORATION_RATE_PPM,
		"decay_rate": OrganicField.BASE_DECAY_RATE,
		"establishment_bonus": ESTABLISHMENT_BONUS,
		"field_inputs": field_inputs,
	}

static func _grid_positions() -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	var half := float(GRID_SIDE - 1) * 0.5 * SPACING_M
	for iz in GRID_SIDE:
		for ix in GRID_SIDE:
			var index := iz * GRID_SIDE + ix
			positions.append({
				"identity": "p%02d" % index,
				"world_x_m": snappedf(float(ix) * SPACING_M - half, 1e-9),
				"world_z_m": snappedf(float(iz) * SPACING_M - half, 1e-9),
			})
	return positions

## Phase 1: grow the founding community; organic legacy accumulates generation
## over generation (always feedback ON - the memory builds under real rules).
static func _run_legacy_phase(
	ancestor: Dictionary,
	positions: Array[Dictionary],
	fixture: Dictionary,
	lineage_seed: int,
	generations: int,
	policy: Dictionary
) -> Dictionary:
	var outcome := _run_generations(ancestor, positions, fixture, lineage_seed, generations, policy, {}, true)
	if outcome.is_empty():
		return {}
	return {
		"generations": generations,
		"initial_organic_map_hash": _organic_map_hash({}),
		"final_organic_map": outcome["final_organic_map"],
		"final_organic_map_hash": _organic_map_hash(outcome["final_organic_map"]),
		"final_organic_field_hash": String(outcome["final_organic_field_hash"]),
		"final_plant_litter_hash": String(outcome["final_plant_litter_hash"]),
		"mean_cell_organic": float(outcome["mean_cell_organic"]),
		"mean_cell_moisture": float(outcome["mean_cell_moisture"]),
		"final_population_hash": String(outcome["final_population_hash"]),
		"mean_organic_trajectory": outcome["mean_organic_trajectory"],
	}

	# Phase 3 runner for ONE fresh seed pool. initial_organic = {} means a pristine
## plot; use_feedback selects ON (own-cell moisture with retention + organic
## establishment bonus) versus OFF (base moisture, plain net balance).
static func _run_pool(
	ancestor: Dictionary,
	positions: Array[Dictionary],
	fixture: Dictionary,
	lineage_seed: int,
	generations: int,
	policy: Dictionary,
	initial_organic: Dictionary,
	use_feedback: bool
) -> Dictionary:
	var mode := "organic_modified" if use_feedback else "feedback_off"
	var outcome := _run_generations(ancestor, positions, fixture, lineage_seed, generations, policy, initial_organic, use_feedback)
	if outcome.is_empty():
		return {}
	return {
		"mode": mode,
		"initial_seed_pool_hash": String(outcome["initial_seed_pool_hash"]),
		"initial_organic_map_hash": _organic_map_hash(initial_organic),
		"final_organic_map": outcome["final_organic_map"],
		"final_organic_map_hash": _organic_map_hash(outcome["final_organic_map"]),
		"final_organic_field_hash": String(outcome["final_organic_field_hash"]),
		"final_plant_litter_hash": String(outcome["final_plant_litter_hash"]),
		"final_population_hash": String(outcome["final_population_hash"]),
		"final_population": outcome["final_population"],
		"mean_cell_organic": float(outcome["mean_cell_organic"]),
		"mean_cell_moisture": float(outcome["mean_cell_moisture"]),
		"mean_net_balance": float(outcome["mean_net_balance"]),
		"mean_fitness_with_bonus": float(outcome["mean_fitness_with_bonus"]),
		"mean_establishment_component": float(outcome["mean_establishment_component"]),
		"mean_features": outcome["mean_features"],
	}

## Shared generation loop for every phase/mode.
static func _run_generations(
	ancestor: Dictionary,
	positions: Array[Dictionary],
	fixture: Dictionary,
	lineage_seed: int,
	generations: int,
	policy: Dictionary,
	start_organic: Dictionary,
	use_feedback: bool
) -> Dictionary:
	var base_env: Dictionary = fixture["base_env"]
	var field_inputs: Dictionary = fixture["field_inputs"]
	var organic_textures: Dictionary = field_inputs["textures"]
	var population: Array[Dictionary] = []
	for position in positions:
		population.append({
			"identity": String(position["identity"]),
			"world_x_m": float(position["world_x_m"]),
			"world_z_m": float(position["world_z_m"]),
			"bundle": (ancestor as Dictionary).duplicate(true),
		})

	var organic_map := start_organic.duplicate(true)
	var initial_seed_pool_hash := ""
	var mean_organic_trajectory: Array = []
	var last_mean_cell_organic := 0.0
	var last_mean_cell_moisture := 0.0
	var last_mean_net_balance := 0.0
	var last_mean_fitness := 0.0
	var last_mean_establishment := 0.0
	var last_organic_field_hash := ""
	var last_plant_litter_hash := ""

	for generation in range(1, generations + 1):
		var features := _population_features_of(population, base_env)
		if features.is_empty():
			return {}
		var water_records := _water_records(features)
		var litter_records := _litter_records(features)

		# Water field against the CURRENT organic map (previous generations'
		# litter; this cycle's mulch lands for the next generation).
		var water_inputs := field_inputs.duplicate(true)
		if not organic_map.is_empty() and use_feedback:
			water_inputs["organic_map"] = organic_map.duplicate(true)
		var field := WaterField.compute(water_records, water_inputs)
		if field.is_empty():
			return {}

		# Organic field update: deposits + texture decay -> the next map.
		var organic_inputs := OrganicField.field_inputs_for("fff5-loam-legacy", organic_textures, organic_map)
		var organic_field := OrganicField.compute(litter_records, organic_inputs)
		if organic_field.is_empty():
			return {}
		organic_map = organic_field["organic_map"]
		last_organic_field_hash = String(organic_field["organic_field_hash"])
		last_plant_litter_hash = String(organic_field["plant_litter_hash"])
		last_mean_cell_organic = OrganicField.mean_cell_organic(organic_field)
		mean_organic_trajectory.append(last_mean_cell_organic)

		# Per-cell state for scoring (canonical cell order).
		var cell_moisture := {}
		var moisture_total := 0.0
		var cell_ids: Array = field["cells"].keys()
		cell_ids.sort()
		for cell_id in cell_ids:
			var moisture := float(field["cells"][cell_id]["moisture_after"])
			cell_moisture[cell_id] = moisture
			moisture_total += moisture
		last_mean_cell_moisture = snappedf(moisture_total / float(cell_ids.size()), 1e-9)
		var cell_organic := {}
		var organic_cell_ids: Array = organic_map.keys()
		organic_cell_ids.sort()
		for organic_cell in organic_cell_ids:
			cell_organic[String(organic_cell)] = float(organic_map[organic_cell])

		# Scoring: feedback ON assigns each plant its own-cell state; OFF scores
		# everyone under the base environment (prior-bridge counterfactual).
		var scored: Array[Dictionary] = []
		for entry_index in population.size():
			var entry: Dictionary = population[entry_index]
			var plant_cell := WaterField.cell_identity_for(float(entry["world_x_m"]), float(entry["world_z_m"]))
			var effective_moisture := float(base_env["soil_moisture"])
			var organic_here := 0.0
			if use_feedback:
				effective_moisture = float(cell_moisture[plant_cell])
				organic_here = float(cell_organic.get(plant_cell, 0.0))
			var derived_env := EnvSample.create(
				float(entry["world_x_m"]), float(entry["world_z_m"]),
				float(base_env["temperature_c"]), clampf(effective_moisture, 0.0, 1.0),
				float(base_env["sunlight"]), float(base_env["nutrients"]), float(base_env["flood_frequency"]),
				int(base_env["seed"]),
				"%s|fff5|%s" % [String(base_env["environment_revision"]), String(entry["identity"])])
			var fp := _evaluate(entry["bundle"], derived_env)
			if fp.is_empty():
				return {}
			var net_balance := float(fp["net_resource_proxy"])
			var establishment_component := ESTABLISHMENT_BONUS * float(fp["establishment_capacity"]) * organic_here
			scored.append({
				"identity": String(entry["identity"]),
				"world_x_m": float(entry["world_x_m"]),
				"world_z_m": float(entry["world_z_m"]),
				"bundle": entry["bundle"],
				"fitness": net_balance + establishment_component,
				"net_balance": net_balance,
				"establishment_component": establishment_component,
			})
		if generation == 1:
			initial_seed_pool_hash = _seed_pool_hash(scored)

		var totals := {"net": 0.0, "fit": 0.0, "est": 0.0}
		for scored_entry in scored:
			totals["net"] += float(scored_entry["net_balance"])
			totals["fit"] += float(scored_entry["fitness"])
			totals["est"] += float(scored_entry["establishment_component"])
		last_mean_net_balance = snappedf(totals["net"] / float(scored.size()), 1e-9)
		last_mean_fitness = snappedf(totals["fit"] / float(scored.size()), 1e-9)
		last_mean_establishment = snappedf(totals["est"] / float(scored.size()), 1e-9)

		# Reproduce through the SINGLE lineage authority; global truncation
		# selection; coprime-stride position claim (identical to FFF4).
		var ranked: Array[Dictionary] = scored.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["fitness"]) != float(b["fitness"]):
				return float(a["fitness"]) > float(b["fitness"])
			return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"]))
		var next_population: Array[Dictionary] = []
		var candidates: Array[Dictionary] = []
		for parent_index in population.size():
			var parent: Dictionary = ranked[parent_index]
			for offspring_index in OFFSPRING_PER_PARENT:
				var mutation_seed := ("EVO7-LITTER|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child_result := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child_result.is_empty():
					return {}
				candidates.append({
					"bundle": child_result["bundle"],
					"parent_fitness": float(parent["fitness"]),
				})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["parent_fitness"]) != float(b["parent_fitness"]):
				return float(a["parent_fitness"]) > float(b["parent_fitness"])
			return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"]))
		for rank in mini(candidates.size(), POPULATION_SIZE):
			var position: Dictionary = positions[(rank * 7) % POPULATION_SIZE]
			next_population.append({
				"identity": String(position["identity"]),
				"world_x_m": float(position["world_x_m"]),
				"world_z_m": float(position["world_z_m"]),
				"bundle": candidates[rank]["bundle"],
			})
		next_population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["identity"]) < String(b["identity"]))
		population = next_population

	var checksums := PackedStringArray()
	for entry in population:
		checksums.append(String(entry["bundle"]["bundle_checksum"]))
	checksums.sort()

	var final_features := _population_features_of(population, base_env)
	if final_features.is_empty():
		return {}
	var mean_features := {}
	for field_name in MEAN_FEATURE_FIELDS:
		var total := 0.0
		for feature_entry in final_features:
			total += float(feature_entry["features"][field_name])
		mean_features[field_name] = snappedf(total / float(final_features.size()), 1e-9)

	return {
		"initial_seed_pool_hash": initial_seed_pool_hash,
		"final_population_hash": "|".join(checksums).sha256_text(),
		"final_population": population,
		"final_organic_map": organic_map,
		"final_organic_field_hash": last_organic_field_hash,
		"final_plant_litter_hash": last_plant_litter_hash,
		"mean_cell_organic": last_mean_cell_organic,
		"mean_cell_moisture": last_mean_cell_moisture,
		"mean_net_balance": last_mean_net_balance,
		"mean_fitness_with_bonus": last_mean_fitness,
		"mean_establishment_component": last_mean_establishment,
		"mean_features": mean_features,
		"mean_organic_trajectory": mean_organic_trajectory,
	}

## Cross-evaluation of Experiment D (OBSERVABILITY, not a gate): pool the final
## genomes of BOTH pools and score every genome twice - under the modified-final
## moisture map (organic retention) and under the pristine map. NOTE: PH2
## plasticity re-realizes morphology under the changed moisture, so the net-
## balance delta is NOT structurally sign-definite (calibration: +2.3e-4 /
## -1.4e-4 / +4.3e-5 on seeds 20260823/24/25 - noise-level either way). The
## structurally-guaranteed retention fact ("same plants lose less water on the
## modified map") is asserted at FIELD level in the acceptance test instead;
## the population-level gate is the establishment component delta.
static func _cross_evaluation(pool_a: Dictionary, pool_b: Dictionary, fixture: Dictionary) -> Dictionary:
	var combined: Array[Dictionary] = []
	for entry in pool_a["final_population"]:
		combined.append({
			"identity": "a_%s" % String(entry["identity"]),
			"world_x_m": float(entry["world_x_m"]),
			"world_z_m": float(entry["world_z_m"]),
			"bundle": entry["bundle"],
		})
	for entry in pool_b["final_population"]:
		combined.append({
			"identity": "b_%s" % String(entry["identity"]),
			"world_x_m": float(entry["world_x_m"]),
			"world_z_m": float(entry["world_z_m"]),
			"bundle": entry["bundle"],
		})
	var base_env: Dictionary = fixture["base_env"]
	var features := _population_features_of(combined, base_env)
	if features.is_empty():
		return {}
	var records := _water_records(features)
	var field_inputs: Dictionary = fixture["field_inputs"]
	var modified_map: Dictionary = pool_a["final_organic_map"]
	var modified_inputs := field_inputs.duplicate(true)
	modified_inputs["organic_map"] = modified_map.duplicate(true)
	var field_modified := WaterField.compute(records, modified_inputs)
	var field_pristine := WaterField.compute(records, field_inputs)
	if field_modified.is_empty() or field_pristine.is_empty():
		return {}
	var total_delta := 0.0
	for index in features.size():
		var feature_entry: Dictionary = features[index]
		var cell_id := WaterField.cell_identity_for(float(feature_entry["world_x_m"]), float(feature_entry["world_z_m"]))
		for which in ["modified", "pristine"]:
			var field := field_modified if which == "modified" else field_pristine
			var moisture := float(field["cells"][cell_id]["moisture_after"])
			var derived_env := EnvSample.create(
				float(feature_entry["world_x_m"]), float(feature_entry["world_z_m"]),
				float(base_env["temperature_c"]), clampf(moisture, 0.0, 1.0),
				float(base_env["sunlight"]), float(base_env["nutrients"]), float(base_env["flood_frequency"]),
				int(base_env["seed"]),
				"%s|fff5-cross|%s|%s" % [String(base_env["environment_revision"]), String(feature_entry["identity"]), which])
			var fp := _evaluate(combined[index]["bundle"], derived_env)
			if fp.is_empty():
				return {}
			total_delta += float(fp["net_resource_proxy"]) * (1.0 if which == "modified" else -1.0)
	return {
		"net_balance_delta": snappedf(total_delta / float(features.size()), 1e-9),
		"genome_count": features.size(),
	}

static func _seed_pool_hash(scored: Array) -> String:
	var checksums := PackedStringArray()
	for scored_entry in scored:
		checksums.append(String(scored_entry["bundle"]["bundle_checksum"]))
	checksums.sort()
	return "|".join(checksums).sha256_text()

static func _organic_map_hash(organic_map: Dictionary) -> String:
	var keys: Array = organic_map.keys()
	keys.sort()
	var tokens := PackedStringArray([SCHEMA, VERSION, "organic_map"])
	for key in keys:
		tokens.append("%s:%.9f" % [String(key), float(organic_map[key])])
	return "|".join(tokens).sha256_text()

static func _envelope(bundle: Dictionary, env: Dictionary) -> Dictionary:
	return Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]),
		"evo7-litter|%s|%.3f" % [String(env["environment_revision"]), float(env["soil_moisture"])],
		0, 1.25)

## Shared scoring path: functional phenotype of one bundle under one environment.
static func _evaluate(bundle: Dictionary, env: Dictionary) -> Dictionary:
	var envelope := _envelope(bundle, env)
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
	return FunctionalPhenotype.compile({
		"genome": bundle["genome"],
		"ph2_realized": ph2,
		"traits_extension": bundle["ext_traits"],
		"environment_sample": env,
		"age_fraction": 1.0,
	})

## Realize every plant under the base environment; publish geometry, demand,
## litter flux and functional features.
static func _population_features_of(population: Array[Dictionary], base_env: Dictionary) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for entry in population:
		var bundle: Dictionary = entry["bundle"]
		var envelope := Contract.create_seed_envelope(
			bundle["genome"], bundle["dev_traits"],
			String(bundle["lineage"]["lineage_id"]),
			"evo7-litter-feature|%s" % String(entry["identity"]), 0, 1.25)
		var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], base_env)
		var fp := FunctionalPhenotype.compile({
			"genome": bundle["genome"],
			"ph2_realized": ph2,
			"traits_extension": bundle["ext_traits"],
			"environment_sample": base_env,
			"age_fraction": 1.0,
		})
		if fp.is_empty():
			return []
		var record := {
			"identity": String(entry["identity"]),
			"world_x_m": float(entry["world_x_m"]),
			"world_z_m": float(entry["world_z_m"]),
			"realized_height_m": float(fp["realized_height_m"]),
			"realized_crown_radius_m": float(fp["realized_crown_radius_m"]),
			"realized_crown_density": float(fp["realized_crown_density"]),
			"leaf_area_index_proxy": float(fp["leaf_area_index_proxy"]),
			"realized_root_depth_m": float(fp["realized_root_depth_m"]),
			"realized_root_spread_m": float(fp["realized_root_spread_m"]),
			"root_shoot_ratio": float(fp["root_shoot_ratio"]),
			"transpiration_demand_ppm": int(fp["transpiration_demand_ppm"]),
			"shade_output_ppm": int(fp["shade_output_ppm"]),
			"litter_flux_ppm": int(fp["litter_flux_ppm"]),
			"source_phenotype_hash": String(fp["phenotype_hash"]),
			"features": {},
		}
		for field_name in MEAN_FEATURE_FIELDS:
			record["features"][field_name] = float(fp[field_name])
		features.append(record)
	return features

static func _population_features(ancestor: Dictionary, positions: Array[Dictionary], base_env: Dictionary) -> Array[Dictionary]:
	var population: Array[Dictionary] = []
	for position in positions:
		population.append({
			"identity": String(position["identity"]),
			"world_x_m": float(position["world_x_m"]),
			"world_z_m": float(position["world_z_m"]),
			"bundle": ancestor,
		})
	return _population_features_of(population, base_env)

static func _water_records(feature_entries: Array[Dictionary]) -> Array:
	var records: Array = []
	for entry in feature_entries:
		var record := {}
		for key in ["identity", "world_x_m", "world_z_m", "transpiration_demand_ppm", "realized_crown_radius_m", "realized_crown_density", "realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio", "shade_output_ppm", "source_phenotype_hash"]:
			record[key] = entry[key]
		records.append(record)
	return records

static func _litter_records(feature_entries: Array[Dictionary]) -> Array:
	var records: Array = []
	for entry in feature_entries:
		records.append({
			"identity": String(entry["identity"]),
			"world_x_m": float(entry["world_x_m"]),
			"world_z_m": float(entry["world_z_m"]),
			"litter_flux_ppm": int(entry["litter_flux_ppm"]),
			"source_phenotype_hash": String(entry["source_phenotype_hash"]),
		})
	return records

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("revision", "")),
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("legacy_generations", 0))),
		str(int(result.get("pool_generations", 0))),
		str(int(result.get("population_size", 0))),
		String(result.get("mutation_stream_formula", "")),
		"%.9f" % float(result.get("establishment_bonus", 0.0)),
	])
	var fixture: Dictionary = result.get("scenario", {})
	tokens.append("%s:%s:%s:%.9f:%s" % [
		String(fixture.get("scenario", "")),
		String(fixture.get("texture", "")),
		String(fixture.get("control_point", "")),
		float(fixture.get("base_soil_moisture", 0.0)),
		String(fixture.get("base_env", {}).get("checksum", "")),
	])
	var legacy: Dictionary = result.get("legacy_phase", {})
	tokens.append("%s:%s:%s:%.9f:%.9f:%s" % [
		String(legacy.get("initial_organic_map_hash", "")),
		String(legacy.get("final_organic_map_hash", "")),
		String(legacy.get("final_organic_field_hash", "")),
		float(legacy.get("mean_cell_organic", 0.0)),
		float(legacy.get("mean_cell_moisture", 0.0)),
		String(legacy.get("final_population_hash", "")),
	])
	var experiment: Dictionary = result.get("experiment_d", {})
	tokens.append(String(experiment.get("seed_pool_hash", "")))
	for pool_key in ["pool_modified", "pool_pristine", "feedback_off_on_modified"]:
		var pool: Dictionary = experiment.get(pool_key, {})
		tokens.append("%s:%s:%s:%.9f:%.9f:%.9f:%.9f:%.9f" % [
			pool_key,
			String(pool.get("final_population_hash", "")),
			String(pool.get("final_organic_map_hash", "")),
			float(pool.get("mean_cell_organic", 0.0)),
			float(pool.get("mean_cell_moisture", 0.0)),
			float(pool.get("mean_net_balance", 0.0)),
			float(pool.get("mean_establishment_component", 0.0)),
			float(pool.get("mean_features", {}).get("leaf_area_index_proxy", 0.0)),
		])
	var divergence: Dictionary = experiment.get("divergence", {})
	tokens.append("%s:%s:%.9f:%.9f:%.9f:%.9f" % [
		"divergence",
		"1" if bool(divergence.get("populations_differ_modified_vs_pristine", false)) else "0",
		float(divergence.get("moisture_modified_minus_pristine", 0.0)),
		float(divergence.get("organic_modified_minus_pristine", 0.0)),
		float(divergence.get("establishment_component_modified_minus_pristine", 0.0)),
		float(divergence.get("net_balance_same_genomes_modified_minus_pristine", 0.0)),
	])
	return "|".join(tokens).sha256_text()
