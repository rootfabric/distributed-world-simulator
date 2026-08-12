extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const MorphologyProfile = preload("res://scripts/research/ecology/plant_morphology_resource_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_c_spatial_crown_root_competition.v1"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001

static func evaluate_crown_pair(
	phenotype_a: Dictionary,
	phenotype_b: Dictionary,
	environment: Dictionary,
	position_a: Vector2,
	position_b: Vector2
) -> Dictionary:
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	var traits_a: Dictionary = phenotype_a.get("realized_development_traits", {})
	var traits_b: Dictionary = phenotype_b.get("realized_development_traits", {})
	if traits_a.is_empty() or traits_b.is_empty():
		return {}
	var spread_a := float(traits_a.get("crown_spread_m", 0.0))
	var spread_b := float(traits_b.get("crown_spread_m", 0.0))
	var branch_a := float(traits_a.get("branch_probability", 0.0))
	var branch_b := float(traits_b.get("branch_probability", 0.0))
	if spread_a <= 0.0 or spread_b <= 0.0:
		return {}

	var radius_a := spread_a * 0.5
	var radius_b := spread_b * 0.5
	var distance := position_a.distance_to(position_b)
	var overlap_area := _circle_overlap_area(radius_a, radius_b, distance)
	var area_a := PI * radius_a * radius_a
	var area_b := PI * radius_b * radius_b
	var overlap_fraction_a := clampf(overlap_area / maxf(area_a, EPSILON), 0.0, 1.0)
	var overlap_fraction_b := clampf(overlap_area / maxf(area_b, EPSILON), 0.0, 1.0)

	var profile: Dictionary = MorphologyProfile.create_default()
	var sunlight := float(environment["sunlight"])
	var reference_crown := float(profile["reference_crown_spread_m"])
	var gain := float(profile["crown_light_capture_gain"])
	var crown_scale_a := maxf(0.01, spread_a / reference_crown)
	var crown_scale_b := maxf(0.01, spread_b / reference_crown)
	var potential_a := gain * sunlight * (1.0 - exp(-0.85 * crown_scale_a))
	var potential_b := gain * sunlight * (1.0 - exp(-0.85 * crown_scale_b))
	var neighbour_pressure_a := clampf(overlap_fraction_a * clampf(branch_b, 0.0, 1.0), 0.0, 1.0)
	var neighbour_pressure_b := clampf(overlap_fraction_b * clampf(branch_a, 0.0, 1.0), 0.0, 1.0)
	var overlap_loss_a := potential_a * neighbour_pressure_a
	var overlap_loss_b := potential_b * neighbour_pressure_b

	var result := {
		"schema": SCHEMA + ".crown_pair",
		"version": VERSION,
		"environment_checksum": String(environment["checksum"]),
		"phenotype_a_hash": String(phenotype_a.get("phenotype_hash", "")),
		"phenotype_b_hash": String(phenotype_b.get("phenotype_hash", "")),
		"position_a": position_a,
		"position_b": position_b,
		"center_distance_m": distance,
		"crown_radius_a_m": radius_a,
		"crown_radius_b_m": radius_b,
		"crown_area_a_m2": area_a,
		"crown_area_b_m2": area_b,
		"overlap_area_m2": overlap_area,
		"overlap_fraction_a": overlap_fraction_a,
		"overlap_fraction_b": overlap_fraction_b,
		"branch_probability_a": branch_a,
		"branch_probability_b": branch_b,
		"accepted_saturating_crown_potential_a": potential_a,
		"accepted_saturating_crown_potential_b": potential_b,
		"neighbour_shading_pressure_a": neighbour_pressure_a,
		"neighbour_shading_pressure_b": neighbour_pressure_b,
		"crown_overlap_loss_a": overlap_loss_a,
		"crown_overlap_loss_b": overlap_loss_b,
	}
	result["result_hash"] = _crown_hash(result)
	return result

static func evaluate_root_pair(
	genome_a: Dictionary,
	genome_b: Dictionary,
	environment: Dictionary,
	position_a: Vector2,
	position_b: Vector2
) -> Dictionary:
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not bool(PlantGenome.validate(genome_a).get("success", false)) or not bool(PlantGenome.validate(genome_b).get("success", false)):
		return {}

	# CAL1-C controlled geometry proxy only: horizontal root-zone radius equals root depth.
	# This does not canonize a 1:1 botanical relation; a future root-spread trait may replace it.
	var radius_a := float(genome_a["root_depth_m"])
	var radius_b := float(genome_b["root_depth_m"])
	var distance := position_a.distance_to(position_b)
	var overlap_area := _circle_overlap_area(radius_a, radius_b, distance)
	var area_a := PI * radius_a * radius_a
	var area_b := PI * radius_b * radius_b
	var overlap_fraction_a := clampf(overlap_area / maxf(area_a, EPSILON), 0.0, 1.0)
	var overlap_fraction_b := clampf(overlap_area / maxf(area_b, EPSILON), 0.0, 1.0)

	var capacity_a := maxf(float(genome_a["root_depth_m"]) * float(genome_a["growth_rate"]), EPSILON)
	var capacity_b := maxf(float(genome_b["root_depth_m"]) * float(genome_b["growth_rate"]), EPSILON)
	var total_capacity := capacity_a + capacity_b
	var shared_claim_a := capacity_a / total_capacity
	var shared_claim_b := capacity_b / total_capacity

	# The competitor can only remove its claim from the geometrically shared part.
	var retained_factor_a := clampf(1.0 - overlap_fraction_a * shared_claim_b, 0.0, 1.0)
	var retained_factor_b := clampf(1.0 - overlap_fraction_b * shared_claim_a, 0.0, 1.0)
	var effective_environment_a := _effective_root_environment(environment, retained_factor_a, "A")
	var effective_environment_b := _effective_root_environment(environment, retained_factor_b, "B")
	var baseline_a := ResourceModel.evaluate(environment, genome_a)
	var baseline_b := ResourceModel.evaluate(environment, genome_b)
	var competed_a := ResourceModel.evaluate(effective_environment_a, genome_a)
	var competed_b := ResourceModel.evaluate(effective_environment_b, genome_b)
	if baseline_a.is_empty() or baseline_b.is_empty() or competed_a.is_empty() or competed_b.is_empty():
		return {}

	var result := {
		"schema": SCHEMA + ".root_pair",
		"version": VERSION,
		"environment_checksum": String(environment["checksum"]),
		"genome_a_checksum": String(genome_a["checksum"]),
		"genome_b_checksum": String(genome_b["checksum"]),
		"position_a": position_a,
		"position_b": position_b,
		"center_distance_m": distance,
		"root_radius_proxy_a_m": radius_a,
		"root_radius_proxy_b_m": radius_b,
		"root_area_a_m2": area_a,
		"root_area_b_m2": area_b,
		"overlap_area_m2": overlap_area,
		"overlap_fraction_a": overlap_fraction_a,
		"overlap_fraction_b": overlap_fraction_b,
		"uptake_capacity_a": capacity_a,
		"uptake_capacity_b": capacity_b,
		"shared_claim_a": shared_claim_a,
		"shared_claim_b": shared_claim_b,
		"claim_conservation_error": absf((shared_claim_a + shared_claim_b) - 1.0),
		"retained_resource_factor_a": retained_factor_a,
		"retained_resource_factor_b": retained_factor_b,
		"effective_soil_moisture_a": float(effective_environment_a["soil_moisture"]),
		"effective_soil_moisture_b": float(effective_environment_b["soil_moisture"]),
		"effective_nutrients_a": float(effective_environment_a["nutrients"]),
		"effective_nutrients_b": float(effective_environment_b["nutrients"]),
		"baseline_score_a": float(baseline_a["net_resource_balance"]),
		"baseline_score_b": float(baseline_b["net_resource_balance"]),
		"competed_score_a": float(competed_a["net_resource_balance"]),
		"competed_score_b": float(competed_b["net_resource_balance"]),
		"root_competition_delta_a": float(competed_a["net_resource_balance"]) - float(baseline_a["net_resource_balance"]),
		"root_competition_delta_b": float(competed_b["net_resource_balance"]) - float(baseline_b["net_resource_balance"]),
	}
	result["result_hash"] = _root_hash(result)
	return result

static func _effective_root_environment(environment: Dictionary, retained_factor: float, suffix: String) -> Dictionary:
	return EnvironmentSample.create(
		float(environment["world_x_m"]),
		float(environment["world_z_m"]),
		float(environment["temperature_c"]),
		clampf(float(environment["soil_moisture"]) * retained_factor, 0.0, 1.0),
		float(environment["sunlight"]),
		clampf(float(environment["nutrients"]) * retained_factor, 0.0, 1.0),
		float(environment["flood_frequency"]),
		int(environment["seed"]),
		String(environment["environment_revision"]) + "/cal1c-root-" + suffix
	)

static func _circle_overlap_area(radius_a: float, radius_b: float, distance: float) -> float:
	if radius_a <= 0.0 or radius_b <= 0.0 or distance < 0.0:
		return 0.0
	if distance >= radius_a + radius_b:
		return 0.0
	if distance <= absf(radius_a - radius_b):
		var inner := minf(radius_a, radius_b)
		return PI * inner * inner
	var d2 := distance * distance
	var a2 := radius_a * radius_a
	var b2 := radius_b * radius_b
	var alpha := acos(clampf((d2 + a2 - b2) / (2.0 * distance * radius_a), -1.0, 1.0))
	var beta := acos(clampf((d2 + b2 - a2) / (2.0 * distance * radius_b), -1.0, 1.0))
	var radicand := maxf(0.0, (-distance + radius_a + radius_b) * (distance + radius_a - radius_b) * (distance - radius_a + radius_b) * (distance + radius_a + radius_b))
	return a2 * alpha + b2 * beta - 0.5 * sqrt(radicand)

static func _crown_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(result.get("schema", "")), VERSION,
		String(result.get("environment_checksum", "")),
		String(result.get("phenotype_a_hash", "")), String(result.get("phenotype_b_hash", "")),
		"%.9f,%.9f" % [Vector2(result.get("position_a", Vector2.ZERO)).x, Vector2(result.get("position_a", Vector2.ZERO)).y],
		"%.9f,%.9f" % [Vector2(result.get("position_b", Vector2.ZERO)).x, Vector2(result.get("position_b", Vector2.ZERO)).y],
		"%.12f" % float(result.get("overlap_area_m2", 0.0)),
		"%.12f" % float(result.get("overlap_fraction_a", 0.0)), "%.12f" % float(result.get("overlap_fraction_b", 0.0)),
		"%.12f" % float(result.get("neighbour_shading_pressure_a", 0.0)), "%.12f" % float(result.get("neighbour_shading_pressure_b", 0.0)),
		"%.12f" % float(result.get("crown_overlap_loss_a", 0.0)), "%.12f" % float(result.get("crown_overlap_loss_b", 0.0))
	])).sha256_text()

static func _root_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(result.get("schema", "")), VERSION,
		String(result.get("environment_checksum", "")),
		String(result.get("genome_a_checksum", "")), String(result.get("genome_b_checksum", "")),
		"%.9f,%.9f" % [Vector2(result.get("position_a", Vector2.ZERO)).x, Vector2(result.get("position_a", Vector2.ZERO)).y],
		"%.9f,%.9f" % [Vector2(result.get("position_b", Vector2.ZERO)).x, Vector2(result.get("position_b", Vector2.ZERO)).y],
		"%.12f" % float(result.get("overlap_area_m2", 0.0)),
		"%.12f" % float(result.get("shared_claim_a", 0.0)), "%.12f" % float(result.get("shared_claim_b", 0.0)),
		"%.12f" % float(result.get("retained_resource_factor_a", 0.0)), "%.12f" % float(result.get("retained_resource_factor_b", 0.0)),
		"%.12f" % float(result.get("root_competition_delta_a", 0.0)), "%.12f" % float(result.get("root_competition_delta_b", 0.0))
	])).sha256_text()
