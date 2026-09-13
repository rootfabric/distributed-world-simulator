extends RefCounted
## A5 inherited life-history/regulation contract. Integer-only deterministic policy.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const SCHEMA := "dws.ecology.life-history-program.v1"

static func create_default() -> Dictionary:
	return {
		"schema": SCHEMA,
		"uptake": {
			"basal_water_mg": 120,
			"basal_nutrient_mg": 80,
			"basal_organic_mg": 40,
			"water_per_absorber_unit_mg": 160,
			"nutrient_per_absorber_unit_mg": 90,
			"organic_per_absorber_unit_mg": 60,
		},
		"regulation": {
			"growth_light_min": 180,
			"growth_water_min": 180,
			"growth_competition_max": 900,
			"growth_temperature_min": 100,
			"growth_temperature_max": 900,
		},
		"metabolism": {
			"photosynthesis_area_divisor_mm2": 20,
			"max_photosynthesis_energy_mj": 200000,
			"photosynthesis_water_saturation_mg": 200,
			"maintenance_energy_per_module_mj": 12,
			"maintenance_water_per_module_mg": 3,
		},
		"growth": {
			"transfer_permille": 650,
			"max_transfer": {"material_mg": 50000, "water_mg": 50000, "energy_mj": 50000},
		},
		"survival": {
			"starvation_limit_ticks": 3,
		},
		"reproduction": {
			"maturity_ticks": 4,
			"interval_ticks": 3,
			"required_reproductive_modules": 1,
			"offspring_per_event": 1,
			"endowment": {"material_mg": 8000, "water_mg": 5000, "energy_mj": 3000},
			"fee_energy_mj": 600,
		},
	}

static func validate(v: Variant) -> String:
	if not C.keys(v, ["schema", "uptake", "regulation", "metabolism", "growth", "survival", "reproduction"]) or v.schema != SCHEMA:
		return "LIFE_HISTORY_SCHEMA"
	if not _valid_uptake(v.uptake):
		return "LIFE_HISTORY_UPTAKE"
	if not _valid_regulation(v.regulation):
		return "LIFE_HISTORY_REGULATION"
	if not _valid_metabolism(v.metabolism):
		return "LIFE_HISTORY_METABOLISM"
	if not _valid_growth(v.growth):
		return "LIFE_HISTORY_GROWTH"
	if not _valid_survival(v.survival):
		return "LIFE_HISTORY_SURVIVAL"
	if not _valid_reproduction(v.reproduction):
		return "LIFE_HISTORY_REPRODUCTION"
	return "NONCANONICAL_LIFE_HISTORY" if C.encode(v).is_empty() else ""

static func biological_hash(v: Dictionary) -> String:
	return C.digest(v) if validate(v).is_empty() else ""

static func _valid_uptake(v: Variant) -> bool:
	var keys := ["basal_water_mg", "basal_nutrient_mg", "basal_organic_mg", "water_per_absorber_unit_mg", "nutrient_per_absorber_unit_mg", "organic_per_absorber_unit_mg"]
	if not C.keys(v, keys): return false
	for k in keys:
		if not C.integer(v[k], 0, 1000000): return false
	return true

static func _valid_regulation(v: Variant) -> bool:
	var keys := ["growth_light_min", "growth_water_min", "growth_competition_max", "growth_temperature_min", "growth_temperature_max"]
	if not C.keys(v, keys): return false
	for k in keys:
		if not C.integer(v[k], 0, 1000): return false
	return v.growth_temperature_min <= v.growth_temperature_max

static func _valid_metabolism(v: Variant) -> bool:
	var keys := ["photosynthesis_area_divisor_mm2", "max_photosynthesis_energy_mj", "photosynthesis_water_saturation_mg", "maintenance_energy_per_module_mj", "maintenance_water_per_module_mg"]
	if not C.keys(v, keys): return false
	if not C.integer(v.photosynthesis_area_divisor_mm2, 1, 1000000): return false
	if not C.integer(v.max_photosynthesis_energy_mj, 0, B.MAX_STOCK): return false
	if not C.integer(v.photosynthesis_water_saturation_mg, 1, 1000000): return false
	if not C.integer(v.maintenance_energy_per_module_mj, 0, 1000000): return false
	return C.integer(v.maintenance_water_per_module_mg, 0, 1000000)

static func _valid_growth(v: Variant) -> bool:
	if not C.keys(v, ["transfer_permille", "max_transfer"]): return false
	return C.integer(v.transfer_permille, 0, 1000) and B.valid_stock(v.max_transfer)

static func _valid_survival(v: Variant) -> bool:
	return C.keys(v, ["starvation_limit_ticks"]) and C.integer(v.starvation_limit_ticks, 1, 1000)

static func _valid_reproduction(v: Variant) -> bool:
	var keys := ["maturity_ticks", "interval_ticks", "required_reproductive_modules", "offspring_per_event", "endowment", "fee_energy_mj"]
	if not C.keys(v, keys): return false
	if not C.integer(v.maturity_ticks, 1, 1000000) or not C.integer(v.interval_ticks, 1, 1000000): return false
	if not C.integer(v.required_reproductive_modules, 1, 32) or not C.integer(v.offspring_per_event, 1, 4): return false
	if not B.valid_stock(v.endowment): return false
	return C.integer(v.fee_energy_mj, 0, B.MAX_STOCK)
