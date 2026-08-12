extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_d_lifecycle_payoff.v1"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001
const REFERENCE_RELEASE_HEIGHT_M := 1.0

static func create_state(current_height_m: float, biomass_kg_m2: float, reserve_resource: float, years_alive: float) -> Dictionary:
	if not is_finite(current_height_m) or not is_finite(biomass_kg_m2) or not is_finite(reserve_resource) or not is_finite(years_alive):
		return {}
	if current_height_m < 0.0 or biomass_kg_m2 < 0.0 or reserve_resource < 0.0 or years_alive < 0.0:
		return {}
	return {
		"current_height_m": current_height_m,
		"biomass_kg_m2": biomass_kg_m2,
		"reserve_resource": reserve_resource,
		"years_alive": years_alive,
	}

static func create_disturbance(severity: float) -> Dictionary:
	if not is_finite(severity) or severity < 0.0 or severity > 1.0:
		return {}
	return {"severity": severity}

static func evaluate(genome: Dictionary, environment: Dictionary, state: Dictionary, disturbance: Dictionary) -> Dictionary:
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if state.is_empty() or disturbance.is_empty():
		return {}

	var current_height := float(state.get("current_height_m", -1.0))
	var biomass := float(state.get("biomass_kg_m2", -1.0))
	var reserve := float(state.get("reserve_resource", -1.0))
	var years_alive := float(state.get("years_alive", -1.0))
	var severity := float(disturbance.get("severity", -1.0))
	if current_height < 0.0 or biomass < 0.0 or reserve < 0.0 or years_alive < 0.0 or severity < 0.0 or severity > 1.0:
		return {}

	var target_height := float(genome["height_m"])
	var growth_rate := maxf(float(genome["growth_rate"]), EPSILON)
	var root_depth := float(genome["root_depth_m"])
	var lifespan := float(genome["lifespan_years"])
	var seed_ceiling := float(genome["seed_count"])
	var base_dispersal_m := float(genome["seed_dispersal_distance_m"])

	# Dimensionless maturity: current realized size relative to the inherited target size.
	var maturity_fraction := clampf(current_height / maxf(target_height, EPSILON), 0.0, 1.0)

	# Reserve is explicitly competed against current standing biomass. A large seed ceiling
	# therefore cannot produce seeds from an empty reserve state.
	var reserve_fraction := 0.0
	if reserve + biomass > EPSILON:
		reserve_fraction = clampf(reserve / (reserve + biomass), 0.0, 1.0)
	var realized_seed_output_per_year := seed_ceiling * maturity_fraction * reserve_fraction

	# Treat the inherited dispersal distance as the 1 m release-height baseline. For the
	# same seed/aerodynamic trait, ballistic/flight time grows with sqrt(height).
	var release_height_factor := sqrt(maxf(current_height, 0.0) / REFERENCE_RELEASE_HEIGHT_M)
	var effective_seed_dispersal_m := base_dispersal_m * release_height_factor

	# CAL1-D uses an explicit time index rather than hiding maturity inside a final score.
	# height/growth_rate is intentionally reported as a research index; CAL1-E may later
	# combine it with other accepted terms, and CAL1-F may calibrate units/magnitudes.
	var maturity_time_index_years := target_height / growth_rate
	var lifetime_reproductive_window_years := maxf(lifespan - maturity_time_index_years, 0.0)
	var remaining_reproductive_window_years := maxf(lifespan - maxf(years_alive, maturity_time_index_years), 0.0)
	var lifetime_seed_potential := realized_seed_output_per_year * lifetime_reproductive_window_years

	var resource := ResourceModel.evaluate(environment, genome, biomass)
	if resource.is_empty():
		return {}
	var structural_investment := float(resource["structural_cost"])
	var amortized_structural_cost_per_year := structural_investment / maxf(lifespan, EPSILON)

	# Mechanical disturbance path. Height increases exposed lever length while root depth
	# increases anchoring. The product is causal and bounded; no generic resilience bonus.
	var support_sum := maxf(target_height + root_depth, EPSILON)
	var exposure_fraction := clampf(target_height / support_sum, 0.0, 1.0)
	var anchoring_fraction := clampf(root_depth / support_sum, 0.0, 1.0)
	var disturbance_damage_fraction := clampf(severity * exposure_fraction * (1.0 - anchoring_fraction), 0.0, 1.0)
	var disturbance_survival_fraction := 1.0 - disturbance_damage_fraction
	var recovery_time_index_years := disturbance_damage_fraction / growth_rate
	var post_disturbance_reproductive_window_years := maxf(remaining_reproductive_window_years - recovery_time_index_years, 0.0) * disturbance_survival_fraction
	var post_disturbance_seed_potential := realized_seed_output_per_year * post_disturbance_reproductive_window_years

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"genome_checksum": String(genome["checksum"]),
		"environment_checksum": String(environment["checksum"]),
		"current_height_m": current_height,
		"biomass_kg_m2": biomass,
		"reserve_resource": reserve,
		"years_alive": years_alive,
		"disturbance_severity": severity,
		"maturity_fraction": maturity_fraction,
		"reserve_fraction": reserve_fraction,
		"seed_output_ceiling_per_year": seed_ceiling,
		"realized_seed_output_per_year": realized_seed_output_per_year,
		"release_height_factor": release_height_factor,
		"effective_seed_dispersal_m": effective_seed_dispersal_m,
		"maturity_time_index_years": maturity_time_index_years,
		"lifetime_reproductive_window_years": lifetime_reproductive_window_years,
		"remaining_reproductive_window_years": remaining_reproductive_window_years,
		"lifetime_seed_potential": lifetime_seed_potential,
		"structural_investment": structural_investment,
		"amortized_structural_cost_per_year": amortized_structural_cost_per_year,
		"exposure_fraction": exposure_fraction,
		"anchoring_fraction": anchoring_fraction,
		"disturbance_damage_fraction": disturbance_damage_fraction,
		"disturbance_survival_fraction": disturbance_survival_fraction,
		"recovery_time_index_years": recovery_time_index_years,
		"post_disturbance_reproductive_window_years": post_disturbance_reproductive_window_years,
		"post_disturbance_seed_potential": post_disturbance_seed_potential,
	}
	result["result_hash"] = compute_hash(result)
	return result

static func compute_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("genome_checksum", "")),
		String(result.get("environment_checksum", "")),
	])
	for field_name in [
		"current_height_m", "biomass_kg_m2", "reserve_resource", "years_alive", "disturbance_severity",
		"maturity_fraction", "reserve_fraction", "seed_output_ceiling_per_year", "realized_seed_output_per_year",
		"release_height_factor", "effective_seed_dispersal_m", "maturity_time_index_years",
		"lifetime_reproductive_window_years", "remaining_reproductive_window_years", "lifetime_seed_potential",
		"structural_investment", "amortized_structural_cost_per_year", "exposure_fraction", "anchoring_fraction",
		"disturbance_damage_fraction", "disturbance_survival_fraction", "recovery_time_index_years",
		"post_disturbance_reproductive_window_years", "post_disturbance_seed_potential"
	]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	return "|".join(tokens).sha256_text()
