extends RefCounted

## ECO.EVO7 FFF4 - water feedback bridge: plants dry the soil, dried soil changes
## selection, soil texture scales the loop (spec sections 9, 13; gates G8/G9).
##
## Community microcosm: the same 5x5 positions on a 0.35 m grid as FFF3 (crown
## scale - skeleton crowns are sub-meter), one plant per position. Two scenarios
## are texture x moisture fixture variants over the SAME positions:
##   dry_sand   - sand cells, base moisture from the dry_ridge control point;
##   mesic_loam - loam cells, base moisture from the wet_lowland control point.
## Each generation:
##   1. realize every plant under the BASE environment and publish geometry and
##      transpiration demand (the water field is aggregated from published records);
##   2. aggregate the soil water field (canonical identity order, cell buckets,
##      bounded uptake, canopy-suppressed evaporation) and publish effect records;
##   3. feedback ON: each plant is re-realized and scored under its OWN cell
##      moisture (derived EnvironmentSample with soil_moisture = cell moisture);
##      feedback OFF (counterfactual): every plant scores under the base
##      moisture - the mutation stream formula "EVO7-WATER|seed|gen|parent|off"
##      is identical in both modes AND both scenarios, only the environment
##      assignment differs (that difference IS the tested causality);
##   4. reproduce through the single lineage authority and select: all offspring
##      compete globally (truncation, FFF2 discipline) and the survivors claim
##      the fixed community positions along a coprime stride - one plant per
##      position, deterministic, no dispersal randomness.
##
## Texture enters ONLY as water field parameters (uptake efficiency, evaporation
## multiplier, fixture moisture) - never as a morphology rule (gate G9 source
## boundary). No plant writes the environment directly: water effects are
## published as plant_environment_effect records in canonical order.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_water_feedback_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF4.1"

const GRID_SIDE := 5
const SPACING_M := 0.35
const POPULATION_SIZE := GRID_SIDE * GRID_SIDE
## FFF2 directional-evolution discipline: 4 offspring per ranked parent give the
## truncation selection enough mutation supply to move morphology axes within
## the 16-generation R1 budget.
const OFFSPRING_PER_PARENT := 4
const GENERATIONS := 16
const MUTATION_STREAM_FORMULA := "EVO7-WATER|seed|gen|parent|off"

## Fixture channel: identical atmospheric evaporation demand in both scenarios,
## so the dry/mesic contrast comes from texture parameters + fixture moisture.
const BASE_EVAPORATION_RATE_PPM := 20000.0
const SCENARIOS: Array[String] = ["dry_sand", "mesic_loam"]

const FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment",
]

## Mean-feature report adds the allocation axis (G9 root-heavy direction).
const MEAN_FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment", "root_shoot_ratio",
]

static func run_all(lineage_seed := 20260823, generations := GENERATIONS) -> Dictionary:
	if generations < 2:
		return {}
	var policy := LineageExtension.default_policy()
	if LineageExtension.policy_hash(policy).is_empty():
		return {}
	var ancestor := default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	var positions := _grid_positions()

	var scenarios := {}
	for scenario in SCENARIOS:
		var fixture := scenario_fixture(scenario, lineage_seed, positions)
		if fixture.is_empty():
			return {}
		var initial_features := _population_features(ancestor, positions, fixture["base_env"])
		var initial_field := WaterField.compute(_water_records(initial_features), fixture["field_inputs"])
		if initial_field.is_empty():
			return {}
		var on_result := _run_mode(ancestor, positions, fixture, lineage_seed, generations, policy, true)
		var off_result := _run_mode(ancestor, positions, fixture, lineage_seed, generations, policy, false)
		if on_result.is_empty() or off_result.is_empty():
			return {}
		var feature_delta := {}
		for field_name in FEATURE_FIELDS:
			feature_delta[field_name] = snappedf(
				float(on_result["mean_features"][field_name]) - float(off_result["mean_features"][field_name]), 1e-9)
		scenarios[scenario] = {
			"fixture": fixture,
			"initial_field_hash": String(initial_field["field_hash"]),
			"initial_plant_uptake_hash": String(initial_field["plant_uptake_hash"]),
			"feedback_on": on_result,
			"feedback_off": off_result,
			"feature_delta_on_minus_off": feature_delta,
		}

	# G9 comparison: feedback-ON dry_sand vs mesic_loam final communities.
	var dry: Dictionary = scenarios["dry_sand"]["feedback_on"]["mean_features"]
	var mesic: Dictionary = scenarios["mesic_loam"]["feedback_on"]["mean_features"]
	var dry_moisture: float = scenarios["dry_sand"]["feedback_on"]["mean_cell_moisture"]
	var mesic_moisture: float = scenarios["mesic_loam"]["feedback_on"]["mean_cell_moisture"]
	var comparison := {
		"lai_dry_minus_mesic": snappedf(float(dry["leaf_area_index_proxy"]) - float(mesic["leaf_area_index_proxy"]), 1e-9),
		"root_depth_mesic_minus_dry": snappedf(float(mesic["realized_root_depth_m"]) - float(dry["realized_root_depth_m"]), 1e-9),
		"rsr_dry_minus_mesic": snappedf(float(dry["root_shoot_ratio"]) - float(mesic["root_shoot_ratio"]), 1e-9),
		"moisture_mesic_minus_dry": snappedf(mesic_moisture - dry_moisture, 1e-9),
	}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"lineage_seed": lineage_seed,
		"generations": generations,
		"population_size": POPULATION_SIZE,
		"mutation_stream_formula": MUTATION_STREAM_FORMULA,
		"scenarios": scenarios,
		"comparison_dry_sand_vs_mesic_loam": comparison,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func default_ancestor_bundle(lineage_seed: int) -> Dictionary:
	var genome := Genome.create_default()
	var dev_traits := Traits.create(
		"plant-development/evo7-ancestor-ref", 3.2, 0.32, 0.62, 0.9, 42.0, 0.78, 4, 6.0)
	var ext_traits := ExtensionTraits.create("plant-development-extension/evo7-water-ancestor", 0.65, 0.50, 0.40, 1.60, 0.50)
	return LineageExtension.create_ancestor_bundle(genome, dev_traits, ext_traits, lineage_seed)

## Texture x moisture fixture variant over the given positions: texture map and
## per-cell base moisture (control-point soil moisture) cover every occupied cell.
static func scenario_fixture(scenario: String, lineage_seed: int, positions: Array[Dictionary]) -> Dictionary:
	var control_point := ""
	var texture := ""
	match scenario:
		"dry_sand":
			control_point = "dry_ridge"
			texture = "sand"
		"mesic_loam":
			control_point = "wet_lowland"
			texture = "loam"
		_:
			return {}
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
		"fixture_id": "eco-soil-texture/fff4-%s" % scenario,
		"fixture_version": "1.0.0",
		"textures": textures,
		"base_moisture": base_moisture,
		"base_evaporation_rate": BASE_EVAPORATION_RATE_PPM,
	}
	var probe_ancestor := default_ancestor_bundle(lineage_seed)
	if probe_ancestor.is_empty():
		return {}
	var probe_features := _population_features(probe_ancestor, positions, base_env)
	if WaterField.compute(_water_records(probe_features), field_inputs).is_empty():
		return {}
	return {
		"scenario": scenario,
		"texture": texture,
		"control_point": control_point,
		"base_env": base_env,
		"base_soil_moisture": snappedf(float(base_env["soil_moisture"]), 1e-9),
		"base_evaporation_rate": BASE_EVAPORATION_RATE_PPM,
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

## One generation step shared by both modes up to the environment assignment.
static func _run_mode(
	ancestor: Dictionary,
	positions: Array[Dictionary],
	fixture: Dictionary,
	lineage_seed: int,
	generations: int,
	policy: Dictionary,
	use_feedback: bool
) -> Dictionary:
	var mode := "feedback_on" if use_feedback else "feedback_off"
	var base_env: Dictionary = fixture["base_env"]
	var field_inputs: Dictionary = fixture["field_inputs"]
	var population: Array[Dictionary] = []
	for position in positions:
		var bundle: Dictionary = ancestor.duplicate(true)
		population.append({
			"identity": String(position["identity"]),
			"world_x_m": float(position["world_x_m"]),
			"world_z_m": float(position["world_z_m"]),
			"bundle": bundle,
		})

	var first_pool_hash := ""
	var last_field_hash := ""
	var last_mean_moisture := 0.0
	var last_mean_fitness := 0.0
	var last_effects_combined := ""
	for generation in range(1, generations + 1):
		var features := _population_features_of(population, base_env)
		var records := _water_records(features)
		var field := WaterField.compute(records, field_inputs)
		if field.is_empty():
			return {}
		var effects := WaterField.effect_records(records, field_inputs, generation)
		if effects.is_empty():
			return {}
		last_field_hash = String(field["field_hash"])
		last_effects_combined = String(Effect.combined_hash(effects))

		var cell_moisture := {}
		var moisture_total := 0.0
		var cell_ids: Array = field["cells"].keys()
		cell_ids.sort()
		for cell_id in cell_ids:
			var moisture := float(field["cells"][cell_id]["moisture_after"])
			cell_moisture[cell_id] = moisture
			moisture_total += moisture
		last_mean_moisture = snappedf(moisture_total / float(cell_ids.size()), 1e-9)

		var scored: Array[Dictionary] = []
		var candidate_hashes := PackedStringArray()
		for entry_index in population.size():
			var entry: Dictionary = population[entry_index]
			var effective_moisture := float(base_env["soil_moisture"])
			if use_feedback:
				var plant_cell := String(field["plant_uptake"][String(entry["identity"])]["cell_identity"])
				effective_moisture = float(cell_moisture[plant_cell])
			var derived_env := EnvSample.create(
				float(entry["world_x_m"]), float(entry["world_z_m"]),
				float(base_env["temperature_c"]), clampf(effective_moisture, 0.0, 1.0),
				float(base_env["sunlight"]), float(base_env["nutrients"]), float(base_env["flood_frequency"]),
				int(base_env["seed"]),
				"%s|fff4|%s" % [String(base_env["environment_revision"]), String(entry["identity"])])
			var fp := _evaluate(entry["bundle"], derived_env)
			if fp.is_empty():
				return {}
			var scored_entry := {
				"identity": String(entry["identity"]),
				"world_x_m": float(entry["world_x_m"]),
				"world_z_m": float(entry["world_z_m"]),
				"bundle": entry["bundle"],
				"fitness": float(fp["net_resource_proxy"]),
				"cell_moisture": snappedf(effective_moisture, 1e-9),
			}
			scored.append(scored_entry)
		if generation == 1:
			for scored_entry in scored:
				candidate_hashes.append("%s:%.9f" % [String(scored_entry["bundle"]["bundle_checksum"]), float(scored_entry["fitness"])])
			first_pool_hash = "|".join(candidate_hashes).sha256_text()
		var fitness_total := 0.0
		for scored_entry in scored:
			fitness_total += float(scored_entry["fitness"])
		last_mean_fitness = snappedf(fitness_total / float(scored.size()), 1e-9)

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
				var mutation_seed := ("EVO7-WATER|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child_result := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child_result.is_empty():
					return {}
				candidates.append({
					"bundle": child_result["bundle"],
					"parent_fitness": float(parent["fitness"]),
				})
		# Global truncation (FFF2 directional discipline): all offspring compete,
		# the best POPULATION_SIZE claim the community positions. Positions are
		# assigned along a fixed coprime stride (7 is coprime to 25) so fitness
		# rank never systematically aligns with one spatial cell, and exactly one
		# plant occupies each position. Identity stays the canonical position key.
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
				"parent_fitness": float(candidates[rank]["parent_fitness"]),
			})
		next_population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["identity"]) < String(b["identity"]))
		population = next_population

	var final_features := _population_features_of(population, base_env)
	var final_field := WaterField.compute(_water_records(final_features), field_inputs)
	if final_field.is_empty():
		return {}
	var mean_features := {}
	for field_name in MEAN_FEATURE_FIELDS:
		var total := 0.0
		for entry in final_features:
			total += float(entry["features"][field_name])
		mean_features[field_name] = snappedf(total / float(final_features.size()), 1e-9)

	var checksums := PackedStringArray()
	for entry in population:
		checksums.append(String(entry["bundle"]["bundle_checksum"]))
	checksums.sort()
	var population_hash := "|".join(checksums).sha256_text()

	var moisture_by_identity := {}
	for identity in final_field["plant_uptake"].keys():
		var plant_cell := String(final_field["plant_uptake"][identity]["cell_identity"])
		moisture_by_identity[identity] = float(final_field["cells"][plant_cell]["moisture_after"])
	var dry_quartile_root_depth := _quartile_mean_root_depth(final_features, moisture_by_identity, true)
	var wet_quartile_root_depth := _quartile_mean_root_depth(final_features, moisture_by_identity, false)

	return {
		"mode": mode,
		"first_generation_score_hash": first_pool_hash,
		"final_population_hash": population_hash,
		"final_field_hash": String(final_field["field_hash"]),
		"final_plant_uptake_hash": String(final_field["plant_uptake_hash"]),
		"last_effects_combined_hash": last_effects_combined,
		"mean_cell_moisture": last_mean_moisture,
		"mean_fitness": last_mean_fitness,
		"mean_features": mean_features,
		"driest_quartile_mean_root_depth": dry_quartile_root_depth,
		"wettest_quartile_mean_root_depth": wet_quartile_root_depth,
	}

static func _envelope(bundle: Dictionary, env: Dictionary) -> Dictionary:
	return Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]),
		"evo7-water|%s|%.3f" % [String(env["environment_revision"]), float(env["soil_moisture"])],
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

## Realize every plant under the base environment and publish geometry features.
static func _population_features_of(population: Array[Dictionary], base_env: Dictionary) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for entry in population:
		var bundle: Dictionary = entry["bundle"]
		var envelope := Contract.create_seed_envelope(
			bundle["genome"], bundle["dev_traits"],
			String(bundle["lineage"]["lineage_id"]),
			"evo7-water-feature|%s" % String(entry["identity"]), 0, 1.25)
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

## Mean realized root depth of the driest quartile (true) vs wettest quartile
## (false) of plants, ranked by the moisture of the cell each plant occupies.
static func _quartile_mean_root_depth(feature_entries: Array[Dictionary], moisture_by_identity: Dictionary, driest: bool) -> float:
	var pairs: Array[Dictionary] = []
	for entry in feature_entries:
		pairs.append({
			"moisture": float(moisture_by_identity[String(entry["identity"])]),
			"root_depth": float(entry["features"]["realized_root_depth_m"]),
		})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["moisture"]) < float(b["moisture"]))
	var quartile := maxi(pairs.size() / 4, 1)
	var total := 0.0
	var range_start := 0 if driest else pairs.size() - quartile
	for index in range(range_start, range_start + quartile):
		total += float(pairs[index]["root_depth"])
	return snappedf(total / float(quartile), 1e-9)

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("revision", "")),
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("generations", 0))),
		str(int(result.get("population_size", 0))),
		String(result.get("mutation_stream_formula", "")),
	])
	for scenario in SCENARIOS:
		var scenario_result: Dictionary = result.get("scenarios", {}).get(scenario, {})
		var fixture: Dictionary = scenario_result.get("fixture", {})
		tokens.append("%s:%s:%s:%s:%s" % [
			scenario,
			String(fixture.get("texture", "")),
			String(fixture.get("control_point", "")),
			"%.9f" % float(fixture.get("base_soil_moisture", 0.0)),
			String(fixture.get("base_env", {}).get("checksum", "")),
		])
		tokens.append(String(scenario_result.get("initial_field_hash", "")))
		for mode in ["feedback_on", "feedback_off"]:
			var mode_result: Dictionary = scenario_result.get(mode, {})
			tokens.append("%s:%s:%s:%s:%s:%.9f:%.9f:%.9f:%.9f:%.9f" % [
				mode,
				String(mode_result.get("final_population_hash", "")),
				String(mode_result.get("final_field_hash", "")),
				String(mode_result.get("last_effects_combined_hash", "")),
				String(mode_result.get("first_generation_score_hash", "")),
				float(mode_result.get("mean_cell_moisture", 0.0)),
				float(mode_result.get("mean_fitness", 0.0)),
				float(mode_result.get("driest_quartile_mean_root_depth", 0.0)),
				float(mode_result.get("wettest_quartile_mean_root_depth", 0.0)),
				float(mode_result.get("mean_features", {}).get("leaf_area_index_proxy", 0.0)),
			])
	return "|".join(tokens).sha256_text()
