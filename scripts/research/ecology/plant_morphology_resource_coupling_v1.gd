extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Profile = preload("res://scripts/research/ecology/plant_morphology_resource_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_morphology_resource_coupling.v1"
const VERSION := "1.0.0"

static func evaluate(
	environment: Dictionary,
	genome: Dictionary,
	phenotype: Dictionary,
	biomass_kg_m2: float = 0.05,
	coupling_profile: Dictionary = {}
) -> Dictionary:
	var profile := Profile.create_default() if coupling_profile.is_empty() else coupling_profile
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not bool(Profile.validate(profile).get("success", false)):
		return {}
	if not is_finite(biomass_kg_m2) or biomass_kg_m2 < 0.0:
		return {}
	if String(phenotype.get("genome_checksum", "")) != String(genome.get("checksum", "")):
		return {}
	if String(phenotype.get("environment_checksum", "")) != String(environment.get("checksum", "")):
		return {}
	var traits: Dictionary = phenotype.get("realized_development_traits", {})
	var graph: Dictionary = phenotype.get("growth_graph", {})
	var metrics: Dictionary = graph.get("metrics", {})
	if traits.is_empty() or metrics.is_empty() or String(graph.get("graph_hash", "")).length() != 64:
		return {}

	var base := ResourceModel.evaluate(environment, genome, biomass_kg_m2)
	if base.is_empty():
		return {}

	var height_scale := maxf(0.01, float(metrics.get("height_m", 0.0)) / float(profile["reference_height_m"]))
	var crown_scale := maxf(0.01, float(traits.get("crown_spread_m", 0.0)) / float(profile["reference_crown_spread_m"]))
	var branch_scale := maxf(0.01, float(traits.get("branch_probability", 0.0)) / float(profile["reference_branch_probability"]))
	var length_scale := maxf(0.01, float(metrics.get("total_length_m", 0.0)) / float(profile["reference_total_length_m"]))
	var sunlight := float(environment["sunlight"])
	var moisture := float(environment["soil_moisture"])
	var nutrients := float(environment["nutrients"])
	var shade_pressure := clampf(1.0 - sunlight, 0.0, 1.0)
	var drought_pressure := clampf((0.40 - moisture) / 0.40, 0.0, 1.0)
	var nutrient_support := clampf(nutrients / 0.70, 0.0, 1.0)

	# Benefits saturate; costs rise super-linearly. The score is a PH3 research
	# overlay over the immutable accepted P1 resource result, never a rewrite of it.
	var height_light_access_benefit := float(profile["height_light_access_gain"]) * shade_pressure * (1.0 - exp(-0.90 * height_scale))
	var crown_light_capture_benefit := float(profile["crown_light_capture_gain"]) * sunlight * (1.0 - exp(-0.85 * crown_scale))
	var branch_light_capture_benefit := float(profile["branch_light_capture_gain"]) * sunlight * nutrient_support * (1.0 - exp(-0.90 * branch_scale))

	var structural_cost := float(profile["structural_cost_scale"]) * pow(height_scale, 1.55)
	var branch_maintenance_cost := float(profile["branch_maintenance_cost_scale"]) * pow(length_scale, 1.35)
	var branch_construction_cost := float(profile["branch_construction_cost_scale"]) * pow(branch_scale, 1.60)
	var crown_water_cost := float(profile["crown_water_cost_scale"]) * drought_pressure * pow(crown_scale, 1.25)

	var morphology_benefit := height_light_access_benefit + crown_light_capture_benefit + branch_light_capture_benefit
	var morphology_cost := structural_cost + branch_maintenance_cost + branch_construction_cost + crown_water_cost
	var morphology_delta := morphology_benefit - morphology_cost
	var coupled_net := float(base["net_resource_balance"]) + morphology_delta
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"environment_checksum": String(environment["checksum"]),
		"genome_checksum": String(genome["checksum"]),
		"phenotype_hash": String(phenotype.get("phenotype_hash", "")),
		"growth_graph_hash": String(graph["graph_hash"]),
		"resource_balance_checksum": String(base["checksum"]),
		"profile_checksum": String(profile["checksum"]),
		"height_scale": height_scale,
		"crown_scale": crown_scale,
		"branch_scale": branch_scale,
		"length_scale": length_scale,
		"height_light_access_benefit": height_light_access_benefit,
		"crown_light_capture_benefit": crown_light_capture_benefit,
		"branch_light_capture_benefit": branch_light_capture_benefit,
		"structural_cost": structural_cost,
		"branch_maintenance_cost": branch_maintenance_cost,
		"branch_construction_cost": branch_construction_cost,
		"crown_water_cost": crown_water_cost,
		"morphology_benefit": morphology_benefit,
		"morphology_cost": morphology_cost,
		"morphology_delta": morphology_delta,
		"base_net_resource_balance": float(base["net_resource_balance"]),
		"coupled_net_resource_balance": coupled_net,
	}
	result["coupling_hash"] = compute_checksum(result)
	return result

static func compute_checksum(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION,
		String(result.get("environment_checksum", "")),
		String(result.get("genome_checksum", "")),
		String(result.get("phenotype_hash", "")),
		String(result.get("growth_graph_hash", "")),
		String(result.get("resource_balance_checksum", "")),
		String(result.get("profile_checksum", "")),
	])
	for name in [
		"height_scale", "crown_scale", "branch_scale", "length_scale",
		"height_light_access_benefit", "crown_light_capture_benefit", "branch_light_capture_benefit",
		"structural_cost", "branch_maintenance_cost", "branch_construction_cost", "crown_water_cost",
		"morphology_benefit", "morphology_cost", "morphology_delta",
		"base_net_resource_balance", "coupled_net_resource_balance"
	]:
		tokens.append("%.9f" % float(result.get(name, 0.0)))
	return "|".join(tokens).sha256_text()
