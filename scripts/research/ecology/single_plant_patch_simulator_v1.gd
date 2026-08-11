extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.single_plant_patch_simulation.v1"
const VERSION := "1.0.0"
const DEFAULT_SEASONS := 120
const DEFAULT_INITIAL_BIOMASS_KG_M2 := 0.05
const MAX_BIOMASS_KG_M2 := 8.0


static func simulate(
	environment: Dictionary,
	genome: Dictionary,
	seasons: int = DEFAULT_SEASONS,
	initial_biomass_kg_m2: float = DEFAULT_INITIAL_BIOMASS_KG_M2
) -> Dictionary:
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if seasons <= 0 or not is_finite(initial_biomass_kg_m2) or initial_biomass_kg_m2 < 0.0:
		return {}

	var biomass := initial_biomass_kg_m2
	var peak_biomass := biomass
	var cumulative_recruitment := 0.0
	var cumulative_mortality := 0.0
	var productive_seasons := 0
	var stress_seasons := 0
	var series_tokens := PackedStringArray()
	var biomass_series: Array[float] = []
	var net_balance_series: Array[float] = []
	biomass_series.append(biomass)

	for season in range(seasons):
		var balance := ResourceModel.evaluate(environment, genome, biomass)
		if balance.is_empty():
			return {}
		var net := float(balance["net_resource_balance"])
		if net >= 0.0:
			productive_seasons += 1
		else:
			stress_seasons += 1

		var positive_net := maxf(net, 0.0)
		var negative_net := maxf(-net, 0.0)
		var growth_rate := float(genome["growth_rate"])
		var seed_count := int(genome["seed_count"])
		var lifespan_years := float(genome["lifespan_years"])

		var vegetative_growth := positive_net * growth_rate * biomass * 0.20
		var recruitment_efficiency := minf(0.12, 0.015 + log(1.0 + float(seed_count)) * 0.008)
		var recruitment := positive_net * recruitment_efficiency * biomass
		var baseline_turnover := biomass / (lifespan_years * 4.0) * 0.08
		var stress_mortality := negative_net * biomass * 0.24
		var mortality := minf(biomass + vegetative_growth + recruitment, baseline_turnover + stress_mortality)

		biomass = clampf(biomass + vegetative_growth + recruitment - mortality, 0.0, MAX_BIOMASS_KG_M2)
		peak_biomass = maxf(peak_biomass, biomass)
		cumulative_recruitment += recruitment
		cumulative_mortality += mortality
		biomass_series.append(biomass)
		net_balance_series.append(net)
		series_tokens.append("%d:%s:%s" % [season, _format_float(biomass), _format_float(net)])

	var final_balance := ResourceModel.evaluate(environment, genome, biomass)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"environment_checksum": String(environment["checksum"]),
		"genome_checksum": String(genome["checksum"]),
		"seasons": seasons,
		"initial_biomass_kg_m2": initial_biomass_kg_m2,
		"final_biomass_kg_m2": biomass,
		"peak_biomass_kg_m2": peak_biomass,
		"cumulative_recruitment_kg_m2": cumulative_recruitment,
		"cumulative_mortality_kg_m2": cumulative_mortality,
		"productive_seasons": productive_seasons,
		"stress_seasons": stress_seasons,
		"final_net_resource_balance": float(final_balance.get("net_resource_balance", 0.0)),
		"final_dominant_limiting_factor": String(final_balance.get("dominant_limiting_factor", "")),
		"initial_viability_class": String(ResourceModel.evaluate(environment, genome, initial_biomass_kg_m2).get("viability_class", "")),
		"biomass_series": biomass_series,
		"net_balance_series": net_balance_series,
		"series_hash": "\n".join(series_tokens).sha256_text(),
	}
	result["checksum"] = compute_checksum(result)
	return result


static func compute_checksum(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("environment_checksum", "")),
		String(result.get("genome_checksum", "")),
		str(int(result.get("seasons", 0))),
		_format_float(float(result.get("initial_biomass_kg_m2", 0.0))),
		_format_float(float(result.get("final_biomass_kg_m2", 0.0))),
		_format_float(float(result.get("peak_biomass_kg_m2", 0.0))),
		_format_float(float(result.get("cumulative_recruitment_kg_m2", 0.0))),
		_format_float(float(result.get("cumulative_mortality_kg_m2", 0.0))),
		str(int(result.get("productive_seasons", 0))),
		str(int(result.get("stress_seasons", 0))),
		_format_float(float(result.get("final_net_resource_balance", 0.0))),
		String(result.get("final_dominant_limiting_factor", "")),
		String(result.get("initial_viability_class", "")),
		String(result.get("series_hash", "")),
	])).sha256_text()


static func _format_float(value: float) -> String:
	return "%.9f" % value
