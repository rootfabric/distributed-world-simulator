extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_final_unseen_world_protocol.v1"
const VERSION := "1.0.0"
const WORLD_ID := "eco-evo2-final/unseen-world-r1"
const SOURCE_PATCH_ID := "eco-evo2-final/source-port"
const DRY_PATCH_ID := "eco-evo2-final/unseen/dry-ridge"
const WET_PATCH_ID := "eco-evo2-final/unseen/wet-basin"
const ISOLATED_PATCH_ID := "eco-evo2-final/unseen/isolated-control"
const TRANSPORT_VECTOR := Vector2(1.0, 0.0)
const TURBULENCE := 0.25
const EMISSION_MULTIPLIER := 32
const POPULATION_SIZE := 8
const GENERATIONS := 10
const OFFSPRING_PER_PARENT := 4
const EVALUATION_BIOMASS_KG_M2 := 0.05
const MIN_REACHABLE_COLONIZED_PATCHES := 2
const MIN_UNIQUE_RECRUITED_SPECIES := 2
const MIN_SORTING_OBSERVED_CELLS := 1
const MIN_ADAPTATION_POSITIVE_CELLS := 1
const REQUIRE_ISOLATED_NO_COLONIZATION := true
const CENSOR_NULL_REVERSAL := false
const TARGET_AWARE_SPECIES_FILTER_ALLOWED := false
const BIOME_SPECIES_TABLE_ALLOWED := false
const REBAKE_ALLOWED := false
const PRODUCTION_AUTHORITY_CLAIMED := false

static func treatment_policy() -> Dictionary:
	return {
		"mutation_probability": 0.30,
		"water_preference_step": 0.055,
		"root_depth_m_step": 0.20,
		"growth_rate_step": 0.045,
		"shade_tolerance_step": 0.045,
		"seed_dispersal_distance_m_step": 0.0,
	}

static func control_policy() -> Dictionary:
	var policy := treatment_policy()
	policy["mutation_probability"] = 0.0
	return policy

static func build() -> Dictionary:
	var source_environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.40, 0.94, 0.82, 0.02, 2808001, "eco-evo2-final-source-port-r1")
	var dry_environment := EnvironmentSample.create(70.0, -120.0, 19.0, 0.26, 0.96, 0.78, 0.01, 2808002, "eco-evo2-final-hidden-dry-r1")
	var wet_environment := EnvironmentSample.create(70.0, 120.0, 18.0, 0.74, 0.92, 0.86, 0.08, 2808003, "eco-evo2-final-hidden-wet-r1")
	var isolated_environment := EnvironmentSample.create(560.0, 0.0, 16.5, 0.50, 0.90, 0.80, 0.03, 2808004, "eco-evo2-final-hidden-isolated-r1")
	var source_patch := PatchMigration.create_patch(SOURCE_PATCH_ID, Rect2(-1.0, -1.0, 2.0, 2.0), source_environment)
	var dry_patch := PatchMigration.create_patch(DRY_PATCH_ID, Rect2(1.001, -300.0, 300.0, 299.999), dry_environment)
	var wet_patch := PatchMigration.create_patch(WET_PATCH_ID, Rect2(1.001, 0.001, 300.0, 299.999), wet_environment)
	var isolated_patch := PatchMigration.create_patch(ISOLATED_PATCH_ID, Rect2(500.0, -300.0, 120.0, 600.0), isolated_environment)
	if source_patch.is_empty() or dry_patch.is_empty() or wet_patch.is_empty() or isolated_patch.is_empty():
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"world_id": WORLD_ID,
		"source_patch": source_patch,
		"target_patches": [dry_patch, wet_patch, isolated_patch],
		"transport_vector": TRANSPORT_VECTOR,
		"turbulence": TURBULENCE,
		"emission_multiplier": EMISSION_MULTIPLIER,
		"population_size": POPULATION_SIZE,
		"generations": GENERATIONS,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"evaluation_biomass_kg_m2": EVALUATION_BIOMASS_KG_M2,
		"control_policy": control_policy(),
		"treatment_policy": treatment_policy(),
		"min_reachable_colonized_patches": MIN_REACHABLE_COLONIZED_PATCHES,
		"min_unique_recruited_species": MIN_UNIQUE_RECRUITED_SPECIES,
		"min_sorting_observed_cells": MIN_SORTING_OBSERVED_CELLS,
		"min_adaptation_positive_cells": MIN_ADAPTATION_POSITIVE_CELLS,
		"require_isolated_no_colonization": REQUIRE_ISOLATED_NO_COLONIZATION,
		"censor_null_reversal": CENSOR_NULL_REVERSAL,
		"target_aware_species_filter_allowed": TARGET_AWARE_SPECIES_FILTER_ALLOWED,
		"biome_species_table_allowed": BIOME_SPECIES_TABLE_ALLOWED,
		"rebake_allowed": REBAKE_ALLOWED,
		"production_authority_claimed": PRODUCTION_AUTHORITY_CLAIMED,
	}
	result["protocol_hash"] = compute_hash(result)
	return result

static func validate(protocol: Dictionary) -> bool:
	var expected := build()
	return not expected.is_empty() and protocol == expected

static func compute_hash(protocol: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		WORLD_ID,
		String(Dictionary(protocol.get("source_patch", {})).get("checksum", "")),
		"transport=%.12f,%.12f|%.12f" % [TRANSPORT_VECTOR.x, TRANSPORT_VECTOR.y, TURBULENCE],
		"emission_multiplier=%d" % EMISSION_MULTIPLIER,
		"population=%d|generations=%d|offspring=%d|biomass=%.12f" % [POPULATION_SIZE, GENERATIONS, OFFSPRING_PER_PARENT, EVALUATION_BIOMASS_KG_M2],
		"gates=%d|%d|%d|%d|%s" % [MIN_REACHABLE_COLONIZED_PATCHES, MIN_UNIQUE_RECRUITED_SPECIES, MIN_SORTING_OBSERVED_CELLS, MIN_ADAPTATION_POSITIVE_CELLS, str(REQUIRE_ISOLATED_NO_COLONIZATION)],
		"forbidden=%s|%s|%s|%s|%s" % [str(CENSOR_NULL_REVERSAL), str(TARGET_AWARE_SPECIES_FILTER_ALLOWED), str(BIOME_SPECIES_TABLE_ALLOWED), str(REBAKE_ALLOWED), str(PRODUCTION_AUTHORITY_CLAIMED)],
	])
	for value in Array(protocol.get("target_patches", [])):
		tokens.append(String(Dictionary(value).get("checksum", "")))
	for key in ["mutation_probability", "water_preference_step", "root_depth_m_step", "growth_rate_step", "shade_tolerance_step", "seed_dispersal_distance_m_step"]:
		tokens.append("control|%s|%.12f" % [key, float(Dictionary(protocol.get("control_policy", {})).get(key, -1.0))])
		tokens.append("treatment|%s|%.12f" % [key, float(Dictionary(protocol.get("treatment_policy", {})).get(key, -1.0))])
	return "\n".join(tokens).sha256_text()
