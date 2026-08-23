extends RefCounted

## ECO.EVO7 FFF3 - light feedback bridge: plants change the light field, the changed
## field changes selection (spec sections 8, 13; gates G6/G7/G10/G12).
##
## Community microcosm: 5x5 plants on a 0.5 m grid (crown scale - skeleton crowns
## are sub-meter). Each generation:
##   1. realize every plant under its CURRENT light (plasticity), publish geometry;
##   2. aggregate the understory light field from published geometry (canonical
##      identity order, cell buckets, Beer-Lambert);
##   3. feedback ON: each plant is re-realized and scored under its OWN understory
##      light; feedback OFF (counterfactual): every plant scores under base light -
##      the mutation stream formula is identical in both modes, only the
##      environment assignment differs (that difference IS the tested causality);
##   4. reproduce through the single lineage authority and select.
##
## No plant writes the environment directly: geometry is published as
## plant_environment_effect records in canonical order.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_light_feedback_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF3.1"

const GRID_SIDE := 5
const SPACING_M := 0.35
const POPULATION_SIZE := GRID_SIDE * GRID_SIDE
const OFFSPRING_PER_PARENT := 2
const GENERATIONS := 16
const BASE_SCENARIO := "plateau"

const FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment",
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
	var base_env := Fixture.control_point(BASE_SCENARIO, lineage_seed)
	var positions := _grid_positions()

	var initial_features := _population_features(ancestor, positions, base_env)
	var initial_records := _records(initial_features)
	var initial_field := LightField.compute(initial_records)
	if initial_field.is_empty():
		return {}

	var on_result := _run_mode(ancestor, positions, base_env, lineage_seed, generations, policy, true)
	var off_result := _run_mode(ancestor, positions, base_env, lineage_seed, generations, policy, false)
	if on_result.is_empty() or off_result.is_empty():
		return {}

	var feature_delta := {}
	for field_name in FEATURE_FIELDS:
		feature_delta[field_name] = snappedf(
			float(on_result["mean_features"][field_name]) - float(off_result["mean_features"][field_name]), 1e-9)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"lineage_seed": lineage_seed,
		"generations": generations,
		"population_size": POPULATION_SIZE,
		"base_environment_checksum": String(base_env["checksum"]),
		"base_sunlight": float(base_env["sunlight"]),
		"initial_field_hash": String(initial_field["field_hash"]),
		"initial_plant_light_hash": String(initial_field["plant_light_hash"]),
		"feedback_on": on_result,
		"feedback_off": off_result,
		"feature_delta_on_minus_off": feature_delta,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func default_ancestor_bundle(lineage_seed: int) -> Dictionary:
	var genome := Genome.create_default()
	var dev_traits := Traits.create(
		"plant-development/evo7-ancestor-ref", 3.2, 0.32, 0.62, 0.9, 42.0, 0.78, 4, 6.0)
	var ext_traits := ExtensionTraits.create("plant-development-extension/evo7-light-ancestor", 0.65, 0.50, 0.40, 1.60, 0.50)
	return LineageExtension.create_ancestor_bundle(genome, dev_traits, ext_traits, lineage_seed)

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
	base_env: Dictionary,
	lineage_seed: int,
	generations: int,
	policy: Dictionary,
	use_feedback: bool
) -> Dictionary:
	var mode := "feedback_on" if use_feedback else "feedback_off"
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
	var last_mean_understory := 0.0
	var last_effects_combined := ""
	for generation in range(1, generations + 1):
		var features := _population_features_of(population, base_env)
		var records := _records(features)
		var field := LightField.compute(records)
		if field.is_empty():
			return {}
		var effects := LightField.effect_records(records, generation)
		if effects.is_empty():
			return {}
		last_field_hash = String(field["field_hash"])
		last_effects_combined = String(Effect.combined_hash(effects))

		var understory := {}
		var mean_light := 0.0
		for identity in field["plant_light"].keys():
			var light := float(field["plant_light"][identity]["understory_light"])
			understory[identity] = light
			mean_light += light
		last_mean_understory = snappedf(mean_light / float(population.size()), 1e-9)

		var scored: Array[Dictionary] = []
		var candidate_hashes := PackedStringArray()
		for entry_index in population.size():
			var entry: Dictionary = population[entry_index]
			var effective_sunlight := float(base_env["sunlight"])
			if use_feedback:
				effective_sunlight = float(understory[String(entry["identity"])])
			var derived_env := EnvSample.create(
				float(entry["world_x_m"]), float(entry["world_z_m"]),
				float(base_env["temperature_c"]), float(base_env["soil_moisture"]),
				clampf(effective_sunlight, 0.0, 1.0),
				float(base_env["nutrients"]), float(base_env["flood_frequency"]),
				int(base_env["seed"]),
				"%s|fff3|%s" % [String(base_env["environment_revision"]), String(entry["identity"])])
			var envelope := _envelope(entry["bundle"], derived_env)
			var ph2 := CoupledDevelopment.realize(envelope, entry["bundle"]["dev_traits"], derived_env)
			var fp := FunctionalPhenotype.compile({
				"genome": entry["bundle"]["genome"],
				"ph2_realized": ph2,
				"traits_extension": entry["bundle"]["ext_traits"],
				"environment_sample": derived_env,
				"age_fraction": 1.0,
			})
			if fp.is_empty():
				return {}
			var scored_entry := {
				"identity": String(entry["identity"]),
				"world_x_m": float(entry["world_x_m"]),
				"world_z_m": float(entry["world_z_m"]),
				"bundle": entry["bundle"],
				"fitness": float(fp["net_resource_proxy"]),
				"understory_light": snappedf(effective_sunlight, 1e-9),
			}
			scored.append(scored_entry)
		if generation == 1:
			for scored_entry in scored:
				candidate_hashes.append("%s:%.9f" % [String(scored_entry["bundle"]["bundle_checksum"]), float(scored_entry["fitness"])])
			first_pool_hash = "|".join(candidate_hashes).sha256_text()

		var ranked: Array[Dictionary] = scored.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["fitness"]) != float(b["fitness"]):
				return float(a["fitness"]) > float(b["fitness"])
			return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"]))
		var next_population: Array[Dictionary] = []
		for parent_index in population.size():
			var parent: Dictionary = ranked[parent_index]
			for offspring_index in OFFSPRING_PER_PARENT:
				var mutation_seed := ("EVO7-LIGHT|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child_result := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child_result.is_empty():
					return {}
				var child_bundle: Dictionary = child_result["bundle"]
				var child_entry := {
					"identity": parent["identity"],
					"world_x_m": float(parent["world_x_m"]),
					"world_z_m": float(parent["world_z_m"]),
					"bundle": child_bundle,
					"parent_fitness": float(parent["fitness"]),
				}
				next_population.append(child_entry)
		next_population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.get("parent_fitness", 0.0)) != float(b.get("parent_fitness", 0.0)):
				return float(a.get("parent_fitness", 0.0)) > float(b.get("parent_fitness", 0.0))
			return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"]))
		# One plant per community position: identity is the canonical order key,
		# so competing offspring of the same position collapse to their best-ranked member.
		var occupied := {}
		var settled: Array[Dictionary] = []
		for candidate in next_population:
			var identity := String(candidate["identity"])
			if occupied.has(identity):
				continue
			occupied[identity] = true
			settled.append(candidate)
			if settled.size() >= POPULATION_SIZE:
				break
		population = settled

	var final_features := _population_features_of(population, base_env)
	var final_field := LightField.compute(_records(final_features))
	if final_field.is_empty():
		return {}
	var mean_features := {}
	for field_name in FEATURE_FIELDS:
		var total := 0.0
		for entry in final_features:
			total += float(entry["features"][field_name])
		mean_features[field_name] = snappedf(total / float(final_features.size()), 1e-9)

	var checksums := PackedStringArray()
	for entry in population:
		checksums.append(String(entry["bundle"]["bundle_checksum"]))
	checksums.sort()
	var population_hash := "|".join(checksums).sha256_text()

	var shade_lai := _quartile_mean_lai(final_features, final_field, true)
	var light_lai := _quartile_mean_lai(final_features, final_field, false)

	return {
		"mode": mode,
		"first_generation_score_hash": first_pool_hash,
		"final_population_hash": population_hash,
		"final_field_hash": String(final_field["field_hash"]),
		"final_plant_light_hash": String(final_field["plant_light_hash"]),
		"last_effects_combined_hash": last_effects_combined,
		"mean_understory_light": last_mean_understory,
		"mean_features": mean_features,
		"deep_shade_mean_lai": shade_lai,
		"open_light_mean_lai": light_lai,
	}

static func _envelope(bundle: Dictionary, env: Dictionary) -> Dictionary:
	return Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]),
		"evo7-light|%s|%.3f" % [String(env["environment_revision"]), float(env["sunlight"])],
		0, 1.25)

## Realize every plant under the base environment and publish geometry features.
static func _population_features_of(population: Array[Dictionary], base_env: Dictionary) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for entry in population:
		var bundle: Dictionary = entry["bundle"]
		var envelope := Contract.create_seed_envelope(
			bundle["genome"], bundle["dev_traits"],
			String(bundle["lineage"]["lineage_id"]),
			"evo7-light-feature|%s" % String(entry["identity"]), 0, 1.25)
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
			"base_sunlight": float(base_env["sunlight"]),
			"shade_output_ppm": int(fp["shade_output_ppm"]),
			"source_phenotype_hash": String(fp["phenotype_hash"]),
			"features": {},
		}
		for field_name in FEATURE_FIELDS:
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

static func _records(feature_entries: Array[Dictionary]) -> Array:
	var records: Array = []
	for entry in feature_entries:
		var record := {}
		for key in ["identity", "world_x_m", "world_z_m", "realized_height_m", "realized_crown_radius_m", "realized_crown_density", "leaf_area_index_proxy", "base_sunlight", "shade_output_ppm", "source_phenotype_hash"]:
			record[key] = entry[key]
		records.append(record)
	return records

## Mean LAI of the deepest-shade quartile (true) vs lightest quartile (false).
static func _quartile_mean_lai(feature_entries: Array[Dictionary], field: Dictionary, deep_shade: bool) -> float:
	var pairs: Array[Dictionary] = []
	for entry in feature_entries:
		var light_entry: Dictionary = field["plant_light"][String(entry["identity"])]
		pairs.append({
			"light": float(light_entry["understory_light"]),
			"lai": float(entry["features"]["leaf_area_index_proxy"]),
		})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["light"]) < float(b["light"]))
	var quartile := maxi(pairs.size() / 4, 1)
	var total := 0.0
	var range_start := 0 if deep_shade else pairs.size() - quartile
	for index in range(range_start, range_start + quartile):
		total += float(pairs[index]["lai"])
	return snappedf(total / float(quartile), 1e-9)

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("revision", "")),
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("generations", 0))),
		str(int(result.get("population_size", 0))),
		String(result.get("initial_field_hash", "")),
		String(result.get("initial_plant_light_hash", "")),
	])
	for mode in ["feedback_on", "feedback_off"]:
		var mode_result: Dictionary = result.get(mode, {})
		tokens.append("%s:%s:%s:%s:%.9f" % [
			mode,
			String(mode_result.get("final_population_hash", "")),
			String(mode_result.get("final_field_hash", "")),
			String(mode_result.get("last_effects_combined_hash", "")),
			float(mode_result.get("mean_understory_light", 0.0)),
		])
	return "|".join(tokens).sha256_text()
