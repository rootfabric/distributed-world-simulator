extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_resource_balance.v1"
const VERSION := "1.0.0"
const FAVOURABLE_THRESHOLD := 0.25
const MARGINAL_THRESHOLD := 0.0
const FIELD_NAMES: Array[String] = [
	"schema",
	"version",
	"environment_checksum",
	"genome_checksum",
	"biomass_kg_m2",
	"effective_soil_moisture",
	"light_response",
	"water_response",
	"nutrient_response",
	"temperature_response",
	"gross_photosynthetic_income",
	"maintenance_cost",
	"root_cost",
	"structural_cost",
	"growth_allocation_cost",
	"reproduction_allocation_cost",
	"water_stress_penalty",
	"flood_penalty",
	"density_cost",
	"light_limitation",
	"water_limitation",
	"nutrient_limitation",
	"temperature_limitation",
	"flood_limitation",
	"net_resource_balance",
	"dominant_limiting_factor",
	"viability_class",
	"checksum",
]


static func evaluate(environment: Dictionary, genome: Dictionary, biomass_kg_m2: float = 0.05) -> Dictionary:
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not is_finite(biomass_kg_m2) or biomass_kg_m2 < 0.0:
		return {}

	var root_depth_m := float(genome["root_depth_m"])
	var height_m := float(genome["height_m"])
	var growth_rate := float(genome["growth_rate"])
	var water_preference := float(genome["water_preference"])
	var water_tolerance_width := float(genome["water_tolerance_width"])
	var shade_tolerance := float(genome["shade_tolerance"])
	var seed_count := int(genome["seed_count"])
	var dispersal_m := float(genome["seed_dispersal_distance_m"])

	var soil_moisture := float(environment["soil_moisture"])
	var sunlight := float(environment["sunlight"])
	var nutrients := float(environment["nutrients"])
	var flood_frequency := float(environment["flood_frequency"])
	var temperature_c := float(environment["temperature_c"])

	# Deeper roots recover a bounded fraction of otherwise unavailable moisture.
	# The benefit saturates while root construction cost below rises super-linearly.
	var root_reach := clampf(root_depth_m / 2.0, 0.0, 1.0)
	var effective_soil_moisture := clampf(soil_moisture + root_reach * 0.22 * (1.0 - soil_moisture), 0.0, 1.0)
	var water_z := (effective_soil_moisture - water_preference) / water_tolerance_width
	var water_response := exp(-0.5 * water_z * water_z)

	# Shade tolerance allows useful capture under dim conditions, but it carries a
	# lower maximum photosynthetic capacity so high shade tolerance is not free.
	var effective_light := sunlight + 0.35 * shade_tolerance * (1.0 - sunlight)
	var light_denominator := 0.55 + 0.15 * (1.0 - shade_tolerance)
	var light_response := clampf(effective_light / light_denominator, 0.0, 1.0)
	var photosynthetic_capacity := 1.0 - 0.22 * shade_tolerance

	var nutrient_response := (nutrients / (nutrients + 0.22)) / (1.0 / 1.22)
	nutrient_response = clampf(nutrient_response, 0.0, 1.0)
	var temperature_response := exp(-0.5 * pow((temperature_c - 17.0) / 11.0, 2.0))

	var gross_photosynthetic_income := 2.5 * light_response * water_response * nutrient_response * temperature_response * photosynthetic_capacity
	var maintenance_cost := 0.48 + 0.10 * growth_rate + 0.035 * height_m
	var root_cost := 0.20 * pow(root_depth_m, 1.25)
	var structural_cost := 0.095 * pow(height_m, 1.20)
	var growth_allocation_cost := 0.16 * growth_rate
	var reproduction_allocation_cost := 0.00045 * float(seed_count) + 0.0012 * dispersal_m

	var drought_stress := maxf(water_preference - effective_soil_moisture - water_tolerance_width * 0.45, 0.0) * 1.45
	var excess_water_stress := maxf(effective_soil_moisture - (water_preference + water_tolerance_width * 0.45), 0.0) * 1.25
	var water_stress_penalty := drought_stress + excess_water_stress
	var flood_penalty := pow(flood_frequency, 1.35) * 1.05
	var height_factor := clampf(height_m / 5.0, 0.0, 1.0)
	var density_cost := 0.18 * biomass_kg_m2 * (0.85 + 0.15 * height_factor)

	var net_resource_balance := gross_photosynthetic_income - (
		maintenance_cost
		+ root_cost
		+ structural_cost
		+ growth_allocation_cost
		+ reproduction_allocation_cost
		+ water_stress_penalty
		+ flood_penalty
		+ density_cost
	)

	var light_limitation := clampf(1.0 - light_response, 0.0, 1.0)
	var water_limitation := clampf(maxf(1.0 - water_response, water_stress_penalty / 1.45), 0.0, 1.0)
	var nutrient_limitation := clampf(1.0 - nutrient_response, 0.0, 1.0)
	var temperature_limitation := clampf(1.0 - temperature_response, 0.0, 1.0)
	var flood_limitation := clampf(flood_penalty / 1.05, 0.0, 1.0)
	var dominant_limiting_factor := _dominant_limiting_factor(
		light_limitation,
		water_limitation,
		nutrient_limitation,
		temperature_limitation,
		flood_limitation
	)
	var viability_class := _viability_class(net_resource_balance)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"environment_checksum": String(environment["checksum"]),
		"genome_checksum": String(genome["checksum"]),
		"biomass_kg_m2": biomass_kg_m2,
		"effective_soil_moisture": effective_soil_moisture,
		"light_response": light_response,
		"water_response": water_response,
		"nutrient_response": nutrient_response,
		"temperature_response": temperature_response,
		"gross_photosynthetic_income": gross_photosynthetic_income,
		"maintenance_cost": maintenance_cost,
		"root_cost": root_cost,
		"structural_cost": structural_cost,
		"growth_allocation_cost": growth_allocation_cost,
		"reproduction_allocation_cost": reproduction_allocation_cost,
		"water_stress_penalty": water_stress_penalty,
		"flood_penalty": flood_penalty,
		"density_cost": density_cost,
		"light_limitation": light_limitation,
		"water_limitation": water_limitation,
		"nutrient_limitation": nutrient_limitation,
		"temperature_limitation": temperature_limitation,
		"flood_limitation": flood_limitation,
		"net_resource_balance": net_resource_balance,
		"dominant_limiting_factor": dominant_limiting_factor,
		"viability_class": viability_class,
	}
	result["checksum"] = compute_checksum(result)
	return result


static func validate(result: Dictionary) -> Dictionary:
	if result.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_RESOURCE_BALANCE_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not result.has(field_name):
			return _failure("ECO_RESOURCE_BALANCE_MISSING_FIELD", {"field": field_name})
	for field_name in result.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_RESOURCE_BALANCE_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(result.get("schema", "")) != SCHEMA:
		return _failure("ECO_RESOURCE_BALANCE_SCHEMA_MISMATCH")
	if String(result.get("version", "")) != VERSION:
		return _failure("ECO_RESOURCE_BALANCE_VERSION_MISMATCH")
	for field_name in FIELD_NAMES:
		if field_name in ["schema", "version", "environment_checksum", "genome_checksum", "dominant_limiting_factor", "viability_class", "checksum"]:
			continue
		if typeof(result.get(field_name)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(result.get(field_name))):
			return _failure("ECO_RESOURCE_BALANCE_NON_FINITE_FIELD", {"field": field_name})
	if float(result.get("biomass_kg_m2", -1.0)) < 0.0:
		return _failure("ECO_RESOURCE_BALANCE_NEGATIVE_BIOMASS")
	for field_name in ["light_response", "water_response", "nutrient_response", "temperature_response", "light_limitation", "water_limitation", "nutrient_limitation", "temperature_limitation", "flood_limitation"]:
		var value := float(result.get(field_name, -1.0))
		if value < 0.0 or value > 1.0:
			return _failure("ECO_RESOURCE_BALANCE_INVALID_RATIO", {"field": field_name})
	if not String(result.get("dominant_limiting_factor", "")) in ["LIGHT", "WATER", "NUTRIENT", "TEMPERATURE", "FLOOD"]:
		return _failure("ECO_RESOURCE_BALANCE_INVALID_LIMITING_FACTOR")
	if not String(result.get("viability_class", "")) in ["FAVOURABLE", "MARGINAL", "UNSUSTAINABLE"]:
		return _failure("ECO_RESOURCE_BALANCE_INVALID_VIABILITY_CLASS")
	var checksum := String(result.get("checksum", ""))
	if checksum.length() != 64 or checksum != compute_checksum(result):
		return _failure("ECO_RESOURCE_BALANCE_CHECKSUM_MISMATCH")
	return _success()


static func compute_checksum(result: Dictionary) -> String:
	var values := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("environment_checksum", "")),
		String(result.get("genome_checksum", "")),
	])
	for field_name in FIELD_NAMES:
		if field_name in ["schema", "version", "environment_checksum", "genome_checksum", "dominant_limiting_factor", "viability_class", "checksum"]:
			continue
		values.append(_format_float(float(result.get(field_name, 0.0))))
	values.append(String(result.get("dominant_limiting_factor", "")))
	values.append(String(result.get("viability_class", "")))
	return "|".join(values).sha256_text()


static func _dominant_limiting_factor(light: float, water: float, nutrient: float, temperature: float, flood: float) -> String:
	var best_name := "LIGHT"
	var best_value := light
	for pair in [
		["WATER", water],
		["NUTRIENT", nutrient],
		["TEMPERATURE", temperature],
		["FLOOD", flood],
	]:
		if float(pair[1]) > best_value:
			best_name = String(pair[0])
			best_value = float(pair[1])
	return best_name


static func _viability_class(net_resource_balance: float) -> String:
	if net_resource_balance >= FAVOURABLE_THRESHOLD:
		return "FAVOURABLE"
	if net_resource_balance >= MARGINAL_THRESHOLD:
		return "MARGINAL"
	return "UNSUSTAINABLE"


static func _format_float(value: float) -> String:
	return "%.9f" % value


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
