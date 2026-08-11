extends RefCounted

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Profile = preload("res://scripts/research/ecology/plant_development_plasticity_profile_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.environment_coupled_development.v1"
const VERSION := "1.0.0"

static func realize(
	seed_envelope: Dictionary,
	inherited_traits: Dictionary,
	environment_sample: Dictionary,
	response_profile: Dictionary = {}
) -> Dictionary:
	var profile := Profile.create_default() if response_profile.is_empty() else response_profile
	if not bool(Traits.validate(inherited_traits).get("success", false)):
		return {}
	if not bool(Profile.validate(profile).get("success", false)):
		return {}
	if not bool(EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	if String(seed_envelope.get("schema", "")) != Contract.SEED_ENVELOPE_SCHEMA:
		return {}
	if String(seed_envelope.get("development_traits_checksum", "")) != String(inherited_traits.get("checksum", "")):
		return {}
	var individual_seed := int(seed_envelope.get("individual_seed", -1))
	if individual_seed < 0:
		return {}

	var response := _response(environment_sample, profile)
	var realized := _realized_traits(inherited_traits, environment_sample, profile, response)
	if realized.is_empty():
		return {}
	var graph := Skeleton.build(realized, individual_seed)
	if graph.is_empty():
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"individual_seed": individual_seed,
		"genome_checksum": String(seed_envelope.get("genome_checksum", "")),
		"inherited_traits_checksum": String(inherited_traits.get("checksum", "")),
		"environment_checksum": String(environment_sample.get("checksum", "")),
		"response_profile_checksum": String(profile.get("checksum", "")),
		"response": response,
		"realized_development_traits": realized,
		"growth_graph": graph,
	}
	result["phenotype_hash"] = compute_phenotype_hash(result)
	return result

static func _response(environment_sample: Dictionary, profile: Dictionary) -> Dictionary:
	var sunlight := float(environment_sample["sunlight"])
	var moisture := float(environment_sample["soil_moisture"])
	var nutrients := float(environment_sample["nutrients"])
	var flood := float(environment_sample["flood_frequency"])
	var shade_deficit := clampf((0.65 - sunlight) / 0.65, 0.0, 1.0)
	var sun_excess := clampf((sunlight - 0.55) / 0.45, 0.0, 1.0)
	var drought_stress := clampf((0.35 - moisture) / 0.35, 0.0, 1.0)
	var nutrient_bonus := clampf((nutrients - 0.35) / 0.65, 0.0, 1.0)
	return {
		"shade_deficit": shade_deficit,
		"sun_excess": sun_excess,
		"drought_stress": drought_stress,
		"nutrient_bonus": nutrient_bonus,
		"flood_stress": flood,
		"shade_elongation": shade_deficit * float(profile["shade_elongation_strength"]),
		"shade_branch_suppression": shade_deficit * float(profile["shade_branch_suppression"]),
		"light_branching": sun_excess * float(profile["light_branching_strength"]),
		"drought_suppression": drought_stress * float(profile["drought_size_suppression"]),
		"nutrient_growth": nutrient_bonus * float(profile["nutrient_growth_strength"]),
		"flood_suppression": flood * float(profile["flood_growth_suppression"]),
	}

static func _realized_traits(
	base: Dictionary,
	environment_sample: Dictionary,
	profile: Dictionary,
	response: Dictionary
) -> Dictionary:
	var shade_elong := float(response["shade_elongation"])
	var shade_branch := float(response["shade_branch_suppression"])
	var light_branch := float(response["light_branching"])
	var drought := float(response["drought_suppression"])
	var nutrient := float(response["nutrient_growth"])
	var flood := float(response["flood_suppression"])

	var max_height := float(base["max_height_m"]) * (1.0 + 0.25 * shade_elong - 0.35 * drought - 0.25 * flood + 0.12 * nutrient)
	var internode := float(base["internode_length_m"]) * (1.0 + 0.35 * shade_elong - 0.12 * light_branch)
	var apical := float(base["apical_dominance"]) + 0.18 * shade_branch - 0.12 * light_branch
	var branch_probability := float(base["branch_probability"]) * (1.0 - 0.50 * shade_branch - 0.35 * drought - 0.25 * flood) + 0.16 * light_branch + 0.08 * nutrient
	var branch_angle := float(base["branch_angle_deg"]) * (1.0 - 0.10 * shade_branch + 0.12 * light_branch)
	var branch_length_ratio := float(base["branch_length_ratio"]) * (1.0 - 0.20 * drought - 0.15 * flood + 0.10 * nutrient)
	var crown_spread := float(base["crown_spread_m"]) * (1.0 - 0.30 * shade_branch + 0.28 * light_branch - 0.35 * drought - 0.20 * flood + 0.10 * nutrient)

	max_height = _bounded("max_height_m", max_height)
	internode = _bounded("internode_length_m", internode)
	apical = _bounded("apical_dominance", apical)
	branch_probability = _bounded("branch_probability", branch_probability)
	branch_angle = _bounded("branch_angle_deg", branch_angle)
	branch_length_ratio = _bounded("branch_length_ratio", branch_length_ratio)
	crown_spread = _bounded("crown_spread_m", crown_spread)

	return Traits.create(
		String(base["traits_id"]) + "/plasticity/" + String(environment_sample["checksum"]).substr(0, 12),
		max_height,
		internode,
		apical,
		branch_probability,
		branch_angle,
		branch_length_ratio,
		int(base["branching_depth"]),
		crown_spread
	)

static func compute_phenotype_hash(result: Dictionary) -> String:
	var realized: Dictionary = result.get("realized_development_traits", {})
	var graph: Dictionary = result.get("growth_graph", {})
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		str(int(result.get("individual_seed", -1))),
		String(result.get("genome_checksum", "")),
		String(result.get("inherited_traits_checksum", "")),
		String(result.get("environment_checksum", "")),
		String(result.get("response_profile_checksum", "")),
		String(realized.get("checksum", "")),
		String(graph.get("graph_hash", "")),
	])).sha256_text()

static func _bounded(name: String, value: float) -> float:
	var bounds: Array = Traits.BOUNDS[name]
	return clampf(value, float(bounds[0]), float(bounds[1]))
