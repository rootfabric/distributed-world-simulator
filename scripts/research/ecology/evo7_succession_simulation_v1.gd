extends RefCounted

## ECO.EVO7 FFF6 - closed community evolution / succession simulation (spec
## sections 13, 15, 17 Experiment A, 19 FFF6; design doc
## docs/plans/ECO_EVO7_FFF6_SUCCESSION_LAB_DESIGN_RU.md).
##
## Pure non-node research module: NO SceneTree, NO RNG, no rendering. BOTH the
## FFF6 lab scene and the FFF6 acceptance test consume THIS module, so the
## ecological math lives in exactly one place and the visual truth boundary
## stays clean (G15): the lab only reads derived results.
##
## Community microcosm per zone: the same 5x5 positions on a 0.35 m grid as
## FFF3/FFF4/FFF5, one plant per position, evolution loop of the FFF3 pattern
## (_run_mode): realize under base environment -> aggregate fields from published
## geometry -> score under OWN cell state (feedback ON) or base state
## (counterfactual OFF; identical mutation stream, only the environment
## assignment differs) -> reproduce ONLY through LineageExtension -> offspring
## keep their parent's position, best-ranked child claims it.
##
## COMBINED FEEDBACKS per generation (feedback ON):
##   1. LIGHT: understory_light_field_v1 over population geometry PLUS the static
##      canopy ring of UNDER_CANOPY / CANOPY_GAP (canopy trees publish geometry,
##      G6, but never reproduce and never enter water/litter records);
##   2. WATER: soil_water_field_v1 with zone texture fixture (sand/loam/clay),
##      bounded uptake, canopy-independent evaporation;
##   3. SOIL MEMORY: soil_organic_field_v1 accumulates litter into a carried
##      organic map across generations; the map feeds water retention next cycle
##      and the establishment bonus of the CURRENT cycle (FFF5 semantics).
## Scoring fitness = net_resource_proxy + ESTABLISHMENT_BONUS * establishment
## _capacity * own-cell organic (ON); plain net balance (OFF).
##
## EXPERIMENT A observability (spec section 17-A steps 5-6): CANOPY_GAP is
## input-identical to UNDER_CANOPY, but its canopy ring is REMOVED from the
## geometry records at a deterministic mid-run generation boundary (generation >
## CANOPY_REMOVAL_GENERATION). Removal is an operation on the research record
## list only; light restores and the light-demanding direction of selection
## returns. The lab mirrors the same removal in its presentation layer.
##
## TEXTURE CHANNEL (design-doc open question 1): environment_sample v1 is NOT
## extended; texture enters ONLY as versioned water/organic field parameters
## (FFF4 discipline). Zone checksums differ through the environment_revision
## suffix "<fixture_revision>|fff6|<zone>|<identity>".
##
## Deterministic: keyed mutation seeds "EVO7-FFF6|seed|gen|parent|off", canonical
## identity order for every float sum, snapped floats, fail-closed on invalid
## input (empty result). Effect records are published once at the FINAL
## generation of each mode run (the replay evidence channel); intermediate
## generations skip effect publication because nothing consumes it - this is a
## declared deviation from the FFF3/FFF4 bridges, documented for runtime cost.

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const OrganicField = preload("res://scripts/research/ecology/soil_organic_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const MorphologyBridge = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_succession_simulation.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF6.1"

const GRID_SIDE := 5
const SPACING_M := 0.35
const POPULATION_SIZE := GRID_SIDE * GRID_SIDE
const OFFSPRING_PER_PARENT := 2
const GENERATIONS := 16
const MUTATION_STREAM_FORMULA := "EVO7-FFF6|seed|gen|parent|off"

## Stability evidence horizon (spec section 19 FFF6: >= 100 generation-equivalents).
const STABILITY_GENERATIONS := 108

## Experiment A: the canopy ring leaves the geometry records AFTER this many
## generations have run WITH canopy (CANOPY_GAP zone only).
const CANOPY_REMOVAL_GENERATION := 8

const BASE_EVAPORATION_RATE_PPM := 20000.0

## FFF5 establishment constant reused verbatim (documented there): the bonus
## contributes the same order as the net spread between morphologies without
## masking physiology.
const ESTABLISHMENT_BONUS := 0.05

## Bound-pinning indicator threshold (G11 preview): an axis counts as pinned
## when its value reaches >= 99% of its bound range above the lower bound.
const BOUND_PINNING_FRACTION := 0.99

const ZONE_ORDER: Array[String] = [
	"FLOODED", "RIPARIAN", "MESIC_LOAM", "DRY_SAND", "UNDER_CANOPY", "CANOPY_GAP",
]

## Frozen R1 zone inputs (design doc section 3 table). control_point anchors the
## temperature/seed to the accepted synthetic fixture; moisture/sunlight/
## nutrients/flood are frozen zone constants; texture is a field-fixture channel.
const ZONE_PARAMETERS := {
	"FLOODED": {
		"texture": "clay", "soil_moisture": 0.95, "sunlight": 0.85,
		"nutrients": 0.70, "flood_frequency": 0.80,
		"canopy": false, "control_point": "river_bank",
	},
	"RIPARIAN": {
		"texture": "loam", "soil_moisture": 0.65, "sunlight": 0.85,
		"nutrients": 0.60, "flood_frequency": 0.35,
		"canopy": false, "control_point": "floodplain",
	},
	"MESIC_LOAM": {
		"texture": "loam", "soil_moisture": 0.45, "sunlight": 0.80,
		"nutrients": 0.45, "flood_frequency": 0.02,
		"canopy": false, "control_point": "plateau",
	},
	"DRY_SAND": {
		"texture": "sand", "soil_moisture": 0.18, "sunlight": 0.95,
		"nutrients": 0.25, "flood_frequency": 0.00,
		"canopy": false, "control_point": "dry_ridge",
	},
	"UNDER_CANOPY": {
		"texture": "loam", "soil_moisture": 0.45, "sunlight": 0.85,
		"nutrients": 0.45, "flood_frequency": 0.02,
		"canopy": true, "canopy_removed_at_generation": -1, "control_point": "wet_lowland",
	},
	"CANOPY_GAP": {
		"texture": "loam", "soil_moisture": 0.45, "sunlight": 0.85,
		"nutrients": 0.45, "flood_frequency": 0.02,
		"canopy": true, "canopy_removed_at_generation": CANOPY_REMOVAL_GENERATION, "control_point": "wet_lowland",
	},
}

## G5 numeric form: single source of truth stays in the FFF2 bridge.
const GEOMETRY_THRESHOLDS := MorphologyBridge.GEOMETRY_THRESHOLDS

const FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment",
]

## Mean-feature report adds allocation + establishment axes (G9/G11 observability).
const MEAN_FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment", "root_shoot_ratio", "establishment_capacity",
]

## Static canopy ring phenotype constants (fixed, non-evolving, G6 scenery).
const CANOPY_PLANT_COUNT := 8
const CANOPY_HEIGHT_M := 6.5
const CANOPY_CROWN_RADIUS_M := 1.30
const CANOPY_CROWN_DENSITY := 0.85
const CANOPY_LAI := 1.60
const CANOPY_RING_RADII_M: Array[float] = [0.90, 1.25]


static func run_all(lineage_seed := 20260823, generations := GENERATIONS) -> Dictionary:
	var context := create_context(lineage_seed, generations)
	if context.is_empty():
		return {}
	while not context_step(context):
		pass
	return context_finish(context)


## Incremental driver for non-blocking hosts (the FFF6 lab steps one zone per
## frame between repaints - design-doc open question 3: no threads, no SceneTree
## dependence, byte-identical aggregate to run_all).
## Context fields (internal): lineage_seed, generations, policy, ancestor,
## positions, zones (finished results), pool_hashes, pending (zone names).
static func create_context(lineage_seed := 20260823, generations := GENERATIONS) -> Dictionary:
	if generations < 2:
		return {}
	var policy := LineageExtension.default_policy()
	var policy_id := LineageExtension.policy_hash(policy)
	if policy_id.is_empty():
		return {}
	var ancestor := default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	return {
		"schema": SCHEMA,
		"lineage_seed": lineage_seed,
		"generations": generations,
		"policy": policy,
		"policy_hash": policy_id,
		"ancestor": ancestor,
		"positions": grid_positions(),
		"zones": {},
		"pool_hashes": PackedStringArray(),
		# Mutable working copy: ZONE_ORDER itself is a read-only constant.
		"pending": (ZONE_ORDER as Array).duplicate(),
	}


## Runs the next pending zone synchronously. Returns true when nothing remains.
static func context_step(context: Dictionary) -> bool:
	if context.is_empty() or (context["pending"] as Array).is_empty():
		return true
	var pending: Array = context["pending"]
	var zone_name := String(pending.pop_front())
	var zone_result := _run_zone(
		zone_name,
		context["ancestor"],
		context["positions"],
		int(context["lineage_seed"]),
		int(context["generations"]),
		context["policy"])
	if zone_result.is_empty():
		context["failed"] = zone_name
		context["pending"] = []
		return true
	context["zones"][zone_name] = zone_result
	context["pool_hashes"].append(String(zone_result["common_first_generation_pool_hash"]))
	return context["pending"].is_empty()


## Aggregates the finished context into the exact run_all result shape.
static func context_finish(context: Dictionary) -> Dictionary:
	if context.is_empty() or not context.get("failed", "").is_empty():
		return {}
	if context["zones"].size() != ZONE_ORDER.size():
		return {}

	# G4: one generation-one candidate pool shared by every zone (and by both
	# feedback modes inside each zone) - identical ancestor bundles + identical
	# keyed mutation stream make the pool hashes equal by construction;
	# enforced, not assumed.
	var common_pool: String = context["pool_hashes"][0]
	for pool_hash in context["pool_hashes"]:
		if pool_hash != common_pool:
			return {}

	var comparison := _cross_zone_comparison(context["zones"])
	if comparison.is_empty():
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"lineage_seed": int(context["lineage_seed"]),
		"generations": int(context["generations"]),
		"population_size": POPULATION_SIZE,
		"mutation_stream_formula": MUTATION_STREAM_FORMULA,
		"evo7_policy_hash": String(context["policy_hash"]),
		"ancestor_bundle_checksum": String(context["ancestor"]["bundle_checksum"]),
		"common_first_generation_pool_hash": common_pool,
		"zones": context["zones"],
		"comparison": comparison,
	}
	result["result_hash"] = _result_hash(result)
	return result


## Long-horizon stability evidence for ONE zone (feedback ON), >= 100 cycles.
## Returns a compact verdict dict; any NaN / out-of-bounds mean marks failure.
static func run_zone_stability(zone_name: String, lineage_seed := 20260823, generations := STABILITY_GENERATIONS) -> Dictionary:
	var parameters := zone_parameters(zone_name)
	if parameters.is_empty() or generations < 2:
		return {}
	var policy := LineageExtension.default_policy()
	if LineageExtension.policy_hash(policy).is_empty():
		return {}
	var ancestor := default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	var on_result := _run_zone_mode(
		zone_name, parameters, ancestor, grid_positions(), lineage_seed, generations, policy, true)
	if on_result.is_empty():
		return {}
	var finite_means := true
	for value in [
		float(on_result["mean_understory_light"]), float(on_result["mean_cell_moisture"]),
		float(on_result["mean_cell_organic"]), float(on_result["mean_net_balance"]),
	]:
		if not is_finite(value):
			finite_means = false
	for field_name in MEAN_FEATURE_FIELDS:
		if not is_finite(float(on_result["mean_features"][field_name])):
			finite_means = false
	var means_in_bounds := true
	for ratio_field in ["mean_understory_light", "mean_cell_moisture", "mean_cell_organic"]:
		var value := float(on_result[ratio_field])
		if value < -1e-9 or value > 1.0 + 1e-9:
			means_in_bounds = false
	var pinning: Dictionary = on_result["bound_pinning_fractions"]
	var no_axis_fully_pinned := float(on_result["max_bound_pinning_fraction"]) < 1.0
	var trajectory_finite := true
	for entry in on_result["mean_understory_light_trajectory"]:
		if not is_finite(float(entry)):
			trajectory_finite = false
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"zone": zone_name,
		"generations": generations,
		"completed_cycles": int(on_result["generations_completed"]),
		"finite_means": finite_means,
		"means_within_bounds": means_in_bounds,
		"no_axis_fully_pinned": no_axis_fully_pinned,
		"trajectory_finite": trajectory_finite,
		"max_bound_pinning_fraction": float(on_result["max_bound_pinning_fraction"]),
		"bound_pinning_fractions": pinning.duplicate(true),
		"final_population_hash": String(on_result["final_population_hash"]),
		"mean_understory_light": float(on_result["mean_understory_light"]),
		"mean_cell_moisture": float(on_result["mean_cell_moisture"]),
		"mean_cell_organic": float(on_result["mean_cell_organic"]),
		"mean_features": Dictionary(on_result["mean_features"]).duplicate(true),
	}


static func zone_parameters(zone_name: String) -> Dictionary:
	if not ZONE_PARAMETERS.has(zone_name):
		return {}
	return Dictionary(ZONE_PARAMETERS[zone_name]).duplicate(true)


## The frozen base EnvironmentSample of a zone (shared by the simulation, the
## lab's read-only realization for rendering, and overlay aggregation).
static func base_environment(zone_name: String) -> Dictionary:
	var parameters := zone_parameters(zone_name)
	if parameters.is_empty():
		return {}
	var control_sample := Fixture.control_point(String(parameters["control_point"]), Fixture.DEFAULT_SEED)
	if control_sample.is_empty():
		return {}
	var base_env := EnvSample.create(
		0.0, 0.0,
		snappedf(float(control_sample["temperature_c"]), 1e-9),
		snappedf(float(parameters["soil_moisture"]), 1e-9),
		snappedf(float(parameters["sunlight"]), 1e-9),
		snappedf(float(parameters["nutrients"]), 1e-9),
		snappedf(float(parameters["flood_frequency"]), 1e-9),
		int(control_sample["seed"]),
		"%s|fff6|%s" % [Fixture.ENVIRONMENT_REVISION, zone_name])
	if base_env.is_empty() or not bool(EnvSample.validate(base_env).get("success", false)):
		return {}
	return base_env


static func default_ancestor_bundle(lineage_seed: int) -> Dictionary:
	var genome := Genome.create_default()
	var dev_traits := Traits.create(
		"plant-development/evo7-ancestor-ref", 3.2, 0.32, 0.62, 0.9, 42.0, 0.78, 4, 6.0)
	var ext_traits := ExtensionTraits.create("plant-development-extension/evo7-succession-ancestor", 0.65, 0.50, 0.40, 1.60, 0.50)
	return LineageExtension.create_ancestor_bundle(genome, dev_traits, ext_traits, lineage_seed)


static func grid_positions() -> Array[Dictionary]:
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


## Static canopy ring geometry records: tall/dense fixed phenotypes that join
## LightField.compute(...) alongside the population (G6) but never reproduce and
## never enter water/litter records (declared R1 boundary).
static func canopy_records() -> Array:
	var records: Array = []
	for k in CANOPY_PLANT_COUNT:
		var angle := TAU * float(k) / float(CANOPY_PLANT_COUNT)
		var ring_radius: float = CANOPY_RING_RADII_M[k % CANOPY_RING_RADII_M.size()]
		records.append({
			"identity": "canopy%02d" % k,
			"world_x_m": snappedf(cos(angle) * ring_radius, 1e-9),
			"world_z_m": snappedf(sin(angle) * ring_radius, 1e-9),
			"realized_height_m": CANOPY_HEIGHT_M,
			"realized_crown_radius_m": CANOPY_CROWN_RADIUS_M,
			"realized_crown_density": CANOPY_CROWN_DENSITY,
			"leaf_area_index_proxy": CANOPY_LAI,
			"base_sunlight": 0.85,
			"shade_output_ppm": 90000,
			"source_phenotype_hash": "e".repeat(64),
		})
	return records


## Per-axis fraction of a population pinned at >= 99% toward the UPPER bound
## (G11 anti-runaway observability; canonical axis order of the single lineage
## authority).
static func bound_pinning_fractions(population: Array[Dictionary]) -> Dictionary:
	var fractions := {}
	if population.is_empty():
		return fractions
	for axis in LineageExtension.AXES:
		var layer := String(axis["layer"])
		var axis_name := String(axis["name"])
		var bounds: Array = Traits.BOUNDS[axis_name] if layer == "ph0" else ExtensionTraits.BOUNDS[axis_name]
		var low := float(bounds[0])
		var span := float(bounds[1]) - low
		var pinned := 0
		for entry in population:
			var source: Dictionary = entry["bundle"]["dev_traits"] if layer == "ph0" else entry["bundle"]["ext_traits"]
			var value := float(source[axis_name])
			if span > 0.0 and value >= low + BOUND_PINNING_FRACTION * span:
				pinned += 1
		fractions["%s:%s" % [layer, axis_name]] = snappedf(float(pinned) / float(population.size()), 1e-9)
	return fractions


static func max_pinning_fraction(fractions: Dictionary) -> float:
	var maximum := 0.0
	for key in fractions.keys():
		maximum = maxf(maximum, float(fractions[key]))
	return snappedf(maximum, 1e-9)


## Greedy threshold clustering of feature vectors (diagnostic label only, spec
## section 18: no hardcoded species-form labels anywhere near selection).
## Individuals are
## visited in canonical identity order; a vector joins the first cluster whose
## running centroid is NOT geometry-distinct from it, else founds a new cluster.
## Deterministic and traversal-order-safe because the order itself is canonical.
static func morphology_cluster_count(feature_entries: Array[Dictionary]) -> int:
	var ordered := feature_entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))
	var centroids: Array = []
	var counts: Array[int] = []
	for entry in ordered:
		var vector: Dictionary = entry["features"]
		var assigned := false
		for cluster_index in centroids.size():
			if not geometry_distinct(vector, centroids[cluster_index]):
				var count := counts[cluster_index] + 1
				counts[cluster_index] = count
				var centroid: Dictionary = centroids[cluster_index]
				for field_name in FEATURE_FIELDS:
					centroid[field_name] = snappedf(
						float(centroid[field_name]) + (float(vector[field_name]) - float(centroid[field_name])) / float(count), 1e-9)
				assigned = true
				break
		if not assigned:
			var fresh := {}
			for field_name in FEATURE_FIELDS:
				fresh[field_name] = float(vector[field_name])
			centroids.append(fresh)
			counts.append(1)
	return centroids.size()


## Same numeric semantics as the FFF2 gate: distinct when ANY field delta
## reaches its GEOMETRY_THRESHOLDS entry.
static func geometry_distinct(a: Dictionary, b: Dictionary) -> bool:
	for field_name in FEATURE_FIELDS:
		if absf(float(a[field_name]) - float(b[field_name])) >= float(GEOMETRY_THRESHOLDS[field_name]):
			return true
	return false


## ------------------------------------------------------------------ runners --

static func _run_zone(
	zone_name: String,
	ancestor: Dictionary,
	positions: Array[Dictionary],
	lineage_seed: int,
	generations: int,
	policy: Dictionary
) -> Dictionary:
	var parameters := zone_parameters(zone_name)
	if parameters.is_empty():
		return {}

	var control_sample := Fixture.control_point(String(parameters["control_point"]), Fixture.DEFAULT_SEED)
	if control_sample.is_empty():
		return {}
	var base_env := EnvSample.create(
		0.0, 0.0,
		snappedf(float(control_sample["temperature_c"]), 1e-9),
		snappedf(float(parameters["soil_moisture"]), 1e-9),
		snappedf(float(parameters["sunlight"]), 1e-9),
		snappedf(float(parameters["nutrients"]), 1e-9),
		snappedf(float(parameters["flood_frequency"]), 1e-9),
		int(control_sample["seed"]),
		"%s|fff6|%s" % [Fixture.ENVIRONMENT_REVISION, zone_name])
	if base_env.is_empty():
		return {}

	var textures := {}
	var base_moisture := {}
	for position in positions:
		var cell_id := WaterField.cell_identity_for(float(position["world_x_m"]), float(position["world_z_m"]))
		textures[cell_id] = String(parameters["texture"])
		base_moisture[cell_id] = snappedf(float(parameters["soil_moisture"]), 1e-9)
	var field_inputs := {
		"fixture_id": "eco-soil-texture/fff6-%s" % zone_name.to_lower(),
		"fixture_version": "1.0.0",
		"textures": textures,
		"base_moisture": base_moisture,
		"base_evaporation_rate": BASE_EVAPORATION_RATE_PPM,
	}

	var initial_population := _fresh_population(ancestor, positions)
	var initial_features := _population_features_of(initial_population, base_env)
	if initial_features.is_empty():
		return {}
	var initial_geometry := _geometry_records(initial_features)
	var initial_light_records := _with_canopy(initial_geometry, bool(parameters["canopy"]), -1)
	var initial_field := LightField.compute(initial_light_records)
	if initial_field.is_empty():
		return {}
	var initial_water := WaterField.compute(_water_records(initial_features), field_inputs)
	if initial_water.is_empty():
		return {}

	var initial_checksums := PackedStringArray()
	for entry in initial_population:
		initial_checksums.append(String(entry["bundle"]["bundle_checksum"]))
	initial_checksums.sort()

	var on_result := _run_zone_mode(zone_name, parameters, ancestor, positions, lineage_seed, generations, policy, true)
	var off_result := _run_zone_mode(zone_name, parameters, ancestor, positions, lineage_seed, generations, policy, false)
	if on_result.is_empty() or off_result.is_empty():
		return {}

	var common_pool := String(on_result["common_first_generation_pool_hash"])
	if common_pool.is_empty() or common_pool != String(off_result["common_first_generation_pool_hash"]):
		return {}

	return {
		"zone": zone_name,
		"parameters": parameters,
		"base_environment_checksum": String(base_env["checksum"]),
		"texture": String(parameters["texture"]),
		"initial_population_hash": "|".join(initial_checksums).sha256_text(),
		"initial_field_hash": String(initial_field["field_hash"]),
		"initial_plant_light_hash": String(initial_field["plant_light_hash"]),
		"initial_mean_understory_light": _population_mean_understory(initial_field, initial_population),
		"initial_water_field_hash": String(initial_water["field_hash"]),
		"common_first_generation_pool_hash": common_pool,
		"feedback_on": on_result,
		"feedback_off": off_result,
	}


static func _run_zone_mode(
	zone_name: String,
	parameters: Dictionary,
	ancestor: Dictionary,
	positions: Array[Dictionary],
	lineage_seed: int,
	generations: int,
	policy: Dictionary,
	use_feedback: bool
) -> Dictionary:
	var mode := "feedback_on" if use_feedback else "feedback_off"
	var has_canopy := bool(parameters["canopy"])
	var removed_at := int(parameters.get("canopy_removed_at_generation", -1))

	var control_sample := Fixture.control_point(String(parameters["control_point"]), Fixture.DEFAULT_SEED)
	if control_sample.is_empty():
		return {}
	var base_env := EnvSample.create(
		0.0, 0.0,
		snappedf(float(control_sample["temperature_c"]), 1e-9),
		snappedf(float(parameters["soil_moisture"]), 1e-9),
		snappedf(float(parameters["sunlight"]), 1e-9),
		snappedf(float(parameters["nutrients"]), 1e-9),
		snappedf(float(parameters["flood_frequency"]), 1e-9),
		int(control_sample["seed"]),
		"%s|fff6|%s" % [Fixture.ENVIRONMENT_REVISION, zone_name])

	var textures := {}
	var base_moisture := {}
	for position in positions:
		var cell_id := WaterField.cell_identity_for(float(position["world_x_m"]), float(position["world_z_m"]))
		textures[cell_id] = String(parameters["texture"])
		base_moisture[cell_id] = snappedf(float(parameters["soil_moisture"]), 1e-9)
	var field_inputs := {
		"fixture_id": "eco-soil-texture/fff6-%s" % zone_name.to_lower(),
		"fixture_version": "1.0.0",
		"textures": textures,
		"base_moisture": base_moisture,
		"base_evaporation_rate": BASE_EVAPORATION_RATE_PPM,
	}
	var organic_textures := textures.duplicate(true)

	var population := _fresh_population(ancestor, positions)
	var organic_map := {}

	var common_pool_hash := ""
	var first_score_hash := ""
	var last_mean_understory := 0.0
	var last_mean_moisture := 0.0
	var last_mean_organic := 0.0
	var last_mean_net := 0.0
	var last_mean_fitness := 0.0
	var pre_removal_light := -1.0
	var post_removal_light := -1.0
	var light_trajectory: Array = []
	var generations_completed := 0

	for generation in range(1, generations + 1):
		var canopy_active := has_canopy and not (removed_at > 0 and generation > removed_at)
		var features := _population_features_of(population, base_env)
		if features.is_empty():
			return {}
		var light_records := _with_canopy(_geometry_records(features), canopy_active, -1)
		var field := LightField.compute(light_records)
		if field.is_empty():
			return {}

		var understory := {}
		var light_total := 0.0
		for entry in population:
			var identity := String(entry["identity"])
			var light := float(field["plant_light"][identity]["understory_light"])
			understory[identity] = light
			light_total += light
		last_mean_understory = snappedf(light_total / float(population.size()), 1e-9)
		light_trajectory.append(last_mean_understory)
		if removed_at > 0 and generation == removed_at:
			pre_removal_light = last_mean_understory
		if removed_at > 0 and generation == removed_at + 1:
			post_removal_light = last_mean_understory

		var water_inputs := field_inputs.duplicate(true)
		if use_feedback and not organic_map.is_empty():
			water_inputs["organic_map"] = organic_map.duplicate(true)
		var water := WaterField.compute(_water_records(features), water_inputs)
		if water.is_empty():
			return {}
		var cell_moisture := {}
		var moisture_total := 0.0
		var cell_ids: Array = water["cells"].keys()
		cell_ids.sort()
		for cell_id in cell_ids:
			var moisture := float(water["cells"][cell_id]["moisture_after"])
			cell_moisture[cell_id] = moisture
			moisture_total += moisture
		last_mean_moisture = snappedf(moisture_total / float(cell_ids.size()), 1e-9)

		var organic_inputs := OrganicField.field_inputs_for("fff6-%s" % zone_name.to_lower(), organic_textures, organic_map)
		var organic_field := OrganicField.compute(_litter_records(features), organic_inputs)
		if organic_field.is_empty():
			return {}
		organic_map = organic_field["organic_map"]
		last_mean_organic = OrganicField.mean_cell_organic(organic_field)

		var scored: Array[Dictionary] = []
		var net_total := 0.0
		var fitness_total := 0.0
		for entry in population:
			var identity := String(entry["identity"])
			var effective_sunlight := float(base_env["sunlight"])
			var effective_moisture := float(base_env["soil_moisture"])
			var organic_here := 0.0
			if use_feedback:
				effective_sunlight = clampf(float(understory[identity]), 0.0, 1.0)
				var plant_cell := WaterField.cell_identity_for(float(entry["world_x_m"]), float(entry["world_z_m"]))
				effective_moisture = clampf(float(cell_moisture[plant_cell]), 0.0, 1.0)
				organic_here = float(organic_map.get(plant_cell, 0.0))
			var derived_env := EnvSample.create(
				float(entry["world_x_m"]), float(entry["world_z_m"]),
				float(base_env["temperature_c"]), effective_moisture,
				effective_sunlight, float(base_env["nutrients"]), float(base_env["flood_frequency"]),
				int(base_env["seed"]),
				"%s|fff6|%s|%s" % [String(base_env["environment_revision"]), zone_name, identity])
			var fp := _evaluate(entry["bundle"], derived_env)
			if fp.is_empty():
				return {}
			var net_balance := float(fp["net_resource_proxy"])
			var fitness := net_balance
			if use_feedback:
				fitness += ESTABLISHMENT_BONUS * float(fp["establishment_capacity"]) * organic_here
			net_total += net_balance
			fitness_total += fitness
			scored.append({
				"identity": identity,
				"bundle": entry["bundle"],
				"fitness": fitness,
			})
		last_mean_net = snappedf(net_total / float(scored.size()), 1e-9)
		last_mean_fitness = snappedf(fitness_total / float(scored.size()), 1e-9)
		generations_completed = generation

		if generation == 1:
			var score_tokens := PackedStringArray()
			for scored_entry in scored:
				score_tokens.append("%s:%.9f" % [String(scored_entry["bundle"]["bundle_checksum"]), float(scored_entry["fitness"])])
			first_score_hash = "|".join(score_tokens).sha256_text()

		# Reproduce through the SINGLE lineage authority (FFF3 settlement):
		# rank scored parents, every parent produces OFFSPRING_PER_PARENT
		# children that keep the parent's position, and the best-ranked child
		# claims it (one plant per community position).
		var ranked: Array[Dictionary] = scored.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["fitness"]) != float(b["fitness"]):
				return float(a["fitness"]) > float(b["fitness"])
			return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"]))
		var candidate_pool_hashes := PackedStringArray()
		var next_population: Array[Dictionary] = []
		for parent_index in population.size():
			var parent: Dictionary = ranked[parent_index]
			var best_child := {}
			for offspring_index in OFFSPRING_PER_PARENT:
				var mutation_seed := (MUTATION_STREAM_FORMULA.replace("seed", str(lineage_seed)).replace("gen", str(generation)).replace("parent", str(parent_index)).replace("off", str(offspring_index))).hash()
				var child_result := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child_result.is_empty():
					return {}
				if generation == 1:
					candidate_pool_hashes.append(String(child_result["result_hash"]))
				var child_bundle: Dictionary = child_result["bundle"]
				if best_child.is_empty() \
						or String(child_bundle["bundle_checksum"]) < String(best_child["bundle_checksum"]):
					best_child = child_bundle
			next_population.append({
				"identity": String(parent["identity"]),
				"world_x_m": float(positions[_position_index(String(parent["identity"]))]["world_x_m"]),
				"world_z_m": float(positions[_position_index(String(parent["identity"]))]["world_z_m"]),
				"bundle": best_child,
			})
		next_population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["identity"]) < String(b["identity"]))
		population = next_population

		if generation == 1:
			candidate_pool_hashes.sort()
			common_pool_hash = "|".join(candidate_pool_hashes).sha256_text()

	# Final-state publication: features, all three fields, effects, aggregates.
	var final_features := _population_features_of(population, base_env)
	if final_features.is_empty():
		return {}
	var final_canopy_active := has_canopy and not (removed_at > 0 and generations > removed_at)
	var final_light_records := _with_canopy(_geometry_records(final_features), final_canopy_active, -1)
	var final_field := LightField.compute(final_light_records)
	if final_field.is_empty():
		return {}
	var final_water_inputs := field_inputs.duplicate(true)
	if use_feedback and not organic_map.is_empty():
		final_water_inputs["organic_map"] = organic_map.duplicate(true)
	var final_water := WaterField.compute(_water_records(final_features), final_water_inputs)
	if final_water.is_empty():
		return {}
	var final_cell_moisture := {}
	var final_cell_ids: Array = final_water["cells"].keys()
	final_cell_ids.sort()
	for cell_id in final_cell_ids:
		final_cell_moisture[String(cell_id)] = float(final_water["cells"][cell_id]["moisture_after"])

	var light_effects := LightField.effect_records(final_light_records, generations)
	var water_effects := WaterField.effect_records(_water_records(final_features), final_water_inputs, generations)
	var litter_effects := OrganicField.effect_records(_litter_records(final_features), OrganicField.field_inputs_for("fff6-%s" % zone_name.to_lower(), organic_textures, {}), generations)
	if light_effects.is_empty() or water_effects.is_empty() or litter_effects.is_empty():
		return {}
	var combined_effects: Array = []
	combined_effects.append_array(light_effects)
	combined_effects.append_array(water_effects)
	combined_effects.append_array(litter_effects)

	var mean_features := {}
	for field_name in MEAN_FEATURE_FIELDS:
		var total := 0.0
		for entry in final_features:
			total += float(entry["features"][field_name])
		mean_features[field_name] = snappedf(total / float(final_features.size()), 1e-9)

	var economics_total := 0.0
	var checksums := PackedStringArray()
	var unique_checksums := {}
	for entry in population:
		economics_total += float(entry["bundle"]["ext_traits"]["leaf_economics_proxy"])
		var checksum := String(entry["bundle"]["bundle_checksum"])
		checksums.append(checksum)
		unique_checksums[checksum] = true
	checksums.sort()

	var pinning := bound_pinning_fractions(population)

	return {
		"mode": mode,
		"generations_completed": generations_completed,
		"common_first_generation_pool_hash": common_pool_hash,
		"first_generation_score_hash": first_score_hash,
		"final_population_hash": "|".join(checksums).sha256_text(),
		"unique_bundles": unique_checksums.size(),
		"final_field_hash": String(final_field["field_hash"]),
		"final_plant_light_hash": String(final_field["plant_light_hash"]),
		"final_water_field_hash": String(final_water["field_hash"]),
		"final_cell_moisture": final_cell_moisture,
		"final_organic_map_hash": _organic_map_hash(organic_map),
		"final_effects_combined_hash": Effect.combined_hash(combined_effects),
		"mean_understory_light": last_mean_understory,
		"mean_understory_light_trajectory": light_trajectory,
		"pre_removal_mean_understory_light": pre_removal_light,
		"post_removal_mean_understory_light": post_removal_light,
		"mean_cell_moisture": last_mean_moisture,
		"mean_cell_organic": last_mean_organic,
		"mean_net_balance": last_mean_net,
		"mean_fitness_with_bonus": last_mean_fitness,
		"mean_features": mean_features,
		"mean_leaf_economics_proxy": snappedf(economics_total / float(population.size()), 1e-9),
		"morphology_cluster_count": morphology_cluster_count(final_features),
		"bound_pinning_fractions": pinning,
		"max_bound_pinning_fraction": max_pinning_fraction(pinning),
		"canopy_present_at_end": final_canopy_active,
		"final_population": population,
	}


## --------------------------------------------------------------- comparison --

static func _cross_zone_comparison(zones: Dictionary) -> Dictionary:
	var names: Array[String] = []
	for zone_name in ZONE_ORDER:
		names.append(zone_name)
	var baseline := "MESIC_LOAM"
	var geometry_distinct_pairs := 0
	var distinct_pairs_list: Array[String] = []
	var zones_distinct_from_baseline := 0
	var on_off_divergent_zones := 0
	for i in names.size():
		var zone_a: Dictionary = zones[names[i]]
		if String(zone_a["feedback_on"]["final_population_hash"]) != String(zone_a["feedback_off"]["final_population_hash"]):
			on_off_divergent_zones += 1
		if names[i] != baseline and geometry_distinct(
				Dictionary(zone_a["feedback_on"]["mean_features"]),
				Dictionary(zones[baseline]["feedback_on"]["mean_features"])):
			zones_distinct_from_baseline += 1
		for j in range(i + 1, names.size()):
			var zone_b: Dictionary = zones[names[j]]
			if geometry_distinct(
					Dictionary(zone_a["feedback_on"]["mean_features"]),
					Dictionary(zone_b["feedback_on"]["mean_features"])):
				geometry_distinct_pairs += 1
				distinct_pairs_list.append("%s|%s" % [names[i], names[j]])

	var gap_light_restoration_delta := -1.0
	if zones.has("CANOPY_GAP") and zones.has("UNDER_CANOPY"):
		var gap_post := float(zones["CANOPY_GAP"]["feedback_on"]["post_removal_mean_understory_light"])
		var under_final := float(zones["UNDER_CANOPY"]["feedback_on"]["mean_understory_light"])
		if gap_post >= 0.0:
			gap_light_restoration_delta = snappedf(gap_post - under_final, 1e-9)

	return {
		"geometry_distinct_pairs": geometry_distinct_pairs,
		"geometry_distinct_pair_list": distinct_pairs_list,
		"zones_distinct_from_moderate_baseline": zones_distinct_from_baseline,
		"on_off_divergent_zones": on_off_divergent_zones,
		"gap_light_restoration_delta": gap_light_restoration_delta,
	}


## ------------------------------------------------------------------ helpers --

static func _fresh_population(ancestor: Dictionary, positions: Array[Dictionary]) -> Array[Dictionary]:
	var population: Array[Dictionary] = []
	for position in positions:
		population.append({
			"identity": String(position["identity"]),
			"world_x_m": float(position["world_x_m"]),
			"world_z_m": float(position["world_z_m"]),
			"bundle": (ancestor as Dictionary).duplicate(true),
		})
	population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))
	return population


static func _position_index(identity: String) -> int:
	return int(identity.substr(1).to_int())


static func _with_canopy(geometry: Array, include_canopy: bool, _unused: int) -> Array:
	var records: Array = []
	records.append_array(geometry)
	if include_canopy:
		records.append_array(canopy_records())
	return records


static func _population_mean_understory(field: Dictionary, population: Array[Dictionary]) -> float:
	var total := 0.0
	for entry in population:
		total += float(field["plant_light"][String(entry["identity"])]["understory_light"])
	return snappedf(total / float(population.size()), 1e-9)


static func _envelope(bundle: Dictionary, env: Dictionary) -> Dictionary:
	return Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]),
		"evo7-succession|%s|%.3f|%.3f" % [
			String(env["environment_revision"]),
			float(env["soil_moisture"]), float(env["sunlight"])],
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


## Public read-only realization of ONE community entry under a zone's frozen
## base environment - the exact call path behind _population_features_of, exposed
## so the FFF6 lab materializes visuals from the SAME growth graphs that feed the
## ecological fields (visual truth boundary, G15). Returns {} on failure.
static func realize_entry(bundle: Dictionary, identity: String, base_env: Dictionary) -> Dictionary:
	var envelope := Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]),
		"evo7-succession-feature|%s" % identity, 0, 1.25)
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], base_env)
	var fp := FunctionalPhenotype.compile({
		"genome": bundle["genome"],
		"ph2_realized": ph2,
		"traits_extension": bundle["ext_traits"],
		"environment_sample": base_env,
		"age_fraction": 1.0,
	})
	if fp.is_empty() or String(ph2.get("schema", "")) != CoupledDevelopment.SCHEMA:
		return {}
	return {"phenotype": fp, "growth_graph": ph2["growth_graph"]}


## Realize every plant under the base environment; publish geometry, demand and
## litter flux plus functional features (read-model records).
static func _population_features_of(population: Array[Dictionary], base_env: Dictionary) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for entry in population:
		var bundle: Dictionary = entry["bundle"]
		var envelope := Contract.create_seed_envelope(
			bundle["genome"], bundle["dev_traits"],
			String(bundle["lineage"]["lineage_id"]),
			"evo7-succession-feature|%s" % String(entry["identity"]), 0, 1.25)
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
			"establishment_capacity": float(fp["establishment_capacity"]),
			"base_sunlight": float(base_env["sunlight"]),
			"source_phenotype_hash": String(fp["phenotype_hash"]),
			"features": {},
		}
		for field_name in MEAN_FEATURE_FIELDS:
			record["features"][field_name] = float(fp[field_name])
		features.append(record)
	return features


## Geometry subset consumed by the understory light field.
static func _geometry_records(feature_entries: Array[Dictionary]) -> Array:
	var records: Array = []
	for entry in feature_entries:
		var record := {}
		for key in ["identity", "world_x_m", "world_z_m", "realized_height_m", "realized_crown_radius_m", "realized_crown_density", "leaf_area_index_proxy", "base_sunlight", "shade_output_ppm", "source_phenotype_hash"]:
			record[key] = entry[key]
		records.append(record)
	return records


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


static func _organic_map_hash(organic_map: Dictionary) -> String:
	var keys: Array = organic_map.keys()
	keys.sort()
	var tokens := PackedStringArray([SCHEMA, VERSION, "organic_map"])
	for key in keys:
		tokens.append("%s:%.9f" % [String(key), float(organic_map[key])])
	return "|".join(tokens).sha256_text()


static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("revision", "")),
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("generations", 0))),
		str(int(result.get("population_size", 0))),
		String(result.get("mutation_stream_formula", "")),
		String(result.get("evo7_policy_hash", "")),
		String(result.get("ancestor_bundle_checksum", "")),
		String(result.get("common_first_generation_pool_hash", "")),
	])
	for zone_name in ZONE_ORDER:
		var zone: Dictionary = result.get("zones", {}).get(zone_name, {})
		if zone.is_empty():
			continue
		var parameters: Dictionary = zone.get("parameters", {})
		tokens.append("%s:%s:%.2f:%.2f:%.2f:%.2f:%s" % [
			zone_name,
			String(parameters.get("texture", "")),
			float(parameters.get("soil_moisture", 0.0)),
			float(parameters.get("sunlight", 0.0)),
			float(parameters.get("nutrients", 0.0)),
			float(parameters.get("flood_frequency", 0.0)),
			String(zone.get("base_environment_checksum", "")),
		])
		tokens.append(String(zone.get("initial_field_hash", "")))
		tokens.append(String(zone.get("initial_plant_light_hash", "")))
		tokens.append(String(zone.get("initial_water_field_hash", "")))
		for mode_key in ["feedback_on", "feedback_off"]:
			var mode_result: Dictionary = zone.get(mode_key, {})
			tokens.append("%s:%s:%s:%s:%s:%s:%s:%.9f:%.9f:%.9f:%.9f:%.9f:%d:%d:%.9f" % [
				mode_key,
				String(mode_result.get("first_generation_score_hash", "")),
				String(mode_result.get("final_population_hash", "")),
				String(mode_result.get("final_field_hash", "")),
				String(mode_result.get("final_plant_light_hash", "")),
				String(mode_result.get("final_water_field_hash", "")),
				String(mode_result.get("final_organic_map_hash", "")),
				float(mode_result.get("mean_understory_light", 0.0)),
				float(mode_result.get("mean_cell_moisture", 0.0)),
				float(mode_result.get("mean_cell_organic", 0.0)),
				float(mode_result.get("mean_net_balance", 0.0)),
				float(mode_result.get("mean_leaf_economics_proxy", 0.0)),
				int(mode_result.get("unique_bundles", 0)),
				int(mode_result.get("morphology_cluster_count", 0)),
				float(mode_result.get("max_bound_pinning_fraction", 0.0)),
			])
	var comparison: Dictionary = result.get("comparison", {})
	tokens.append("%s:%d:%d:%d:%.9f" % [
		"comparison",
		int(comparison.get("geometry_distinct_pairs", 0)),
		int(comparison.get("zones_distinct_from_moderate_baseline", 0)),
		int(comparison.get("on_off_divergent_zones", 0)),
		float(comparison.get("gap_light_restoration_delta", -1.0)),
	])
	return "|".join(tokens).sha256_text()
